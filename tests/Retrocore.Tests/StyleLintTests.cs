// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Assembler;
using Retrocore.Debug.Language;
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
    ///  A constant defined with <c>:=</c>, spaced or not, follows the rules of one defined with <c>=</c>: it is a
    ///  definition at column 0, not code to indent or a label sharing its line, and its name is checked.
    /// </summary>
    [TestMethod]
    public void ColonEqualsConstantsAreDefinitions()
    {
        string text = Pragma + """
            .cpu Mos6502
            .org $0300

            ;; The Apple II's carriage return, with its high bit set.
            RETURN := $8D

            ;; The width of a line.
            WIDTH:=40

            ;; An address.
            L_F8C2 := 1
                Indented := 3

            ;; Prints a carriage return.
            .proc PrintReturn
                lda #RETURN
                ldx #WIDTH
                rts
            .endproc
            """;

        Problems(text).Should().BeEquivalentTo(
            "12: Name L_F8C2 for what it is: a name that is only an address says nothing.",
            "13: Put definitions, labels and block directives at column 0.");
    }

    /// <summary>
    ///  A constant or variable defined with a colon and <c>.equ</c> or <c>.set</c> follows the rules of one defined
    ///  with <c>=</c>: it is a definition at column 0, not a label sharing its line, and its name is checked.
    /// </summary>
    [TestMethod]
    public void ColonDirectiveConstantsAreDefinitions()
    {
        string text = Pragma + """
            .cpu Mos6502
            .org $0300

            ;; The Apple II's carriage return, with its high bit set.
            RETURN: .equ $8D

            ;; The width of a line.
            WIDTH: .set 40

            ;; An address.
            L_F8C2: .equ 1
                Indented: .equ 3

            ;; Prints a carriage return.
            .proc PrintReturn
                lda #RETURN
                ldx #WIDTH
            Loop: rts
            .endproc
            """;

        Problems(text).Should().BeEquivalentTo(
            "12: Name L_F8C2 for what it is: a name that is only an address says nothing.",
            "13: Put definitions, labels and block directives at column 0.",
            "19: Put the label Loop on its own line.");
    }

    /// <summary>
    ///  Prose that names a documented definition without linking it is reported; links, code spans, entry names,
    ///  instructions, a capitalized word starting a sentence, a scope's name and a historical name (from an Also: section)
    ///  are not.
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

            ;; Code that runs under Pascal.
            .scope Pascal
            .endscope

            ;; Prints a line with Print, then `Print` and <Print> again. Table it is. The listing called it OUT.
            ;; It runs under Pascal's rules: a scope's name in prose is a plain word.
            ;; In: A = the line, LDA = an instruction
            ;; Errors: Table = not a link
            .proc PrintTable
                rts
            .endproc
            """;

        Problems(text).Should().BeEquivalentTo(
            "12: Link PrintTable as <PrintTable>: it names a documented definition.",
            "21: Link Print as <Print>: it names a documented definition.");
    }

    /// <summary>
    ///  Configured prose words need no link, but names are case-sensitive and other names are still checked.
    /// </summary>
    [TestMethod]
    public void ConfiguredWordsAreNotReportedAsUnlinkedNames()
    {
        string text = Pragma + """
            .cpu Mos6502
            .org $0300

            ;; The ROM flag.
            ROM = 1

            ;; A differently cased name.
            Rom = 2

            ;; Reads ROM and Rom, then calls Print; see <ROM> and <Missing>.
            .proc Start
                rts
            .endproc

            ;; Prints.
            .proc Print
                rts
            .endproc
            """;

        Lint(text).Where(diagnostic => diagnostic.Rule == DocumentationRules.UnlinkedName)
            .Select(diagnostic => diagnostic.Name).Should().BeEquivalentTo("ROM", "Rom", "Print");

        List<DocumentationDiagnostic> configured = Lint(text, new HashSet<string>(["ROM", "Missing"], StringComparer.Ordinal));
        configured
            .Where(diagnostic => diagnostic.Rule == DocumentationRules.UnlinkedName)
            .Select(diagnostic => diagnostic.Name).Should().BeEquivalentTo("Rom", "Print");

        configured.Should().ContainSingle(diagnostic => diagnostic.Rule == DocumentationRules.Link && diagnostic.Name == "Missing");
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

    /// <summary>
    ///  The rules are the spec's, and each diagnostic the parser and resolver produce carries one of them.
    /// </summary>
    [TestMethod]
    public void EveryDiagnosticHasARuleFromTheTable()
    {
        DocumentationRules.All.Select(rule => rule.Id).Should().Equal(
            "line-length", "ascii", "trailing-doc", "label-alone", "address-name", "column-zero", "indent",
            "comment-indent", "unlinked-name", "link", "ambiguous-link", "also", "sections", "historical-name",
            "deprecated", "using-shadow", "undocumented-export", "placement", "exclusion");

        DocumentationRules.All.Where(rule => !rule.Ignorable).Select(rule => rule.Id).Should().Equal("placement", "exclusion");

        string text = Pragma + $"""
            .cpu Mos6502
            .org $0300
            RETURN = $8D ;; trailing
            Start: lda #RETURN
            ;; A routine, with <Nowhere>.
            ;; In: Q = a register no CPU has
            ;; Also: BAD FORM
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
            ;; Documents nothing.

            ; retrocore: ignore=nothing-at-all
            """;

        List<DocumentationDiagnostic> diagnostics = Lint(text);
        diagnostics.Should().NotBeEmpty();
        diagnostics.Should().AllSatisfy(diagnostic => DocumentationRules.Find(diagnostic.Rule).Should().NotBeNull(diagnostic.Message));
        Rules(text).Should().BeEquivalentTo(
            "4: trailing-doc",
            "5: label-alone Start",
            "6: link Nowhere",
            "7: sections",
            "8: also",
            "9: address-name L_F8C2",
            "11: ascii",
            "13: line-length",
            "15: indent",
            "16: column-zero",
            "17: comment-indent",
            "20: comment-indent",
            "25: indent",
            "27: placement",
            "29: exclusion");

        diagnostics.First(diagnostic => diagnostic.Rule == "line-length").Text.Should().Be("Line is over 120 columns. [line-length]");

        // The rules of names: an unlinked documented name, and an export without documentation.
        string names = Pragma + """
            .cpu Mos6502
            .org $0300
            .export Hidden

            ;; Prints.
            .proc Print
                rts
            .endproc

            ;; Calls Print.
            .proc Caller
                rts
            .endproc

            Hidden:
                rts
            """;

        Rules(names).Should().BeEquivalentTo("11: unlinked-name Print", "16: undocumented-export");
    }

    /// <summary>
    ///  An exclusion on the first line turns a rule off in the whole file, and the other rules stay on.
    /// </summary>
    [TestMethod]
    public void AFileExclusionIgnoresItsRuleInTheFile()
    {
        string text = $"""
            ; retrocore: style=strict ignore=line-length -- the table lines up with the listing
            .cpu Mos6502
            .org $0300
            ;; {new string('x', 120)}
            Value = 1
                .byte 0 ; {new string('x', 120)}
            Start: lda #0
            """;

        Rules(text).Should().BeEquivalentTo("7: label-alone Start");
    }

    /// <summary>
    ///  A file exclusion needs no style=strict: it turns off the rules that run without it too.
    /// </summary>
    [TestMethod]
    public void AFileExclusionNeedsNoStyle()
    {
        string text = """
            ; retrocore: ignore=link
            .cpu Mos6502
            .org $0300
            ;; Calls <Nowhere>.
            Start:
                rts
            """;

        Rules(text).Should().BeEmpty();
        Rules(text[(text.IndexOf('\n') + 1)..]).Should().BeEquivalentTo("3: link Nowhere");
    }

    /// <summary>
    ///  A line's own trailing pragma turns a rule off on that line only.
    /// </summary>
    [TestMethod]
    public void ALineExclusionIgnoresOnlyItsLine()
    {
        string data = string.Join(", ", Enumerable.Repeat("$C1", 26));
        string text = Pragma + $"""
            .cpu Mos6502
            .org $0300
            ;; The table.
            Table:
                .byte {data} ; retrocore: ignore=line-length -- the listing's columns
                .byte {data}
            """;

        Rules(text).Should().BeEquivalentTo("7: line-length");
    }

    /// <summary>
    ///  A pragma line above a ;; block turns a rule off for that block, not for the definition's code below it or
    ///  another block.
    /// </summary>
    [TestMethod]
    public void ACommentExclusionIgnoresOnlyItsBlock()
    {
        string text = Pragma + $"""
            .cpu Mos6502
            .org $0300

            ;; Runs.
            .proc Run
                rts
            .endproc

            ; retrocore: ignore=unlinked-name:Run,line-length -- Run is the verb here
            ;; Start makes Run go.
            ;; {new string('x', 120)}
            .proc Start
                lda #0 ; {new string('x', 120)}
                rts
            .endproc

            ;; Stop makes Run halt.
            .proc Stop
                rts
            .endproc
            """;

        Rules(text).Should().BeEquivalentTo("14: line-length", "18: unlinked-name Run");
    }

    /// <summary>
    ///  Narrowing a rule to names turns it off for those names only, and a name on a rule that reports none is an
    ///  error.
    /// </summary>
    [TestMethod]
    public void NarrowingByNameIgnoresOnlyThoseNames()
    {
        string text = Pragma + """
            .cpu Mos6502
            .org $0300

            ;; Prints.
            .proc Print
                rts
            .endproc

            ;; Clears.
            .proc Clear
                rts
            .endproc

            ; retrocore: ignore=unlinked-name:Print|Home
            ;; Uses Print and Clear.
            .proc Both
                rts
            .endproc
            """;

        Rules(text).Should().BeEquivalentTo("16: unlinked-name Clear", "15: exclusion unlinked-name:Home");
        string named = text.Replace("unlinked-name:Print|Home", "unlinked-name:Print,line-length:Wide", StringComparison.Ordinal);
        Lint(named).Should().ContainSingle(diagnostic => diagnostic.Rule == "exclusion")
            .Which.Should().Match<DocumentationDiagnostic>(diagnostic =>
                diagnostic.Message == "line-length takes no names." && diagnostic.Severity == DocumentationSeverity.Error);
    }

    /// <summary>
    ///  An unknown rule warns, an exclusion that turns nothing off is information, and errors can't be ignored:
    ///  naming a rule of errors only is an error, and a file exclusion of it leaves the errors.
    /// </summary>
    [TestMethod]
    public void ExclusionsReportTheirOwnProblems()
    {
        string body = """
            .cpu Mos6502
            .org $0300
            ;; Documents nothing.

            Start:
                rts
            """;

        List<DocumentationDiagnostic> unknown = Lint("; retrocore: ignore=line-lenght\n" + body);
        unknown.Should().ContainSingle(diagnostic => diagnostic.Rule == "exclusion")
            .Which.Should().Match<DocumentationDiagnostic>(diagnostic =>
                diagnostic.Message == "No lint rule named 'line-lenght'." && diagnostic.Severity == DocumentationSeverity.Warning);

        List<DocumentationDiagnostic> unused = Lint("; retrocore: ignore=ascii\n" + body);
        unused.Should().ContainSingle(diagnostic => diagnostic.Rule == "exclusion")
            .Which.Should().Match<DocumentationDiagnostic>(diagnostic =>
                diagnostic.Message == "Nothing here breaks ascii; remove the exclusion."
                    && diagnostic.Severity == DocumentationSeverity.Information
                    && diagnostic.Line == 0);

        List<DocumentationDiagnostic> errors = Lint("; retrocore: ignore=placement,exclusion\n" + body);
        errors.Where(diagnostic => diagnostic.Rule == "exclusion").Select(diagnostic => (diagnostic.Message, diagnostic.Severity))
            .Should().BeEquivalentTo([
                ("placement reports only errors, which can't be ignored.", DocumentationSeverity.Error),
                ("exclusion can't be ignored.", DocumentationSeverity.Error)]);

        errors.Should().ContainSingle(diagnostic => diagnostic.Rule == "placement")
            .Which.Severity.Should().Be(DocumentationSeverity.Error);

        // An exclusion that is on neither a line of code nor above a ;; block applies nowhere.
        Rules(Pragma + "Start:\n    ; retrocore: ignore=ascii\n    rts\n").Should().BeEquivalentTo("3: exclusion");
    }

    /// <summary>
    ///  The assembler accepts the exclusion words on the first line, with or without a dialect, and they change no
    ///  bytes.
    /// </summary>
    [TestMethod]
    public void TheAssemblerAcceptsExclusions()
    {
        const string Body = ".cpu Mos6502\n.org $0300\nStart:\n    lda #1 ; retrocore: ignore=line-length\n    rts\n";
        byte[] expected = Assemble(Body).Sections[0].Bytes.ToArray();
        foreach (string pragma in new[]
        {
            "; retrocore: ignore=line-length -- the reason, with = and words\n",
            "; retrocore: dialect=native ignore=unlinked-name:Run|Stop\n",
            "; retrocore: style=strict ignore=line-length,ascii\n"
        })
        {
            AssemblyResult result = Assemble(pragma + Body);
            result.Diagnostics.Should().BeEmpty(pragma);
            result.Sections[0].Bytes.ToArray().Should().Equal(expected, pragma);
        }
    }

    /// <summary>
    ///  The editor shows the rule as the diagnostic's code, and its quick fixes write the exclusion for the line, the
    ///  comment or the file.
    /// </summary>
    [TestMethod]
    public void TheEditorShowsTheRuleAndFixesIt()
    {
        string data = string.Join(", ", Enumerable.Repeat("$C1", 26));
        string text = Pragma + $"""
            .cpu Mos6502
            .org $0300

            ;; Calls <Nowhere>.
            Table:
                .byte {data}
            """;

        List<Diagnostic> diagnostics = [.. Lint(text).Select(diagnostic =>
            LintEditor.ToDiagnostic(diagnostic, new LspRange(diagnostic.Line, 0, diagnostic.Line, 0), replacement: null))];

        diagnostics.Select(diagnostic => (diagnostic.Range.Start.Line, diagnostic.Code, diagnostic.Severity)).Should().BeEquivalentTo([
            (4, "link", DiagnosticSeverity.Warning),
            (6, "line-length", DiagnosticSeverity.Warning)]);

        Diagnostic link = diagnostics.Single(diagnostic => diagnostic.Code == "link");
        Required(link.Data?["name"]).GetValue<string>().Should().Be("Nowhere");
        string[] lines = text.Split('\n');
        const string Uri = "file:///test.asm";
        JsonArray actions = LintEditor.Actions(Uri, lines, [.. diagnostics.Select(diagnostic => (JsonNode)diagnostic.ToJson())]);
        Fixes(actions, Uri, lines).Should().BeEquivalentTo(
            "Ignore link:Nowhere for this comment: " + Join([.. lines[..4], "; retrocore: ignore=link:Nowhere", .. lines[4..]]),
            "Ignore link:Nowhere in this file: " + Join(["; retrocore: style=strict ignore=link:Nowhere", .. lines[1..]]),
            "Ignore line-length on this line: " + Join([.. lines[..6], lines[6] + " ; retrocore: ignore=line-length", .. lines[7..]]),
            "Ignore line-length in this file: " + Join(["; retrocore: style=strict ignore=line-length", .. lines[1..]]));

        // The fixes' exclusions turn the diagnostics off.
        Lint(Join([.. lines[..4], "; retrocore: ignore=link:Nowhere", .. lines[4..]])).Select(diagnostic => diagnostic.Rule)
            .Should().Equal("line-length");

        // An existing pragma takes the rule into its list, before the reason.
        string[] excluded = ["; retrocore: ignore=ascii -- why", "Start:", "    lda #0 ; retrocore: ignore=ascii"];
        Apply(excluded, [LintEditor.File(excluded, "line-length")])[0].Should().Be("; retrocore: ignore=ascii,line-length -- why");
        Apply(excluded, [Required(LintEditor.Here(excluded, 2, "indent")).Edit])[2]
            .Should().Be("    lda #0 ; retrocore: ignore=ascii,indent");

        // Code on the first line takes its own trailing pragma, which the parser reads for that line alone; a ;; block
        // there has no line above it for one.
        string[] first = ["    jsr COUT", "    rts"];
        string[] fixedFirst = Apply(first, [Required(LintEditor.Here(first, 0, "historical-name:COUT")).Edit]);
        fixedFirst[0].Should().Be("    jsr COUT ; retrocore: ignore=historical-name:COUT");
        DocumentationParser.Parse(Join(fixedFirst), "test.asm").Exclusions.Should().ContainSingle()
            .Which.Should().Match<DocumentationExclusion>(exclusion =>
                exclusion.Scope == DocumentationExclusionScope.Line && exclusion.FirstLine == 0 && exclusion.LastLine == 0);

        LintEditor.Here([";; The file.", "Start:"], 0, "link").Should().BeNull();

        // A line whose own comment is not a pragma has no room for one, and errors get no exclusion.
        LintEditor.Here(["", "    lda #0 ; the count"], 1, "indent").Should().BeNull();
        JsonObject error = new()
        {
            ["range"] = new LspRange(1, 0, 1, 0).ToJson(),
            ["severity"] = 1,
            ["code"] = "placement"
        };

        LintEditor.Actions(Uri, lines, [error]).Should().BeEmpty();
    }

    /// <summary>
    ///  The editor completes rule IDs after ignore= and a comma, not after a colon's names or outside a pragma, and
    ///  describes the rule under the cursor.
    /// </summary>
    [TestMethod]
    public void TheEditorCompletesAndDescribesRules()
    {
        Required(LintEditor.Complete("; retrocore: style=strict ignore=", 0)).Select(item => item.Label)
            .Should().Contain(["line-length", "unlinked-name", "historical-name"]).And.NotContain(["placement", "exclusion"]);

        LintEditor.Complete("    lda #0 ; retrocore: ignore=line-length,un", 0).Should().NotBeNull();
        LintEditor.Complete("; retrocore: ignore=unlinked-name:", 0).Should().BeNull();
        LintEditor.Complete("; retrocore: style=strict", 0).Should().BeNull();
        LintEditor.Complete("; ignore=", 0).Should().BeNull();
        LintEditor.Complete("; retrocore: ignore=line-length -- ", 0).Should().BeNull();

        // A completion replaces the whole rule typed so far, hyphen and all.
        const string Typed = "; retrocore: ignore=ascii,line-l";
        Required(LintEditor.Complete(Typed, 3)).Should().AllSatisfy(item => item.Range.Should().Be(new LspRange(3, Typed.Length - 6, 3, Typed.Length)));

        const string Line = "; retrocore: ignore=line-length,unlinked-name:Run -- why";
        (DocumentationRule rule, int start) = Required(LintEditor.RuleAt(Line, Line.IndexOf("length", StringComparison.Ordinal)));
        rule.Id.Should().Be("line-length");
        start.Should().Be(Line.IndexOf("line-length", StringComparison.Ordinal));
        Required(LintEditor.RuleAt(Line, Line.IndexOf("unlinked", StringComparison.Ordinal))).Rule.Id.Should().Be("unlinked-name");
        LintEditor.RuleAt(Line, Line.IndexOf("Run", StringComparison.Ordinal)).Should().BeNull();
        LintEditor.RuleAt("; line-length", 4).Should().BeNull();
    }

    /// <summary>
    ///  A quick fix for a name the pragma's words can't hold ignores the whole rule; one on a line whose string holds
    ///  an apostrophe goes on the line's own comment as the lint reads it; and a historical name's fix still writes
    ///  the current name.
    /// </summary>
    [TestMethod]
    public void TheEditorsFixesFitThePragma()
    {
        string text = Pragma + """
            .cpu Mos6502
            .org $0300

            ;; Calls <see above>.
            Table:
                .byte 0
            """;

        List<DocumentationDiagnostic> lint = Lint(text);
        DocumentationDiagnostic link = lint.Single(diagnostic => diagnostic.Rule == "link");
        link.Name.Should().Be("see above");
        string[] lines = text.Split('\n');
        JsonArray actions = LintEditor.Actions(
            "file:///test.asm",
            lines,
            [(JsonNode)LintEditor.ToDiagnostic(link, new LspRange(link.Line, 0, link.Line, 0), replacement: null).ToJson()]);

        List<string> fixes = Fixes(actions, "file:///test.asm", lines);
        fixes.Should().HaveCount(2).And.AllSatisfy(fix => fix.Should().StartWith("Ignore link "));
        Lint(fixes[0][(fixes[0].IndexOf(": ", StringComparison.Ordinal) + 2)..]).Should().BeEmpty();

        // The apostrophe in "Don't" is not a quote, so the line's comment is its own and has no room for a pragma.
        string[] quoted = ["", "    .byte \"Don't\", 0 ; the message"];
        LintEditor.Here(quoted, 1, "indent").Should().BeNull();
        string[] pragma = ["", "    .byte \"Don't\", 0 ; retrocore: ignore=ascii"];
        Apply(pragma, [Required(LintEditor.Here(pragma, 1, "indent")).Edit])[1].Should().EndWith("ignore=ascii,indent");

        JsonObject historical = new()
        {
            ["range"] = new LspRange(1, 8, 1, 12).ToJson(),
            ["severity"] = 3,
            ["code"] = "historical-name",
            ["data"] = new JsonObject { ["name"] = "COUT", ["replacement"] = "Output" }
        };

        string[] code = ["", "    jsr COUT"];
        JsonArray historicalFixes = LintEditor.Actions("file:///test.asm", code, [historical]);
        Fixes(historicalFixes, "file:///test.asm", code).Should().Equal(
            "Use Output: \n    jsr Output",
            "Ignore historical-name:COUT on this line: \n    jsr COUT ; retrocore: ignore=historical-name:COUT",
            "Ignore historical-name:COUT in this file: ; retrocore: ignore=historical-name:COUT\n\n    jsr COUT");
    }

    /// <summary>
    ///  An unlinked name gets quick fixes that add it to the workspace's or the user's dictionary through the
    ///  client's command, beside the exclusions.
    /// </summary>
    [TestMethod]
    public void TheEditorOffersToAddAnUnlinkedNameToADictionary()
    {
        JsonObject unlinked = new()
        {
            ["range"] = new LspRange(1, 12, 1, 15).ToJson(),
            ["severity"] = 2,
            ["code"] = "unlinked-name",
            ["data"] = new JsonObject { ["name"] = "RAM" }
        };

        JsonArray actions = LintEditor.Actions("file:///test.asm", ["Start:", ";; Copies to RAM."], [unlinked]);
        actions
            .Where(action => action?["command"] is not null)
            .Select(action => $"{Required(action?["title"]).GetValue<string>()}: {Required(action?["command"]).ToJsonString()}")
            .Should().Equal(
            """Add RAM to the workspace dictionary: {"title":"Add RAM to the workspace dictionary","command":"retrocore.lint.addUnlinkedNameWord","arguments":["RAM","workspace"]}""",
            """Add RAM to the user dictionary: {"title":"Add RAM to the user dictionary","command":"retrocore.lint.addUnlinkedNameWord","arguments":["RAM","user"]}""");

        actions.Select(action => Required(action?["title"]).GetValue<string>()).Should().Contain("Ignore unlinked-name:RAM in this file");
    }

    /// <summary>
    ///  An exclusion's own mistakes are reported once each: a colon with no names, an empty list on the first line,
    ///  and a rule written twice.
    /// </summary>
    [TestMethod]
    public void ExclusionMistakesAreReported()
    {
        const string Body = ".cpu Mos6502\n.org $0300\nStart:\n    rts\n";
        Lint("; retrocore: ignore=line-length:\n" + Body).Should().ContainSingle()
            .Which.Message.Should().Be("line-length: names no name; write the names after the colon, or leave the colon out.");

        Lint("; retrocore: ignore=\n" + Body).Should().ContainSingle().Which.Message.Should().Be("ignore= names no rule.");
        Lint("; retrocore: ignore=ascii,ascii\n" + Body).Should().ContainSingle()
            .Which.Message.Should().Be("Nothing here breaks ascii; remove the exclusion.");
    }

    /// <summary>
    ///  An exclusion is reported unused only where the lint could have used it: not for a rule only the editor runs
    ///  when its problems aren't passed in, and not for a block of a definition another build assembles.
    /// </summary>
    [TestMethod]
    public void UnusedIsOnlyReportedWhereTheLintLooked()
    {
        const string Body = ".cpu Mos6502\n.org $0300\nStart:\n    rts\n";
        Lint("; retrocore: ignore=historical-name:COUT,deprecated\n" + Body).Should().BeEmpty();
        DocumentationFile file = DocumentationParser.Parse("; retrocore: ignore=historical-name:COUT\n" + Body, "test.asm");
        DocumentationResolver resolver = new(DocumentationSet.Create([file], Assemble("; retrocore: ignore=historical-name:COUT\n" + Body)));
        resolver.Lint([], DocumentationRules.EditorRules).Should().ContainSingle()
            .Which.Message.Should().Be("Nothing here breaks historical-name:COUT; remove the exclusion.");

        // In LF, so the replacements below find their lines in a checkout with CRLF endings.
        string text = Pragma + """
            .cpu Mos6502
            .org $0300

            ;; Runs.
            .proc Run
                rts
            .endproc

            .if 0
            ; retrocore: ignore=unlinked-name:Run
            ;; Makes Run go.
            Other:
                rts
            .endif
            """.ReplaceLineEndings("\n");

        Lint(text).Should().BeEmpty();

        // The same for the whole file: the build that assembles Other uses the exclusion.
        string wide = text.Replace("; retrocore: ignore=unlinked-name:Run\n", "", StringComparison.Ordinal)
            .Replace(Pragma, "; retrocore: style=strict ignore=unlinked-name:Run\n", StringComparison.Ordinal);

        Lint(wide).Should().BeEmpty();
        Lint(wide.Replace(".if 0", ".if 1", StringComparison.Ordinal)).Should().BeEmpty();
        Lint(wide.Replace("Makes Run go", "Makes it go", StringComparison.Ordinal).Replace(".if 0", ".if 1", StringComparison.Ordinal))
            .Should().ContainSingle().Which.Message.Should().Be("Nothing here breaks unlinked-name:Run; remove the exclusion.");
    }

    // Each quick fix as its title and the text its edits make.
    private static List<string> Fixes(JsonArray actions, string uri, string[] lines) =>
        [.. actions.Select(action =>
        {
            JsonArray edits = Required(action?["edit"]?["changes"]?[uri]?.AsArray());
            return $"{Required(action?["title"]).GetValue<string>()}: {Join(Apply(lines, [.. edits.Select(edit => Required(edit).AsObject())]))}";
        })];

    private static string Join(string[] lines) => string.Join('\n', lines);

    // Applies the quick fixes' edits, each within one line, to lines.
    private static string[] Apply(string[] lines, JsonObject[] edits)
    {
        string text = Join(lines);
        int Offset(JsonNode? position) =>
            lines.Take(Required(position?["line"]).GetValue<int>()).Sum(each => each.Length + 1)
                + Required(position?["character"]).GetValue<int>();

        foreach ((int start, int end, string inserted) in edits
            .Select(edit => (Offset(edit["range"]?["start"]), Offset(edit["range"]?["end"]), Required(edit["newText"]).GetValue<string>()))
            .OrderByDescending(edit => edit.Item1))
        {
            text = text.Remove(start, end - start).Insert(start, inserted);
        }

        return text.Split('\n');
    }

    private static T Required<T>(T? value) where T : class =>
        value ?? throw new InvalidOperationException("A value was expected.");

    private static T Required<T>(T? value) where T : struct =>
        value ?? throw new InvalidOperationException("A value was expected.");

    // The lint as the editor and the tests run it, exclusions applied.
    private static List<DocumentationDiagnostic> Lint(string text, HashSet<string>? words = null)
    {
        DocumentationFile file = DocumentationParser.Parse(text, "test.asm");
        DocumentationSet set = DocumentationSet.Create([file], Assemble(text));
        DocumentationResolver resolver = new(set, isInstruction: name => name.Equals("LDA", StringComparison.OrdinalIgnoreCase))
        {
            IgnoreUnlinkedName = words is null ? null : (_, name) => words.Contains(name)
        };

        return resolver.Lint();
    }

    // The rules of the problems in a file, as "line: rule name" with 1-based lines.
    private static List<string> Rules(string text) =>
        [.. Lint(text).Select(diagnostic => $"{diagnostic.Line + 1}: {diagnostic.Rule} {diagnostic.Name}".TrimEnd())];

    // The problems the editor reports for one strict file, as "line: message" with 1-based lines.
    private static List<string> Problems(string text) =>
        [.. Lint(text).Select(diagnostic => $"{diagnostic.Line + 1}: {diagnostic.Message}")];

    private static AssemblyResult Assemble(string text) =>
        new NativeAssembler().Assemble(
            new AssemblySource(text, "test.asm"),
            new AssemblyOptions(ProcessorVariant.Mos6502, origin: 0x0300, imageSize: 0x100));
}
