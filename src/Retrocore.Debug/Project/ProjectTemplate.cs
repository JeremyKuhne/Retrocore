// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json;
using System.Text.Json.Nodes;
using DefineList = System.Collections.Generic.IReadOnlyList<System.Collections.Generic.KeyValuePair<string, long>>;

namespace Retrocore.Debug.Project;

/// <summary>
///  A template <c>retrocore new</c> and <c>retrocore init</c> start a project from: a CPU family's program, its
///  platform folders, and the machine families it builds for, each with the environment its targets use.
/// </summary>
/// <remarks>
///  <para>
///   A template is a folder of the SDK's <c>templates/</c>, such as <c>Sdk/1/templates/6502/</c>, with a
///   <c>template.json</c>; <c>templates/common/</c> holds the repository's files every template shares.
///   <c>sdk/1/templates/README.md</c> is the contract.
///  </para>
/// </remarks>
internal sealed class ProjectTemplate
{
    /// <summary>
    ///  The name of a template's description file.
    /// </summary>
    internal const string FileName = "template.json";

    /// <summary>
    ///  The name of the folder of files every template shares.
    /// </summary>
    internal const string CommonFolder = "common";

    private static readonly JsonDocumentOptions s_json = new()
    {
        CommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true
    };

    private static readonly Dictionary<string, DefineList> s_noDefines = [];

    private ProjectTemplate(string name, string directory) => (Name, Directory) = (name, directory);

    /// <summary>
    ///  Gets the SDK's templates folder beside the host.
    /// </summary>
    internal static string DefaultRoot => Path.Join(SdkModules.SdkDirectory, RetrocoreProject.SdkVersions[^1], "templates");

    /// <summary>
    ///  Gets the template's name, its folder's: the CPU family it is for, such as <c>6502</c>.
    /// </summary>
    internal string Name { get; }

    /// <summary>
    ///  Gets the template's folder.
    /// </summary>
    internal string Directory { get; }

    /// <summary>
    ///  Gets what the template makes, in a line.
    /// </summary>
    internal string Description { get; private set; } = "";

    /// <summary>
    ///  Gets the project's <c>cpu</c>.
    /// </summary>
    internal string Cpu { get; private set; } = "";

    /// <summary>
    ///  Gets the project's <c>sources</c>.
    /// </summary>
    internal IReadOnlyList<string> Sources { get; private set; } = [];

    /// <summary>
    ///  Gets the project's <c>entry</c>, or null for none.
    /// </summary>
    internal string? Entry { get; private set; }

    /// <summary>
    ///  Gets the project's <c>defines</c>, in the template's order.
    /// </summary>
    internal DefineList Defines { get; private set; } = [];

    /// <summary>
    ///  Gets the machine families the template builds for, in its order.
    /// </summary>
    internal IReadOnlyList<TemplateFamily> Families { get; private set; } = [];

    /// <summary>
    ///  Gets the defines a machine's targets add, by its catalog id.
    /// </summary>
    internal IReadOnlyDictionary<string, DefineList> MachineDefines { get; private set; } = s_noDefines;

    /// <summary>
    ///  Gets every template in a templates folder, by name.
    /// </summary>
    /// <param name="root">The templates folder.</param>
    /// <returns>The templates, in ordinal order of their names.</returns>
    /// <exception cref="ProjectException">A template's file is malformed.</exception>
    internal static List<ProjectTemplate> LoadAll(string root) =>
        !System.IO.Directory.Exists(root)
            ? []
            : [
                .. System.IO.Directory.EnumerateDirectories(root)
                    .Where(folder => File.Exists(Path.Join(folder, FileName)))
                    .Order(StringComparer.Ordinal)
                    .Select(folder => Load(Path.GetFileName(folder), folder))
            ];

    /// <summary>
    ///  Finds the machine family a name means: a family's own name, or the catalog id of one of its machines.
    /// </summary>
    /// <param name="name">The name, such as <c>apple2</c> or <c>apple2-iie</c>.</param>
    /// <returns>The family, and the machine the name means; null when the template has none.</returns>
    internal (TemplateFamily Family, CatalogMachine Machine)? FindMachine(string name)
    {
        foreach (TemplateFamily family in Families)
        {
            if (family.Name == name && CatalogMachine.Find(family.Machine) is { } machine)
            {
                return (family, machine);
            }
        }

        return CatalogMachine.Find(name) is { } named && Families.FirstOrDefault(family => family.Name == named.Family) is { } owner
            ? (owner, named)
            : null;
    }

    private static ProjectTemplate Load(string name, string directory)
    {
        string file = Path.Join(directory, FileName);
        JsonObject json = JsonNode.Parse(File.ReadAllText(file), documentOptions: s_json) as JsonObject
            ?? throw new ProjectException($"{file}: a template is a JSON object.");

        ProjectTemplate template = new(name, directory)
        {
            Description = Text(file, json, "description"),
            Cpu = Text(file, json, "cpu"),
            Sources = json["sources"] is JsonArray sources
                ? [.. sources.Select(source => source?.GetValueKind() == JsonValueKind.String
                    ? source.GetValue<string>()
                    : throw new ProjectException($"{file}: 'sources' lists text."))]
                : throw new ProjectException($"{file}: a template gives 'sources'."),
            Entry = json["entry"] is null ? null : Text(file, json, "entry"),
            Defines = ReadDefines(file, json["defines"])
        };

        if (json["families"] is not JsonObject families || families.Count == 0)
        {
            throw new ProjectException($"{file}: a template gives 'families', at least one.");
        }

        List<TemplateFamily> list = [];
        foreach ((string family, JsonNode? value) in families)
        {
            if (value is not JsonObject entry)
            {
                throw new ProjectException($"{file}: family '{family}' is an object.");
            }

            TemplateFamily parsed = new(family, Text(file, entry, "machine"), Text(file, entry, "environment"), Text(file, entry, "suffix"));
            if (CatalogMachine.Find(parsed.Machine) is not { } machine || machine.Family != family)
            {
                throw new ProjectException($"{file}: family '{family}' names '{parsed.Machine}', which is not one of its machines.");
            }

            list.Add(parsed);
        }

        template.Families = list;

        Dictionary<string, DefineList> machineDefines = [];
        if (json["machineDefines"] is JsonObject byMachine)
        {
            foreach ((string machine, JsonNode? defines) in byMachine)
            {
                machineDefines[machine] = ReadDefines(file, defines);
            }
        }

        template.MachineDefines = machineDefines;
        return template;
    }

    private static string Text(string file, JsonObject json, string field) =>
        json[field] is { } node && node.GetValueKind() == JsonValueKind.String && node.GetValue<string>().Length != 0
            ? node.GetValue<string>()
            : throw new ProjectException($"{file}: '{field}' must be text.");

    private static List<KeyValuePair<string, long>> ReadDefines(string file, JsonNode? node)
    {
        if (node is null) { return []; }
        if (node is not JsonObject defines)
        {
            throw new ProjectException($"{file}: defines are an object of numbers.");
        }

        return
        [
            .. defines.Select(define => define.Value?.GetValueKind() == JsonValueKind.Number && define.Value.AsValue().TryGetValue(out long value)
                ? KeyValuePair.Create(define.Key, value)
                : throw new ProjectException($"{file}: define '{define.Key}' must be a whole number."))
        ];
    }
}
