// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug.Language;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the language server's Apple Pascal features: the lint's problems, hover for documentation comments and
///  historical names, go to definition, and the outline, for a file read as part of the program that includes it.
/// </summary>
[TestClass]
public sealed class PascalLanguageTests
{
    private string _folder = "";

    /// <summary>
    ///  Makes a folder for the test's files.
    /// </summary>
    [TestInitialize]
    public void MakeFolder() => _folder = Directory.CreateTempSubdirectory("pascal").FullName;

    /// <summary>
    ///  Removes the test's folder.
    /// </summary>
    [TestCleanup]
    public void RemoveFolder() => Directory.Delete(_folder, recursive: true);

    /// <summary>
    ///  An included file, opened alone, is read as part of its program: its problems are the lint's, and a name it
    ///  uses from the main file is found there.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task IncludedFileIsReadWithItsProgram()
    {
        string part = Write("PART.TEXT", PascalSourceTests.Part.Replace("BEGIN\n  WriteLine", "begin\n  WriteLine", StringComparison.Ordinal));
        Write("SAMPLE.TEXT", PascalSourceTests.Sample);
        RecordingLanguageClient client = new();
        (DocumentSyncHandler sync, HoverHandler hover, DefinitionHandler definition, _) = Handlers(client);
        DocumentUri uri = Open(sync, part);

        List<Diagnostic> problems = await client.Wait(uri, found => found.Count > 0);
        Diagnostic problem = problems.Should().ContainSingle().Which;
        problem.Code.Should().Be("case");
        problem.Message.Should().Contain("BEGIN");

        string[] lines = File.ReadAllLines(part);
        int line = Array.FindIndex(lines, text => text.Contains("INCR(", StringComparison.Ordinal));
        Position at = new(line, lines[line].IndexOf("INCR", StringComparison.Ordinal) + 1);

        string text = (await hover.Handle(Request(uri, at)))?.Contents.Value ?? "";
        text.Should().Contain("FUNCTION Increment");
        text.Should().Contain("`INCR` is a historical name of `Increment`.");
        text.Should().Contain("Adds one to a number, as `Increment` does.");
        text.Should().Contain("**Parameters:** Number: the number.");
        text.Should().Contain("UCSD Pascal");

        List<LspLocation> definitions = [.. await definition.Handle(Request(uri, at))];
        LspLocation found = definitions.Should().ContainSingle().Which;
        found.Uri.GetFileSystemPath().Should().EndWith("SAMPLE.TEXT");
        string[] sample = File.ReadAllLines(Path.Join(_folder, "SAMPLE.TEXT"));
        sample[found.Range.Start.Line].Should().StartWith("FUNCTION Increment");
    }

    /// <summary>
    ///  A link in a documentation comment hovers and leads to what it names.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task LinksInCommentsLeadToTheirDeclarations()
    {
        string sample = Write("SAMPLE.TEXT", PascalSourceTests.Sample);
        Write("PART.TEXT", PascalSourceTests.Part);
        (DocumentSyncHandler sync, HoverHandler hover, DefinitionHandler definition, _) = Handlers(new RecordingLanguageClient());
        DocumentUri uri = Open(sync, sample);

        string[] lines = File.ReadAllLines(sample);
        int line = Array.FindIndex(lines, text => text.Contains("<Increment>", StringComparison.Ordinal));
        Position at = new(line, lines[line].IndexOf("<Increment>", StringComparison.Ordinal) + 2);

        ((await hover.Handle(Request(uri, at)))?.Contents.Value).Should().Contain("FUNCTION Increment");
        List<LspLocation> definitions = [.. await definition.Handle(Request(uri, at))];
        lines[definitions.Should().ContainSingle().Which.Range.Start.Line].Should().StartWith("FUNCTION Increment");
    }

    /// <summary>
    ///  The outline lists a file's routines, types, constants and variables, with what a routine or record declares
    ///  under it.
    /// </summary>
    /// <returns>The test.</returns>
    [TestMethod]
    public async Task OutlineListsDeclarations()
    {
        string sample = Write("SAMPLE.TEXT", PascalSourceTests.Sample);
        string part = Write("PART.TEXT", PascalSourceTests.Part);
        (DocumentSyncHandler sync, _, _, DocumentSymbolHandler outline) = Handlers(new RecordingLanguageClient());
        DocumentUri uri = Open(sync, sample);

        List<DocumentSymbol> symbols = [.. await outline.Handle(Request(uri, new Position(0, 0))) ?? []];
        symbols.Select(symbol => symbol.Name).Should().Equal("Sample", "MaxItems", "Item", "Count", "First", "Increment");
        (symbols.Single(symbol => symbol.Name == "Item").Children ?? []).Select(child => child.Name)
            .Should().Equal("Value", "Next");

        symbols.Single(symbol => symbol.Name == "Increment").Children.Should().BeNull();

        DocumentUri included = Open(sync, part);
        symbols = [.. await outline.Handle(Request(included, new Position(0, 0))) ?? []];
        DocumentSymbol report = symbols.Should().ContainSingle().Which;
        report.Name.Should().Be("Report");
        (report.Children ?? []).Select(child => child.Name).Should().Equal("WriteLine");
    }

    private static (DocumentSyncHandler, HoverHandler, DefinitionHandler, DocumentSymbolHandler) Handlers(
        RecordingLanguageClient client)
    {
        LanguageWorkspace workspace = new(client);
        BasicDocuments basic = new(client);
        PascalDocuments pascal = new(client);
        return (
            new DocumentSyncHandler(workspace, basic, pascal),
            new HoverHandler(workspace, basic, pascal),
            new DefinitionHandler(workspace, basic, pascal),
            new DocumentSymbolHandler(workspace, basic, pascal));
    }

    private static DocumentUri Open(DocumentSyncHandler sync, string path)
    {
        DocumentUri uri = DocumentUri.FromFileSystemPath(path);
        sync.Open(Request(uri, new Position(0, 0), File.ReadAllText(path)));
        return uri;
    }

    private static LspParams Request(DocumentUri uri, Position position, string text = "") => new(
        new TextDocumentItem(uri, LanguageHost.PascalId, text),
        position,
        new ReferenceContext(IncludeDeclaration: false),
        "",
        []);

    private string Write(string name, string text)
    {
        string path = Path.Join(_folder, name);
        File.WriteAllText(path, text);
        return path;
    }
}
