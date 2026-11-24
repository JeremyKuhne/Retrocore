// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;
using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  <see cref="BasicNames"/> adds a predefined old name's current names only from the build a test assembles, or, for
///  all builds, only where every build gives the name the same definitions, so one build's name never reaches another
///  build's assembly.
/// </summary>
[TestClass]
public sealed class BasicNamesBuildTests
{
    // The value a test predefines under the old name.
    private const long Value = 0x1234;

    // An old name two builds give to different definitions, and one they agree on.
    private const string Differing = "OLDNAM";
    private const string Agreed = "SAMNAM";

    // Two builds' tables: Differing is AppleSoft's AppleOnly and PET's PetOnly; both give Agreed to Shared.
    private static readonly Dictionary<string, IReadOnlyDictionary<string, string[]>> s_tables = new(StringComparer.Ordinal)
    {
        [BasicNames.Build(Apple2Model.IIeEnhanced)] = new Dictionary<string, string[]>(StringComparer.Ordinal)
        {
            [Differing] = ["AppleOnly"],
            [Agreed] = ["Shared"]
        },
        [BasicNames.Build(PetModel.Pet4032, original: false)] = new Dictionary<string, string[]>(StringComparer.Ordinal)
        {
            [Differing] = ["PetOnly"],
            [Agreed] = ["Shared"]
        }
    };

    /// <summary>
    ///  For one build, an old name the builds give to different definitions gets only that build's current name.
    /// </summary>
    /// <param name="apple">Whether the build is AppleSoft's rather than PET BASIC's.</param>
    [TestMethod]
    [DataRow(data: true)]
    [DataRow(data: false)]
    public void ABuildGetsOnlyItsOwnNameForAnOldNameTheBuildsDisagreeOn(bool apple)
    {
        string build = apple ? BasicNames.Build(Apple2Model.IIeEnhanced) : BasicNames.Build(PetModel.Pet4032, original: false);

        Dictionary<string, long> names = BasicNames.WithCurrentNames(One(Differing), s_tables, build);

        names.Should().ContainKey(Differing).WhoseValue.Should().Be(Value);
        names.Should().ContainKey(apple ? "AppleOnly" : "PetOnly").WhoseValue.Should().Be(Value);
        names.Should().NotContainKey(apple ? "PetOnly" : "AppleOnly", "another build's name must not reach this assembly");
    }

    /// <summary>
    ///  For all builds, an old name the builds give to different definitions is an error naming each build's
    ///  definition, while one they agree on gets its one current name.
    /// </summary>
    [TestMethod]
    public void AllBuildsRejectAnOldNameTheBuildsDisagreeOn()
    {
        Action differing = () => BasicNames.WithCurrentNames(One(Differing), s_tables, build: null);

        differing.Should().Throw<InvalidOperationException>()
            .WithMessage("*" + Differing + "*AppleOnly*PetOnly*");

        Dictionary<string, long> agreed = BasicNames.WithCurrentNames(One(Agreed), s_tables, build: null);
        agreed.Should().ContainKey("Shared").WhoseValue.Should().Be(Value);
    }

    /// <summary>
    ///  A build that is not a native BASIC build is an error, rather than a build with no names.
    /// </summary>
    [TestMethod]
    public void AnUnknownBuildIsAnError()
    {
        Action unknown = () => BasicNames.WithCurrentNames(One(Agreed), s_tables, "AppleSoft IIc");

        unknown.Should().Throw<ArgumentException>();
    }

    /// <summary>
    ///  In the native sources, each build's old names get that build's current names, and the all-builds lookup
    ///  either gives the definitions every build agrees on or rejects the name, for every old name of all eight
    ///  builds.
    /// </summary>
    [TestMethod]
    public void TheNativeBuildsNamesStayWithTheirBuild()
    {
        IReadOnlyDictionary<string, IReadOnlyDictionary<string, string[]>> tables = BasicNames.CurrentNamesByBuild();
        tables.Should().HaveCount(8, "three AppleSoft and five PET BASIC builds");

        foreach ((string build, IReadOnlyDictionary<string, string[]> table) in tables)
        {
            foreach ((string name, string[] targets) in table)
            {
                Dictionary<string, long> own = BasicNames.WithCurrentNames(One(name), build);
                own.Keys.Except([name]).Should().BeEquivalentTo(targets, $"{build} gives {name} only to its own names");
            }
        }

        foreach (string name in tables.Values.SelectMany(table => table.Keys).Distinct(StringComparer.Ordinal))
        {
            string[][] given = [.. tables.Values.Where(table => table.ContainsKey(name)).Select(table => table[name])];
            Func<Dictionary<string, long>> all = () => BasicNames.WithCurrentNames(One(name));
            if (given.All(targets => targets.SequenceEqual(given[0], StringComparer.Ordinal)))
            {
                all().Keys.Except([name]).Should().BeEquivalentTo(given[0]);
            }
            else
            {
                all.Should().Throw<InvalidOperationException>($"the builds give {name} to different definitions");
            }
        }
    }

    // The predefined symbols: one old name, with the test's value.
    private static Dictionary<string, long> One(string name) => new(StringComparer.Ordinal) { [name] = Value };
}
