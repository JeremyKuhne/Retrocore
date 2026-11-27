// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Reflection;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using Touki.Text;

namespace Retrocore.Debug.Project;

/// <summary>
///  Writes a project from a template: its <c>retrocore.json</c>, its sources and platform folders, and the
///  repository's files that build it: the pinned tool, the extension's recommendation, the <c>.gitignore</c>, the CI
///  workflow and a README.
/// </summary>
/// <remarks>
///  <para>
///   Each machine asked for becomes a target with its family's environment, named for the machine and the
///   environment (<c>apple2-dos</c>; <c>apple2-iie-dos</c> for a machine other than the family's own). The platform
///   folders copied are the machines' families' and models', their environments', and <c>bare</c>'s, so a bare target
///   can be added by hand. Nothing is written until every file has been checked: a project file that would replace one
///   already there is an error, and a repository file already there is added to (the tool manifest, the extension
///   recommendations, the <c>.gitignore</c>) or left as it is.
///  </para>
/// </remarks>
internal static class ProjectScaffold
{
    /// <summary>
    ///  The extension's id, which the repository's <c>.vscode/extensions.json</c> recommends.
    /// </summary>
    internal const string ExtensionId = "retrocore.retrocore";

    /// <summary>
    ///  The tool's package and command name.
    /// </summary>
    internal const string ToolName = "retrocore";

    private static readonly JsonDocumentOptions s_strictJson = new() { CommentHandling = JsonCommentHandling.Disallow };

    private static readonly JsonWriterOptions s_writer = new()
    {
        Indented = true,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        NewLine = "\n"
    };

    /// <summary>
    ///  Gets the tool's own version, which a new project pins: the package's, without any build metadata.
    /// </summary>
    internal static string ToolVersion { get; } = ReadToolVersion();

    /// <summary>
    ///  Chooses a project's targets: one per machine named, with its family's environment.
    /// </summary>
    /// <param name="template">The template.</param>
    /// <param name="machines">Families or catalog ids; none means each of the template's families.</param>
    /// <returns>The targets, in the order named.</returns>
    /// <exception cref="ProjectException">A name is no machine of the template's, or two give one target.</exception>
    internal static List<ScaffoldTarget> Targets(ProjectTemplate template, IReadOnlyList<string> machines)
    {
        IEnumerable<string> names = machines.Count == 0 ? template.Families.Select(family => family.Name) : machines;
        List<ScaffoldTarget> targets = [];
        foreach (string name in names)
        {
            if (template.FindMachine(name) is not ({ } family, { } machine))
            {
                throw new ProjectException(
                    $"The {template.Name} template has no machine '{name}'; give a family ({string.Join(", ", template.Families.Select(family => family.Name))}) or one of their machines ({string.Join(", ", Machines(template))}).");
            }

            string target = machine.Id == family.Machine ? $"{family.Name}-{family.Suffix}" : $"{machine.Id}-{family.Suffix}";
            if (targets.Any(existing => existing.Name == target))
            {
                throw new ProjectException($"'{name}' gives the target {target} again; name each machine once.");
            }

            targets.Add(new ScaffoldTarget(
                target,
                machine,
                family,
                template.MachineDefines.TryGetValue(machine.Id, out IReadOnlyList<KeyValuePair<string, long>>? defines) ? defines : []));
        }

        return targets;
    }

    /// <summary>
    ///  Gets the catalog ids of the machines a template builds for, in the catalog's order.
    /// </summary>
    /// <param name="template">The template.</param>
    /// <returns>The ids.</returns>
    internal static IEnumerable<string> Machines(ProjectTemplate template) =>
        CatalogMachine.All.Where(machine => template.Families.Any(family => family.Name == machine.Family)).Select(machine => machine.Id);

    /// <summary>
    ///  Plans a project's files from a template, checking each against what is there, and writes nothing.
    /// </summary>
    /// <param name="template">The template.</param>
    /// <param name="commonFolder">The folder of the files every template shares.</param>
    /// <param name="name">The project's name.</param>
    /// <param name="targets">Its targets.</param>
    /// <param name="folder">The project's folder.</param>
    /// <param name="repository">
    ///  The repository's root, where the tool manifest, the extension recommendations and the workflow go: the
    ///  project's folder for a new repository.
    /// </param>
    /// <returns>Every file to write, with what it says and why.</returns>
    /// <exception cref="ProjectException">
    ///  A project file is already there, or a folder is where a file goes or a file where a folder goes.
    /// </exception>
    internal static List<ScaffoldFile> Plan(
        ProjectTemplate template,
        string commonFolder,
        string name,
        IReadOnlyList<ScaffoldTarget> targets,
        string folder,
        string repository)
    {
        folder = Path.GetFullPath(folder);
        repository = Path.GetFullPath(repository);
        string relative = Path.GetRelativePath(repository, folder).Replace('\\', '/');
        bool atRoot = relative == ".";

        // The workflow is build.yml in a new repository; beside the repository's own workflows, it has a name of its own.
        bool ownWorkflow = atRoot && !File.Exists(Path.Join(repository, ".github", "workflows", "build.yml"));
        string workflowName = atRoot ? name : relative.Replace('/', '-');
        string workflow = ownWorkflow ? ".github/workflows/build.yml" : $".github/workflows/retrocore-{workflowName}.yml";
        Dictionary<string, string> values = new()
        {
            ["name"] = name,
            ["cpu"] = template.Cpu,
            ["version"] = ToolVersion,
            ["firstTarget"] = targets[0].Name,
            ["targets"] = string.Join("\n", targets.Select(target =>
                $"| `{target.Name}` | `{target.Machine.Id}` | `{target.Family.Environment}` | {Builds(target.Family.Environment)} |")),
            ["projectOption"] = atRoot ? "" : $" --project {relative}",
            ["workflow"] = workflow,
            ["projectFolder"] = atRoot ? "" : relative + "/"
        };

        List<ScaffoldFile> files = [];

        // The project's own files: retrocore.json, the template's sources and the platform folders its targets use.
        files.Add(ProjectFile(Path.Join(folder, RetrocoreProject.FileName), ProjectText(template, name, targets)));
        HashSet<string> platforms = ["bare"];
        foreach (ScaffoldTarget target in targets)
        {
            platforms.Add(target.Family.Name);
            platforms.Add(target.Machine.Id);
            platforms.Add(target.Family.Environment);
        }

        foreach (string file in System.IO.Directory.EnumerateFiles(template.Directory, "*", SearchOption.AllDirectories).Order(StringComparer.Ordinal))
        {
            string path = Path.GetRelativePath(template.Directory, file).Replace('\\', '/');
            if (path == ProjectTemplate.FileName) { continue; }
            string[] parts = path.Split('/');
            if (parts.Length > 3 && parts[0] == "src" && parts[1] == "platform" && !platforms.Contains(parts[2]))
            {
                continue;
            }

            files.Add(ProjectFile(Path.Join(folder, path), Fill(File.ReadAllText(file), values)));
        }

        // The repository's files. The README and .gitignore go beside the project; the rest at the repository's root.
        foreach (string file in System.IO.Directory.EnumerateFiles(commonFolder, "*", SearchOption.AllDirectories).Order(StringComparer.Ordinal))
        {
            string path = Path.GetRelativePath(commonFolder, file).Replace('\\', '/');
            path = path.StartsWith('_') ? "." + path[1..] : path;
            string text = Fill(File.ReadAllText(file), values);
            switch (path)
            {
                case "README.md":
                    files.Add(Optional(Path.Join(folder, path), text));
                    break;
                case ".gitignore":
                    files.Add(Lines(Path.Join(folder, path), text));
                    break;
                case ".vscode/extensions.json":
                    files.Add(Recommendation(Path.Join(repository, path), text));
                    break;
                case ".github/workflows/build.yml":
                    files.Add(Optional(Path.Join(repository, workflow), text));
                    break;
                default:
                    files.Add(Optional(Path.Join(repository, path), text));
                    break;
            }
        }

        files.Add(ToolManifest(Path.Join(repository, ".config", "dotnet-tools.json")));
        if (!atRoot && File.Exists(Path.Join(repository, RetrocoreProject.FileName)))
        {
            files.Add(RootProjects(Path.Join(repository, RetrocoreProject.FileName), relative));
        }

        return files;
    }

    /// <summary>
    ///  Writes the files a plan says to write.
    /// </summary>
    /// <param name="files">The plan.</param>
    internal static void Write(IEnumerable<ScaffoldFile> files)
    {
        foreach (ScaffoldFile file in files.Where(file => file.Text is not null))
        {
            System.IO.Directory.CreateDirectory(Path.GetDirectoryName(file.Path) ?? file.Path);
            File.WriteAllText(file.Path, file.Text, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        }
    }

    // What an environment's targets build, for the README's table.
    private static string Builds(string environment) => environment switch
    {
        "wozmon" => "Woz Monitor hex, and an ACI tape",
        "dos33" => "a B file on a DOS 3.3 disk",
        "sos" => "SOS.INTERP on a SOS boot disk",
        "basic" => "a PRG with a SYS line, and a tape",
        "dfs" => "a file on a DFS disk that !BOOT runs, and a UEF tape",
        _ => "a program the debugger loads"
    };

    // The project's retrocore.json, written as the samples' are: one line per target.
    private static string ProjectText(ProjectTemplate template, string name, IReadOnlyList<ScaffoldTarget> targets)
    {
        using ValueStringBuilder text = new(stackalloc char[512]);
        text.Append($"// {name}: one {template.Cpu} program, built for each of its targets. `dotnet retrocore build --all` builds them\n");
        text.Append("// into artifacts/; in VS Code, F5 builds and debugs the target picked in the status bar. A target is a machine,\n");
        text.Append("// as Start Machine lists it, and an environment; its defines are added to the project's.\n");
        text.Append("{\n");
        text.Append($"  \"sdk\": {Quote(RetrocoreProject.SdkVersions[^1])},\n");
        text.Append($"  \"name\": {Quote(name)},\n");
        text.Append($"  \"cpu\": {Quote(template.Cpu)},\n");
        text.Append($"  \"sources\": [{string.Join(", ", template.Sources.Select(Quote))}],\n");
        if (template.Entry is { } entry) { text.Append($"  \"entry\": {Quote(entry)},\n"); }
        if (template.Defines.Count != 0) { text.Append($"  \"defines\": {DefinesText(template.Defines)},\n"); }
        text.Append("  \"targets\": {\n");
        for (int index = 0; index < targets.Count; index++)
        {
            ScaffoldTarget target = targets[index];
            text.Append($"    {Quote(target.Name)}: {{ \"machine\": {Quote(target.Machine.Id)}, \"environment\": {Quote(target.Family.Environment)}");
            if (target.Defines.Count != 0) { text.Append($", \"defines\": {DefinesText(target.Defines)}"); }
            text.Append(index == targets.Count - 1 ? " }\n" : " },\n");
        }

        text.Append("  }\n}\n");
        return text.ToString();
    }

    private static string DefinesText(IEnumerable<KeyValuePair<string, long>> defines) =>
        "{ " + string.Join(", ", defines.Select(define => $"{Quote(define.Key)}: {define.Value}")) + " }";

    private static string Quote(string text) => "\"" + JsonEncodedText.Encode(text, JavaScriptEncoder.UnsafeRelaxedJsonEscaping).Value + "\"";

    // A template's text with its {{placeholders}} filled, and its lines ended in line feeds, as Git stores them.
    private static string Fill(string text, IReadOnlyDictionary<string, string> values)
    {
        text = text.Replace("\r\n", "\n");
        foreach ((string key, string value) in values)
        {
            text = text.Replace("{{" + key + "}}", value);
        }

        return text;
    }

    // A file of the project's own, which must not be there yet.
    private static ScaffoldFile ProjectFile(string path, string text)
    {
        if (File.Exists(path) || System.IO.Directory.Exists(path))
        {
            throw new ProjectException($"{path} is already there; retrocore writes a project only where none of its files are.");
        }

        NotFolder(path);
        return new ScaffoldFile(path, text, What: "wrote");
    }

    // A repository file that is written when it is not there, and left as it is when it is.
    private static ScaffoldFile Optional(string path, string text)
    {
        NotFolder(path);
        return File.Exists(path) ? new ScaffoldFile(path, Text: null, "kept, as it is already there") : new ScaffoldFile(path, text, What: "wrote");
    }

    // A file to write or add to, which a folder of its name, or a file where one of its folders goes, would stop, so
    // that is refused before anything is written.
    private static void NotFolder(string path)
    {
        if (System.IO.Directory.Exists(path))
        {
            throw new ProjectException($"{path} is a folder; retrocore writes a file there.");
        }

        for (string? folder = Path.GetDirectoryName(path); folder is not null; folder = Path.GetDirectoryName(folder))
        {
            if (File.Exists(folder))
            {
                throw new ProjectException($"{folder} is a file; retrocore writes {path} in a folder of that name.");
            }
        }
    }

    // A .gitignore, given the template's lines it lacks.
    private static ScaffoldFile Lines(string path, string text)
    {
        NotFolder(path);
        if (!File.Exists(path)) { return new ScaffoldFile(path, text, What: "wrote"); }
        string existing = File.ReadAllText(path);
        HashSet<string> lines = [.. existing.Split('\n').Select(IgnoredFolder)];
        List<string> missing = [.. text.Split('\n').Where(line => line.Length != 0 && !line.StartsWith('#') && !lines.Contains(IgnoredFolder(line)))];
        if (missing.Count == 0)
        {
            return new ScaffoldFile(path, Text: null, "kept, as it already ignores artifacts/ and obj/");
        }

        string separator = existing.Length == 0 || existing.EndsWith('\n') ? "" : "\n";
        return new ScaffoldFile(path, existing + separator + string.Join("\n", missing) + "\n", $"added {string.Join(" and ", missing)}");
    }

    // A .gitignore line as the folder it ignores, so that /artifacts/ and artifacts count as artifacts/ does.
    private static string IgnoredFolder(string line) => line.Trim().Trim('/');

    // .vscode/extensions.json, with the extension among its recommendations.
    private static ScaffoldFile Recommendation(string path, string text)
    {
        NotFolder(path);
        if (!File.Exists(path)) { return new ScaffoldFile(path, text, What: "wrote"); }
        string existing = File.ReadAllText(path);
        if (existing.Contains($"\"{ExtensionId}\"", StringComparison.OrdinalIgnoreCase))
        {
            return new ScaffoldFile(path, Text: null, "kept, as it already recommends the extension");
        }

        if (Parse(existing) is not JsonObject json || json["recommendations"] is not (null or JsonArray))
        {
            return new ScaffoldFile(path, Text: null, $"kept; add \"{ExtensionId}\" to its recommendations yourself, as it has comments or is not a list");
        }

        JsonArray recommendations = json["recommendations"] as JsonArray ?? [];
        json["recommendations"] = recommendations;
        recommendations.Add((JsonNode)JsonValue.Create(ExtensionId));
        return new ScaffoldFile(path, Serialize(json), "added the Retrocore extension to its recommendations");
    }

    // .config/dotnet-tools.json, with the tool pinned at this version, unless it already has an entry for it.
    private static ScaffoldFile ToolManifest(string path)
    {
        JsonObject tool = new()
        {
            ["version"] = ToolVersion,
            ["commands"] = new JsonArray(ToolName),
            ["rollForward"] = false
        };

        NotFolder(path);
        if (!File.Exists(path))
        {
            JsonObject manifest = new()
            {
                ["version"] = 1,
                ["isRoot"] = true,
                ["tools"] = new JsonObject { [ToolName] = tool }
            };

            return new ScaffoldFile(path, Serialize(manifest), $"wrote, pinning {ToolName} {ToolVersion}");
        }

        if (Parse(File.ReadAllText(path)) is not JsonObject json || json["tools"] is not (null or JsonObject))
        {
            return new ScaffoldFile(path, Text: null, $"kept; it cannot be read, so pin {ToolName} {ToolVersion} with dotnet tool install {ToolName} --version {ToolVersion}");
        }

        JsonObject tools = json["tools"] as JsonObject ?? [];
        json["tools"] = tools;
        if (tools[ToolName] is { } entry)
        {
            return entry is JsonObject pin && pin["version"]?.GetValueKind() == JsonValueKind.String
                ? new ScaffoldFile(path, Text: null, $"kept, as it already pins {ToolName} {pin["version"]?.GetValue<string>()}")
                : new ScaffoldFile(path, Text: null, $"kept; its {ToolName} entry gives no version, so pin {ToolName} {ToolVersion} there yourself");
        }

        tools[ToolName] = tool;
        return new ScaffoldFile(path, Serialize(json), $"added {ToolName} {ToolVersion}");
    }

    // A root retrocore.json that lists its projects, given the new one's folder.
    private static ScaffoldFile RootProjects(string path, string relative)
    {
        if (Parse(File.ReadAllText(path)) is not JsonObject json || json["projects"] is not JsonArray projects)
        {
            return new ScaffoldFile(path, Text: null, $"kept; it is not a list of projects, or has comments, so add \"{relative}\" to its projects yourself if it lists them");
        }

        static string Folder(string path) => path.Replace('\\', '/').TrimEnd('/') is var trimmed && trimmed.StartsWith("./", StringComparison.Ordinal)
            ? trimmed[2..]
            : trimmed;

        if (projects.Any(project => project?.GetValueKind() == JsonValueKind.String && Folder(project.GetValue<string>()) == relative))
        {
            return new ScaffoldFile(path, Text: null, "kept, as it already lists the project");
        }

        projects.Add((JsonNode)JsonValue.Create(relative));
        return new ScaffoldFile(path, Serialize(json), $"added {relative} to its projects");
    }

    // JSON that has no comments, which is the only kind rewritten: rewriting would drop them.
    private static JsonNode? Parse(string text)
    {
        try
        {
            return JsonNode.Parse(text, documentOptions: s_strictJson);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static string Serialize(JsonNode json)
    {
        using MemoryStream stream = new();
        using (Utf8JsonWriter writer = new(stream, s_writer))
        {
            json.WriteTo(writer);
        }

        return Encoding.UTF8.GetString(stream.ToArray()) + "\n";
    }

    private static string ReadToolVersion()
    {
        Assembly assembly = typeof(ProjectScaffold).Assembly;
        string version = assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "0.0.0";
        int metadata = version.IndexOf('+');
        return metadata < 0 ? version : version[..metadata];
    }
}
