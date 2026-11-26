// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Project;

/// <summary>
///  <c>retrocore build [--target name|--all] [--project path]</c>: builds a project's targets as
///  <see cref="ProjectBuild"/> does.
/// </summary>
/// <remarks>
///  <para>
///   The project is the <c>retrocore.json</c> that <c>--project</c> names (a file or its folder), or else the nearest
///   one in the current folder or above it. A root file builds its projects' targets, and <c>--target</c> takes a
///   target's name or <c>project/target</c>. Without <c>--target</c> or <c>--all</c>, the only target there is
///   builds. Each target's line, or its errors, is printed as it builds; with <c>--all</c> the rest still build
///   after one fails. The build includes the SDK beside the host; <c>--sdk-roms</c>, which the host reads for every
///   command, is accepted but changes only where machines load their ROMs.
///  </para>
/// </remarks>
internal static class BuildCommand
{
    private const string Usage = "Usage: retrocore build [--target name|--all] [--project path]";

    /// <summary>
    ///  Runs the command.
    /// </summary>
    /// <param name="args">The arguments after <c>build</c>.</param>
    /// <param name="output">Where each built target's line goes.</param>
    /// <param name="error">Where errors go.</param>
    /// <returns>
    ///  0 when every target built; 1 when one failed, or the project could not be read or the target chosen; 2 for
    ///  wrong arguments.
    /// </returns>
    internal static int Run(string[] args, TextWriter output, TextWriter error)
    {
        string? targetName = null;
        string? projectPath = null;
        bool all = false;
        for (int index = 0; index < args.Length; index++)
        {
            switch (args[index])
            {
                case "--all":
                    all = true;
                    break;
                case "--target" when index + 1 < args.Length:
                    targetName = args[++index];
                    break;
                case "--project" when index + 1 < args.Length:
                    projectPath = args[++index];
                    break;
                case "--sdk-roms" when index + 1 < args.Length:
                    // Program reads it for every command.
                    index++;
                    break;
                default:
                    error.WriteLine($"{args[index]}: unknown or incomplete option.");
                    error.WriteLine(Usage);
                    return 2;
            }
        }

        if (all && targetName is not null)
        {
            error.WriteLine("Give --target or --all, not both.");
            error.WriteLine(Usage);
            return 2;
        }

        List<ProjectTarget> targets;
        try
        {
            string path = projectPath
                ?? Find(Directory.GetCurrentDirectory())
                ?? throw new ProjectException(
                    $"There is no {RetrocoreProject.FileName} in {Directory.GetCurrentDirectory()} or above it; give --project.");

            targets = Select(RetrocoreProject.LoadAll(path), targetName, all);
        }
        catch (Exception exception)
            when (exception is ProjectException or ArgumentException or IOException or UnauthorizedAccessException or NotSupportedException)
        {
            // A path the system cannot take, such as an empty one, is an ArgumentException.
            error.WriteLine(exception.Message);
            return 1;
        }

        // Each project's steps run once, before its first target that can build, and what they print is shown once. When
        // they fail, the error is shown once and the project's other targets are not built.
        int failed = 0;
        Dictionary<RetrocoreProject, bool> steps = [];
        foreach (ProjectTarget target in targets)
        {
            if (steps.TryGetValue(target.Project, out bool stepsRan) && !stepsRan)
            {
                error.WriteLine($"{target.Project.Name}/{target.Name}: not built, as the project's steps failed.");
                failed++;
                continue;
            }

            try
            {
                if (!steps.ContainsKey(target.Project) && Supported(target))
                {
                    steps[target.Project] = false;
                    List<StepResult> results = ProjectSteps.Run(target.Project);
                    steps[target.Project] = true;
                    Report(target.Project, results, output);
                }

                TargetBuild build = ProjectBuild.Build(target);
                Report(target.Project, build.Steps, output);
                (int start, byte[] bytes) = ProjectBuild.Image(build);
                output.WriteLine(
                    $"{target.Project.Name}/{target.Name}: {build.Binary} (${start:X4}-${start + bytes.Length - 1:X4}, {bytes.Length} {(bytes.Length == 1 ? "byte" : "bytes")}, entry ${build.Entry:X4})");
            }
            catch (Exception exception)
                when (exception is ProjectException or ArgumentException or IOException or UnauthorizedAccessException or NotSupportedException)
            {
                error.WriteLine(exception.Message);
                failed++;
            }
        }

        return failed == 0 ? 0 : 1;
    }

    // Each step that ran, with what it read and wrote and what it printed.
    private static void Report(RetrocoreProject project, IEnumerable<StepResult> results, TextWriter output)
    {
        string Relative(string path) => Path.GetRelativePath(project.Directory, path).Replace('\\', '/');
        foreach (StepResult step in results.Where(step => step.Ran))
        {
            string files = string.Join(", ", step.Step.Inputs.Select(Relative)) + " -> " + string.Join(", ", step.Step.Outputs.Select(Relative));
            output.WriteLine($"{project.Name}: ran {Relative(step.Step.Tool)} ({files})");
            if (step.Output.Length != 0) { output.Write(step.Output); }
        }
    }

    // Whether a target builds at all, so its project's steps are worth running for it.
    private static bool Supported(ProjectTarget target)
    {
        try
        {
            target.RequireSupported();
            return true;
        }
        catch (ProjectException)
        {
            return false;
        }
    }

    /// <summary>
    ///  Finds the nearest project file in a folder or above it.
    /// </summary>
    /// <param name="folder">The folder to start in.</param>
    /// <returns>The file's path, or null when there is none.</returns>
    internal static string? Find(string folder)
    {
        for (string? current = Path.GetFullPath(folder); current is not null; current = Path.GetDirectoryName(current))
        {
            string file = Path.Join(current, RetrocoreProject.FileName);
            if (File.Exists(file)) { return file; }
        }

        return null;
    }

    /// <summary>
    ///  Chooses the targets to build.
    /// </summary>
    /// <param name="projects">The projects loaded.</param>
    /// <param name="name">The target named, or null.</param>
    /// <param name="all">Whether every target builds.</param>
    /// <returns>The targets, in the projects' and their files' order.</returns>
    /// <exception cref="ProjectException">No target, or more than one, is the one meant.</exception>
    internal static List<ProjectTarget> Select(IReadOnlyList<RetrocoreProject> projects, string? name, bool all)
    {
        List<ProjectTarget> every = [.. projects.SelectMany(project => project.Targets)];
        string names = string.Join(", ", every.Select(Qualified));
        if (all) { return every; }
        if (name is null)
        {
            return every.Count == 1
                ? every
                : throw new ProjectException($"Give --target name or --all; the targets are {names}.");
        }

        List<ProjectTarget> named = [.. every.Where(target => target.Name == name || Qualified(target) == name)];
        return named.Count switch
        {
            1 => named,
            0 => throw new ProjectException($"There is no target '{name}'; the targets are {names}."),
            _ => throw new ProjectException(
                $"The projects {string.Join(" and ", named.Select(target => target.Project.Name))} each have a target '{name}'; name it as project/target, or give that project's own retrocore.json.")
        };
    }

    private static string Qualified(ProjectTarget target) => $"{target.Project.Name}/{target.Name}";
}