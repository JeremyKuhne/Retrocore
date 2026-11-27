// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug.Project;
using System.Text.Json.Nodes;

namespace Retrocore.Tests;

/// <summary>
///  <c>retrocore new</c> and <c>retrocore init</c> write a project from the SDK's templates that builds for every
///  target at once, and the repository's files that build it: the pinned tool, the extension's recommendation, the
///  <c>.gitignore</c> and the CI workflow.
/// </summary>
[TestClass]
public sealed class ProjectScaffoldTests
{
    // How a template's placeholders start.
    private static readonly string Placeholder = new('{', 2);

    private string _folder = "";

    /// <summary>
    ///  Gets each test a folder of its own.
    /// </summary>
    [TestInitialize]
    public void Initialize()
    {
        _folder = Path.Join(Path.GetTempPath(), "retrocore-new-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_folder);
    }

    /// <summary>
    ///  Removes the test's folder.
    /// </summary>
    [TestCleanup]
    public void Cleanup()
    {
        if (Directory.Exists(_folder)) { Directory.Delete(_folder, recursive: true); }
    }

    /// <summary>
    ///  The templates ship beside the host, and the 6502 template builds for the five starting machines.
    /// </summary>
    [TestMethod]
    public void TheTemplatesShipBesideTheHost()
    {
        List<ProjectTemplate> templates = ProjectTemplate.LoadAll(ProjectTemplate.DefaultRoot);
        templates.Select(template => template.Name).Should().Equal("6502");
        string[] families = [.. templates[0].Families.Select(family => $"{family.Name}:{family.Machine}:{family.Environment}")];
        families.Should().Equal("apple1:apple1:wozmon", "apple2:apple2-iiplus:dos33", "apple3:apple3:sos", "pet:pet4032:basic", "bbc:bbcb:dfs");
        string common = Path.Join(ProjectTemplate.DefaultRoot, ProjectTemplate.CommonFolder);
        File.Exists(Path.Join(common, "_github", "workflows", "build.yml")).Should().BeTrue();
        ProjectScaffold.ToolVersion.Should().MatchRegex(@"^\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$", "the pinned version carries no build metadata");
    }

    /// <summary>
    ///  <c>retrocore new</c> with no machines named writes a target for each family, with its usual environment, and
    ///  the repository's files; every target builds its environment's media at once.
    /// </summary>
    [TestMethod]
    public void NewWritesARepositoryWhoseTargetsAllBuild()
    {
        (int code, string output, string error) = Run(init: false, "6502", "greeting", "--output", Path.Join(_folder, "greeting"));
        code.Should().Be(0, error);
        string project = Path.Join(_folder, "greeting");
        output.Should().Contain("greeting: 5 targets, apple1-wozmon, apple2-dos, apple3-sos, pet-basic, bbc-dfs.");

        Files(project).Should().BeEquivalentTo(
            ".config/dotnet-tools.json", ".github/workflows/build.yml", ".gitignore", ".vscode/extensions.json", "README.md",
            "retrocore.json", "src/main.s",
            "src/platform/apple1/console.s", "src/platform/apple2/console.s", "src/platform/pet/console.s",
            "src/platform/bbc/console.s", "src/platform/sos/console.s",
            "src/platform/bare/exit.s", "src/platform/wozmon/exit.s", "src/platform/dos33/exit.s", "src/platform/sos/exit.s",
            "src/platform/basic/exit.s", "src/platform/dfs/exit.s");

        JsonNode tools = ReadJson(Path.Join(project, ".config", "dotnet-tools.json"));
        ((bool?)At(tools, "isRoot")).Should().BeTrue();
        Text(tools, "tools", "retrocore", "version").Should().Be(ProjectScaffold.ToolVersion);
        Texts(tools, "tools", "retrocore", "commands").Should().Equal("retrocore");

        File.ReadAllText(Path.Join(project, ".vscode", "extensions.json")).Should().Contain("\"retrocore.retrocore\"");
        File.ReadAllText(Path.Join(project, ".gitignore")).Should().Contain("artifacts/\nobj/\n");
        string workflow = File.ReadAllText(Path.Join(project, ".github", "workflows", "build.yml"));
        workflow.Should().Contain("run: dotnet tool restore\n");
        workflow.Should().Contain("run: dotnet retrocore build --all\n");
        workflow.Should().Contain("path: artifacts/\n");
        workflow.Should().NotContain(Placeholder, "every placeholder is filled");
        string readme = File.ReadAllText(Path.Join(project, "README.md"));
        readme.Should().StartWith("# greeting\n");
        readme.Should().Contain("| `apple2-dos` | `apple2-iiplus` | `dos33` |");
        readme.Should().NotContain(Placeholder, "every placeholder is filled");

        RetrocoreProject loaded = RetrocoreProject.Load(project);
        string[] built = [.. loaded.Targets.Select(target => $"{target.Name}:{target.Machine.Id}:{target.Environment}")];
        built.Should().Equal(
            "apple1-wozmon:apple1:wozmon", "apple2-dos:apple2-iiplus:dos33", "apple3-sos:apple3:sos", "pet-basic:pet4032:basic",
            "bbc-dfs:bbcb:dfs");

        foreach (ProjectTarget target in loaded.Targets)
        {
            TargetBuild build = ProjectBuild.Build(target);
            File.Exists(build.Binary).Should().BeTrue(target.Name);
            (build.Media.File ?? build.Media.Image).Should().NotBeNull($"{target.Name} writes its environment's media");
        }
    }

    /// <summary>
    ///  Each family alone gets its own console and environment, and <c>bare</c>'s, and builds; a machine named by
    ///  its catalog id gets a target named for it, with the defines the template gives that machine.
    /// </summary>
    [TestMethod]
    public void EachMachineBuildsAlone()
    {
        string[] machines =
        [
            "apple1", "apple2", "apple2-ii", "apple2-iie", "apple2-iie-enhanced", "apple3", "pet", "pet2001", "pet2001-basic2",
            "pet4032-business", "bbc", "bbca"
        ];

        foreach (string machine in machines)
        {
            string project = Path.Join(_folder, machine);
            (int code, _, string error) = Run(init: false, "6502", "greet", "--machines", machine, "--output", project);
            code.Should().Be(0, error);
            ProjectTarget target = RetrocoreProject.Load(project).Targets.Single();
            string[] platforms = [.. Directory.EnumerateDirectories(Path.Join(project, "src", "platform")).Select(folder => Path.GetFileName(folder)).Order()];
            platforms.Should().Contain(["bare", target.Environment], machine);
            platforms.Should().HaveCount(target.Environment == "sos" ? 2 : 3, $"{machine} gets its family's console, its environment's and bare's");
            TargetBuild build = ProjectBuild.Build(target);
            File.Exists(build.Binary).Should().BeTrue(machine);
        }

        string iie = File.ReadAllText(Path.Join(_folder, "apple2-iie", RetrocoreProject.FileName));
        iie.Should().Contain("\"apple2-iie-dos\": { \"machine\": \"apple2-iie\", \"environment\": \"dos33\", \"defines\": { \"LOWERCASE\": 1 } }");
        string pet = File.ReadAllText(Path.Join(_folder, "pet2001", RetrocoreProject.FileName));
        pet.Should().Contain("\"pet2001-basic\": { \"machine\": \"pet2001\", \"environment\": \"basic\" }");
    }

    /// <summary>
    ///  <c>retrocore new</c> refuses what it cannot write, before it writes anything.
    /// </summary>
    [TestMethod]
    public void NewRefusesWhatItCannotWrite()
    {
        string taken = Path.Join(_folder, "taken");
        Directory.CreateDirectory(taken);
        File.WriteAllText(Path.Join(taken, "notes.txt"), "mine");
        Refusal("6502", "taken", "--output", taken).Should().Contain("is already there and not empty");

        string elsewhere = Path.Join(_folder, "elsewhere");
        string hello = Refusal("6502", "hello", "--output", elsewhere);
        hello.Should().Contain("'hello' would name the program HELLO on the Apple II's DOS 3.3 disk");
        int bbc = Run(init: false, "6502", "hello", "--machines", "bbc", "--output", elsewhere).Code;
        bbc.Should().Be(0, "only a DOS 3.3 disk has HELLO");

        string other = Path.Join(_folder, "other");
        Refusal("6502", "game", "--machines", "atari", "--output", other).Should().Contain("The 6502 template has no machine 'atari'");
        string twice = Refusal("6502", "game", "--machines", "apple2,apple2-iiplus", "--output", other);
        twice.Should().Contain("'apple2-iiplus' gives the target apple2-dos again");
        Refusal("6502", "my game", "--output", other).Should().Contain("'my game' cannot name a project");
        Refusal("z80", "game", "--output", other).Should().Contain("There is no template 'z80'; the templates are 6502.");
        Run(init: false, "6502").Code.Should().Be(2);

        // A folder where a repository file goes, or a file where one of its folders goes, is refused before anything
        // is written.
        string blocked = Path.Join(_folder, "blocked");
        Directory.CreateDirectory(Path.Join(blocked, ".gitignore"));
        (int code, _, string error) = Run(init: true, "6502", "--name", "game", "--output", blocked);
        code.Should().Be(1);
        error.Should().Contain(".gitignore is a folder; retrocore writes a file there.");
        Directory.EnumerateFileSystemEntries(blocked).Should().HaveCount(1, "nothing but the folder in the way is there");
        Directory.CreateDirectory(Path.Join(_folder, ".git"));
        File.WriteAllText(Path.Join(_folder, ".vscode"), "a file");
        Directory.CreateDirectory(Path.Join(_folder, "below"));
        (code, _, error) = Run(init: true, "6502", "--output", Path.Join(_folder, "below"));
        code.Should().Be(1);
        error.Should().Contain(".vscode is a file; retrocore writes");
        Directory.EnumerateFileSystemEntries(Path.Join(_folder, "below")).Should().BeEmpty("nothing is written when a file is in the way");
        Directory.Exists(other).Should().BeFalse("nothing is written when the project is refused");
    }

    /// <summary>
    ///  <c>retrocore init</c> adds a project in a folder of a repository: its own files there, and the repository's
    ///  files at the root added to, not replaced: the tool pinned beside the tools there, the extension among the
    ///  recommendations, the project among the root's projects, and a workflow of its own that builds it.
    /// </summary>
    [TestMethod]
    public void InitAddsAProjectToARepository()
    {
        Directory.CreateDirectory(Path.Join(_folder, ".git"));
        Write(".config/dotnet-tools.json", """{ "version": 1, "isRoot": true, "tools": { "dotnet-ef": { "version": "9.0.0", "commands": ["dotnet-ef"] } } }""");
        Write(".vscode/extensions.json", """{ "recommendations": ["ms-dotnettools.csharp"] }""");
        Write(".github/workflows/build.yml", "name: Theirs\n");
        Write("retrocore.json", """{ "projects": ["tools"] }""");
        Write("games/greeting/.gitignore", "bin/\n/obj/\n");
        string project = Path.Join(_folder, "games", "greeting");

        (int code, string output, string error) = Run(init: true, "6502", "--machines", "apple2,bbc", "--output", project + Path.DirectorySeparatorChar);
        code.Should().Be(0, error);
        output.Should().Contain("dotnet retrocore build --all --project games/greeting");

        JsonNode tools = ReadJson(Path.Join(_folder, ".config", "dotnet-tools.json"));
        Text(tools, "tools", "dotnet-ef", "version").Should().Be("9.0.0");
        Text(tools, "tools", "retrocore", "version").Should().Be(ProjectScaffold.ToolVersion);
        IEnumerable<string?> recommendations = Texts(ReadJson(Path.Join(_folder, ".vscode", "extensions.json")), "recommendations");
        recommendations.Should().Equal("ms-dotnettools.csharp", "retrocore.retrocore");
        Texts(ReadJson(Path.Join(_folder, "retrocore.json")), "projects").Should().Equal("tools", "games/greeting");

        File.ReadAllText(Path.Join(_folder, ".github", "workflows", "build.yml")).Should().Be("name: Theirs\n");
        string workflow = File.ReadAllText(Path.Join(_folder, ".github", "workflows", "retrocore-games-greeting.yml"));
        workflow.Should().Contain("\nname: Build greeting\n");
        File.ReadAllText(Path.Join(project, "README.md")).Should().Contain("`.github/workflows/retrocore-games-greeting.yml`");
        workflow.Should().Contain("run: dotnet retrocore build --all --project games/greeting\n");
        workflow.Should().Contain("path: games/greeting/artifacts/\n");
        File.ReadAllText(Path.Join(project, ".gitignore")).Should().Be("bin/\n/obj/\nartifacts/\n", "/obj/ ignores obj/ already");

        RetrocoreProject loaded = RetrocoreProject.Load(project);
        loaded.Name.Should().Be("greeting", "the project is named for its folder");
        loaded.Targets.Select(target => target.Name).Should().Equal("apple2-dos", "bbc-dfs");
        foreach (ProjectTarget target in loaded.Targets)
        {
            File.Exists(ProjectBuild.Build(target).Binary).Should().BeTrue(target.Name);
        }

        // A second init there would replace the project's own files, so it is refused; a repository file with comments
        // is kept, with a word on what to add.
        Run(init: true, "6502", "--output", project).Error.Should().Contain("is already there; retrocore writes a project only where none of its files are.");
        Write(".vscode/extensions.json", "// ours\n{ \"recommendations\": [] }");
        Directory.CreateDirectory(Path.Join(_folder, "second"));
        (code, output, error) = Run(init: true, "6502", "--name", "second", "--machines", "pet", "--output", Path.Join(_folder, "second"));
        code.Should().Be(0, error);
        output.Should().Contain("add \"retrocore.retrocore\" to its recommendations yourself");
        output.Should().Contain("already pins retrocore");
        File.ReadAllText(Path.Join(_folder, ".vscode", "extensions.json")).Should().StartWith("// ours");
    }

    /// <summary>
    ///  <c>retrocore init</c> at a repository's root that has a <c>build.yml</c> of its own gives the project a workflow
    ///  of its own name, and its README names that one; a manifest entry for the tool with no version is kept, and the
    ///  command says so rather than that it pins one.
    /// </summary>
    [TestMethod]
    public void InitAtTheRootKeepsTheRepositorysWorkflow()
    {
        Directory.CreateDirectory(Path.Join(_folder, ".git"));
        Write(".github/workflows/build.yml", "name: Theirs\n");
        Write(".config/dotnet-tools.json", """{ "version": 1, "isRoot": true, "tools": { "retrocore": {} } }""");

        (int code, string output, string error) = Run(init: true, "6502", "--name", "greeting", "--machines", "bbc", "--output", _folder);
        code.Should().Be(0, error);
        File.ReadAllText(Path.Join(_folder, ".github", "workflows", "build.yml")).Should().Be("name: Theirs\n");
        string workflow = File.ReadAllText(Path.Join(_folder, ".github", "workflows", "retrocore-greeting.yml"));
        workflow.Should().Contain("run: dotnet retrocore build --all\n");
        File.ReadAllText(Path.Join(_folder, "README.md")).Should().Contain("`.github/workflows/retrocore-greeting.yml`, at the repository's root");
        output.Should().Contain("its retrocore entry gives no version");
    }

    /// <summary>
    ///  <c>retrocore new --list --json</c> gives each template's families and machines, for tools to read.
    /// </summary>
    [TestMethod]
    public void ListGivesTheTemplatesAsJson()
    {
        (int code, string output, string error) = Run(init: false, "--list", "--json");
        code.Should().Be(0, error);
        JsonNode list = JsonNode.Parse(output) ?? throw new AssertFailedException("No list.");
        Text(list, "version").Should().Be(ProjectScaffold.ToolVersion);
        Text(list, "templates", 0, "name").Should().Be("6502");
        Text(list, "templates", 0, "cpu").Should().Be("6502");
        JsonNode apple2 = At(list, "templates", 0, "families", 1);
        Text(apple2, "name").Should().Be("apple2");
        Text(apple2, "target").Should().Be("apple2-dos");
        Texts(apple2, "machines").Should().Equal("apple2-iie-enhanced", "apple2-iie", "apple2-iiplus", "apple2-ii");

        (code, output, _) = Run(init: false, "--list");
        code.Should().Be(0);
        output.Should().Contain("6502: 6502 assembly");
        output.Should().Contain("  pet: pet-basic (pet4032, basic); machines pet2001-basic2, pet2001, pet4032, pet4032-business");
    }

    private static (int Code, string Output, string Error) Run(bool init, params string[] args)
    {
        using StringWriter output = new();
        using StringWriter error = new();
        int code = NewCommand.Run(init, args, output, error);
        return (code, output.ToString(), error.ToString());
    }

    // The node at a path of names and indexes.
    private static JsonNode At(JsonNode node, params object[] path)
    {
        JsonNode? current = node;
        foreach (object step in path)
        {
            current = step is int index ? current?[index] : current?[(string)step];
        }

        return current ?? throw new AssertFailedException($"No {string.Join("/", path)} in {node.ToJsonString()}.");
    }

    private static string? Text(JsonNode node, params object[] path) => (string?)At(node, path);

    private static IEnumerable<string?> Texts(JsonNode node, params object[] path) =>
        At(node, path).AsArray().Select(item => (string?)item);

    private static JsonNode ReadJson(string file) =>
        JsonNode.Parse(File.ReadAllText(file)) ?? throw new AssertFailedException($"{file} holds no JSON.");

    private static string Refusal(params string[] args)
    {
        (int code, _, string error) = Run(init: false, args);
        code.Should().Be(1, error);
        return error;
    }

    private static List<string> Files(string folder) =>
        [.. Directory.EnumerateFiles(folder, "*", SearchOption.AllDirectories).Select(file => Path.GetRelativePath(folder, file).Replace('\\', '/'))];

    private void Write(string path, string text)
    {
        string file = Path.Join(_folder, path);
        Directory.CreateDirectory(Path.GetDirectoryName(file) ?? _folder);
        File.WriteAllText(file, text);
    }
}
