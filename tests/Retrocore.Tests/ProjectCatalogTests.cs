// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Retrocore.Debug;
using Retrocore.Debug.Project;

namespace Retrocore.Tests;

/// <summary>
///  The host's tables for <c>retrocore.json</c> agree with the extension's machine catalog and with the project
///  schema the host ships.
/// </summary>
[TestClass]
public sealed partial class ProjectCatalogTests
{
    private static readonly string s_repository = RepositoryRoot();

    /// <summary>
    ///  Each catalog machine launches with the same <c>machine</c>, <c>model</c> and <c>rom</c> as the extension's
    ///  catalog gives it, which Start Machine spreads into its launch configuration.
    /// </summary>
    [TestMethod]
    public void MachinesMatchTheExtensionsCatalog()
    {
        string machines = File.ReadAllText(Path.Join(s_repository, "extension", "src", "machines.ts"));
        Dictionary<string, Dictionary<string, string>> catalog = [];
        foreach (Match entry in CatalogEntry().Matches(machines))
        {
            catalog.Add(
                entry.Groups["id"].Value,
                ConfigurationPair().Matches(entry.Groups["configuration"].Value)
                    .ToDictionary(pair => pair.Groups["key"].Value, pair => pair.Groups["value"].Value));
        }

        catalog.Should().NotBeEmpty();
        CatalogMachine.All.Select(machine => machine.Id).Should().Equal(catalog.Keys);
        foreach (CatalogMachine machine in CatalogMachine.All)
        {
            Dictionary<string, string> launch = new() { ["machine"] = machine.Machine };
            if (machine.Model is { } model) { launch["model"] = model; }
            if (machine.Rom is { } rom) { launch["rom"] = rom; }
            catalog[machine.Id].Should().BeEquivalentTo(launch, machine.Id);
        }

        // Start Machine's launch is the catalog's configuration spread into it (startFlow.ts's setupConfiguration).
        machines.Should().Contain("...machine.configuration");
        File.ReadAllText(Path.Join(s_repository, "extension", "src", "startFlow.ts"))
            .Should().Contain("launchConfiguration(machine, setupName(machine, setup))");
    }

    /// <summary>
    ///  Each catalog machine's launch names a machine the debug host launches.
    /// </summary>
    [TestMethod]
    public void MachinesAreTheHosts()
    {
        foreach (CatalogMachine machine in CatalogMachine.All)
        {
            DebugMachines.Require(machine.Machine).Should().Be(machine.Machine);
        }
    }

    /// <summary>
    ///  The schema lists the catalog's machines, the CPUs, the environments and each object's fields as the loader
    ///  takes them.
    /// </summary>
    [TestMethod]
    public void SchemaMatchesTheLoader()
    {
        // The host ships the schema beside it, where the host's own output and this test's copy it.
        File.Exists(Path.Join(AppContext.BaseDirectory, "Schemas", "project-1.schema.json")).Should().BeTrue();
        string text = File.ReadAllText(Path.Join(s_repository, "src", "Retrocore.Debug", "Project", "project-1.schema.json"));
        JsonNode schema = JsonNode.Parse(text) ?? throw new AssertFailedException("The schema is empty.");

        JsonNode definitions = schema["definitions"] ?? throw new AssertFailedException("The schema has no definitions.");
        Strings(definitions["machine"]?["enum"]).Should().Equal(CatalogMachine.All.Select(machine => machine.Id));
        Strings(definitions["cpu"]?["enum"]).Should().Equal(ProjectCpu.All.Select(cpu => cpu.Name));
        Strings(definitions["environment"]?["enum"]).Should().Equal(ProjectTarget.Environments);
        Strings(definitions["cpu"]?["enumDescriptions"]).Should().HaveCount(ProjectCpu.All.Count);
        Strings(definitions["environment"]?["enumDescriptions"]).Should().HaveCount(ProjectTarget.Environments.Length);
        Fields(definitions["project"]).Should().BeEquivalentTo(RetrocoreProject.ProjectFields);
        Fields(definitions["root"]).Should().BeEquivalentTo(RetrocoreProject.RootFields);
        Fields(definitions["target"]).Should().BeEquivalentTo(RetrocoreProject.TargetFields);
        Fields(definitions["sources"]?["items"]?["oneOf"]?[1]).Should().BeEquivalentTo(RetrocoreProject.SourceFields);
        Fields(definitions["step"]).Should().BeEquivalentTo(ProjectStep.Fields);
        Fields(definitions["target"]?["properties"]?["memoryMap"]).Should().BeEquivalentTo(MemoryMap.OverrideFields);
        Fields(definitions["memoryArea"]).Should().BeEquivalentTo(MemoryMap.AreaFields);
        Strings(definitions["target"]?["properties"]?["options"]?["propertyNames"]?["not"]?["enum"])
            .Should().BeEquivalentTo(RetrocoreProject.ReservedOptions);

        foreach (string field in RetrocoreProject.UnsupportedFields)
        {
            string description = (string?)(definitions["project"]?["properties"]?[field] ?? definitions["target"]?["properties"]?[field])?["description"] ?? "";
            description.Should().Contain("Not yet supported", field);
        }
    }

    private static List<string> Strings(JsonNode? node) =>
        node is JsonArray array ? [.. array.Select(item => (string?)item ?? "")] : throw new AssertFailedException("Expected a list.");

    private static List<string> Fields(JsonNode? node) =>
        node?["properties"] is JsonObject properties
            ? [.. properties.Select(property => property.Key)]
            : throw new AssertFailedException("Expected properties.");

    private static string RepositoryRoot()
    {
        string? root = AppContext.BaseDirectory;
        while (root is not null && !File.Exists(Path.Join(root, "Retrocore.slnx")))
        {
            root = Path.GetDirectoryName(root);
        }

        return root ?? throw new InvalidOperationException("The repository root was not found.");
    }

    [GeneratedRegex("""\bid: "(?<id>[^"]+)",[^{}]*?\bconfiguration: \{(?<configuration>[^}]*)\}""")]
    private static partial Regex CatalogEntry();

    [GeneratedRegex("(?<key>[A-Za-z0-9]+): \"(?<value>[^\"]*)\"")]
    private static partial Regex ConfigurationPair();
}
