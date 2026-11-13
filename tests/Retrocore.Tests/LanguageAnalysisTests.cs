// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug.Language;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the language server's analysis: definitions, comments, names under the cursor and instruction help.
/// </summary>
[TestClass]
public sealed class LanguageAnalysisTests
{
    private const string Equates = """
        ; Keyboard data, bit 7 set when a key is waiting.
        KBD = $C000

        ; Prints a value.
        .macro show value
            lda #value
        .endmacro

        """;

    private const string ReferencesSource = """
        .include "equates.asm"
        .org $6000
        ;; Waits for <KBD>, then shows it.
        start:
            lda KBD
        wait:
            bit KBD                 ; KBD in a comment is not a reference
            bpl wait
            show 1
            show 2
            .byte "KBD"
            jmp start

        """;

    /// <summary>
    ///  Definitions come from the assembly, across includes, with the comment above them; open text overrides disk.
    /// </summary>
    [TestMethod]
    public void DefinitionsSpanIncludes()
    {
        string directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            string equates = Path.Join(directory, "equates.asm");
            File.WriteAllText(equates, "KBD = $1234\n");
            File.WriteAllText(main, "");
            Dictionary<string, string> open = new(StringComparer.OrdinalIgnoreCase)
            {
                [main] = ".include \"equates.asm\"\n.org $6000\nstart:\n    lda KBD\n    show 1\n",
                [equates] = Equates
            };

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, path => open.GetValueOrDefault(path));

            analysis.Result.Diagnostics.Should().BeEmpty();
            analysis.Members.Should().Contain(equates);
            SymbolSite kbd = analysis.Find("KBD").Single();
            kbd.Path.Should().Be(equates);
            kbd.Line.Should().Be(1);
            kbd.Value.Should().Be(0xC000, "the open document, not disk, is assembled");
            kbd.Kind.Should().Be(SymbolSiteKind.Constant);
            SourceText.CommentFor(analysis.LinesOf(equates), kbd.Line).Should().Equal("Keyboard data, bit 7 set when a key is waiting.");
            analysis.Find("show").Single().Kind.Should().Be(SymbolSiteKind.Macro);
            analysis.Find("start").Single().Value.Should().Be(0x6000);

            // The macro invocation's line produced the macro's bytes.
            analysis.Emitted(main, 4).Should().ContainSingle().Which.Address.Should().Be(0x6003);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A source that does not assemble still has its definitions, found in its text.
    /// </summary>
    [TestMethod]
    public void DefinitionsSurviveErrors()
    {
        string directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(main, ".org $6000\nstart:\n    jmp missing\nVALUE = 3\n");

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);

            analysis.Result.Success.Should().BeFalse();
            analysis.Find("start").Single().Line.Should().Be(1);
            analysis.Find("VALUE").Single().Kind.Should().Be(SymbolSiteKind.Constant);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A <c>.define</c> in an included file is found from its uses, with its documentation, even when its name
    ///  is also a mnemonic.
    /// </summary>
    [TestMethod]
    public void DefinesAreDefinitions()
    {
        string directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            string commands = Path.Join(directory, "commands.asm");
            File.WriteAllText(commands, ";; An entry that does nothing.\n.define NOP(state) ((state) << 4 | $8)\n");
            File.WriteAllText(main, ".include \"commands.asm\"\n.org $6000\n    .byte NOP($1)\n");

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);

            analysis.Result.Diagnostics.Should().BeEmpty();
            SymbolSite nop = analysis.Find("NOP").Single();
            nop.Path.Should().Be(commands);
            nop.Line.Should().Be(1);
            nop.Kind.Should().Be(SymbolSiteKind.Macro);
            analysis.Documentation.Find("NOP")?.Summary.Should().Be("An entry that does nothing.");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  A directive in column 0 is not a local label, so it does not resolve to the line it starts.
    /// </summary>
    [TestMethod]
    public void DirectivesAreNotLocalLabels()
    {
        string[] lines = [";; An entry that does nothing.", ".define NOP(state) ((state) << 4 | $8)", ".loop", "    bne .loop"];

        SourceText.LocalDefinition(lines, ".define", 1).Should().BeNull();
        SourceText.LocalDefinition(lines, ".loop", 3)?.Line.Should().Be(2, "a local label still resolves");
    }

    /// <summary>
    ///  An included file is analyzed through the outermost source that includes it, the later version when two
    ///  do, and a MACRO-10 base through its overlay.
    /// </summary>
    /// <param name="file">The opened file, under the test's inputs.</param>
    /// <param name="root">The root it is analyzed through.</param>
    [TestMethod]
    [DataRow("Dos/BootLoader.asm", "Dos/Dos33.asm")]
    [DataRow("DiskII/Boot.asm", "DiskII/Boot16.asm")]
    [DataRow("DiskII/Sequencer.asm", "DiskII/Sequencer16.asm")]
    [DataRow("AppleSoft/m6502.asm", "AppleSoft/applesoft.mac")]
    [DataRow("Dos/Dos33.asm", "Dos/Dos33.asm")]
    public void IncludedFilesAreAnalyzedThroughTheirRoot(string file, string root)
    {
        string inputs = Path.Join(AppContext.BaseDirectory, "Inputs");
        SourceIncludes.RootOf(Path.GetFullPath(Path.Join(inputs, file)))
            .Should().Be(Path.GetFullPath(Path.Join(inputs, root)));
    }

    /// <summary>
    ///  The name under the cursor includes scope qualifiers and cheap locals, but not a label's colon.
    /// </summary>
    /// <param name="line">The line.</param>
    /// <param name="column">The cursor's column.</param>
    /// <param name="expected">The name.</param>
    [TestMethod]
    [DataRow("    lda Outer::Value,x", 10, "Outer::Value")]
    [DataRow("start:", 2, "start")]
    [DataRow("    bne @loop", 10, "@loop")]
    [DataRow("    jsr B_FUNC", 12, "B_FUNC")]
    [DataRow("    .org $F800", 6, ".org")]
    public void WordAtFindsTheName(string line, int column, string expected) =>
        SourceText.WordAt(line, column)?.Word.Should().Be(expected);

    /// <summary>
    ///  A definition from an older analysis may no longer have a line in the edited document.
    /// </summary>
    /// <param name="line">The stale definition's line.</param>
    [TestMethod]
    [DataRow(1)]
    [DataRow(3)]
    public void CommentsIgnoreStaleDefinitions(int line) =>
        SourceText.CommentFor(["; Not the stale definition's comment."], line).Should().BeEmpty();

    /// <summary>
    ///  In a file of p-code and 6502 code, a line's help is that of what wrote its bytes: under the <c>.cpu Pcode</c> an
    ///  include sets, <c>LDA</c> expands its macro, so its help is the macro's; under <c>.cpu Mos6502</c> it is the
    ///  6502's instruction. A macro-only CPU has no instruction help or mnemonics of its own.
    /// </summary>
    [TestMethod]
    public void MixedPcodeAndM6502LinesKnowWhatWroteThem()
    {
        string directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            File.WriteAllText(Path.Join(directory, "pcode.asm"), """
                .cpu Pcode
                ;; Loads an intermediate variable's address.
                .macro LDA level, offset
                .byte 178, level, offset
                .endmacro
                """);

            File.WriteAllText(main, """
                .include "pcode.asm"
                .org $6000
                        LDA 1, 4
                        .cpu Mos6502
                        LDA #1
                """);

            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);

            analysis.Result.Diagnostics.Should().BeEmpty();
            analysis.ExpandsMacro(main, line: 2).Should().BeTrue("the p-code LDA expands Pcode's macro");
            analysis.ExpandsMacro(main, line: 4).Should().BeFalse("under .cpu Mos6502, LDA is the 6502's");
            analysis.Find("LDA").Should().ContainSingle().Which.Kind.Should().Be(SymbolSiteKind.Macro);

            Retrocore.Isa.InstructionSet pcode = Retrocore.Assembler.CpuCatalog.Get("Pcode");
            InstructionDocs.Describe("LDA", pcode).Should().BeNull();
            InstructionDocs.MnemonicsFor(pcode).Should().BeEmpty();
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  Instruction help lists the CPU's encodings, and says when an instruction is not the CPU's.
    /// </summary>
    [TestMethod]
    public void InstructionHelpFollowsTheCpu()
    {
        InstructionDocs.Describe("STZ", ProcessorVariant.Rockwell65C02).Should().Contain("$9C");
        InstructionDocs.Describe("STZ", ProcessorVariant.Mos6502).Should().Contain("Not an instruction");
        InstructionDocs.Describe("LDA", ProcessorVariant.Mos6502).Should().Contain("immediate").And.Contain("$A9");
        InstructionDocs.Describe("KBD", ProcessorVariant.Mos6502).Should().BeNull();
        InstructionDocs.MnemonicsFor(ProcessorVariant.Rockwell65C02).Should().Contain("BBR3");
    }

    /// <summary>
    ///  Z80 help lists canonical encodings with their fields and T-states, and the nearest <c>.cpu</c> selects it.
    /// </summary>
    [TestMethod]
    public void InstructionHelpDescribesTheZ80()
    {
        Retrocore.Isa.InstructionSet z80 = Retrocore.Cpu.Z80.Z80Isa.InstructionSet;
        string? load = InstructionDocs.Describe("LD", z80);
        load.Should().Contain("| `LD A,[IX+d]` | `DD 7E d` | 19 |");
        load.Should().Contain("| `LD IXH,n` (undocumented) | `DD 26 n` | 11 |");
        InstructionDocs.Describe("BIT", z80).Should().Contain("`DD CB d 46+8b`").And.NotContain("DD CB d 40");
        InstructionDocs.Describe("DJNZ", z80).Should().Contain("| 13/8 |");
        InstructionDocs.Describe("RST", z80).Should().Contain("`C7+p`");
        InstructionDocs.Describe("LDA", z80).Should().BeNull();
        InstructionDocs.MnemonicsFor(z80).Should().Contain(["LDIR", "SLL", "DJNZ"]).And.NotContain("LDA");
        InstructionDocs.IsMnemonic("djnz").Should().BeTrue();

        string[] lines = ["    lda #1", ".cpu Z80 ; Model I", "    ld a,b"];
        SourceText.InstructionSetOf(lines, 0).Name.Should().Be("Mos6502");
        SourceText.InstructionSetOf(lines, 2).Should().BeSameAs(z80);
    }

    /// <summary>
    ///  References to a constant, a label and a macro: in code across includes and in documentation links, not in
    ///  strings or ordinary comments, and not another assembly's name spelled the same.
    /// </summary>
    [TestMethod]
    public void ReferencesFollowResolution()
    {
        string directory = Directory.CreateTempSubdirectory().FullName;
        try
        {
            string main = Path.Join(directory, "main.asm");
            string equates = Path.Join(directory, "equates.asm");
            string other = Path.Join(directory, "other.asm");
            File.WriteAllText(equates, Equates);
            File.WriteAllText(main, ReferencesSource);
            File.WriteAllText(other, ".org $7000\nKBD = $C010\n    lda KBD\n");
            SourceAnalysis analysis = SourceAnalysis.Assemble(main, _ => null);
            SourceAnalysis unrelated = SourceAnalysis.Assemble(other, _ => null);
            SourceAnalysis[] analyses = [analysis, unrelated];

            string[] uses = ["main.asm:2:14", "main.asm:4:8", "main.asm:6:8"];
            References(analysis, "KBD", analyses, declarations: true).Should().Equal(["equates.asm:1:0", .. uses]);
            References(analysis, "KBD", analyses, declarations: false).Should().Equal(uses);
            References(analysis, "show", analyses, declarations: false).Should().Equal("main.asm:8:4", "main.asm:9:4");
            References(analysis, "start", analyses, declarations: true).Should().Equal("main.asm:3:0", "main.asm:11:8");
            References(unrelated, "KBD", analyses, declarations: false).Should().Equal("other.asm:2:8");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    // The references to a name an assembly defines, each as file:line:column.
    private static string[] References(SourceAnalysis analysis, string name, SourceAnalysis[] analyses, bool declarations) =>
    [
        .. SymbolReferences.Find(name, analysis.Find(name), analyses, sdk: [], declarations)
            .Select(site => $"{Path.GetFileName(site.Path)}:{site.Line}:{site.Column}")
    ];
}
