// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Documentation;
using Retrocore.Machines.Chips;
using Retrocore.Machines.Commodore.Serial;
using Retrocore.Machines.Commodore.Vic20;
using Retrocore.Media.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the SDK's source for the 1541's and 1540's DOS, <c>Serial/Dos1541.asm</c>: 325302-01 with each of the
///  1541's 901229 revisions it builds, 01, 02, 03, 05 and 06, or with the 1540's 325303-01.
/// </summary>
/// <remarks>
///  <para>
///   Digests pin each build, so no ROM is needed. With MAME's <c>c1541</c> and <c>c1540</c> sets in
///   <see cref="Vic20MachineTests.RomRoot"/>, a build that differs names its first different byte.
///  </para>
/// </remarks>
[TestClass]
public sealed class Dos1541SourceTests
{
    // Fewer old names than this means the check found almost none: the DOS keeps about 1,500.
    private const int MinimumOldNames = 1400;

    private static string Sources => Path.Join(BasicNames.Inputs, "Pet", "Serial");

    /// <summary>
    ///  Each build is byte-identical to its chips, 325302-01 at <c>$C000</c> and the second ROM at <c>$E000</c>.
    /// </summary>
    /// <param name="revision">The build's <c>REVISION</c>: 901229's revision, or 40 for the 1540.</param>
    /// <param name="chip">The second ROM's file in its MAME set.</param>
    /// <param name="expected">The build's SHA-256.</param>
    [TestMethod]
    [DataRow(1, "c1541/901229-01.uab5", "DF1DAD21D992EBB2DDC7BE49B4A8A31BC5D22909977B1C3B40096A0304340F6F")]
    [DataRow(2, "c1541/901229-02.uab5", "5CDF8E33468F4189F9E9A13C598A060FA84203CE64F5F5512F2EEE0CA763F002")]
    [DataRow(3, "c1541/901229-03.uab5", "9D2D88AB750114022C7A382088A6064E8BA4EFB6A76FDED610128E99079E20D4")]
    [DataRow(5, "c1541/901229-05 ae.uab5", "D1D45AFB46FD4E2B48D93CA367B889D75654A3B7ACF73044E51F6D880C09369E")]
    [DataRow(6, "c1541/901229-06 aa.uab5", "A6286DB635A91D0982242C10FE2832978502D2D6E95F33DD5EC019834CB0C54A")]
    [DataRow(40, "c1540/325303-01.uab5", "A966E3FF6FD2DB7B8F6D57E4D105C589A92E88A6705201215604AC864CC3C27F")]
    public void BuildsMatchTheChips(int revision, string chip, string expected)
    {
        ReadOnlySpan<byte> image = Cbm1541SdkModules.Assemble(Sources, revision).Sections[0].Bytes.Span;
        image.Length.Should().Be(2 * Cbm1541SdkModules.ChipSize);
        string hash = Convert.ToHexString(SHA256.HashData(image));
        if (hash == expected) { return; }

        string because = "the digest pins the chips (without their dumps the first different byte can't be named)";
        string low = Path.Join(Vic20MachineTests.RomRoot, "c1541", "325302-01.uab4");
        string high = Path.Join(Vic20MachineTests.RomRoot, chip);
        if (File.Exists(low) && File.Exists(high))
        {
            byte[] chips = [.. File.ReadAllBytes(low), .. File.ReadAllBytes(high)];
            because = $"the first difference is at ${Cbm1541SdkModules.Origin + image.CommonPrefixLength(chips):X4}";
        }

        hash.Should().Be(expected, because);
    }

    /// <summary>
    ///  Every old name in the source cites only Commodore's listing of 901229-05 (D1541), which is in the bibliography,
    ///  and each build resolves the listing's names for code every build has.
    /// </summary>
    /// <param name="revision">The build's <c>REVISION</c>.</param>
    [TestMethod]
    [DataRow(1)]
    [DataRow(2)]
    [DataRow(3)]
    [DataRow(5)]
    [DataRow(6)]
    [DataRow(40)]
    public void OldNamesCiteTheListing(int revision)
    {
        AssemblyResult result = Cbm1541SdkModules.Assemble(Sources, revision);
        List<string> wrong = [];
        int count = 0;
        foreach (string path in Directory.EnumerateFiles(Sources, "Dos1541*.asm"))
        {
            string name = Path.GetFileName(path);
            foreach (DocumentationAlso also in DocumentationParser.Parse(File.ReadAllText(path), path).Comments
                .SelectMany(comment => DocumentationAlso.Of(comment.Sections)))
            {
                count++;
                if (also.Sources.Count == 0) { wrong.Add($"{name}: {also.Name} cites no document"); }
                foreach (string key in also.Sources)
                {
                    if (key != "D1541") { wrong.Add($"{name}: {also.Name} cites {key}, not the DOS's listing"); }
                    if (BasicAttribution.Bibliography.Find(key) is null)
                    {
                        wrong.Add($"{name}: {also.Name} cites {key}, not in the bibliography");
                    }
                }
            }
        }

        // Old names reach their definitions in the build, as code typed in from the listing uses them.
        foreach (string old in new[] { "ILERR", "JOBS", "SETJOB", "DSKINT", "ERRTAB" })
        {
            result.HistoricalNames.ContainsKey(old).Should().BeTrue($"{old} is an old name in every build");
        }

        wrong.Should().BeEmpty($"the DOS's old names cite its listing:{Environment.NewLine}{string.Join(Environment.NewLine, wrong)}");
        count.Should().BeGreaterThan(MinimumOldNames, "the DOS keeps the listing's names");
    }

    /// <summary>
    ///  Each build has the code of its own revision: the boot loader before -05, -05's patches, -06's format patch, and
    ///  the 1540 without the 64's bus speed.
    /// </summary>
    /// <param name="revision">The build's <c>REVISION</c>.</param>
    /// <param name="has">Definitions the build has.</param>
    /// <param name="lacks">Definitions it does not.</param>
    [TestMethod]
    [DataRow(1, "Startup::BootExit,Serial::SlowDown,Startup::Nmi", "Startup::ResetPatch,Commands::FormatPatch")]
    [DataRow(5, "Startup::ResetPatch,Serial::ReceiveBytePatch,Serial::SlowDown", "Startup::BootExit,Commands::FormatPatch")]
    [DataRow(6, "Startup::ResetPatch,Commands::FormatPatch", "Startup::BootExit")]
    [DataRow(40, "Startup::BootExit,Startup::Reinitialize", "Serial::SlowDown,Startup::Nmi,Startup::ResetPatch")]
    public void EachBuildHasItsOwnCode(int revision, string has, string lacks)
    {
        IReadOnlyDictionary<string, long> symbols = Cbm1541SdkModules.Assemble(Sources, revision).Symbols;
        foreach (string name in has.Split(',')) { symbols.Should().ContainKey(name); }
        foreach (string name in lacks.Split(',')) { symbols.Should().NotContainKey(name); }
    }

    /// <summary>
    ///  A VIC-20 and its drive, both from the SDK's builds with no dumps, format a disk, save a program on it and load
    ///  it back, in each of the drive's builds.
    /// </summary>
    /// <param name="model">The drive.</param>
    /// <param name="revision">For a 1541, 901229's revision.</param>
    [TestMethod]
    [DataRow("1541", 1)]
    [DataRow("1541", 2)]
    [DataRow("1541", 3)]
    [DataRow("1541", 5)]
    [DataRow("1541", 6)]
    [DataRow("1540", 0)]
    public void DriveRunsFromTheSdkBuilds(string model, int revision)
    {
        Vic20Roms roms = Vic20SdkModules.BuildRoms(VicVideoStandard.Ntsc, Path.Join(BasicNames.Inputs, "Pet", "Vic20"));
        Vic20Machine machine = new(roms, VicVideoStandard.Ntsc);
        Cbm1541 drive = machine.AddDisk(Cbm1541SdkModules.BuildRoms(model, revision, Sources));
        CommodoreDisk disk = CommodoreDisk.Blank();
        drive.Drive.Insert(disk, "blank", "G64", changed: true);
        Vic20MachineTests.RunToReady(machine);

        Command(machine, "N0:RETROCORE,RC").Should().Contain("RESULT 0 OK");
        Vic20MachineTests.Type(machine, "NEW\r10 PRINT \"DISK\";6*7\rSAVE\"PROG\",8\r");
        Vic20TapeTests.WaitForReady(machine);
        Vic20MachineTests.Type(machine, "NEW\rLOAD\"PROG\",8\r");
        Vic20TapeTests.WaitForReady(machine);
        Vic20MachineTests.Type(machine, "RUN\r");
        Vic20TapeTests.WaitForReady(machine);
        string screen = string.Join('\n', machine.ReadTextScreen());
        screen.Should().Contain("DISK 42", "the program came back from the disk");

        CbmDosDisk.FromD64(D64Format.Write(disk).Image).ReadFile("PROG").Should().NotBeEmpty("the disk holds the program");
    }

    /// <summary>
    ///  With the dumps, the SDK's builds are MAME's chips: the 1541's with -06, its default, and the 1540's.
    /// </summary>
    [TestMethod]
    public void SdkBuildsAreTheChips()
    {
        string c1541 = Path.Join(Vic20MachineTests.RomRoot, "c1541");
        string c1540 = Path.Join(Vic20MachineTests.RomRoot, "c1540");
        if (!File.Exists(Path.Join(c1541, "901229-06 aa.uab5")) || !File.Exists(Path.Join(c1540, "325303-01.uab5")))
        {
            Assert.Inconclusive("Set RETROCORE_VIC20_ROMS to a folder with MAME's c1541 and c1540 sets unzipped.");
        }

        foreach ((Cbm1541Roms chips, Cbm1541Roms built) in new[]
        {
            (Cbm1541Roms.Load1541FromDirectory(c1541), Cbm1541SdkModules.BuildRoms("1541", directory: Sources)),
            (Cbm1541Roms.Load1540FromDirectory(c1540), Cbm1541SdkModules.BuildRoms("1540", directory: Sources))
        })
        {
            built.Model.Should().Be(chips.Model);
            built.Low.SequenceEqual(chips.Low).Should().BeTrue($"the {chips.Model}'s $C000 ROM is 325302-01");
            built.High.SequenceEqual(chips.High).Should().BeTrue($"the {chips.Model}'s $E000 ROM is the chip");
        }
    }

    // Sends a command to the drive's command channel and prints its answer: RESULT, the number and the message.
    private static string Command(Vic20Machine machine, string command)
    {
        Vic20MachineTests.Type(machine, $"NEW\r10 OPEN15,8,15,\"{command}\":INPUT#15,A,B$:PRINT\"RESULT\";A;B$:CLOSE15\rRUN\r");
        Vic20TapeTests.WaitForReady(machine);
        return string.Concat(machine.ReadTextScreen());
    }
}
