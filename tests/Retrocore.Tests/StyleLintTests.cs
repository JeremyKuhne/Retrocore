// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Documentation;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  The style guide's checks (docs/AssemblyStyle.md), which a source opts in to with
///  <c>; retrocore: style=strict</c> on its first line.
/// </summary>
[TestClass]
public sealed class StyleLintTests
{
    private const string Pragma = "; retrocore: style=strict\n";

    /// <summary>
    ///  A source in the style has no problems, and the pragma changes nothing it assembles to.
    /// </summary>
    [TestMethod]
    public void TheStyleIsClean()
    {
        string text = Pragma + """
            .cpu Mos6502
            .org $0300

            ;; The Apple II's carriage return, with its high bit set.
            RETURN = $8D

            ;; Prints a carriage return through <Print>.
            .proc PrintReturn
                lda #RETURN

                ; Then print it, by a jump where the build allows.
            .if RETURN = $8D
                jmp Print
            .else
                jsr Print
                rts
            .endif
            .endproc

            ;; Prints a character.
            ;; In: A = the character
            .proc Print
            Loop:
                rts
            .endproc

            ;; Two return characters.
            ;; Parameters:
            ;;   count = how many
            .macro Returns count
                .repeat count
                    .byte RETURN
                .endrepeat
            .endmacro

            ;; A table.
            Table:
                Returns 2
            """;

        Problems(text).Should().BeEmpty();
        Assemble(text).Diagnostics.Should().BeEmpty();
        Assemble(text).Sections[0].Bytes.ToArray().Should().Equal(Assemble(text[Pragma.Length..]).Sections[0].Bytes.ToArray());
    }

    /// <summary>
    ///  A source without the pragma is not checked against the style.
    /// </summary>
    [TestMethod]
    public void OnlyStrictSourcesAreChecked()
    {
        DocumentationParser.Parse("Start: lda #0 ;; loads\n", "test.asm").Diagnostics.Should().BeEmpty();
        DocumentationParser.Parse(Pragma + "Start: lda #0\n", "test.asm").Strict.Should().BeTrue();
        DocumentationParser.IsStrict("; retrocore: dialect=native style=strict\n").Should().BeTrue();
        DocumentationParser.IsStrict("; retrocore: dialect=native\n").Should().BeFalse();
    }

    /// <summary>
    ///  Each line rule reports its problem: trailing documentation, a label sharing a line, a name that is only an
    ///  address, non-ASCII, a long line, and indentation of code, definitions, comments and macro bodies.
    /// </summary>
    [TestMethod]
    public void LineRulesAreReported()
    {
        string text = Pragma + $"""
            .cpu Mos6502
            .org $0300
            RETURN = $8D ;; trailing
            Start: lda #RETURN
            ;; A routine.
            L_F8C2:
                rts
            ;; Ends with a dash — here.
            Value = 1
            ;; {new string('x', 120)}
            Other = 2
            lda #0
                Indented = 3
                ; a misplaced heading
            .proc Proc
                ldx #0
              ; also misplaced
                rts
            .endproc
            ;; A macro.
            .macro Bad
            .byte 0
            .endmacro
            """;

        Problems(text).Should().BeEquivalentTo(
            "4: Put ;; documentation above the definition, not after it.",
            "5: Put the label Start on its own line.",
            "7: Name L_F8C2 for what it is: a name that is only an address says nothing.",
            "9: Write plain ASCII: 'times' rather than a multiplication sign, '-' rather than a dash.",
            "11: Line is over 120 columns.",
            "13: Indent instructions and data 4 columns.",
            "14: Put definitions, labels and block directives at column 0.",
            "15: Indent this comment like the code it describes (0 columns).",
            "18: Indent this comment like the code it describes (4 columns).",
            "23: Indent this line of the macro 4 columns.");
    }

    /// <summary>
    ///  Prose that names a documented definition without linking it is reported; links, code spans, entry names,
    ///  instructions, a capitalized word starting a sentence and a historical name (from an Also: section) are not.
    /// </summary>
    [TestMethod]
    public void UnlinkedNamesAreReported()
    {
        string text = Pragma + """
            .cpu Mos6502
            .org $0300

            ;; Prints a character.
            ;; In: A = the character
            ;; Also: OUT (TEST)
            .proc Print
                rts
            .endproc

            ;; The table PrintTable reads.
            .proc Table
                rts
            .endproc

            ;; Prints a line with Print, then `Print` and <Print> again. Table it is. The listing called it OUT.
            ;; In: A = the line, LDA = an instruction
            ;; Errors: Table = not a link
            .proc PrintTable
                rts
            .endproc
            """;

        Problems(text).Should().BeEquivalentTo(
            "12: Link PrintTable as <PrintTable>: it names a documented definition.",
            "17: Link Print as <Print>: it names a documented definition.");
    }

    /// <summary>
    ///  Cheap-local and anonymous labels are labels: alone at column 0 they are clean, and with code after them
    ///  they belong on their own line.
    /// </summary>
    [TestMethod]
    public void LocalAndAnonymousLabelsAreLabels()
    {
        string text = Pragma + """
            .cpu Mos6502
            .org $0300

            ;; Counts X down to zero.
            .proc CountDown
            @loop:
                dex
                bne @loop
            :
                dex
                bne :-
            @again: dex
                rts
            .endproc
            """;

        Problems(text).Should().BeEquivalentTo("13: Put the label @again on its own line.");
    }

    /// <summary>
    ///  A word that looks like a one-letter prefix and four hex letters (LACED, DECAF) is not an address name; one
    ///  with a digit (LF8C2) is.
    /// </summary>
    [TestMethod]
    public void WordsAreNotAddressNames()
    {
        string text = Pragma + """
            .cpu Mos6502
            .org $0300

            ;; Laced, as a word.
            LACED = 1

            ;; An address as a name.
            LF8C2 = 2

            ;; A union named for an address.
            .union L_F8C3
                ;; One.
                ONE .byte
            .endunion
            """;

        Problems(text).Where(problem => problem.Contains("only an address", StringComparison.Ordinal)).Should()
            .BeEquivalentTo(
                "9: Name LF8C2 for what it is: a name that is only an address says nothing.",
                "12: Name L_F8C3 for what it is: a name that is only an address says nothing.");
    }

    /// <summary>
    ///  Inside a type, members are one level in and a nested type's members one more, with the nested type's own
    ///  lines at its parent's member level; a member's block sits at its indentation, and a member may have a
    ///  trailing <c>;;</c> comment instead.
    /// </summary>
    [TestMethod]
    public void NestedTypesAreIndentedByLevel()
    {
        string text = Pragma + """
            .cpu Mos6502
            .org $0300

            ;; A pair.
            .struct Pair
                LOW .byte ;; The low byte.
                HIGH .byte ;; The high byte.
            .endstruct

            ;; An I/O block.
            .struct Iob
                ;; The block's type.
                TYPE .byte
                .union
                    ;; The command, before the call.
                    COMMAND .byte
                    ;; The status, after it.
                    STATUS .byte
                .endunion
                NEST .struct Nested ;; A nested part, documented by its member.
                    ;; Its byte.
                    BYTE .byte
                .endstruct
                ;; Where.
                WHERE .tag Pair
                ;; A nested type.
                .struct Inner
                    ;; Inside it.
                    DEEP .byte
                    ; More fields go here.
                .endstruct
                ; Reserved.
            .endstruct

            ;; The commands.
            .enum Command
                SEEK ;; Seek only.
                ;; Read.
                READ
            .endenum

            ;; A union at the top.
            .union Either
                ;; One.
                ONE .byte
                ;; Two.
                TWO .word
            .endunion
            """;

        Problems(text).Should().BeEmpty();
        Assemble(text).Diagnostics.Should().BeEmpty();
    }

    /// <summary>
    ///  A type's lines indented for the wrong level are reported, and so are their comments.
    /// </summary>
    [TestMethod]
    public void NestedTypesIndentedWronglyAreReported()
    {
        string text = Pragma + """
            .cpu Mos6502
            .org $0300

            ;; An I/O block.
            .struct Iob
              ;; The block's type.
              TYPE .byte
                .union
                ;; The command.
                COMMAND .byte
                    ;; The status.
                    STATUS .byte
                    .endunion
            .endstruct

                ;; A union.
                .union Either
                ;; One.
                ONE .byte
                .endunion

            ;; A type.
            .struct Marked
                .org 4 ;; Not a member either.
                .union ;; Not a member.
                    ;; A member.
                    MEMBER .byte
                .endunion
            .endstruct
            """;

        Problems(text).Should().BeEquivalentTo(
            "8: Indent this line 4 columns: a type's members one level in, a nested type's one more.",
            "11: Indent this line 8 columns: a type's members one level in, a nested type's one more.",
            "14: Indent this line 4 columns: a type's members one level in, a nested type's one more.",
            "18: Put definitions, labels and block directives at column 0.",
            "21: Put definitions, labels and block directives at column 0.",
            "25: Put ;; documentation above the definition, not after it.",
            "25: A trailing documentation comment must follow a definition, such as a constant or member.",
            "26: Put ;; documentation above the definition, not after it.",
            "26: A trailing documentation comment must follow a definition, such as a constant or member.");
    }

    // The problems the editor reports for one strict file, as "line: message" with 1-based lines.
    private static List<string> Problems(string text)
    {
        DocumentationFile file = DocumentationParser.Parse(text, "test.asm");
        DocumentationSet set = DocumentationSet.Create([file], Assemble(text));
        DocumentationResolver resolver = new(set, isInstruction: name => name.Equals("LDA", StringComparison.OrdinalIgnoreCase));
        return [.. resolver.Check().Select(diagnostic => $"{diagnostic.Line + 1}: {diagnostic.Message}")];
    }

    private static AssemblyResult Assemble(string text) =>
        new NativeAssembler().Assemble(
            new AssemblySource(text, "test.asm"),
            new AssemblyOptions(ProcessorVariant.Mos6502, origin: 0x0300, imageSize: 0x100));
}
