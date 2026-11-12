// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Documentation;
using Retrocore.Machines.Apple2;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  The DOS 3.3 System Masters' BASIC images and MASTER CREATE utility, against the SDK's sources.
/// </summary>
/// <remarks>
///  <para>
///   The 1980 masters' images are the II Plus's and II's 12 KiB, $D000-$FFFF, with the Autostart Monitor. The 1983
///   master's are 10 KiB, $D000-$F7FF, as the IIe's own Monitor stays. INTBASIC's $D000-$D7FF is Programmer's Aid #1,
///   as its chip holds it in 1980 and with RAMTESTFIX in 1983; the $D800-$DFFF after it is AppleSoft's, left from the
///   image it was made from.
///  </para>
/// </remarks>
[TestClass]
public class SystemMasterBasicTests
{
    private const int Base = 0xD000;
    private const int ProgrammersAidEnd = 0xD800;
    private const int IntegerBasicStart = 0xE000;
    private const int MonitorStart = 0xF800;

    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  The 1980 master's MASTER CREATE assembles byte-identically, without requiring the disk image.
    /// </summary>
    [TestMethod]
    public void MasterCreateSourceMatchesThe1980Master()
    {
        string path = Path.Join(s_inputs, "Software", "MasterCreate.asm");
        string source = File.ReadAllText(path);
        AssemblyOptions options = new("Mos6502", origin: 0x0800, imageSize: 0x06FF)
        {
            SourceResolver = new FileAssemblySourceResolver()
        };

        AssemblyResult result = new NativeAssembler().Assemble(new AssemblySource(source, path), options);
        result.Diagnostics.Should().BeEmpty();
        Convert.ToHexString(SHA256.HashData(result.Sections[0].Bytes.Span))
            .Should().Be("B6B6978F771F9F4233B367F2643692E6FD998FDB1D9E03C81BF2D411E6BA4EC5");

        DocumentationSet docs = DocumentationSet.Create([DocumentationParser.Parse(source, path)], result);
        new DocumentationResolver(docs).Check().Should().BeEmpty();
    }

    /// <summary>
    ///  The 1980 masters' FPBASIC is the II Plus's AppleSoft and Autostart Monitor.
    /// </summary>
    /// <param name="master">The System Master's file.</param>
    [TestMethod]
    [DataRow("DOS 3.3 System Master - 680-0051-00.dsk")]
    [DataRow("DOS 3.3 System Master - 680-0051-01 (1980).dsk")]
    public void FpBasic1980IsTheIIPlusRom(string master)
    {
        byte[] image = Binary(master, "FPBASIC");
        image.Should().Equal(SdkModules.BuildBoardSystem(Apple2Model.IIPlus, autostart: true, s_inputs));
    }

    /// <summary>
    ///  The 1980 masters' INTBASIC is Programmer's Aid #1 as its chip holds it, AppleSoft's $D800-$DFFF, then Integer
    ///  BASIC and the Autostart Monitor.
    /// </summary>
    /// <param name="master">The System Master's file.</param>
    [TestMethod]
    [DataRow("DOS 3.3 System Master - 680-0051-00.dsk")]
    [DataRow("DOS 3.3 System Master - 680-0051-01 (1980).dsk")]
    public void IntBasic1980IsTheIIRom(string master)
    {
        byte[] image = Binary(master, "INTBASIC");
        image.Length.Should().Be(0x3000);
        byte[] board = SdkModules.BuildBoardSystem(Apple2Model.II, autostart: true, s_inputs, programmersAid: true);
        Range(image, Base, ProgrammersAidEnd).Should().Equal(Range(board, Base, ProgrammersAidEnd));
        byte[] appleSoft = Range(AppleSoft(Apple2Model.IIPlus), ProgrammersAidEnd, IntegerBasicStart);
        Range(image, ProgrammersAidEnd, IntegerBasicStart).Should().Equal(appleSoft);
        Range(image, IntegerBasicStart, 0x10000).Should().Equal(Range(board, IntegerBasicStart, 0x10000));
    }

    /// <summary>
    ///  The 1983 master's FPBASIC is the IIe's AppleSoft, $D000-$F7FF, whose last byte is the IIe's rather than the
    ///  II Plus's.
    /// </summary>
    [TestMethod]
    public void FpBasic1983IsTheIIeAppleSoft()
    {
        byte[] image = Binary("DOS 3.3 System Master - 680-0210-A (1982).dsk", "FPBASIC");
        image.Should().Equal(AppleSoft(Apple2Model.IIe));
    }

    /// <summary>
    ///  The 1983 master's INTBASIC is Programmer's Aid #1 as RAMTESTFIX builds it, AppleSoft's $D800-$DFFF, then
    ///  Integer BASIC as FORFIX builds it; each option changes only the bytes of its fix.
    /// </summary>
    [TestMethod]
    public void IntBasic1983IsTheFixedIntegerBasic()
    {
        byte[] image = Binary("DOS 3.3 System Master - 680-0210-A (1982).dsk", "INTBASIC");
        image.Length.Should().Be(0x2800);
        string aidPath = SdkModules.ProgrammersAidPath(s_inputs);
        byte[] fixedAid = SdkModules.AssembleProgrammersAid(aidPath, ramTestFix: true).Sections[0].Bytes.ToArray();
        Range(image, Base, ProgrammersAidEnd).Should().Equal(fixedAid);
        byte[] chip = SdkModules.AssembleProgrammersAid(aidPath).Sections[0].Bytes.ToArray();
        Enumerable.Range(0, chip.Length)
            .Where(offset => fixedAid[offset] != chip[offset])
            .Select(offset => $"${Base + offset:X4}: {chip[offset]:X2} -> {fixedAid[offset]:X2}")
            .Should()
            .Equal("$D670: 4C -> 20", "$D671: CB -> 8A", "$D672: 02 -> D6");

        byte[] appleSoft = Range(AppleSoft(Apple2Model.IIe), ProgrammersAidEnd, IntegerBasicStart);
        Range(image, ProgrammersAidEnd, IntegerBasicStart).Should().Equal(appleSoft);
        string path = SdkModules.IntegerBasicPath(s_inputs);
        byte[] fixedBasic = SdkModules.AssembleIntegerBasic(path, forFix: true).Sections[0].Bytes.ToArray();
        Range(image, IntegerBasicStart, MonitorStart).Should().Equal(fixedBasic);

        byte[] rom = SdkModules.AssembleIntegerBasic(path).Sections[0].Bytes.ToArray();
        Enumerable.Range(0, rom.Length)
            .Where(offset => fixedBasic[offset] != rom[offset])
            .Select(offset => $"${IntegerBasicStart + offset:X4}: {rom[offset]:X2} -> {fixedBasic[offset]:X2}")
            .Should()
            .Equal("$F2D5: A1 -> B1", "$F2D8: A0 -> B0");
    }

    // AppleSoft as built for a model, $D000-$F7FF.
    private static byte[] AppleSoft(Apple2Model model) =>
        SdkModules.AppleSoftImage(SdkModules.AssembleAppleSoft(Path.Join(s_inputs, "AppleSoft", "applesoft.mac"), model)).ToArray();

    // The bytes of an image starting at $D000 from one address up to another.
    private static byte[] Range(byte[] image, int start, int end) => image[(start - Base)..(end - Base)];

    // A binary file's bytes from a System Master, after its address and length, or inconclusive without the master.
    private static byte[] Binary(string master, string name)
    {
        string path = Path.Join(ExternalTestData.Root, "iie-disks", master);
        if (!File.Exists(path)) { Assert.Inconclusive($"The DOS 3.3 System Master ({path}) is missing."); }

        byte[] data = DosFiles.Find(File.ReadAllBytes(path), name) ?? throw new InvalidDataException($"{master} has no {name}.");
        int length = data[2] | (data[3] << 8);
        return data[4..(4 + length)];
    }
}
