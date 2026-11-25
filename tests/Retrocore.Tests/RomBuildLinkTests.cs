// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Debug.Language;
using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  In each build of the Apple II's ROM and DOS sources that build several variants with <c>.if</c>, every link in a
///  comment the build assembles reaches a definition the build assembles (see <see cref="BuildLinkTests"/>): the
///  Monitor's four models, the IIe firmware's two, the character generator's three, and the DOS masters and running
///  copies of each year.
/// </summary>
[TestClass]
public sealed class RomBuildLinkTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  The Monitor's links reach what the model's build assembles.
    /// </summary>
    /// <param name="model">The model.</param>
    [TestMethod]
    [DataRow(Apple2Model.II)]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void MonitorLinksOnlyWhatItsBuildAssembles(Apple2Model model)
    {
        string path = Path.Join(s_inputs, "System", "Monitor.asm");
        AssemblyResult result = SdkModules.AssembleSystem(path, SdkModules.MonitorOrigin, SdkModules.MonitorSize, model);
        BuildLinkTests.AssertLinksAssembled(result, "Monitor", model.DocumentationName(), model == Apple2Model.IIeEnhanced);
    }

    /// <summary>
    ///  The IIe firmware's links reach what the model's build assembles.
    /// </summary>
    /// <param name="model">The original or Enhanced IIe.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void FirmwareLinksOnlyWhatItsBuildAssembles(Apple2Model model)
    {
        string path = SdkModules.FirmwarePath(model, s_inputs);
        AssemblyResult result = SdkModules.AssembleSystem(path, SdkModules.FirmwareOrigin, SdkModules.FirmwareSize, model);
        BuildLinkTests.AssertLinksAssembled(result, "Firmware", model.IsEnhanced() ? "Enhanced" : "Original", sdkBuild: true);
    }

    /// <summary>
    ///  The character generator's links reach what the model's chip assembles.
    /// </summary>
    /// <param name="model">The II's board, the original IIe's chip or the Enhanced IIe's.</param>
    [TestMethod]
    [DataRow(Apple2Model.II)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void CharacterGeneratorLinksOnlyWhatItsBuildAssembles(Apple2Model model)
    {
        AssemblyResult result = SdkModules.AssembleCharacterGenerator(SdkModules.CharacterGeneratorPath(s_inputs), model);
        BuildLinkTests.AssertLinksAssembled(result, "Video", sdkBuild: model == Apple2Model.IIeEnhanced);
    }

    /// <summary>
    ///  DOS's links reach what each build assembles: the master's image or the running copy, of each year.
    /// </summary>
    /// <param name="file">DOS 3.3's or DOS 3.2's root.</param>
    /// <param name="master">Whether the build is the System Master's image.</param>
    /// <param name="year">The DOS 3.3 to build; DOS 3.2 ignores it.</param>
    [TestMethod]
    [DataRow("Dos33.asm", true, 1983)]
    [DataRow("Dos33.asm", false, 1983)]
    [DataRow("Dos33.asm", true, 1980)]
    [DataRow("Dos33.asm", false, 1980)]
    [DataRow("Dos32.asm", true, 1983)]
    [DataRow("Dos32.asm", false, 1983)]
    public void DosLinksOnlyWhatItsBuildAssembles(string file, bool master, int year)
    {
        AssemblyResult result = SdkModules.AssembleDos(SdkModules.DosPath(file, s_inputs), master, year);
        BuildLinkTests.AssertLinksAssembled(result, SourceAnalysis.ModuleOf(file), sdkBuild: master && year == 1983);
    }
}
