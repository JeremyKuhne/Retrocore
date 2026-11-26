// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;

namespace Retrocore.Debug.Project;

/// <summary>
///  Runs a project's <c>steps</c> before its targets assemble, skipping each one whose tool and inputs are unchanged
///  since it last ran and whose outputs are as it left them.
/// </summary>
/// <remarks>
///  <para>
///   A step's record, <c>obj/steps/&lt;key&gt;.json</c>, is named by a hash of the step itself (its tool, arguments,
///   inputs and outputs), so a changed argument makes a new record, and holds the SHA-256 of what it read (the tool's
///   files and its inputs' contents) and of what it wrote. The tool's files are the tool and, for a file-based app,
///   the files its <c>#:include</c> directives name and the folders of the projects its <c>#:project</c> directives
///   name; for a project, every file in its folder outside <c>bin/</c> and <c>obj/</c> and outside the project's own
///   output and intermediate folders, every step's outputs and folders whose names start with <c>.</c>. Deleting
///   <c>obj/</c> runs every step again.
///  </para>
/// </remarks>
internal static class ProjectSteps
{
    /// <summary>
    ///  The folder under the project's intermediate folder that holds the steps' records.
    /// </summary>
    internal const string RecordFolder = "steps";

    // The file-based app directives that bring in more of the tool's files.
    private const string IncludeDirective = "#:include ";
    private const string ProjectDirective = "#:project ";

    /// <summary>
    ///  Runs a project's steps, in order, that are not up to date.
    /// </summary>
    /// <param name="project">The project.</param>
    /// <param name="run">Runs a tool; by default <see cref="Start"/>.</param>
    /// <returns>Each step, whether it ran, and what it printed.</returns>
    /// <exception cref="ProjectException">
    ///  A tool or an input is missing, a tool fails, or it does not write its outputs.
    /// </exception>
    /// <exception cref="IOException">A record cannot be written.</exception>
    /// <exception cref="UnauthorizedAccessException">A record cannot be written.</exception>
    internal static List<StepResult> Run(RetrocoreProject project, Func<ProjectStep, RetrocoreProject, (int ExitCode, string Output)>? run = null)
    {
        run ??= Start;
        List<StepResult> results = [];
        foreach (ProjectStep step in project.Steps)
        {
            string name = Path.GetRelativePath(project.Directory, step.Tool);
            if (!File.Exists(step.Tool))
            {
                throw new ProjectException($"{project.File}: the step {name}: the tool does not exist.");
            }

            foreach (string input in step.Inputs.Where(input => !File.Exists(input)))
            {
                throw new ProjectException(
                    $"{project.File}: the step {name}: its input {Path.GetRelativePath(project.Directory, input)} does not exist.");
            }

            string record = Path.Join(project.Intermediate, RecordFolder, Key(project, step) + ".json");
            string read = ReadDigest(project, step);
            if (Recorded(record) is { } last && last.Read == read && last.Wrote == WroteDigest(project, step))
            {
                results.Add(new(step, Ran: false, Output: ""));
                continue;
            }

            foreach (string output in step.Outputs)
            {
                if (Path.GetDirectoryName(output) is { } folder) { Directory.CreateDirectory(folder); }
            }

            (int exitCode, string text) = run(step, project);
            if (exitCode != 0)
            {
                throw new ProjectException(
                    $"{project.File}: the step {name} failed (exit code {exitCode}):{Environment.NewLine}{text.TrimEnd()}");
            }

            foreach (string output in step.Outputs.Where(output => !File.Exists(output)))
            {
                throw new ProjectException(
                    $"{project.File}: the step {name} did not write its output {Path.GetRelativePath(project.Directory, output)}.");
            }

            Directory.CreateDirectory(Path.Join(project.Intermediate, RecordFolder));
            JsonObject json = new()
            {
                ["tool"] = Relative(project, step.Tool),
                ["read"] = read,
                ["wrote"] = WroteDigest(project, step)
            };

            File.WriteAllText(record, json.ToJsonString(new() { WriteIndented = true }));
            results.Add(new(step, Ran: true, Output: text));
        }

        return results;
    }

    /// <summary>
    ///  Gets the files that make up a step's tool, as its cache key reads them.
    /// </summary>
    /// <param name="project">The project.</param>
    /// <param name="step">The step.</param>
    /// <returns>The files' full paths, the tool first, the rest in ordinal order.</returns>
    internal static List<string> ToolFiles(RetrocoreProject project, ProjectStep step)
    {
        SortedSet<string> files = [with(StringComparer.Ordinal)];
        if (step.IsProject)
        {
            files.UnionWith(ProjectFolderFiles(project, Path.GetDirectoryName(step.Tool) ?? ""));
        }
        else
        {
            Directives(project, step.Tool, files, [with(ProjectGlob.FileNames)]);
        }

        files.Remove(step.Tool);
        return [step.Tool, .. files];
    }

    /// <summary>
    ///  Starts a step's tool with <c>dotnet run</c> in the project's folder and waits for it.
    /// </summary>
    /// <param name="step">The step.</param>
    /// <param name="project">The project.</param>
    /// <returns>The tool's exit code and what it printed, its output and its errors.</returns>
    /// <exception cref="ProjectException"><c>dotnet</c> cannot be started.</exception>
    internal static (int ExitCode, string Output) Start(ProjectStep step, RetrocoreProject project)
    {
        string? host = Environment.GetEnvironmentVariable("DOTNET_HOST_PATH");
        ProcessStartInfo start = new(host is { Length: > 0 } && File.Exists(host) ? host : "dotnet")
        {
            WorkingDirectory = project.Directory,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            RedirectStandardInput = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        start.ArgumentList.Add("run");
        if (step.IsProject) { start.ArgumentList.Add("--project"); }
        start.ArgumentList.Add(step.Tool);
        start.ArgumentList.Add("--");
        foreach (string argument in step.ToolArguments(project.Intermediate)) { start.ArgumentList.Add(argument); }
        start.Environment["DOTNET_NOLOGO"] = "1";
        start.Environment["DOTNET_CLI_TELEMETRY_OPTOUT"] = "1";

        StringBuilder text = new();
        Lock gate = new();
        void Append(object sender, DataReceivedEventArgs line)
        {
            if (line.Data is null) { return; }
            lock (gate) { text.AppendLine(line.Data); }
        }

        try
        {
            using Process process = Process.Start(start)
                ?? throw new ProjectException($"{project.File}: dotnet could not be started for the step {step.Tool}.");

            process.OutputDataReceived += Append;
            process.ErrorDataReceived += Append;
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            process.StandardInput.Close();
            process.WaitForExit();
            lock (gate) { return (process.ExitCode, text.ToString()); }
        }
        catch (System.ComponentModel.Win32Exception exception)
        {
            throw new ProjectException(
                $"{project.File}: dotnet, which runs the step {Path.GetRelativePath(project.Directory, step.Tool)}, could not be started: {exception.Message}");
        }
    }

    // The step's identity: what it runs, with what, from what, to what. Paths are relative to the project, so a
    // moved checkout keeps its records.
    private static string Key(RetrocoreProject project, ProjectStep step)
    {
        string key = string.Join(
            '\u0001',
            Relative(project, step.Tool),
            string.Join('\0', step.Arguments ?? ["<default>"]),
            string.Join('\0', step.Inputs.Select(input => Relative(project, input))),
            string.Join('\0', step.Outputs.Select(output => Relative(project, output))));

        return Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(key)))[..16];
    }

    // What the step reads: each of the tool's files and each input, by its path and its contents.
    private static string ReadDigest(RetrocoreProject project, ProjectStep step)
    {
        using IncrementalHash hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        foreach (string file in ToolFiles(project, step).Concat(step.Inputs))
        {
            AddFile(hash, Relative(project, file), file);
        }

        return Convert.ToHexStringLower(hash.GetHashAndReset());
    }

    // What the step wrote, or null when an output is missing.
    private static string? WroteDigest(RetrocoreProject project, ProjectStep step)
    {
        using IncrementalHash hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        foreach (string output in step.Outputs)
        {
            if (!File.Exists(output)) { return null; }
            AddFile(hash, Relative(project, output), output);
        }

        return Convert.ToHexStringLower(hash.GetHashAndReset());
    }

    private static void AddFile(IncrementalHash hash, string name, string file)
    {
        byte[] bytes = File.ReadAllBytes(file);
        hash.AppendData(Encoding.UTF8.GetBytes($"{name.Replace('\\', '/')}\0{bytes.Length}\0"));
        hash.AppendData(bytes);
    }

    private static (string Read, string? Wrote)? Recorded(string record)
    {
        try
        {
            if (!File.Exists(record)) { return null; }
            JsonNode? json = JsonNode.Parse(File.ReadAllText(record));
            return json?["read"]?.GetValue<string>() is { } read ? (read, json["wrote"]?.GetValue<string>()) : null;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or System.Text.Json.JsonException or InvalidOperationException)
        {
            // A record that cannot be read is no record: the step runs again and writes a new one.
            return null;
        }
    }

    // A file-based app's own file and the files its directives bring in, following includes in included files.
    private static void Directives(RetrocoreProject project, string file, SortedSet<string> files, HashSet<string> seen)
    {
        if (!seen.Add(file) || !File.Exists(file)) { return; }
        files.Add(file);
        string folder = Path.GetDirectoryName(file) ?? "";
        foreach (string line in File.ReadLines(file))
        {
            string text = line.Trim();
            if (text.StartsWith(IncludeDirective, StringComparison.Ordinal))
            {
                string path = Separators(text[IncludeDirective.Length..].Trim());
                IEnumerable<string> included = ProjectGlob.IsPattern(path)
                    ? ProjectGlob.Expand(folder, path)
                    : [Path.GetFullPath(path, folder)];

                foreach (string include in included) { Directives(project, include, files, seen); }
            }
            else if (text.StartsWith(ProjectDirective, StringComparison.Ordinal))
            {
                string path = Path.GetFullPath(Separators(text[ProjectDirective.Length..].Trim()), folder);
                string projectFolder = Directory.Exists(path) ? path : Path.GetDirectoryName(path) ?? "";
                files.UnionWith(ProjectFolderFiles(project, projectFolder));
            }
            else if (text.Length != 0 && !text.StartsWith('#') && !text.StartsWith("//", StringComparison.Ordinal))
            {
                // Directives come before the code.
                break;
            }
        }
    }

    // A tool project's files: everything in its folder but what builds write there (its bin/ and obj/, the retrocore
    // project's output and intermediate folders, and every step's outputs, should the tool sit beside retrocore.json)
    // and folders whose names start with '.', such as .git/ and .vs/, which change as the repository is used.
    // The walk does not go into the folders it leaves out, so a large .git/ costs nothing, nor into links. Should the
    // project's output or intermediate folder hold the tool's folder itself, that folder's files still count.
    private static List<string> ProjectFolderFiles(RetrocoreProject project, string folder)
    {
        List<string> files = [];
        if (!Directory.Exists(folder)) { return files; }
        HashSet<string> skipped =
        [
            with(ProjectGlob.FileNames),
            .. new[] { Path.Join(folder, "bin"), Path.Join(folder, "obj"), project.Output, project.Intermediate }
                .Select(path => Path.TrimEndingDirectorySeparator(Path.GetFullPath(path)))
        ];

        HashSet<string> outputs = [with(ProjectGlob.FileNames), .. project.Steps.SelectMany(step => step.Outputs)];
        void Walk(string current)
        {
            files.AddRange(Directory.EnumerateFiles(current).Where(file => !outputs.Contains(file)));
            foreach (string child in Directory.EnumerateDirectories(current))
            {
                // A link or junction is not followed, so one to a folder above cannot loop.
                if (!Path.GetFileName(child).StartsWith('.')
                    && !skipped.Contains(child)
                    && !File.GetAttributes(child).HasFlag(FileAttributes.ReparsePoint))
                {
                    Walk(child);
                }
            }
        }

        Walk(Path.TrimEndingDirectorySeparator(Path.GetFullPath(folder)));
        return files;
    }

    // A directive's path with '/' between folders, as dotnet takes it on every system.
    private static string Separators(string path) => path.Replace('\\', '/');

    private static string Relative(RetrocoreProject project, string path) =>
        Path.GetRelativePath(project.Directory, path).Replace('\\', '/');
}
