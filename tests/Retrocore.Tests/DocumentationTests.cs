// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Documentation;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  The <c>;;</c> documentation comment format (docs/DocComments.md): placement, sections, links, inheritance and
///  checks.
/// </summary>
[TestClass]
public class DocumentationTests
{
    /// <summary>
    ///  A compact comment documents the label below it, with its summary and sections.
    /// </summary>
    [TestMethod]
    public void CompactSectionsParse()
    {
        DocumentationFile file = Parse("""
            ;; Plots one lo-res block in the current color.
            ;; In:    A = row (0-47), Y = column (0-39), COLOR = the color, in both nibbles
            ;; Uses:  A, GBASL, GBASH, MASK
            ;; Keeps: X, Y
            ;; See:   <SCRN>, <SETCOL>
            PLOT:
                lsr a                           ; $F800
            """);

        file.Diagnostics.Should().BeEmpty();
        DocumentationComment comment = file.Comments.Single();
        comment.Name.Should().Be("PLOT");
        comment.Kind.Should().Be(DocumentationKind.Routine);
        comment.TargetLine.Should().Be(5);
        comment.Summary.Should().Be("Plots one lo-res block in the current color.");
        Required(comment.Section("In")).Entries.Select(entry => (entry.Name, entry.Meaning)).Should().Equal(
            ("A", "row (0-47)"),
            ("Y", "column (0-39)"),
            ("COLOR", "the color, in both nibbles"));

        Required(comment.Section("Keeps")).Items.Should().Equal("X", "Y");
        Required(comment.Section("See")).Items.Should().Equal("<SCRN>", "<SETCOL>");
    }

    /// <summary>
    ///  The expanded form, remarks, wrapped lists and plain headings parse to the same model.
    /// </summary>
    [TestMethod]
    public void ExpandedSectionsAndRemarksParse()
    {
        DocumentationComment comment = Parse("""
            ;; Reads a line of input.
            ;;
            ;; Backspace deletes a character.
            ;; Control-X cancels the line.
            ;;
            ;; Out:
            ;;   X    = the line's length
            ;;   IN,X = a carriage return,
            ;;          ending the line
            ;; Uses:  A,
            ;;        Y
            ;;
            ;; Notes:
            ;; Anything here.
            GETLN:
                rts
            """).Comments.Single();

        comment.Remarks.Should().Equal("Backspace deletes a character.", "Control-X cancels the line.");
        Required(comment.Section("Out")).Entries.Select(entry => entry.Name).Should().Equal("X", "IN,X");
        Required(comment.Section("Out")).Entries[1].Meaning.Should().Be("a carriage return, ending the line");
        Required(comment.Section("Uses")).Items.Should().Equal("A", "Y");
        Required(comment.Section("Notes")).IsKnown.Should().BeFalse();
        Required(comment.Section("Notes")).Text.Should().Be("Anything here.");
    }

    /// <summary>
    ///  Only <c>;;</c> is documentation; placement mistakes are errors, and the file comment is exempt.
    /// </summary>
    [TestMethod]
    public void PlacementIsChecked()
    {
        DocumentationFile file = Parse("""
            ;; The file.

            ; An ordinary comment.
            LABEL:
                rts
            ;; Separated by a blank line.

            OTHER:
                rts
            ;; Above an instruction.
                nop
            ;; Above a plain comment.
            ; plain
            THIRD:
                rts
                nop                             ;; trailing on an instruction
            """);

        file.Comments.Single().Kind.Should().Be(DocumentationKind.File);
        file.Diagnostics.Select(diagnostic => diagnostic.Line).Should().Equal(5, 9, 11, 15);
        file.Diagnostics.Should().AllSatisfy(diagnostic => diagnostic.Severity.Should().Be(DocumentationSeverity.Error));
    }

    /// <summary>
    ///  Each kind of definition is recognized, with members, parameters, trailing comments and stacked labels.
    /// </summary>
    [TestMethod]
    public void DefinitionKindsAreRecognized()
    {
        DocumentationFile file = Parse("""
            ;; Return, with bit 7 set.
            KEY_CR = $8D
            KEY_ESC = $9B                       ;; Escape.
            ;; A counter.
            .set COUNT, 0
            ;; Packs two modes.
            ;; Parameters: low = the first mode, high = the second
            .macro PAIR low, high
                .byte low | high << 4
            .endmacro
            ;; Addressing modes.
            .enum AM
            IMP
            IMM                                 ;; #$nn
            .endenum
            ;; The table.
            TABLE:
                PAIR 1, 2
            ;; The routine.
            START:
            START1:
                rts
            """);

        file.Diagnostics.Should().BeEmpty();
        file.Comments.Select(comment => (comment.Name, comment.Kind)).Should().Equal(
            ("KEY_CR", DocumentationKind.Constant),
            ("KEY_ESC", DocumentationKind.Constant),
            ("COUNT", DocumentationKind.Variable),
            ("PAIR", DocumentationKind.Macro),
            ("AM", DocumentationKind.Enum),
            ("AM::IMM", DocumentationKind.Member),
            ("TABLE", DocumentationKind.Table),
            ("START", DocumentationKind.Routine));

        file.Comments.Single(comment => comment.Name == "PAIR").Parameters.Should().Equal("low", "high");
        file.Comments.Single(comment => comment.Name == "AM").Members.Should().Equal("IMP", "IMM");
        file.Comments.Single(comment => comment.Name == "START").Aliases.Should().Equal("START1");
        file.Comments.Single(comment => comment.Name == "AM::IMM").IsTrailing.Should().BeTrue();
    }

    /// <summary>
    ///  Links, URLs and references are found, and comparisons are not links.
    /// </summary>
    [TestMethod]
    public void LinksAndReferencesAreFound()
    {
        List<DocumentationLink> links = DocumentationText.Links(
            "See <COUT>, <the hook at CSWL>, https://example.com/x. and A < 10, X <= Y, <$FDED>.");

        links.Select(link => (link.Text, link.Target)).Should().Equal(
            ("COUT", "COUT"),
            ("the hook", "CSWL"),
            ("https://example.com/x", "https://example.com/x"),
            ("$FDED", "$FDED"));

        DocumentationText.References("Returns {A}, keeps {X}.").Select(reference => reference.Name).Should().Equal("A", "X");
    }

    /// <summary>
    ///  Topics documented in both branches of an .if merge, keeping what differs per branch.
    /// </summary>
    [TestMethod]
    public void ConditionalBranchesMerge()
    {
        DocumentationSet set = Set("""
            ENHANCED = 1
            .if ENHANCED
            ;; Gets a key.
            ;; Out:   A = the key
            ;; Keeps: X
            GETKEY:
                rts
            .else
            ;; Gets a key.
            ;; Out:   A = the key
            ;; Keeps: X, Y
            GETKEY:
                nop
                rts
            .endif
            """);

        DocumentationTopic topic = Required(set.Find("GETKEY"));
        topic.Comments.Should().HaveCount(2);
        topic.SectionsNamed("Out").Should().ContainSingle().Which.Condition.Should().BeNull();
        topic.SectionsNamed("Keeps").Select(section => section.Condition).Should().Equal("ENHANCED", "not ENHANCED");
        DocumentationResolver.ModelOf("not ENHANCED").Should().Be("Original");
        topic.Value.Should().Be(0x1000);
    }

    /// <summary>
    ///  Links resolve through scopes, modules, addresses, models and sections, and report what they cannot.
    /// </summary>
    [TestMethod]
    public void LinksResolve()
    {
        DocumentationSet monitor = DocumentationSet.Create(
            [DocumentationParser.Parse(";; Prints A.\nCOUT = $FDED\n", "Monitor.asm")],
            Assemble("COUT = $FDED\n"),
            module: "Monitor");

        DocumentationSet set = Set("""
            ;; Calls <COUT>.
            .proc Outer
            ;; Inner routine; see <Helper>, <::Top>, <Monitor:COUT>, <$1001>, <Top#Keeps>, <.byte>, <lda>, <Missing>.
            Inner:
                rts
            ;; A helper.
            Helper:
                rts
            .endproc
            ;; Top.
            Top:
                rts
            """);

        DocumentationResolver resolver = new(
            set,
            [monitor],
            isDirective: name => name == ".byte",
            isInstruction: name => name.Equals("lda", StringComparison.OrdinalIgnoreCase));

        DocumentationTopic inner = Required(set.Find("Outer::Inner"));
        Required(resolver.Resolve(inner, "COUT").Topic).Set.Should().BeSameAs(monitor);
        resolver.Resolve(inner, "Monitor:COUT").Value.Should().Be(0xFDED);
        resolver.Resolve(inner, "$1001").Name.Should().Be("Outer::Helper");
        resolver.Resolve(inner, "Top#Keeps").Section.Should().Be("Keeps");
        resolver.Resolve(inner, ".byte").Kind.Should().Be(DocumentationTargetKind.Directive);
        resolver.Resolve(inner, "lda").Kind.Should().Be(DocumentationTargetKind.Instruction);
        resolver.Resolve(inner, "Missing").Kind.Should().Be(DocumentationTargetKind.Unresolved);
        resolver.Check().Select(diagnostic => diagnostic.Message).Should().ContainSingle()
            .Which.Should().Contain("'Missing'");
    }

    /// <summary>
    ///  Inherit takes the target's documentation, the topic's own parts win, and sections can be chosen.
    /// </summary>
    [TestMethod]
    public void InheritMergesDocumentation()
    {
        DocumentationSet set = Set("""
            ;; Reads a line after printing the prompt.
            ;; In:   PROMPT = the prompt character
            ;; Out:  X = the length
            ;; Uses: A, Y
            ;; Entry: GETLN1 = skips the prompt
            GETLN:
                nop
            GETLN1:
                rts
            ;; Inherit:
            ;; Does not print the prompt first.
            ;; Uses: A
            GETLN2:
                rts
            ;; Inherit: <GETLN> Out
            ONLY:
                rts
            ;; Inherit: <LOOP2>
            LOOP1:
                rts
            ;; Inherit: <LOOP1>
            LOOP2:
                rts
            """);

        DocumentationResolver resolver = new(set);
        DocumentationTopic second = resolver.Effective(Required(set.Find("GETLN2")));
        second.Summary.Should().BeEmpty("a bare Inherit names the routine this label is an entry of");

        DocumentationTopic only = resolver.Effective(Required(set.Find("ONLY")));
        only.Summary.Should().Be("Reads a line after printing the prompt.");
        only.Sections.Select(section => section.Name).Should().Equal("Out");
        Required(only.InheritedFrom).Name.Should().Be("GETLN");

        List<DocumentationDiagnostic> diagnostics = resolver.Check();
        List<string> messages = [.. diagnostics.Select(diagnostic => diagnostic.Message)];
        messages.Should().Contain(message => message.Contains("documented routine", StringComparison.Ordinal));
        messages.Should().Contain(message => message.Contains("inherits from itself", StringComparison.Ordinal));
    }

    /// <summary>
    ///  An entry label inherits from the routine that lists it.
    /// </summary>
    [TestMethod]
    public void EntryLabelsInheritTheirRoutine()
    {
        DocumentationSet set = Set("""
            ;; Reads a line.
            ;; Out:   X = the length
            ;; Entry: GETLN1 = skips the prompt
            GETLN:
                nop
            ;; Inherit:
            ;; Skips the prompt.
            GETLN1:
                rts
            """);

        DocumentationResolver resolver = new(set);
        DocumentationTopic topic = resolver.Effective(Required(set.Find("GETLN1")));
        topic.Summary.Should().Be("Reads a line.");
        topic.Remarks.Should().Equal("Skips the prompt.");
        Required(topic.Section("Out")).Entries.Single().Name.Should().Be("X");
        resolver.Check().Select(diagnostic => diagnostic.Message).Should().BeEmpty();
    }

    /// <summary>
    ///  Include takes a topic from a documentation text file.
    /// </summary>
    [TestMethod]
    public void IncludeReadsTextTopics()
    {
        Dictionary<string, string> files = new(StringComparer.OrdinalIgnoreCase)
        {
            [Path.GetFullPath("docs/shared.txt")] = "Routine: Shared\nShared summary.\nKeeps: X\n\nTopic: Other\nOther text.\n"
        };

        DocumentationSet set = Set(";; Include: <docs/shared.txt#Shared>\nUSES:\n    rts\n", "main.asm");
        DocumentationResolver resolver = new(
            set,
            readText: path => files.TryGetValue(path, out string? text) ? text : null);

        DocumentationTopic topic = resolver.Effective(Required(set.Find("USES")));
        topic.Summary.Should().Be("Shared summary.");
        Required(topic.Section("Keeps")).Items.Should().Equal("X");
        resolver.Check().Should().BeEmpty();
    }

    /// <summary>
    ///  Section entries are checked against registers, flags, symbols, parameters, members and references.
    /// </summary>
    [TestMethod]
    public void SectionsAreChecked()
    {
        DocumentationSet set = Set("""
            BUFFER = $0200
            ;; Fills {COUNT} bytes, {R}.
            ;; In:    A = the value, X = the count, BUFFER+1 = where, Q2 = unknown
            ;; Out:   C = set on error, zero = done
            ;; Flags: carry = set on error
            ;; Keeps: Y and X, none
            FILL:
                rts
            ;; A macro.
            ;; Parameters: value = what, missing = nothing
            .macro M value
            .endmacro
            """);

        List<string> messages = [.. new DocumentationResolver(set).Check().Select(diagnostic => diagnostic.Message)];
        messages.Should().Contain(message => message.Contains("{COUNT}", StringComparison.Ordinal));
        messages.Should().Contain(message => message.Contains("{R}", StringComparison.Ordinal));
        messages.Should().Contain(message => message.Contains("'Q2'", StringComparison.Ordinal));
        messages.Should().Contain("Out: name the C flag by its word, 'carry'; letters are only for registers.");
        messages.Should().Contain(message => message.StartsWith("Flags: name flags in In or Out", StringComparison.Ordinal));
        messages.Should().Contain(message => message.Contains("'Y and X'", StringComparison.Ordinal));
        messages.Should().Contain(message => message.Contains("'missing' is not a parameter", StringComparison.Ordinal));
        messages.Should().HaveCount(7);
    }

    /// <summary>
    ///  Registers and flags are the routine's own CPU's: on the Z80, C is a register and the flags are words; a
    ///  flag's letter, a branch condition and another CPU's register are not.
    /// </summary>
    [TestMethod]
    public void RegistersAndFlagsFollowTheCpu()
    {
        DocumentationSet set = Set("""
            .cpu Z80
            ;; Looks for a line.
            ;; In:    C = the count, C'H'L' = the mantissa
            ;; Out:   zero = found, carry = past the end, half-carry = a nibble carry, parity = even
            ROUTINE:
                ret
            ;; Looks again.
            ;; Out:   Z = found, NZ = not found, X = a 6502 register
            AGAIN:
                ret
            """);

        List<string> messages = [.. new DocumentationResolver(set).Check().Select(diagnostic => diagnostic.Message)];
        messages.Should().BeEquivalentTo(
            "Out: name the Z flag by its word, 'zero'; letters are only for registers.",
            "Out: 'NZ' is not a register, flag or symbol.",
            "Out: 'X' is not a register, flag or symbol.");
    }

    /// <summary>
    ///  On the 6502, the Z80's words and registers are unknown.
    /// </summary>
    [TestMethod]
    public void M6502DoesNotTakeZ80Names()
    {
        DocumentationSet set = Set("""
            ;; Moves a byte.
            ;; In:    HL = the source
            ;; Out:   carry = set on error, overflow = signed overflow, subtract = no
            ROUTINE:
                rts
            """);

        List<string> messages = [.. new DocumentationResolver(set).Check().Select(diagnostic => diagnostic.Message)];
        messages.Should().BeEquivalentTo(
            "In: 'HL' is not a register, flag or symbol.",
            "Out: 'subtract' is not a register, flag or symbol.");
    }

    /// <summary>
    ///  Each CPU's flags have words and a description, which hover text shows with the CPU's own letter.
    /// </summary>
    [TestMethod]
    public void FlagsHaveWordsAndDescriptions()
    {
        // The undocumented flags, the Z80's X and Y and the 8085's K and V, have no words.
        foreach ((Retrocore.Isa.IsaDescription description, string[] undocumented) in
            (ValueTuple<Retrocore.Isa.IsaDescription, string[]>[])[
                (Retrocore.Cpu.M6502.M6502Isa.Description, []),
                (Retrocore.Cpu.Z80.Z80Isa.Description, ["X", "Y"]),
                (Retrocore.Cpu.M6809.M6809Isa.Description, []),
                (Retrocore.Cpu.I8080.I8080Isa.Description, ["K", "V"])])
        {
            foreach (Retrocore.Isa.IsaFlag flag in description.Flags.Where(flag => !undocumented.Contains(flag.Name)))
            {
                flag.Words.Should().NotBeEmpty(flag.Name);
                flag.Description.Should().NotBeEmpty(flag.Name);
            }
        }

        DocumentationCpu z80 = DocumentationCpu.For(Retrocore.Cpu.Z80.Z80Isa.Description);
        Retrocore.Isa.IsaFlag parity = z80.Flag("parity") ?? throw new AssertFailedException("parity");
        z80.Flag("overflow").Should().BeSameAs(parity);
        DocumentationCpu.Describe("parity", parity).Should().StartWith("**parity (P/V) flag**: ");
        Retrocore.Isa.IsaFlag negative = z80.Flag("negative") ?? throw new AssertFailedException("negative");
        DocumentationCpu.Describe("negative", negative).Should().StartWith("**negative (S) flag**: ");
    }

    /// <summary>
    ///  Exported symbols need documentation, their own or as an entry of a documented routine.
    /// </summary>
    [TestMethod]
    public void UndocumentedExportsAreReported()
    {
        DocumentationSet set = Set("""
            .export Documented, Entered, Bare
            ;; A routine.
            ;; Entry: Entered = skips a byte
            Documented:
                nop
            Entered:
                rts
            Bare:
                rts
            """);

        new DocumentationResolver(set).Check().Select(diagnostic => (diagnostic.Message, diagnostic.Line)).Should().Equal(
            ("Exported 'Bare' has no ;; documentation.", 7));
    }

    private static T Required<T>(T? value) where T : class =>
        value ?? throw new AssertFailedException("Expected a value.");

    private static DocumentationFile Parse(string text) => DocumentationParser.Parse(text, "test.asm");

    private static DocumentationSet Set(string text, string path = "test.asm") =>
        DocumentationSet.Create([DocumentationParser.Parse(text, path)], Assemble(text));

    private static AssemblyResult Assemble(string text) =>
        new NativeAssembler().Assemble(
            new AssemblySource(text, "test.asm"),
            new AssemblyOptions(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: 0x100));
}
