// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;
using Retrocore.Pascal.Source;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the Pascal source model the SDK's lint and the editor share: its lexer, its scan of declarations and
///  references, its documentation comments and historical names, and the lint's rules.
/// </summary>
[TestClass]
public sealed class PascalSourceTests
{
    /// <summary>
    ///  A program written to the style, which the lint passes; it includes <see cref="Part"/>.
    /// </summary>
    internal const string Sample = """
        (** A sample program, to show the style. *)

        PROGRAM Sample;

        CONST
          (** The most items the list holds. *)
          MaxItems = 10;

        TYPE
          (** An item of the list. *)
          Item = RECORD
            Value: INTEGER; (** Its value. *)
            (** The next item, or NIL. *)
            Next: ^Item
          END;

        VAR
          Count: INTEGER; (** How many items there are. *)
          First: Item;

        (** Adds one to a number, as <Increment> does.

            Parameters: Number = the number
            Returns: the number and one.
            Also: INCR (UCSD20) *)
        FUNCTION Increment(Number: INTEGER): INTEGER;
        BEGIN
          Increment := Number + 1
        END;

        (*$I PART*)

        BEGIN
          Count := Increment(MaxItems);
          First.Value := Count;
          Report;
          WRITELN(Count)
        END.
        """;

    /// <summary>
    ///  The file <see cref="Sample"/> includes, <c>PART.TEXT</c>.
    /// </summary>
    internal const string Part = """
        (** Writes the count. *)
        PROCEDURE Report;

          (** Writes one line. *)
          PROCEDURE WriteLine;
          BEGIN
            WRITELN('Count is ', Count)
          END;

        BEGIN
          WriteLine;
          INCR(Count)
        END;
        """;

    /// <summary>
    ///  The lexer tells comments, documentation, options, strings, numbers and symbols apart.
    /// </summary>
    [TestMethod]
    public void LexerTellsTokensApart()
    {
        List<PascalToken> tokens = PascalLexer.Tokenize(
            "(* c *) (** d *) (**) (*$I X*) { b } 'it''s' 1.5 1..5 := x_y BEGIN",
            "T.TEXT");

        tokens.Select(token => token.Kind).Should().Equal(
            PascalTokenKind.Comment,
            PascalTokenKind.DocComment,
            PascalTokenKind.Comment,
            PascalTokenKind.Option,
            PascalTokenKind.BraceComment,
            PascalTokenKind.String,
            PascalTokenKind.Number,
            PascalTokenKind.Number,
            PascalTokenKind.Symbol,
            PascalTokenKind.Number,
            PascalTokenKind.Symbol,
            PascalTokenKind.Identifier,
            PascalTokenKind.Keyword);

        tokens[5].Text.Should().Be("'it''s'");
        tokens[6].Text.Should().Be("1.5");
        tokens[8].Text.Should().Be("..");
        tokens[11].Text.Should().Be("x_y");
    }

    /// <summary>
    ///  A comment over lines is one token, which records where it ends.
    /// </summary>
    [TestMethod]
    public void LexerKeepsCommentsOverLines()
    {
        List<PascalToken> tokens = PascalLexer.Tokenize("(** one\n  two *) X", "T.TEXT");
        tokens[0].Kind.Should().Be(PascalTokenKind.DocComment);
        (tokens[0].EndLine, tokens[0].EndColumn).Should().Be((1, 8));
        (tokens[1].Line, tokens[1].Column).Should().Be((1, 9));
    }

    /// <summary>
    ///  The Compiler reads 8 letters of a name and leaves out underscores.
    /// </summary>
    [TestMethod]
    public void KeysAreTheCompilersEightLetters()
    {
        PascalNames.Key("Get_Next_Token").Should().Be("GETNEXTT");
        PascalNames.Key("GetNextTokenFast").Should().Be(PascalNames.Key("GETNEXTTOKEN"));
        PascalNames.IsKeyword("begin").Should().BeTrue();
        PascalNames.IsStandard("writeln").Should().BeTrue();
        PascalNames.IsStandard("Increment").Should().BeFalse();
    }

    /// <summary>
    ///  The scan finds each declaration, with its kind, scope and documentation, through an include.
    /// </summary>
    [TestMethod]
    public void ScanFindsDeclarations()
    {
        PascalProgram program = Analyze();
        program.Files.Should().HaveCount(2);
        program.Includes.Should().ContainSingle().Which.Path.Should().Be(Path.Join("SRC", "PART.TEXT"));

        PascalDeclaration Find(string name) => program.Declarations.Single(declaration => declaration.Name == name);

        Find("Sample").Kind.Should().Be(PascalDeclarationKind.Program);
        Find("MaxItems").Kind.Should().Be(PascalDeclarationKind.Constant);
        (Find("MaxItems").Doc?.Summary).Should().Be("The most items the list holds.");
        Find("Item").Kind.Should().Be(PascalDeclarationKind.Type);
        Find("Value").Kind.Should().Be(PascalDeclarationKind.Field);
        (Find("Value").Doc?.Summary).Should().Be("Its value.");
        (Find("Next").Doc?.Summary).Should().Be("The next item, or NIL.");
        (Find("Count").Doc?.Summary).Should().Be("How many items there are.");
        Find("First").Doc.Should().BeNull();
        Find("Number").Kind.Should().Be(PascalDeclarationKind.Parameter);
        Find("Number").Scope.Owner.Should().Be(Find("Increment"));
        Find("WriteLine").QualifiedName.Should().Be("Report.WriteLine");
        (program.File(Path.Join("SRC", "SAMPLE.TEXT"))?.Doc?.Summary).Should().Be("A sample program, to show the style.");
        program.StrayDocs.Should().BeEmpty();
    }

    /// <summary>
    ///  A name resolves to the declaration its scope sees, and a field after a dot to the record's field.
    /// </summary>
    [TestMethod]
    public void ReferencesResolve()
    {
        PascalProgram program = Analyze();
        string part = Path.Join("SRC", "PART.TEXT");
        Lines(Part, "            WRITELN('Count is ', Count)", "Count", out int line, out int column, last: true);
        (program.DeclarationAt(part, line, column)?.Declaration.Kind).Should().Be(PascalDeclarationKind.Variable);

        string main = Path.Join("SRC", "SAMPLE.TEXT");
        Lines(Sample, "  First.Value := Count;", "Value", out line, out column);
        (program.DeclarationAt(main, line, column)?.Declaration.Kind).Should().Be(PascalDeclarationKind.Field);

        program.References
            .Where(reference => !PascalNames.IsStandard(reference.Token.Text))
            .Should().OnlyContain(reference => program.Resolve(reference).HasValue);
    }

    /// <summary>
    ///  A documentation comment parses into its summary, its remarks and its sections.
    /// </summary>
    [TestMethod]
    public void DocCommentsParse()
    {
        PascalDeclaration increment = Analyze().Declarations.Single(declaration => declaration.Name == "Increment");
        increment.Doc.Should().NotBeNull();
        PascalDocComment doc = increment.Doc;
        doc.Summary.Should().Be("Adds one to a number, as <Increment> does.");
        (doc.Section("Parameters")?.Text).Should().Be("Number = the number");
        (doc.Section("Returns")?.Text).Should().Be("the number and one.");
        doc.Also.Should().ContainSingle().Which.Item.Should().Be("INCR (UCSD20)");
        (doc.Also.Single().Also?.Name).Should().Be("INCR");
        doc.UnknownSections.Should().BeEmpty();

        PascalToken token = PascalLexer.Tokenize("(** Does it.\n    Param: X: the thing. *)", "T.TEXT")[0];
        PascalDocComment.Parse(token).UnknownSections.Should().ContainSingle().Which.Text.Should().Be("Param");
    }

    /// <summary>
    ///  A historical name leads to the declaration whose <c>Also:</c> gives it, and a link to the declaration it
    ///  names.
    /// </summary>
    [TestMethod]
    public void HistoricalNamesLeadToTheirDeclarations()
    {
        PascalProgram program = Analyze();
        PascalDeclaration increment = program.Declarations.Single(declaration => declaration.Name == "Increment");
        program.OldName("incr").Should().Be(increment);

        Lines(Part, "  INCR(Count)", "INCR", out int line, out int column);
        (PascalDeclaration Declaration, bool Historical)? found =
            program.DeclarationAt(Path.Join("SRC", "PART.TEXT"), line, column);

        found.Should().Be((increment, true));

        (program.FindLink("Report.WriteLine")?.Name).Should().Be("WriteLine");
        program.FindLink("Increment").Should().Be(increment);
        program.FindLink("INCR").Should().Be(increment);
        program.FindLink("Missing.WriteLine").Should().BeNull();
    }

    /// <summary>
    ///  A use of Pascal's own name never leads to a declaration that gives it as a historical name.
    /// </summary>
    /// <param name="name">A standard identifier or a later reserved word.</param>
    [TestMethod]
    [DataRow("EXIT")]
    [DataRow("OTHERWISE")]
    public void PascalsOwnNamesAreNotHistorical(string name)
    {
        string source = $"PROGRAM P;\n(** Q.\n    Also: {name} (UCSD20) *)\nPROCEDURE Q;\nBEGIN\n  {name}(Q)\nEND;\nBEGIN END.";
        PascalProgram program = Analyze(source);

        Lines(source, $"  {name}(Q)", name, out int line, out int column);
        program.DeclarationAt(Path.Join("SRC", "P.TEXT"), line, column).Should().BeNull();
    }

    /// <summary>
    ///  A program written to the style passes the lint.
    /// </summary>
    [TestMethod]
    public void SamplePassesTheLint()
    {
        PascalLint.Check(Analyze(), BasicAttribution.Bibliography).Should().BeEmpty();
    }

    /// <summary>
    ///  Each rule finds what it is for.
    /// </summary>
    /// <param name="rule">The rule.</param>
    /// <param name="source">A program that breaks it once.</param>
    [TestMethod]
    [DataRow("line-length", "PROGRAM P; (* ................................................................... *)\nBEGIN END.")]
    [DataRow("tab", "PROGRAM P;\n\tBEGIN END.")]
    [DataRow("comment", "PROGRAM P; { braces }\nBEGIN END.")]
    [DataRow("case", "PROGRAM P;\nbegin END.")]
    [DataRow("case", "PROGRAM P;\nBEGIN Writeln END.")]
    [DataRow("name", "PROGRAM P;\nVAR Total_Count: INTEGER;\nBEGIN END.")]
    [DataRow("name", "PROGRAM P;\nVAR TOTAL: INTEGER;\nBEGIN END.")]
    [DataRow("name", "PROGRAM P;\nVAR total: INTEGER;\nBEGIN END.")]
    [DataRow("name", "PROGRAM P;\nVAR Otherwise: INTEGER;\nBEGIN END.")]
    [DataRow("name-8", "PROGRAM P;\nVAR CountAllItems, CountAllOthers: INTEGER;\nBEGIN END.")]
    [DataRow("name-8", "PROGRAM P;\nVAR CountAllItems: INTEGER;\nPROCEDURE Q;\nVAR CountAllOthers: INTEGER;\nBEGIN END;\nBEGIN END.")]
    [DataRow("include", "PROGRAM P;\n(*$I GONE*)\nBEGIN END.")]
    [DataRow("doc-placement", "PROGRAM P;\nBEGIN\n(** Nothing. *)\nEND.")]
    [DataRow("doc-section", "PROGRAM P;\n(** Q.\n    Param: X. *)\nPROCEDURE Q;\nBEGIN END;\nBEGIN END.")]
    [DataRow("also", "PROGRAM P;\n(** Q.\n    Also: OLDQ (NOKEY) *)\nPROCEDURE Q;\nBEGIN END;\nBEGIN END.")]
    [DataRow("also", "PROGRAM P;\n(** Q.\n    Also: OLDQ (UCSD20 *)\nPROCEDURE Q;\nBEGIN END;\nBEGIN END.")]
    [DataRow("also", "PROGRAM P;\n(** Q.\n    Also: R (UCSD20) *)\nPROCEDURE Q;\nBEGIN END;\nPROCEDURE R;\nBEGIN END;\nBEGIN END.")]
    [DataRow("also", "PROGRAM P;\n(** Q.\n    Also: X (UCSD20) *)\nPROCEDURE Q;\nBEGIN END;\n(** R.\n    Also: X (UCSD20) *)\nPROCEDURE R;\nBEGIN END;\nBEGIN END.")]
    [DataRow("also", "PROGRAM P;\n(** Q.\n    Also: EXIT (UCSD20) *)\nPROCEDURE Q;\nBEGIN END;\nBEGIN END.")]
    [DataRow("also", "PROGRAM P;\n(** Q.\n    Also: OTHERWISE (UCSD20) *)\nPROCEDURE Q;\nBEGIN END;\nBEGIN END.")]
    [DataRow("also", "PROGRAM P;\n(** Q.\n    Also: REPEAT (UCSD20) *)\nPROCEDURE Q;\nBEGIN END;\nBEGIN END.")]
    [DataRow("link", "PROGRAM P;\n(** Q, not <Missing>. *)\nPROCEDURE Q;\nBEGIN END;\nBEGIN END.")]
    [DataRow("link", "PROGRAM P;\nPROCEDURE Report;\n(** R, not <port.Inner>. *)\nPROCEDURE Inner;\nBEGIN END;\nBEGIN END;\nBEGIN END.")]
    [DataRow("also", "PROGRAM P;\n(** Q.\n    Also: OLDQ (UCSD20), OLDQ (A2POSRM) *)\nPROCEDURE Q;\nBEGIN END;\nBEGIN END.")]
    [DataRow("case", "PROGRAM P;\nTYPE R = RECORD Length: INTEGER END;\nVAR S: STRING;\nBEGIN WRITELN(Length(S)) END.")]
    public void RuleFindsItsProblem(string rule, string source)
    {
        List<PascalDiagnostic> problems = PascalLint.Check(Analyze(source), BasicAttribution.Bibliography);
        problems.Should().ContainSingle(problem => problem.Rule == rule, string.Join("; ", problems));
        problems.Should().OnlyContain(problem => problem.Rule == rule, string.Join("; ", problems));
    }

    /// <summary>
    ///  A standard identifier the program declares again is the program's own name, which the case rule leaves to
    ///  the program.
    /// </summary>
    [TestMethod]
    public void RedeclaredStandardNamesKeepTheirCase()
    {
        PascalProgram program = Analyze("PROGRAM P;\nVAR Input: INTEGER;\nBEGIN Input := 1 END.");
        PascalLint.Check(program, bibliography: null).Should().BeEmpty();
    }

    /// <summary>
    ///  The names the code file keeps, a segment's and the program's, need not be PascalCase.
    /// </summary>
    [TestMethod]
    public void KeptNamesNeedNotBePascalCase()
    {
        PascalProgram program = Analyze("PROGRAM PASCALCO;\nSEGMENT PROCEDURE BODYPART;\nBEGIN END;\nBEGIN END.");
        PascalLint.Check(program, bibliography: null).Should().BeEmpty();
    }

    /// <summary>
    ///  A file over the strictest Editor's 16,348 bytes, or a .TEXT file with a name a disk can't keep, is reported; a .pas file's
    ///  name is the editor's own.
    /// </summary>
    [TestMethod]
    public void FilesTheEditorCannotOpenAreReported()
    {
        string comment = $"(* {new string('.', 70)} *)\n";
        string big = $"PROGRAM P;\n{string.Concat(Enumerable.Repeat(comment, 300))}BEGIN END.";

        PascalLint.Check(Analyze(big), bibliography: null).Should().ContainSingle()
            .Which.Rule.Should().Be("file-size");

        Dictionary<string, string> files = new() { [Path.Join("SRC", "Sample.text")] = "PROGRAM P;\nBEGIN END." };
        PascalProgram program = PascalProgram.Analyze(Path.Join("SRC", "Sample.text"), files.GetValueOrDefault);
        PascalLint.Check(program, bibliography: null).Should().ContainSingle().Which.Rule.Should().Be("file-name");

        files = new() { [Path.Join("SRC", "sample.pas")] = "PROGRAM P;\nBEGIN END." };
        program = PascalProgram.Analyze(Path.Join("SRC", "sample.pas"), files.GetValueOrDefault);
        PascalLint.Check(program, bibliography: null).Should().BeEmpty();

        files = new() { [Path.Join("SRC", "AVERYLONGNAME.TEXT")] = "PROGRAM P;\nBEGIN END." };
        program = PascalProgram.Analyze(Path.Join("SRC", "AVERYLONGNAME.TEXT"), files.GetValueOrDefault);
        PascalLint.Check(program, bibliography: null).Should().ContainSingle().Which.Rule.Should().Be("file-name");
    }

    /// <summary>
    ///  Every Pascal source in the SDK passes the lint, each program read from its main file, and every Assembler
    ///  source the text checks; every source is one or the other.
    /// </summary>
    [TestMethod]
    public void SdkSourcesPassTheLint()
    {
        string? root = AppContext.BaseDirectory;
        while (root is not null && !Directory.Exists(Path.Join(root, "src", "Retrocore.Pascal", "Sdk")))
        {
            root = Path.GetDirectoryName(root);
        }

        root.Should().NotBeNull("the SDK's Pascal sources are in src/Retrocore.Pascal/Sdk above the test's folder");
        string sdk = Path.Join(root, "src", "Retrocore.Pascal", "Sdk");
        List<string> sources =
        [
            .. Directory.EnumerateFiles(sdk, "*", SearchOption.AllDirectories)
                .Where(file => file.EndsWith(".TEXT", StringComparison.OrdinalIgnoreCase))
        ];

        // Until the first source lands there is nothing to check, which is not a pass.
        if (sources.Count == 0)
        {
            Assert.Inconclusive("src/Retrocore.Pascal/Sdk has no Pascal source yet.");
        }

        // Programs from their main files; a source of Apple's Assembler, whose first line after its comments is a
        // directive, as text.
        static string Read(string path) => File.ReadAllText(path);
        List<string> mains = [.. sources.Where(file => PascalProgram.IsMainFile(Read(file)))];
        static bool IsAssembly(string text)
        {
            string? first = PascalLexer.Lines(text)
                .Select(line => line.Trim())
                .FirstOrDefault(line => line.Length > 0 && !line.StartsWith(';'));

            return first is not null && first.StartsWith('.');
        }

        List<string> assembled = [.. sources.Where(file => IsAssembly(Read(file)))];
        List<PascalProgram> programs =
        [
            .. mains.Select(file => PascalProgram.Analyze(
                file,
                path => File.Exists(path) ? File.ReadAllText(path) : null,
                PascalIncludeFolders.For(file)))
        ];

        HashSet<string> read = [.. programs.SelectMany(program => program.Files).Select(file => Path.GetFullPath(file.Path))];
        List<string> problems =
        [
            .. programs
                .SelectMany(program => PascalLint.Check(program, BasicAttribution.Bibliography))
                .Concat(assembled.SelectMany(file => PascalLint.CheckText(file, Read(file))))
                .Distinct()
                .Select(problem => $"{Path.GetRelativePath(sdk, problem.File)}({problem.Line + 1},{problem.Column + 1}): "
                    + $"{problem.Rule}: {problem.Message}"),
            .. sources
                .Where(file => !read.Contains(Path.GetFullPath(file)) && !assembled.Contains(file))
                .Select(file => $"{Path.GetRelativePath(sdk, file)}: no program reads it, and it isn't an Assembler source")
        ];

        problems.Should().BeEmpty($"the lint found:{Environment.NewLine}{string.Join(Environment.NewLine, problems)}");
    }

    /// <summary>
    ///  A Compiler's source includes the system's globals from the System folder of its machine and version.
    /// </summary>
    [TestMethod]
    public void CompilersIncludeTheSystemsGlobals()
    {
        string root = Directory.CreateTempSubdirectory("pascal").FullName;
        try
        {
            string compiler = Path.Join(root, "Compiler", "apple2-1.3");
            string system = Path.Join(root, "System", "apple2-1.3");
            Directory.CreateDirectory(compiler);
            Directory.CreateDirectory(system);
            string main = Path.Join(compiler, "COMPILER.TEXT");
            File.WriteAllText(main, "PROGRAM P;\n(*$I SYSGLOBALS*)\nBEGIN Count := 1 END.\n");
            File.WriteAllText(Path.Join(system, "SYSGLOBALS.TEXT"), "VAR Count: INTEGER;\n");

            PascalIncludeFolders.For(main).Should().Equal(system);
            PascalProgram program = PascalProgram.Analyze(
                main,
                path => File.Exists(path) ? File.ReadAllText(path) : null,
                PascalIncludeFolders.For(main));

            program.Includes.Should().ContainSingle().Which.Path.Should().Be(Path.Join(system, "SYSGLOBALS.TEXT"));
            PascalLint.Check(program, bibliography: null).Should().BeEmpty();
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    /// <summary>
    ///  An include is the file beside the including one if there is one, else the first include folder's.
    /// </summary>
    [TestMethod]
    public void IncludesFindTheFirstFile()
    {
        string root = Directory.CreateTempSubdirectory("pascal").FullName;
        try
        {
            string[] folders = [Path.Join(root, "Main"), Path.Join(root, "First"), Path.Join(root, "Second")];
            foreach (string folder in folders)
            {
                Directory.CreateDirectory(folder);
                File.WriteAllText(Path.Join(folder, "PART.TEXT"), "VAR Count: INTEGER;\n");
            }

            string main = Path.Join(folders[0], "MAIN.TEXT");
            File.WriteAllText(main, "PROGRAM P;\n(*$I PART*)\nBEGIN Count := 1 END.\n");
            string? Found() => PascalProgram.Analyze(main, path => File.Exists(path) ? File.ReadAllText(path) : null, folders[1..])
                .Includes.Single().Path;

            Found().Should().Be(Path.Join(folders[0], "PART.TEXT"));
            File.Delete(Path.Join(folders[0], "PART.TEXT"));
            Found().Should().Be(Path.Join(folders[1], "PART.TEXT"));
            File.Delete(Path.Join(folders[1], "PART.TEXT"));
            Found().Should().Be(Path.Join(folders[2], "PART.TEXT"));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    /// <summary>
    ///  An Assembler source has only the checks of its text: its lines, name and size.
    /// </summary>
    [TestMethod]
    public void AssemblerSourcesHaveTheTextChecks()
    {
        PascalLint.CheckText(Path.Join("SRC", "ASSEMBLED.TEXT"), "         .PROC   SCANIDEN,2\n         RTS\n").Should().BeEmpty();
        PascalLint.CheckText(Path.Join("SRC", "ASSEMBLED.TEXT"), "\t.PROC X\n").Should().ContainSingle().Which.Rule.Should().Be("tab");
    }

    /// <summary>
    ///  A record's variant parts, nested, end where their parentheses do, and what follows is still declared.
    /// </summary>
    [TestMethod]
    public void NestedVariantsEndAtTheirParentheses()
    {
        PascalProgram program = Analyze(
            "PROGRAM P;\nTYPE T = RECORD CASE A: INTEGER OF 1: (CASE B: BOOLEAN OF TRUE: (X: INTEGER)) END;\n"
                + "VAR Count: INTEGER;\nBEGIN END.");

        program.Declarations.Select(declaration => declaration.Name).Should().Contain(["A", "B", "X", "Count"]);
        program.Declarations.Single(declaration => declaration.Name == "Count").Kind
            .Should().Be(PascalDeclarationKind.Variable);
    }

    /// <summary>
    ///  An intrinsic unit's heading, with its CODE and DATA segments, comes before its interface.
    /// </summary>
    [TestMethod]
    public void IntrinsicUnitsHaveTheirInterface()
    {
        PascalProgram program = Analyze(
            "UNIT TURTLE; INTRINSIC CODE 20 DATA 21;\nINTERFACE\nPROCEDURE Move(Distance: INTEGER);\n"
                + "IMPLEMENTATION\nPROCEDURE Move;\nBEGIN END;\nEND.");

        PascalDeclaration move = program.Declarations.Single(declaration => declaration.Name == "Move");
        move.IsInterface.Should().BeTrue();
        move.IsHeadingOnly.Should().BeFalse();
    }

    /// <summary>
    ///  A comment after a field or parameter documents only it, not the type or routine it is in.
    /// </summary>
    [TestMethod]
    public void TrailingCommentsDocumentOnlyTheirDeclaration()
    {
        PascalProgram program = Analyze(
            "PROGRAM P;\nTYPE Item = RECORD\n  Value: INTEGER; (** Its value. *)\n  Next: INTEGER\nEND;\n"
                + "PROCEDURE Q(A: INTEGER; (** The first. *)\n  B: INTEGER);\nBEGIN END;\nBEGIN END.");

        PascalDeclaration Find(string name) => program.Declarations.Single(declaration => declaration.Name == name);
        (Find("Value").Doc?.Summary).Should().Be("Its value.");
        Find("Item").Doc.Should().BeNull();
        (Find("A").Doc?.Summary).Should().Be("The first.");
        Find("Q").Doc.Should().BeNull();
    }

    /// <summary>
    ///  A field after a "." may have a standard identifier's name, in its own case, even from a record the source
    ///  doesn't declare.
    /// </summary>
    [TestMethod]
    public void FieldsAfterADotKeepTheirCase()
    {
        PascalProgram program = Analyze("PROGRAM P;\nUSES Clock;\nVAR T: Clock.Stamp;\nBEGIN WRITELN(T.Time) END.");
        PascalLint.Check(program, bibliography: null).Should().BeEmpty();
    }

    /// <summary>
    ///  An include in braces is followed, and reported for its braces.
    /// </summary>
    [TestMethod]
    public void BracedIncludesAreFollowed()
    {
        PascalProgram program = Analyze("PROGRAM P;\n{$I GONE}\nBEGIN END.");
        program.Includes.Should().ContainSingle().Which.Name.Should().Be("GONE");
        PascalLint.Check(program, bibliography: null).Select(problem => problem.Rule).Should().BeEquivalentTo(["comment", "include"]);
    }

    /// <summary>
    ///  Inside a WITH, a bare name may be a field's, in its own case, even one named like a standard identifier;
    ///  after the WITH's statement, it is the standard one again.
    /// </summary>
    [TestMethod]
    public void FieldsInAWithKeepTheirCase()
    {
        PascalProgram program = Analyze(
            "PROGRAM P;\nTYPE R = RECORD Length: INTEGER END;\nVAR Item: R;\n"
                + "BEGIN\n  WITH Item DO Length := 1;\n  WITH Item DO\n  BEGIN\n    Length := 2\n  END;\n"
                + "  WITH Item DO IF Length > 0 THEN Length := 1 ELSE Length := 2;\n"
                + "  REPEAT WITH Item DO Length := 4 UNTIL Length > 0;\n"
                + "  WITH Item DO REPEAT Length := Length - 1; Length := 5 UNTIL Length = 0;\n"
                + "  Length := 3\nEND.");

        // UNTIL's Length, after the WITH's statement, and the last line's are the standard one's.
        List<PascalDiagnostic> problems = PascalLint.Check(program, bibliography: null);
        problems.Should().OnlyContain(problem => problem.Rule == "case");
        problems.Select(problem => problem.Line).Should().Equal(10, 12);
    }

    /// <summary>
    ///  Text still being typed leaves the declarations after it declared, and the comments on them theirs.
    /// </summary>
    /// <param name="source">A program with something half typed before PROCEDURE Later.</param>
    [TestMethod]
    [DataRow("PROGRAM P;\nCONST\n  Max\nVAR X: INTEGER;\n(** L. *)\nPROCEDURE Later;\nBEGIN END;\nBEGIN END.")]
    [DataRow("PROGRAM P;\nVAR\n  X: INTEGER;\n  Count\n  Total: INTEGER;\n(** L. *)\nPROCEDURE Later;\nBEGIN END;\nBEGIN END.")]
    [DataRow("PROGRAM P;\nVAR X: INTEGER;\nPROCEDURE A;\nBEGIN\n  REPEAT\nEND;\n(** L. *)\nPROCEDURE Later;\nBEGIN END;\nBEGIN END.")]
    [DataRow("PROGRAM P;\nVAR X: INTEGER;\nPROCEDURE A;\nBEGIN\n  X := 1;\n(** L. *)\nPROCEDURE Later;\nBEGIN END;\nBEGIN END.")]
    [DataRow("PROGRAM P;\nVAR X: INTEGER;\nTYPE R = RECORD CASE Tag: BOOLEAN\nEND;\n(** L. *)\nPROCEDURE Later;\nBEGIN END;\nBEGIN END.")]
    [DataRow("PROGRAM P;\nTYPE R = RECORD CASE Tag: BOOLEAN OF 1: (A: INTEGER);\n 2\nEND;\nVAR X: INTEGER;\n(** L. *)\nPROCEDURE Later;\nBEGIN END;\nBEGIN END.")]
    [DataRow("PROGRAM P;\nPROCEDURE A(B: INTEGER\nVAR X: INTEGER;\nBEGIN END;\n(** L. *)\nPROCEDURE Later;\nBEGIN END;\nBEGIN END.")]
    [DataRow("PROGRAM P;\nVAR\n  Y:\n(** L. *)\nPROCEDURE Later;\nBEGIN END;\nBEGIN END.")]
    [DataRow("PROGRAM P;\nCONST\n  Max =\nVAR X: INTEGER;\n(** L. *)\nPROCEDURE Later;\nBEGIN END;\nBEGIN END.")]
    [DataRow("PROGRAM P;\nFUNCTION F:\n(** L. *)\nPROCEDURE Later;\nBEGIN END;\nBEGIN END.")]
    [DataRow("PROGRAM P;\nPROCEDURE A;\nBEGIN END;\nEND;\n(** L. *)\nPROCEDURE Later;\nBEGIN END;\nBEGIN END.")]
    [DataRow("PROGRAM P;\nVAR X: ARRAY[1..\n(** L. *)\nPROCEDURE Later;\nBEGIN END;\nBEGIN END.")]
    [DataRow("PROGRAM P;\nVAR X: INTEGER;\nUSES\n(** L. *)\nPROCEDURE Later;\nBEGIN END;\nBEGIN END.")]
    public void HalfTypedTextKeepsWhatFollows(string source)
    {
        PascalProgram program = Analyze(source);
        PascalDeclaration later = program.Declarations.Single(declaration => declaration.Name == "Later");
        later.Scope.Should().Be(program.Outer);
        (later.Doc?.Summary).Should().Be("L.");
        program.Declarations.Should().NotContain(declaration => declaration.Name == "BEGIN" || declaration.Name == "WRITELN");
    }

    /// <summary>
    ///  A comment after a record's last field, which needs no ";", or after a FORWARD heading or an enumeration,
    ///  documents what is on its line.
    /// </summary>
    [TestMethod]
    public void TrailingCommentsWithoutASemicolon()
    {
        PascalProgram program = Analyze(
            "PROGRAM P;\nTYPE Item = RECORD\n  Value: INTEGER; (** v *)\n  Next: INTEGER (** n *)\nEND;\n"
                + "  Kind = (Red, Green); (** k *)\nPROCEDURE Q; FORWARD; (** q *)\nPROCEDURE S;\nBEGIN END;\n"
                + "PROCEDURE Q;\nBEGIN END;\nFUNCTION F: INTEGER (** f *);\nBEGIN END;\nBEGIN END.");

        PascalDeclaration Find(string name) => program.Declarations.Single(declaration => declaration.Name == name);
        (Find("Next").Doc?.Summary).Should().Be("n");
        (Find("Kind").Doc?.Summary).Should().Be("k");
        Find("Red").Doc.Should().BeNull();
        (Find("Q").Doc?.Summary).Should().Be("q");
        (Find("F").Doc?.Summary).Should().Be("f");
        Find("S").Doc.Should().BeNull();
        program.StrayDocs.Should().BeEmpty();
    }

    /// <summary>
    ///  A comment that trails code documents what its line declared before it: a variant's tag and an enumeration
    ///  take none meant for a field or a value, nor the next value one meant for the one before.
    /// </summary>
    [TestMethod]
    public void TagsAndEnumerationsKeepTheirOwnComments()
    {
        PascalProgram program = Analyze(
            "PROGRAM P;\nTYPE S = RECORD CASE Kind: INTEGER OF (** k *)\n  1: (Radius: INTEGER (** r *))\nEND;\n"
                + "  Color = (Red,   (** red *)\n    Green); (** The colors. *)\n  Shade = (Light (** l *), Dark);\n"
                + "BEGIN END.");

        PascalDeclaration Find(string name) => program.Declarations.Single(declaration => declaration.Name == name);
        (Find("Radius").Doc?.Summary).Should().Be("r");
        (Find("Kind").Doc?.Summary).Should().Be("k");
        (Find("Light").Doc?.Summary).Should().Be("l");
        Find("Dark").Doc.Should().BeNull();
        (Find("Color").Doc?.Summary).Should().Be("The colors.");
        (Find("Red").Doc?.Summary).Should().Be("red");
        Find("Green").Doc.Should().BeNull();
    }

    /// <summary>
    ///  A trailing comment reaches back through its own statement only, over lines if the statement does, and the
    ///  same with or without the ";" before it.
    /// </summary>
    [TestMethod]
    public void TrailingCommentsDocumentTheirStatement()
    {
        PascalProgram program = Analyze(
            "PROGRAM P;\nTYPE S = RECORD Width: INTEGER; CASE Kind: INTEGER OF (** k *)\n"
                + "  1: (X: INTEGER; Y: INTEGER (** y *))\nEND;\n"
                + "  R = RECORD\n    Inner: RECORD Z: INTEGER END; Last: INTEGER (** last *)\n  END (** r *);\n"
                + "VAR A: INTEGER; B: INTEGER (** b *);\n  C,\n  D: INTEGER (** cd *);\n"
                + "PROCEDURE Q(\n  E: INTEGER) (** q *);\nBEGIN E := 1; (** stray *) END;\n"
                + "PROCEDURE T BEGIN (** none *) END;\n"
                + "PROCEDURE U; FORWARD (** u *);\nPROCEDURE V(F: INTEGER); FORWARD;\nPROCEDURE V(F: INTEGER) (** v *);\n"
                + "BEGIN END;\nPROCEDURE U;\nBEGIN END;\n"
                + "TYPE W = RECORD CASE Tag: INTEGER OF 1: (G: INTEGER) (** variant *) END;\n"
                + "VAR H: ARRAY[1..2] OF INTEGER (** h *);\n  J: SET OF CHAR (** j *);\nBEGIN END.");

        PascalDeclaration Find(string name) => program.Declarations.Single(declaration => declaration.Name == name);
        (Find("Kind").Doc?.Summary).Should().Be("k");
        Find("Width").Doc.Should().BeNull();
        Find("S").Doc.Should().BeNull();
        (Find("Y").Doc?.Summary).Should().Be("y");
        Find("X").Doc.Should().BeNull();
        (Find("Last").Doc?.Summary).Should().Be("last");
        Find("Inner").Doc.Should().BeNull();
        (Find("R").Doc?.Summary).Should().Be("r");
        (Find("B").Doc?.Summary).Should().Be("b");
        Find("A").Doc.Should().BeNull();
        (Find("C").Doc?.Summary).Should().Be("cd");
        (Find("D").Doc?.Summary).Should().Be("cd");
        (Find("Q").Doc?.Summary).Should().Be("q");
        Find("E").Doc.Should().BeNull();
        Find("T").Doc.Should().BeNull();
        (Find("U").Doc?.Summary).Should().Be("u");
        (Find("V").Doc?.Summary).Should().Be("v");
        Find("Tag").Doc.Should().BeNull();
        (Find("H").Doc?.Summary).Should().Be("h");
        (Find("J").Doc?.Summary).Should().Be("j");
        program.StrayDocs.Select(doc => doc.Summary).Should().BeEquivalentTo(["stray", "none", "variant"]);
    }

    /// <summary>
    ///  A file's documentation may follow ordinary comments, such as a copyright line.
    /// </summary>
    /// <param name="comment">The comment before it.</param>
    [TestMethod]
    [DataRow("(* Copyright *)")]
    [DataRow("{ Copyright }")]
    public void FileDocsMayFollowComments(string comment)
    {
        PascalProgram program = Analyze($"{comment}\n(** The file. *)\n\nPROGRAM P;\nBEGIN END.");
        (program.Files[0].Doc?.Summary).Should().Be("The file.");
        program.Declarations.Single(declaration => declaration.Name == "P").Doc.Should().BeNull();
    }

    /// <summary>
    ///  A stray UNTIL, as while typing, doesn't end the statement part it is in, so what follows is still declared.
    /// </summary>
    [TestMethod]
    public void StrayUntilKeepsTheStatementPart()
    {
        PascalProgram program = Analyze(
            "PROGRAM P;\nPROCEDURE Q;\nBEGIN\n  UNTIL TRUE\nEND;\nPROCEDURE R;\nBEGIN END;\nBEGIN END.");

        program.Declarations.Single(declaration => declaration.Name == "R").Scope.Should().Be(program.Outer);
    }

    /// <summary>
    ///  A file with a line too long for a page is still measured for the Editor.
    /// </summary>
    [TestMethod]
    public void OverlongLinesStillCount()
    {
        string comment = $"(* {new string('.', 70)} *)\n";
        string source = $"PROGRAM P;\n(* {new string('.', 1100)} *)\n{string.Concat(Enumerable.Repeat(comment, 240))}BEGIN END.";
        PascalLint.Check(Analyze(source), bibliography: null).Select(problem => problem.Rule).Distinct()
            .Should().BeEquivalentTo(["line-length", "file-size"]);
    }

    /// <summary>
    ///  A line too long for a disk's page is reported for its length, not taken for a failure.
    /// </summary>
    [TestMethod]
    public void OverlongLinesAreReported()
    {
        PascalProgram program = Analyze($"PROGRAM P;\n(* {new string('.', 1100)} *)\nBEGIN END.");
        PascalLint.Check(program, bibliography: null).Should().ContainSingle().Which.Rule.Should().Be("line-length");
    }

    /// <summary>
    ///  Text being typed, cut off anywhere, analyzes and lints without throwing, as the editor needs.
    /// </summary>
    [TestMethod]
    public void PartialSourcesAnalyze()
    {
        string text = Sample + "\n(*$I PA";
        for (int end = 0; end <= text.Length; end++)
        {
            string prefix = text[..end];
            Dictionary<string, string> files = new()
            {
                [Path.Join("SRC", "SAMPLE.TEXT")] = prefix,
                [Path.Join("SRC", "PART.TEXT")] = Part,
            };

            PascalProgram program = PascalProgram.Analyze(Path.Join("SRC", "SAMPLE.TEXT"), files.GetValueOrDefault);
            PascalLint.Check(program, BasicAttribution.Bibliography).Should().NotBeNull();
        }
    }

    /// <summary>
    ///  A program's code shape stays the same when its names change and comments come and go, and changes with its
    ///  code.
    /// </summary>
    [TestMethod]
    public void CodeShapeIgnoresNamesAndComments()
    {
        string renamed = Sample
            .Replace("Increment", "AddOne", StringComparison.Ordinal)
            .Replace("MaxItems", "Limit", StringComparison.Ordinal)
            .Replace("(** Its value. *)", "(* A comment instead. *)", StringComparison.Ordinal);

        string changed = Sample.Replace("Number + 1", "Number + 2", StringComparison.Ordinal);
        string option = "(*$R-*)\n" + Sample;
        string braceOption = "{$R-}\n" + Sample;
        string shape = PascalCodeShape.Digest(Analyze());

        PascalCodeShape.Digest(Analyze(renamed, Part)).Should().Be(shape);
        PascalCodeShape.Digest(Analyze(changed, Part)).Should().NotBe(shape);
        PascalCodeShape.Digest(Analyze(option, Part)).Should().NotBe(shape, "an option changes the code");
        PascalCodeShape.Digest(Analyze(braceOption, Part)).Should().NotBe(shape, "an option in braces does too");
    }

    /// <summary>
    ///  A file that includes itself, in another case, is read once: the shape doesn't expand it without end.
    /// </summary>
    [TestMethod]
    public void CodeShapeReadsASelfIncludeOnce()
    {
        const string Source = """
            PROGRAM Loop;
            (*$I p.text*)
            BEGIN
            END.
            """;

        Dictionary<string, string> files = new(StringComparer.OrdinalIgnoreCase)
        {
            [Path.Join("SRC", "P.TEXT")] = Source,
        };

        PascalProgram program = PascalProgram.Analyze(Path.Join("SRC", "P.TEXT"), files.GetValueOrDefault);

        string alone = Source.Replace("(*$I p.text*)", "", StringComparison.Ordinal);
        PascalCodeShape.Digest(program).Should().Be(PascalCodeShape.Digest(Analyze(alone)));
    }

    /// <summary>
    ///  A file's size is its text as the disk stores it: leading blanks compressed, and no page's padding.
    /// </summary>
    [TestMethod]
    public void StoredLengthIsWhatTheEditorReads()
    {
        string line = new string(' ', 30) + "X";
        string text = string.Join("\n", Enumerable.Repeat(line, 100)) + "\n";

        // Each line is DLE, the blanks' count, X and RETURN.
        PascalLint.StoredLength(PascalTextFile.Write(text)).Should().Be(100 * 4);
        PascalLint.StoredLength(PascalTextFile.Write("")).Should().Be(0);
    }

    private static PascalProgram Analyze()
    {
        Dictionary<string, string> files = new()
        {
            [Path.Join("SRC", "SAMPLE.TEXT")] = Sample,
            [Path.Join("SRC", "PART.TEXT")] = Part,
        };

        return PascalProgram.Analyze(Path.Join("SRC", "SAMPLE.TEXT"), files.GetValueOrDefault);
    }

    private static PascalProgram Analyze(string sample, string part)
    {
        Dictionary<string, string> files = new()
        {
            [Path.Join("SRC", "SAMPLE.TEXT")] = sample,
            [Path.Join("SRC", "PART.TEXT")] = part,
        };

        return PascalProgram.Analyze(Path.Join("SRC", "SAMPLE.TEXT"), files.GetValueOrDefault);
    }

    private static PascalProgram Analyze(string source)
    {
        Dictionary<string, string> files = new() { [Path.Join("SRC", "P.TEXT")] = source };
        return PascalProgram.Analyze(Path.Join("SRC", "P.TEXT"), files.GetValueOrDefault);
    }

    // Finds a word on a line of a source.
    private static void Lines(string source, string text, string word, out int line, out int column, bool last = false)
    {
        string[] lines = PascalLexer.Lines(source);
        line = Array.FindIndex(lines, candidate => candidate == text.Trim() || candidate.Trim() == text.Trim());
        line.Should().BeGreaterThanOrEqualTo(0, $"the source has the line '{text}'");
        column = last ? lines[line].LastIndexOf(word, StringComparison.Ordinal) : lines[line].IndexOf(word, StringComparison.Ordinal);
    }
}
