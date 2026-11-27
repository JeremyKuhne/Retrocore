// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json;
using System.Text.Json.Nodes;

namespace Retrocore.Debug.Project;

/// <summary>
///  A project as its <c>retrocore.json</c> describes it: the CPU its code keeps to, its sources and defines, and its
///  targets.
/// </summary>
/// <remarks>
///  <para>
///   A repository has one <c>retrocore.json</c> at its root, which is either a project or lists its projects'
///   folders (<c>{ "projects": ["interpreter", "tools/editor"] }</c>), each with its own <c>retrocore.json</c>. The
///   file is JSON with comments and trailing commas. Fields it does not know are errors, so a misspelled one is not
///   silently ignored; the schema beside the host (<c>Schemas/project-1.schema.json</c>) describes the same fields.
///  </para>
/// </remarks>
internal sealed class RetrocoreProject
{
    /// <summary>
    ///  The project file's name.
    /// </summary>
    internal const string FileName = "retrocore.json";

    /// <summary>
    ///  The SDK's major versions this host builds.
    /// </summary>
    internal static readonly string[] SdkVersions = ["1"];

    /// <summary>
    ///  The fields a project can give.
    /// </summary>
    internal static readonly string[] ProjectFields =
        ["$schema", "sdk", "name", "cpu", "sources", "steps", "defines", "entry", "output", "targets"];

    /// <summary>
    ///  The fields a root file that lists projects can give.
    /// </summary>
    internal static readonly string[] RootFields = ["$schema", "projects"];

    /// <summary>
    ///  The fields a target can give.
    /// </summary>
    internal static readonly string[] TargetFields =
    [
        "machine", "environment", "cpu", "options", "cards", "defines", "sources", "linkerConfiguration",
        "memoryMap", "files", "image", "bootImage"
    ];

    /// <summary>
    ///  The fields a source object can give.
    /// </summary>
    internal static readonly string[] SourceFields = ["path", "dialect", "kind"];

    /// <summary>
    ///  The fields an entry of a target's <c>files</c> can give, as an object.
    /// </summary>
    internal static readonly string[] FileFields = ["path", "name", "address"];

    /// <summary>
    ///  The fields a target's <c>image</c> can give, as an object.
    /// </summary>
    internal static readonly string[] ImageFields = ["template", "boot"];

    /// <summary>
    ///  The dialects a source object can name.
    /// </summary>
    internal static readonly string[] Dialects = ["native", "ca65", "merlin", "macro10"];

    /// <summary>
    ///  The source kinds; only <c>asm</c>, the default, builds yet.
    /// </summary>
    internal static readonly string[] Kinds = ["asm", "basic"];

    /// <summary>
    ///  The launch options a target's <c>options</c> cannot give, as the project and target decide them.
    /// </summary>
    internal static readonly string[] ReservedOptions =
    [
        "type", "request", "name", "project", "target", "machine", "model", "rom", "source", "program", "basic",
        "debugFile", "dialect", "linkerConfiguration", "machineState", "dos", "loadAddress", "entryAddress",
        "executable", "basicSource", "stopOnEntry", "checkContracts"
    ];

    private static readonly JsonDocumentOptions s_json = new()
    {
        CommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true
    };

    private readonly List<ProjectTarget> _targets = [];

    private RetrocoreProject(string file)
    {
        File = file;
        Directory = Folder(file);
    }

    /// <summary>
    ///  Gets the project file's full path.
    /// </summary>
    internal string File { get; }

    /// <summary>
    ///  Gets the project's folder, which its relative paths start from.
    /// </summary>
    internal string Directory { get; }

    /// <summary>
    ///  Gets the SDK's major version the project is written against.
    /// </summary>
    internal string Sdk { get; private set; } = "1";

    /// <summary>
    ///  Gets the project's name, which names its output files; by default its folder's.
    /// </summary>
    internal string Name { get; private set; } = "";

    /// <summary>
    ///  Gets the CPU the project's code keeps to; a target can raise it, never lower it.
    /// </summary>
    internal ProjectCpu Cpu { get; private set; } = ProjectCpu.Mos6502;

    /// <summary>
    ///  Gets the sources every target assembles.
    /// </summary>
    internal IReadOnlyList<ProjectSource> Sources { get; private set; } = [];

    /// <summary>
    ///  Gets the steps that run before any target assembles, in order.
    /// </summary>
    internal IReadOnlyList<ProjectStep> Steps { get; private set; } = [];

    /// <summary>
    ///  Gets the symbols every target defines.
    /// </summary>
    internal IReadOnlyDictionary<string, long> Defines { get; private set; } = new Dictionary<string, long>();

    /// <summary>
    ///  Gets the entry point's label, or null to start at the first byte the project's own sources emit, or at the
    ///  first section when they emit none.
    /// </summary>
    internal string? Entry { get; private set; }

    /// <summary>
    ///  Gets the full path of the folder build output goes in, each target's in a folder of its name.
    /// </summary>
    internal string Output { get; private set; } = "";

    /// <summary>
    ///  Gets the full path of the folder intermediate files go in, each target's in a folder of its name.
    /// </summary>
    internal string Intermediate => Path.Join(Directory, "obj");

    /// <summary>
    ///  Gets the targets, in the file's order.
    /// </summary>
    internal IReadOnlyList<ProjectTarget> Targets => _targets;

    /// <summary>
    ///  Finds a target by name.
    /// </summary>
    /// <param name="name">The target's name, compared exactly.</param>
    /// <returns>The target.</returns>
    /// <exception cref="ProjectException">The project has no such target; the message lists those it has.</exception>
    internal ProjectTarget Target(string name) =>
        _targets.FirstOrDefault(target => target.Name == name)
            ?? throw new ProjectException(
                $"{File}: there is no target '{name}'; the targets are {string.Join(", ", _targets.Select(target => target.Name))}.");

    /// <summary>
    ///  Loads the projects a path names: a project's folder or file, or a root file's folder or file, whose
    ///  projects are each loaded.
    /// </summary>
    /// <param name="path">A folder holding a <c>retrocore.json</c>, or the file itself.</param>
    /// <returns>The projects, one for a project file, or each a root file lists in its order.</returns>
    /// <exception cref="ProjectException">A file is missing or malformed.</exception>
    internal static List<RetrocoreProject> LoadAll(string path)
    {
        string file = FilePath(path);
        JsonObject root = Read(file);
        if (!root.ContainsKey("projects")) { return [Load(file, root)]; }

        Check(file, "the root file", root, RootFields);
        if (root["projects"] is not JsonArray { Count: > 0 } folders)
        {
            throw new ProjectException($"{file}: 'projects' must list the folders of the repository's projects.");
        }

        string directory = Folder(file);
        List<RetrocoreProject> projects = [];
        foreach (JsonNode? folder in folders)
        {
            string name = Text(file, "an entry of 'projects'", folder);
            string projectFile = Path.Join(Path.GetFullPath(name, directory), FileName);
            if (!System.IO.File.Exists(projectFile))
            {
                throw new ProjectException($"{file}: the project '{name}' has no {FileName}.");
            }

            JsonObject project = Read(projectFile);
            if (project.ContainsKey("projects"))
            {
                throw new ProjectException($"{projectFile}: only the repository's root file lists projects.");
            }

            projects.Add(Load(projectFile, project));
        }

        return projects;
    }

    /// <summary>
    ///  Loads a single project.
    /// </summary>
    /// <param name="path">The project's folder or its <c>retrocore.json</c>.</param>
    /// <returns>The project.</returns>
    /// <exception cref="ProjectException">The file is missing or malformed, or lists projects.</exception>
    internal static RetrocoreProject Load(string path)
    {
        string file = FilePath(path);
        JsonObject root = Read(file);
        return root.ContainsKey("projects")
            ? throw new ProjectException($"{file}: the file lists projects; name one of their folders.")
            : Load(file, root);
    }

    private static string FilePath(string path)
    {
        string full = Path.GetFullPath(path);
        string file = System.IO.Directory.Exists(full) ? Path.Join(full, FileName) : full;
        return System.IO.File.Exists(file) ? file : throw new ProjectException($"{file} does not exist.");
    }

    private static string Folder(string file) =>
        Path.GetDirectoryName(file) ?? throw new ProjectException($"{file} is not in a folder.");

    private static JsonObject Read(string file)
    {
        try
        {
            JsonObject json = JsonNode.Parse(System.IO.File.ReadAllText(file), documentOptions: s_json) as JsonObject
                ?? throw new ProjectException($"{file}: the file must hold a JSON object.");

            // An object's keys are only checked for repeats as it is first read.
            Walk(json);
            return json;
        }
        catch (JsonException exception)
        {
            throw new ProjectException($"{file}: {exception.Message}");
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            throw new ProjectException($"{file} cannot be read: {exception.Message}");
        }
        catch (ArgumentException exception)
        {
            throw new ProjectException($"{file}: a field is given twice ({exception.Message}).");
        }
    }

    private static void Walk(JsonNode? node)
    {
        if (node is JsonObject json)
        {
            foreach ((string _, JsonNode? value) in json) { Walk(value); }
        }
        else if (node is JsonArray array)
        {
            foreach (JsonNode? item in array) { Walk(item); }
        }
    }

    private static RetrocoreProject Load(string file, JsonObject json)
    {
        RetrocoreProject project = new(file);
        Check(file, "the project", json, ProjectFields);
        project.Sdk = json["sdk"] is { } sdk ? Text(file, "'sdk'", sdk) : throw Missing(file, "the project", "sdk");
        if (!SdkVersions.Contains(project.Sdk))
        {
            throw new ProjectException(
                $"{file}: the project is written for SDK {project.Sdk}; this tool builds SDK {string.Join(" and ", SdkVersions)}.");
        }

        project.Name = json["name"] is { } name ? Text(file, "'name'", name) : Path.GetFileName(project.Directory);
        if (!IsFileName(project.Name))
        {
            throw new ProjectException(json.ContainsKey("name")
                ? $"{file}: the name '{project.Name}' must be letters, digits, '-', '_' and '.'."
                : $"{file}: the project's folder name, '{project.Name}', cannot name its output; give 'name', letters, digits, '-', '_' and '.'.");
        }

        project.Cpu = json["cpu"] is { } cpu ? ReadCpu(file, "the project", cpu) : throw Missing(file, "the project", "cpu");
        project.Sources = json["sources"] is { } sources ? ReadSources(file, "the project", sources) : [];
        project.Steps = json["steps"] is { } steps ? ReadSteps(project, steps) : [];
        project.Defines = json["defines"] is { } defines ? ReadDefines(file, "the project", defines) : [];
        project.Entry = json["entry"] is { } entry ? Text(file, "'entry'", entry) : null;
        project.Output = Path.GetFullPath(
            json["output"] is { } output ? Text(file, "'output'", output) : "artifacts",
            project.Directory);

        if (json["targets"] is not JsonObject { Count: > 0 } targets)
        {
            throw new ProjectException($"{file}: the project must give 'targets', an object naming at least one target.");
        }

        foreach ((string targetName, JsonNode? target) in targets)
        {
            project._targets.Add(Target(project, targetName, target));
        }

        return project;
    }

    private static ProjectTarget Target(RetrocoreProject project, string name, JsonNode? node)
    {
        string file = project.File;
        string where = $"target {name}";
        if (!IsFileName(name))
        {
            throw new ProjectException($"{file}: the target name '{name}' must be letters, digits, '-', '_' and '.'.");
        }

        if (node is not JsonObject json)
        {
            throw new ProjectException($"{file}: {where} must be an object.");
        }

        Check(file, where, json, TargetFields);
        string machineId = json["machine"] is { } machineNode ? Text(file, $"{where}'s 'machine'", machineNode) : throw Missing(file, where, "machine");
        CatalogMachine machine = CatalogMachine.Find(machineId)
            ?? throw new ProjectException(
                $"{file}: {where}: there is no machine '{machineId}'; the machines are {string.Join(", ", CatalogMachine.All.Select(known => known.Id))}.");

        string environment = json["environment"] is { } environmentNode
            ? Text(file, $"{where}'s 'environment'", environmentNode)
            : throw Missing(file, where, "environment");

        if (!ProjectTarget.Environments.Contains(environment))
        {
            throw new ProjectException(
                $"{file}: {where}: there is no environment '{environment}'; the environments are {string.Join(", ", ProjectTarget.Environments)}.");
        }

        if (!ProjectTarget.Runs(machine, environment))
        {
            throw new ProjectException($"{file}: {where}: {machine.Id} does not run the '{environment}' environment.");
        }

        ProjectCpu cpu = project.Cpu;
        if (json["cpu"] is { } cpuNode)
        {
            cpu = ReadCpu(file, where, cpuNode);
            if (!cpu.Runs(project.Cpu))
            {
                throw new ProjectException(
                    $"{file}: {where}: its CPU, {cpu}, does not run the project's {project.Cpu} code; a target can raise the project's CPU, never lower it.");
            }
        }

        ProjectCpu runs = ProjectTarget.MachineCpu(machine, environment);
        if (!runs.Runs(cpu))
        {
            throw new ProjectException($"{file}: {where}: {machine.Id}'s {runs} does not run {cpu} code.");
        }

        JsonObject options = [];
        if (json["options"] is { } optionsNode)
        {
            options = optionsNode as JsonObject ?? throw new ProjectException($"{file}: {where}'s 'options' must be an object.");
            if (options.Select(option => option.Key).FirstOrDefault(ReservedOptions.Contains) is { } reserved)
            {
                throw new ProjectException(
                    $"{file}: {where}'s 'options' cannot give '{reserved}', which the project and its targets decide.");
            }

            options = (JsonObject)options.DeepClone();
        }

        JsonObject? cards = null;
        if (json["cards"] is { } cardsNode)
        {
            cards = cardsNode as JsonObject ?? throw new ProjectException($"{file}: {where}'s 'cards' must be an object.");
            foreach ((string slot, JsonNode? card) in cards)
            {
                if (card?.GetValueKind() != JsonValueKind.String)
                {
                    throw new ProjectException($"{file}: {where}'s card in slot {slot} must be a card's name.");
                }
            }

            cards = (JsonObject)cards.DeepClone();
        }

        return new(project, name)
        {
            Machine = machine,
            Environment = environment,
            Cpu = cpu,
            Options = options,
            Cards = cards,
            Defines = json["defines"] is { } defines ? ReadDefines(file, where, defines) : [],
            Sources = json["sources"] is { } sources ? ReadSources(file, where, sources) : [],
            MemoryMapOverride = json["memoryMap"] is { } memoryMap ? MemoryMap.ReadOverride(file, where, memoryMap) : null,
            LinkerConfiguration = json["linkerConfiguration"] is { } linker
                ? Path.GetFullPath(Text(file, $"{where}'s 'linkerConfiguration'", linker), project.Directory)
                : null,
            Files = json["files"] is { } files ? ReadFiles(project, where, files) : [],
            ImageGiven = json.ContainsKey("image"),
            BuildsImage = json["image"] is not JsonValue { } image || image.GetValueKind() != JsonValueKind.False,
            ImageTemplate = json["image"] is { } imageNode ? ReadTemplate(project, where, imageNode) : null,
            ImageBoot = json["image"] is JsonObject { } imageObject && imageObject["boot"] is { } imageBoot
                ? Text(file, $"{where}'s image 'boot'", imageBoot)
                : null,
            BootImage = json["bootImage"] is { } boot ? MediaPath(project, where, Text(file, $"{where}'s 'bootImage'", boot)) : null
        };
    }

    // A target's files: each a path, or an object with its path and optionally its name on the disk and its address.
    // A path, relative to the project's folder, may give ${obj}, as a step's output does. Two paths name one file as
    // the system compares file names.
    private static List<TargetFile> ReadFiles(RetrocoreProject project, string where, JsonNode node)
    {
        string file = project.File;
        if (node is not JsonArray entries)
        {
            throw new ProjectException($"{file}: {where}'s 'files' must be a list of paths and file objects.");
        }

        List<TargetFile> files = [];
        foreach (JsonNode? entry in entries)
        {
            string path;
            string? name = null;
            int? address = null;
            if (entry is JsonObject fields)
            {
                Check(file, $"a file of {where}", fields, FileFields);
                path = fields["path"] is { } pathNode ? Text(file, $"a file of {where}'s 'path'", pathNode) : throw Missing(file, $"a file of {where}", "path");
                name = fields["name"] is { } nameNode ? Text(file, $"{path}'s 'name'", nameNode) : null;
                if (fields["address"] is { } addressNode)
                {
                    address = addressNode.GetValueKind() == JsonValueKind.String && MemoryMap.TryAddress(addressNode.GetValue<string>(), out int value)
                        ? value
                        : throw new ProjectException($"{file}: {path}'s 'address' must be an address such as \"$6000\".");
                }
            }
            else
            {
                path = Text(file, $"a file of {where}", entry);
            }

            string full = MediaPath(project, where, path);
            if (files.Any(known => ProjectGlob.FileNames.Equals(known.Path, full)))
            {
                throw new ProjectException($"{file}: {where}'s 'files' names {path} twice.");
            }

            files.Add(new(full, name, address));
        }

        return files;
    }

    // A target's image: true or false, or an object whose template names the disk the image starts from.
    private static string? ReadTemplate(RetrocoreProject project, string where, JsonNode node)
    {
        string file = project.File;
        if (node is JsonValue value && value.GetValueKind() is JsonValueKind.True or JsonValueKind.False)
        {
            return null;
        }

        if (node is not JsonObject image)
        {
            throw new ProjectException($"{file}: {where}'s 'image' must be true, false or an object giving 'template' or 'boot'.");
        }

        Check(file, $"{where}'s 'image'", image, ImageFields);
        if (image.Count == 0)
        {
            throw new ProjectException($"{file}: {where}'s 'image' must give 'template' or 'boot'.");
        }

        return image["template"] is { } template ? MediaPath(project, where, Text(file, $"{where}'s image 'template'", template)) : null;
    }

    // A path a target's media fields give, relative to the project's folder, with ${obj} for its intermediate folder.
    private static string MediaPath(RetrocoreProject project, string where, string path)
    {
        CheckVariables(project.File, where, path, allowLists: false);
        return Path.GetFullPath(path.Replace(ProjectStep.Intermediate, project.Intermediate, StringComparison.Ordinal), project.Directory);
    }

    private static ProjectCpu ReadCpu(string file, string where, JsonNode node)
    {
        string name = Text(file, $"{where}'s 'cpu'", node);
        return ProjectCpu.Named(name)
            ?? throw new ProjectException(
                $"{file}: {where}: there is no CPU '{name}'; the CPUs are {string.Join(", ", ProjectCpu.All.Select(cpu => cpu.Name))}.");
    }

    private static List<ProjectSource> ReadSources(string file, string where, JsonNode node)
    {
        if (node is not JsonArray entries)
        {
            throw new ProjectException($"{file}: {where}'s 'sources' must be a list of files, patterns and source objects.");
        }

        List<ProjectSource> sources = [];
        foreach (JsonNode? entry in entries)
        {
            if (entry is JsonObject source)
            {
                Check(file, $"a source of {where}", source, SourceFields);
                string path = source["path"] is { } pathNode ? Text(file, $"a source of {where}'s 'path'", pathNode) : throw Missing(file, $"a source of {where}", "path");
                string kind = source["kind"] is { } kindNode ? Text(file, $"{path}'s 'kind'", kindNode) : "asm";
                if (!Kinds.Contains(kind))
                {
                    throw new ProjectException(
                        $"{file}: {path}: there is no source kind '{kind}'; the kinds are {string.Join(", ", Kinds)}.");
                }

                string? dialect = source["dialect"] is { } dialectNode ? Text(file, $"{path}'s 'dialect'", dialectNode) : null;
                if (dialect is not null && !Dialects.Contains(dialect))
                {
                    throw new ProjectException(
                        $"{file}: {path}: there is no dialect '{dialect}'; the dialects are {string.Join(", ", Dialects)}.");
                }

                sources.Add(new(path, SourceBuild.Dialect(dialect), kind));
                continue;
            }

            sources.Add(new(Text(file, $"a source of {where}", entry), Dialect: null));
        }

        return sources;
    }

    private static List<ProjectStep> ReadSteps(RetrocoreProject project, JsonNode node)
    {
        string file = project.File;
        if (node is not JsonArray entries)
        {
            throw new ProjectException($"{file}: 'steps' must be a list of steps, each an object giving 'tool'.");
        }

        List<ProjectStep> steps = [];
        foreach (JsonNode? entry in entries)
        {
            int number = steps.Count + 1;
            string where = $"step {number}";
            if (entry is not JsonObject step)
            {
                throw new ProjectException($"{file}: {where} must be an object giving 'tool'.");
            }

            Check(file, where, step, ProjectStep.Fields);
            string tool = step["tool"] is { } toolNode ? Text(file, $"{where}'s 'tool'", toolNode) : throw Missing(file, where, "tool");
            if (tool.Contains("${", StringComparison.Ordinal))
            {
                throw new ProjectException($"{file}: {where}: the tool '{tool}' uses a variable; a tool's path cannot.");
            }

            if (!tool.EndsWith(".cs", StringComparison.OrdinalIgnoreCase) && !tool.EndsWith(".csproj", StringComparison.OrdinalIgnoreCase))
            {
                throw new ProjectException(
                    $"{file}: {where}'s tool {tool} must be a C# file-based app (.cs) or a project (.csproj).");
            }

            List<string>? arguments = null;
            if (step["args"] is { } argumentsNode)
            {
                arguments = argumentsNode is JsonArray list
                    ? [.. list.Select(argument => Text(file, $"an argument of {where}", argument))]
                    : throw new ProjectException($"{file}: {where}'s 'args' must be a list of arguments.");

                foreach (string argument in arguments) { CheckVariables(file, where, argument, allowLists: true); }
            }

            steps.Add(new(
                Path.GetFullPath(tool, project.Directory),
                arguments,
                StepPaths(project, where, "in", step["in"]),
                StepPaths(project, where, "out", step["out"])));
        }

        return steps;
    }

    // A step's 'in' or 'out': a path or a list of them, relative to the project, with ${obj} for its intermediate folder.
    private static List<string> StepPaths(RetrocoreProject project, string where, string field, JsonNode? node)
    {
        string file = project.File;
        List<JsonNode?> entries = [];
        if (node is JsonArray list) { entries.AddRange(list); }
        else if (node is not null) { entries.Add(node); }

        List<string> paths = [];
        foreach (JsonNode? entry in entries)
        {
            string path = Text(file, $"{where}'s '{field}'", entry);
            CheckVariables(file, where, path, allowLists: false);
            paths.Add(Path.GetFullPath(path.Replace(ProjectStep.Intermediate, project.Intermediate, StringComparison.Ordinal), project.Directory));
        }

        return paths;
    }

    // A step's text may use ${obj}; an argument may also be exactly ${in} or ${out}.
    private static void CheckVariables(string file, string where, string text, bool allowLists)
    {
        if (allowLists && text is ProjectStep.AllInputs or ProjectStep.AllOutputs) { return; }
        string rest = text.Replace(ProjectStep.Intermediate, "", StringComparison.Ordinal);
        if (rest.Contains("${", StringComparison.Ordinal))
        {
            throw new ProjectException(allowLists
                ? $"{file}: {where}: '{text}' uses a variable it cannot; an argument can use ${{obj}}, or be exactly ${{in}} or ${{out}}."
                : $"{file}: {where}: '{text}' uses a variable it cannot; a path can use ${{obj}} only.");
        }
    }

    private static Dictionary<string, long> ReadDefines(string file, string where, JsonNode node)
    {
        if (node is not JsonObject defines)
        {
            throw new ProjectException($"{file}: {where}'s 'defines' must be an object of symbols and their values.");
        }

        Dictionary<string, long> symbols = [];
        foreach ((string name, JsonNode? value) in defines)
        {
            if (name.StartsWith("RC_", StringComparison.OrdinalIgnoreCase))
            {
                throw new ProjectException($"{file}: {where} defines {name}; names starting with RC_ are the SDK's.");
            }

            string text = value?.GetValueKind() switch
            {
                JsonValueKind.Number or JsonValueKind.String => value.ToString(),
                JsonValueKind.True => "1",
                JsonValueKind.False => "0",
                _ => throw new ProjectException($"{file}: {where}'s {name} must be a number, true or false, or text such as \"$C000\".")
            };

            if (!IsSymbol(name) || !DefineArgument.TryParse($"{name}={text}", out _, out long parsed))
            {
                throw new ProjectException(
                    $"{file}: {where}'s define {name} = {text} must name a symbol and give an integer, decimal, $hex or 0xhex.");
            }

            symbols[name] = parsed;
        }

        return symbols;
    }

    private static void Check(string file, string where, JsonObject json, string[] fields)
    {
        foreach ((string key, JsonNode? value) in json)
        {
            if (!fields.Contains(key))
            {
                throw new ProjectException($"{file}: {where} has no field '{key}'; its fields are {string.Join(", ", fields)}.");
            }

            if (value is null)
            {
                throw new ProjectException($"{file}: {where}'s '{key}' is null; leave it out instead.");
            }
        }
    }

    private static string Text(string file, string what, JsonNode? node)
    {
        string? text = node?.GetValueKind() == JsonValueKind.String ? node.GetValue<string>() : null;
        return !string.IsNullOrEmpty(text) && !text.Contains('\0') ? text : throw new ProjectException($"{file}: {what} must be text.");
    }

    // A project's or target's name, which names files and folders the same way on every system.
    private static bool IsFileName(string name) =>
        name.Length != 0
            && name is not ("." or "..")
            && name.All(character => char.IsAsciiLetterOrDigit(character) || character is '-' or '_' or '.');

    // A symbol a define can name: a letter or '_', then letters, digits and '_'.
    private static bool IsSymbol(string name) =>
        name.Length != 0
            && (char.IsAsciiLetter(name[0]) || name[0] == '_')
            && name.All(character => char.IsAsciiLetterOrDigit(character) || character == '_');

    private static ProjectException Missing(string file, string where, string field) =>
        new($"{file}: {where} must give '{field}'.");
}