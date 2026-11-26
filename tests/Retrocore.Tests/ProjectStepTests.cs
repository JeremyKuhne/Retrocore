// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug.Project;

namespace Retrocore.Tests;

/// <summary>
///  A project's <c>steps</c> run their tools before assembly, and run again only when the tool, its included files,
///  its arguments or its inputs change, or its outputs are not as it left them.
/// </summary>
[TestClass]
public sealed class ProjectStepTests
{
    private string _folder = "";
    private int _runs;

    /// <summary>
    ///  Gets each test a folder of its own.
    /// </summary>
    [TestInitialize]
    public void Initialize()
    {
        _folder = Path.Join(Path.GetTempPath(), "retrocore-steps-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_folder);
        _runs = 0;
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
    ///  A step's paths start from the project's folder, <c>${obj}</c> is its intermediate folder, and <c>${in}</c> and
    ///  <c>${out}</c> stand for every input and output.
    /// </summary>
    [TestMethod]
    public void StepsLoadTheirPathsAndArguments()
    {
        Project("""[{ "tool": "tools/pack.cs", "args": ["pack", "${in}", "--to", "${out}", "${obj}/x"], "in": ["a.dat", "b.dat"], "out": "${obj}/game.bin" }]""");
        RetrocoreProject project = RetrocoreProject.Load(_folder);
        ProjectStep step = project.Steps.Should().ContainSingle().Subject;
        step.Tool.Should().Be(Path.Join(_folder, "tools", "pack.cs"));
        step.Inputs.Should().Equal(Path.Join(_folder, "a.dat"), Path.Join(_folder, "b.dat"));
        step.Outputs.Should().Equal(Path.Join(_folder, "obj", "game.bin"));
        step.ToolArguments(project.Intermediate).Should().Equal(
            "pack", Path.Join(_folder, "a.dat"), Path.Join(_folder, "b.dat"), "--to", Path.Join(_folder, "obj", "game.bin"),
            project.Intermediate + "/x");

        Project("""[{ "tool": "tools/pack.cs", "in": "a.dat", "out": "${obj}/game.bin" }]""");
        RetrocoreProject.Load(_folder).Steps[0].ToolArguments("").Should().Equal(
            Path.Join(_folder, "a.dat"), Path.Join(_folder, "obj", "game.bin"));
    }

    /// <summary>
    ///  A malformed step fails to load, naming the step.
    /// </summary>
    /// <param name="steps">The project's steps.</param>
    /// <param name="message">The end of the error.</param>
    [TestMethod]
    [DataRow("""{ "tool": "a.cs" }""", "'steps' must be a list of steps, each an object giving 'tool'.")]
    [DataRow("""[{ "in": "a.dat" }]""", "step 1 must give 'tool'.")]
    [DataRow("""[{ "tool": "a.py" }]""", "step 1's tool a.py must be a C# file-based app (.cs) or a project (.csproj).")]
    [DataRow("""[{ "tool": "a.cs", "run": 1 }]""", "step 1 has no field 'run'; its fields are tool, args, in, out.")]
    [DataRow("""[{ "tool": "a.cs", "in": "${target}/a" }]""", "step 1: '${target}/a' uses a variable it cannot; a path can use ${obj} only.")]
    [DataRow("""[{ "tool": "a.cs", "args": ["x${in}"] }]""", "step 1: 'x${in}' uses a variable it cannot; an argument can use ${obj}, or be exactly ${in} or ${out}.")]
    [DataRow("""[{ "tool": "a.cs", "args": "x" }]""", "step 1's 'args' must be a list of arguments.")]
    [DataRow("""[{ "tool": "${obj}/a.cs" }]""", "step 1: the tool '${obj}/a.cs' uses a variable; a tool's path cannot.")]
    public void MalformedStepsFailToLoad(string steps, string message)
    {
        Project(steps);
        Error(() => RetrocoreProject.Load(_folder)).Should().EndWith(message);
    }

    /// <summary>
    ///  A step runs once, then not again until its tool, a file the tool includes, its input or its output changes.
    /// </summary>
    [TestMethod]
    public void StepsRunOnlyWhenWhatTheyReadOrWroteChanges()
    {
        Project("""[{ "tool": "tools/pack.cs", "in": "game.dat", "out": "${obj}/game.bin" }]""");
        Write("tools/pack.cs", "#:include Part.cs\nConsole.WriteLine();\n");
        Write("tools/Part.cs", "class Part;\n");
        Write("game.dat", "1");

        Ran().Should().BeTrue("the step has not run");
        File.ReadAllText(Path.Join(_folder, "obj", "game.bin")).Should().Be("1");
        Ran().Should().BeFalse("nothing changed");

        Write("game.dat", "2");
        Ran().Should().BeTrue("the input changed");
        Ran().Should().BeFalse("nothing changed since");

        Write("tools/Part.cs", "class Part2;\n");
        Ran().Should().BeTrue("a file the tool includes changed");

        Write("tools/pack.cs", "#:include Part.cs\nConsole.WriteLine(1);\n");
        Ran().Should().BeTrue("the tool changed");

        Write("obj/game.bin", "edited");
        Ran().Should().BeTrue("the output is not as the step left it");
        File.Delete(Path.Join(_folder, "obj", "game.bin"));
        Ran().Should().BeTrue("the output is gone");

        Write("tools/Other.cs", "class Other;\n");
        Ran().Should().BeFalse("a file the tool does not include changed");

        Project("""[{ "tool": "tools/pack.cs", "args": ["${in}", "${out}", "again"], "in": "game.dat", "out": "${obj}/game.bin" }]""");
        Ran().Should().BeTrue("its arguments changed");
        Ran().Should().BeFalse("nothing changed since");
        _runs.Should().Be(7);
    }

    /// <summary>
    ///  A step that fails, or does not write its output, fails the build with what it printed; one whose tool or
    ///  input is missing fails before it runs.
    /// </summary>
    [TestMethod]
    public void FailingStepsFailTheBuild()
    {
        Project("""[{ "tool": "tools/pack.cs", "in": "game.dat", "out": "${obj}/game.bin" }]""");
        RetrocoreProject project = RetrocoreProject.Load(_folder);
        Error(() => ProjectSteps.Run(project, Copy)).Should().EndWith($"the step {Path.Join("tools", "pack.cs")}: the tool does not exist.");

        Write("tools/pack.cs", "");
        Error(() => ProjectSteps.Run(project, Copy)).Should().EndWith("the step tools" + Path.DirectorySeparatorChar + "pack.cs: its input game.dat does not exist.");

        Write("game.dat", "1");
        Error(() => ProjectSteps.Run(project, (_, _) => (3, "bad data\n"))).Should().EndWith("failed (exit code 3):" + Environment.NewLine + "bad data");
        Error(() => ProjectSteps.Run(project, (_, _) => (0, ""))).Should().EndWith(
            $"did not write its output {Path.Join("obj", "game.bin")}.");

        _runs.Should().Be(0);
    }

    /// <summary>
    ///  <c>retrocore build</c> runs a real file-based app with <c>dotnet run</c>, whose output the sources
    ///  <c>.incbin</c>, then skips it when nothing changed.
    /// </summary>
    [TestMethod]
    public void BuildRunsAFileBasedAppBeforeAssembling()
    {
        Write("retrocore.json", """
            { "sdk": "1", "name": "steps", "cpu": "6502", "sources": ["main.s"],
              "steps": [{ "tool": "tools/double.cs", "args": ["${in}", "${out}"], "in": "data.txt", "out": "${obj}/data.bin" }],
              "targets": { "t": { "machine": "apple2-iiplus", "environment": "bare" } } }
            """);

        Write("tools/double.cs", """
            // Writes each byte of its input twice.
            byte[] bytes = File.ReadAllBytes(args[0]);
            File.WriteAllBytes(args[1], [.. bytes.SelectMany(value => new[] { value, value })]);
            Console.WriteLine($"doubled {bytes.Length}");
            """);

        Write("data.txt", "AB");
        Write("main.s", """
                rts
                .incbin "obj/data.bin"
            """);

        TargetBuild build = ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("t"));
        build.Steps.Should().ContainSingle().Which.Ran.Should().BeTrue();
        build.Steps[0].Output.Should().Contain("doubled 2");
        File.ReadAllBytes(build.Binary).Should().Equal(0x60, (byte)'A', (byte)'A', (byte)'B', (byte)'B');

        using StringWriter output = new() { NewLine = "\n" };
        using StringWriter error = new() { NewLine = "\n" };
        BuildCommand.Run(["--project", _folder], output, error).Should().Be(0, error.ToString());
        output.ToString().Should().NotContain(": ran ").And.Contain("steps/t:");
    }

    private bool Ran() =>
        ProjectSteps.Run(RetrocoreProject.Load(_folder), Copy).Should().ContainSingle().Subject.Ran;

    // A tool that copies its input to its output.
    private (int ExitCode, string Output) Copy(ProjectStep step, RetrocoreProject project)
    {
        _runs++;
        File.Copy(step.Inputs[0], step.Outputs[0], overwrite: true);
        return (0, "copied\n");
    }

    private void Project(string steps) => Write("retrocore.json", $$"""
        { "sdk": "1", "cpu": "6502", "sources": ["main.s"], "steps": {{steps}},
          "targets": { "t": { "machine": "apple2-iiplus", "environment": "bare" } } }
        """);

    private void Write(string path, string text)
    {
        string file = Path.Join(_folder, path);
        Directory.CreateDirectory(Path.GetDirectoryName(file) ?? _folder);
        File.WriteAllText(file, text);
    }

    private static string Error(Action action)
    {
        try
        {
            action();
        }
        catch (ProjectException exception)
        {
            return exception.Message;
        }

        throw new AssertFailedException("Expected a ProjectException.");
    }
}
