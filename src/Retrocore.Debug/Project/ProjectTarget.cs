// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug.Project;

/// <summary>
///  One of a project's targets: a machine from the extension's catalog and the environment a program runs in there.
/// </summary>
internal sealed class ProjectTarget
{
    /// <summary>
    ///  The environments a target can name; only <c>bare</c> builds yet.
    /// </summary>
    internal static readonly string[] Environments =
        ["bare", "wozmon", "dos33", "prodos", "sos", "basic", "dfs", "cpm", "level2", "trsdos", "colorbasic", "diskbasic"];

    // The machines each environment runs on, by catalog id, as the SDK plan's targets table gives them; bare runs on
    // every machine, and the Model 4P is listed beside the Model 4. What a machine also needs is not checked yet:
    // ProDOS on a II Plus needs 64K, and CP/M on an Apple II needs a SoftCard.
    private static readonly Dictionary<string, string[]> s_machines = new()
    {
        ["wozmon"] = ["apple1"],
        ["dos33"] = ["apple2-ii", "apple2-iiplus", "apple2-iie", "apple2-iie-enhanced"],
        ["prodos"] = ["apple2-iiplus", "apple2-iie", "apple2-iie-enhanced"],
        ["sos"] = ["apple3"],
        ["basic"] = ["pet2001-basic2", "pet2001", "pet4032", "pet4032-business"],
        ["dfs"] = ["bbcb", "bbca"],
        ["cpm"] = ["apple2-ii", "apple2-iiplus", "apple2-iie", "apple2-iie-enhanced", "trs80-model4", "trs80-model4p", "altair", "kaypro2"],
        ["level2"] = ["trs80-model1-level2", "trs80-model3"],
        ["trsdos"] = ["trs80-model1-level2", "trs80-model3", "trs80-model4", "trs80-model4p"],
        ["colorbasic"] = ["coco1", "coco2", "coco3"],
        ["diskbasic"] = ["coco1", "coco2", "coco3"]
    };

    /// <summary>
    ///  The environment a program loaded straight into RAM runs in, with the ROM's routines only.
    /// </summary>
    internal const string Bare = "bare";

    /// <summary>
    ///  The source file extensions a platform folder's files are assembled from; it skips other files, such as
    ///  headers, which sources include.
    /// </summary>
    internal static readonly string[] PlatformExtensions = [".s", ".asm"];

    /// <summary>
    ///  Creates a target.
    /// </summary>
    /// <param name="project">The project it belongs to.</param>
    /// <param name="name">Its name, which also names its output folders.</param>
    internal ProjectTarget(RetrocoreProject project, string name)
    {
        Project = project;
        Name = name;
    }

    /// <summary>
    ///  Gets the project the target belongs to.
    /// </summary>
    internal RetrocoreProject Project { get; }

    /// <summary>
    ///  Gets the target's name, such as <c>apple2-bare</c>.
    /// </summary>
    internal string Name { get; }

    /// <summary>
    ///  Gets the machine.
    /// </summary>
    internal required CatalogMachine Machine { get; init; }

    /// <summary>
    ///  Gets the environment, one of <see cref="Environments"/>.
    /// </summary>
    internal required string Environment { get; init; }

    /// <summary>
    ///  Gets the CPU the target's code keeps to and its build starts with: the target's own <c>cpu</c>, or the
    ///  project's.
    /// </summary>
    internal required ProjectCpu Cpu { get; init; }

    /// <summary>
    ///  Gets the machine's launch options, such as <c>ramKilobytes</c>, as the launch takes them.
    /// </summary>
    internal JsonObject Options { get; init; } = [];

    /// <summary>
    ///  Gets the cards to put in the machine's slots, as a saved machine lists them (<c>{ "4": "mockingboard" }</c>),
    ///  or null to leave the launch's.
    /// </summary>
    internal JsonObject? Cards { get; init; }

    /// <summary>
    ///  Gets the symbols the target defines, over the project's.
    /// </summary>
    internal IReadOnlyDictionary<string, long> Defines { get; init; } = new Dictionary<string, long>();

    /// <summary>
    ///  Gets the sources added for this target only, after the project's and the platform folders'.
    /// </summary>
    internal IReadOnlyList<ProjectSource> Sources { get; init; } = [];

    /// <summary>
    ///  Gets the full path of the target's ld65-style linker configuration, or null for none.
    /// </summary>
    internal string? LinkerConfiguration { get; init; }

    /// <summary>
    ///  Gets the fields the target gives that are not supported yet, such as <c>files</c>.
    /// </summary>
    internal IReadOnlyList<string> Unsupported { get; init; } = [];

    /// <summary>
    ///  Gets the symbols a build defines: the project's, then the target's over them.
    /// </summary>
    /// <returns>Each symbol's value.</returns>
    internal Dictionary<string, long> Symbols()
    {
        Dictionary<string, long> symbols = [with(Project.Defines)];
        foreach ((string name, long value) in Defines) { symbols[name] = value; }
        return symbols;
    }

    /// <summary>
    ///  Throws when the target or its project uses a field that is not supported yet, or an environment that does
    ///  not build yet.
    /// </summary>
    /// <exception cref="ProjectException">Something it uses is not supported yet.</exception>
    internal void RequireSupported()
    {
        List<string> problems =
        [
            .. Project.Unsupported.Select(field => $"the project's '{field}' is not yet supported"),
            .. Unsupported.Select(field => $"'{field}' is not yet supported"),
            .. Project.Sources.Concat(Sources)
                .Where(source => source.Kind != "asm")
                .Select(source => $"the source '{source.Path}' is {source.Kind}, which is not yet supported")
        ];

        if (Environment != Bare)
        {
            problems.Add($"the '{Environment}' environment is not yet supported; only '{Bare}' builds");
        }

        if (problems.Count != 0)
        {
            throw new ProjectException($"{Project.File}: target {Name}: {string.Join("; ", problems)}.");
        }
    }

    /// <summary>
    ///  Gets the CPU a target's code runs on: the machine's, or under CP/M on an Apple II, the SoftCard's Z80.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <param name="environment">The environment.</param>
    /// <returns>The CPU.</returns>
    internal static ProjectCpu MachineCpu(CatalogMachine machine, string environment) =>
        environment == "cpm" && machine.Family == "apple2" ? ProjectCpu.Z80 : machine.Cpu;

    /// <summary>
    ///  Tests whether a machine runs an environment, as the SDK plan's targets table pairs them.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <param name="environment">The environment, one of <see cref="Environments"/>.</param>
    /// <returns>Whether it does; every machine runs <c>bare</c>.</returns>
    internal static bool Runs(CatalogMachine machine, string environment) =>
        environment == Bare || (s_machines.TryGetValue(environment, out string[]? ids) && ids.Contains(machine.Id));

    /// <summary>
    ///  Gets the source files the target assembles, in order: the project's <c>sources</c>, then the platform
    ///  folders (<see cref="PlatformFiles"/>), then the target's own
    ///  <c>sources</c>. A file named twice is assembled once, where it first comes.
    /// </summary>
    /// <returns>The files.</returns>
    /// <exception cref="ProjectException">A file is missing, or a pattern matches nothing.</exception>
    internal List<TargetSourceFile> SourceFiles()
    {
        List<TargetSourceFile> files = [];
        HashSet<string> seen = [with(ProjectGlob.FileNames)];
        void Add(TargetSourceFile file)
        {
            if (seen.Add(file.Path)) { files.Add(file); }
        }

        foreach (ProjectSource source in Project.Sources) { Expand(source).ForEach(Add); }
        foreach (string file in PlatformFiles()) { Add(new(file, Dialect: null)); }
        foreach (ProjectSource source in Sources) { Expand(source).ForEach(Add); }
        if (files.Count == 0)
        {
            throw new ProjectException($"{Project.File}: target {Name} has no sources.");
        }

        return files;
    }

    /// <summary>
    ///  Gets the platform folders' sources for the target: <c>src/platform/&lt;family&gt;/</c>'s, then
    ///  <c>src/platform/&lt;model&gt;/</c>'s, each folder's in ordinal order of their relative paths, the same on every
    ///  system. A model's file takes the place of its family's file of the same relative path, compared as file
    ///  names are.
    /// </summary>
    /// <returns>The files' full paths.</returns>
    internal List<string> PlatformFiles()
    {
        List<KeyValuePair<string, string>> family = Folder(Machine.Family);
        if (Machine.Id == Machine.Family) { return [.. family.Select(entry => entry.Value)]; }

        List<KeyValuePair<string, string>> model = Folder(Machine.Id);
        Dictionary<string, string> replacements = [with(ProjectGlob.FileNames)];
        foreach ((string name, string file) in model) { replacements[name] = file; }
        HashSet<string> familyNames = [with(ProjectGlob.FileNames)];
        List<string> files = [];
        foreach ((string name, string file) in family)
        {
            files.Add(replacements.GetValueOrDefault(name, file));
            familyNames.Add(name);
        }

        files.AddRange(model.Where(entry => !familyNames.Contains(entry.Key)).Select(entry => entry.Value));
        return files;
    }

    // A platform folder's sources by their paths relative to it, with '/' between folders, in ordinal order.
    private List<KeyValuePair<string, string>> Folder(string folder)
    {
        string path = Path.Join(Project.Directory, "src", "platform", folder);
        if (!Directory.Exists(path)) { return []; }
        return
        [
            .. Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories)
                .Where(file => PlatformExtensions.Contains(Path.GetExtension(file), StringComparer.OrdinalIgnoreCase))
                .Select(file => KeyValuePair.Create(Path.GetRelativePath(path, file).Replace('\\', '/'), file))
                .OrderBy(entry => entry.Key, StringComparer.Ordinal)
        ];
    }

    private List<TargetSourceFile> Expand(ProjectSource source)
    {
        if (!ProjectGlob.IsPattern(source.Path))
        {
            string file = Path.GetFullPath(source.Path, Project.Directory);
            return File.Exists(file)
                ? [new(file, source.Dialect)]
                : throw new ProjectException($"{Project.File}: target {Name}: the source '{source.Path}' does not exist.");
        }

        List<string> matched = ProjectGlob.Expand(Project.Directory, source.Path);
        return matched.Count != 0
            ? [.. matched.Select(file => new TargetSourceFile(file, source.Dialect))]
            : throw new ProjectException($"{Project.File}: target {Name}: the sources '{source.Path}' match no files.");
    }
}