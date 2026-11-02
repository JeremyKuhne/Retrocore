// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  The SDK's sources of the Apple II and II Plus ROMs assemble byte-identically to their chips, and the ROMs built
///  from them start the machines without any dumps.
/// </summary>
[TestClass]
public class Apple2SourceTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  Each source, built for the II or II Plus, matches its chip's SHA-256.
    /// </summary>
    /// <param name="part">Which ROM.</param>
    /// <param name="expectedHash">The SHA-256 of the chip.</param>
    [TestMethod]
    [DataRow("original Monitor", "882DB0FBE15C7CFE395FE41451C759C4A21C09FF8FA161473C549FBCE7733964")]
    [DataRow("Autostart Monitor", "29465303E7844FA56A8C846D0565E45F5EE082F98F2CCF1B261DE4A7E902201B")]
    [DataRow("character generator", "08F5D22230481019844492DDE0A29A018CB193712A9E4A43770A3870608F28DE")]
    [DataRow("Integer BASIC", "189C95FF289A186108580D3E416F3EC3D8C636246A9AEED9814E769257EB8A19")]
    [DataRow("II Plus AppleSoft", "ED8D83176BB9445B3EAA815E07956777BDFAA9E4892A8D7F5019DEAD62434C4C")]
    [DataRow("Programmer's Aid #1", "E35D2E96D7B395DD3C035726E76C417B05813AE9675CA7108D5988DC980110A3")]
    public void SourceMatchesTheChip(string part, string expectedHash)
    {
        Convert.ToHexString(SHA256.HashData(Build(part))).Should().Be(expectedHash);
    }

    /// <summary>
    ///  With the user's dumps, the 12 KiB the SDK builds for each board matches the chips, which names the first
    ///  difference.
    /// </summary>
    /// <param name="model">The II or II Plus.</param>
    /// <param name="autostart">For the II, whether its Monitor is the Autostart ROM.</param>
    [TestMethod]
    [DataRow(Apple2Model.II, false)]
    [DataRow(Apple2Model.II, true)]
    [DataRow(Apple2Model.IIPlus, true)]
    public void BoardRomMatchesTheDumps(Apple2Model model, bool autostart)
    {
        string root = Path.Join(ExternalTestData.Root, "apple2-roms");
        string directory = Path.Join(root, model == Apple2Model.II ? "APPLE II" : "APPLE II+");
        if (!Directory.Exists(directory))
        {
            Assert.Inconclusive("The II's and II Plus's chip dumps are not in apple2-roms.");
        }


        Apple2Roms dumps = Apple2Roms.LoadFromDirectory(model, directory, autostart);
        Apple2Roms built = SdkModules.BuildRoms(model, s_inputs, autostart);
        built.System.ToArray().Should().Equal(dumps.System.ToArray());
        built.Characters.ToArray().Should().Equal(dumps.Characters.ToArray());
    }

    /// <summary>
    ///  From the SDK's ROMs alone, the II Plus starts AppleSoft and the II with the Autostart Monitor starts Integer
    ///  BASIC.
    /// </summary>
    /// <param name="model">The II or II Plus.</param>
    /// <param name="prompt">The prompt its BASIC shows.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus, ']')]
    [DataRow(Apple2Model.II, '>')]
    public void SdkRomsStartBasic(Apple2Model model, char prompt)
    {
        Apple2Machine machine = new(model, SdkModules.BuildRoms(model, s_inputs, autostart: true));
        machine.Run(cycles: 2_000_000);
        string screen = new([.. Enumerable.Range(0, 24 * 40)
            .Select(cell => (char)(machine.Bus.TextByte(cell / 40, cell % 40) & 0x7F))]);

        screen.Should().Contain("APPLE ][").And.Contain(prompt.ToString());
    }

    private static byte[] Build(string part)
    {
        string system = Path.Join(s_inputs, "System");
        AssemblyResult result = part switch
        {
            "original Monitor" => SdkModules.AssembleSystem(
                Path.Join(system, "Monitor.asm"),
                SdkModules.MonitorOrigin,
                SdkModules.MonitorSize,
                Apple2Model.II),
            "Autostart Monitor" => SdkModules.AssembleSystem(
                Path.Join(system, "Monitor.asm"),
                SdkModules.MonitorOrigin,
                SdkModules.MonitorSize,
                Apple2Model.IIPlus),
            "character generator" => SdkModules.AssembleCharacterGenerator(Path.Join(system, "CharacterGenerator.asm"), Apple2Model.II),
            "Integer BASIC" => SdkModules.AssembleIntegerBasic(SdkModules.IntegerBasicPath(s_inputs)),
            "Programmer's Aid #1" => SdkModules.AssembleProgrammersAid(SdkModules.ProgrammersAidPath(s_inputs)),
            _ => SdkModules.AssembleAppleSoft(Path.Join(s_inputs, "AppleSoft", "applesoft.mac"), Apple2Model.IIPlus)
        };

        result.Diagnostics.Should().BeEmpty();
        return part == "II Plus AppleSoft" ? SdkModules.AppleSoftImage(result).ToArray() : result.Sections[0].Bytes.ToArray();
    }
}
