// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.IO.Compression;
using System.Xml.Linq;
using Retrocore.Machines.Chips;
using Retrocore.Machines.Commodore.Vic20;

namespace Retrocore.Tests;

/// <summary>
///  The VIC-20's cartridges: the images that hold them, and a sample of MAME's <c>vic1001_cart</c> list starting on
///  the RAM they were sold for.
/// </summary>
/// <remarks>
///  <para>
///   The list's zips are under <c>%USERPROFILE%\Retrocore\vic20-media\extract</c>, and its hash file, which says where
///   each chip goes, in MAME's <c>hash</c> folder; the tests that need them are inconclusive without them.
///  </para>
/// </remarks>
[TestClass]
public class Vic20CartridgeTests
{
    /// <summary>
    ///  A chip's extension is its address's high byte; a 4K chip is seen again in the rest of its block, and one at
    ///  <c>$A000</c> with <c>A0CBM</c> starts itself.
    /// </summary>
    [TestMethod]
    public void ChipsGoWhereTheirNamesSay()
    {
        byte[] low = Chip(0x1000, 0x11);
        "A0CBM"u8.ToArray().CopyTo(low, 4);
        low[6] = 0xC3;
        low[7] = 0xC2;
        low[8] = 0xCD;
        Vic20Cartridge cartridge = Vic20Cartridge.Load(("game.a0", low), ("aid.70", Chip(0x1000, 0x22)));

        cartridge.Blocks.Should().Be(Vic20Expansion.Block3 | Vic20Expansion.Block5);
        cartridge.Autostarts.Should().BeTrue();
        cartridge.Read(0xA010).Should().Be(0x11);
        cartridge.Read(0xB010).Should().Be(0x11, "the 4K chip is seen again at $B000");
        cartridge.Read(0x7010).Should().Be(0x22);
        cartridge.Read(0x6010).Should().Be(0x22, "the 4K chip at $7000 is seen at $6000 too");
        cartridge.Fills(0x2000).Should().BeFalse();
    }

    /// <summary>
    ///  A <c>.prg</c> cartridge's first two bytes say where it goes; one with no extension that has none of the
    ///  starts is a chip at <c>$A000</c>.
    /// </summary>
    [TestMethod]
    public void PrgCartridgeGoesWhereItsAddressSays()
    {
        byte[] prg = [0x00, 0x20, .. Chip(0x4000, 0x33)];
        Vic20Cartridge cartridge = Vic20Cartridge.Load(("big.prg", prg));
        cartridge.Blocks.Should().Be(Vic20Expansion.Block1 | Vic20Expansion.Block2);
        cartridge.Read(0x5FFF).Should().Be(0x33);

        Vic20Cartridge.Load(("325323-01", Chip(0x1000, 0x44))).Blocks.Should().Be(Vic20Expansion.Block5);
        Vic20Cartridge.Load(("noname", prg)).Blocks.Should().Be(Vic20Expansion.Block1 | Vic20Expansion.Block2);
    }

    /// <summary>
    ///  A VICE <c>.crt</c> of the generic type puts each CHIP packet at its address, and a RAM packet adds RAM; other
    ///  types are refused, as are chips that overlap or fall outside the blocks.
    /// </summary>
    [TestMethod]
    public void CrtPacketsGoWhereTheySay()
    {
        byte[] crt = Crt(0, (0, 0x6000, Chip(0x2000, 0x55)), (0, 0xA000, Chip(0x2000, 0x66)), (1, 0x0400, []));
        Vic20Cartridge cartridge = Vic20Cartridge.Load(("game.crt", crt));
        cartridge.Blocks.Should().Be(Vic20Expansion.Block3 | Vic20Expansion.Block5);
        cartridge.Ram.Should().Be(Vic20Expansion.Ram3K);
        cartridge.Read(0x6000).Should().Be(0x55);
        cartridge.Read(0xBFFF).Should().Be(0x66);

        Refused(("mega.crt", Crt(1, (0, 0xA000, Chip(0x2000, 0))))).Should().Contain("type 1");
        Refused(("a.a0", Chip(0x2000, 0)), ("b.b0", Chip(0x1000, 0))).Should().Contain("Two chips");
        Refused(("bad.prg", [0x00, 0x80, .. Chip(0x400, 0)])).Should().Contain("outside blocks");

        static string Refused(params (string Name, byte[] Data)[] files)
        {
            try
            {
                Vic20Cartridge.Load(files);
            }
            catch (InvalidDataException e)
            {
                return e.Message;
            }

            throw new AssertFailedException("The cartridge was not refused.");
        }
    }

    /// <summary>
    ///  The list's cartridges read from their files' names go where MAME's hash file puts them.
    /// </summary>
    /// <param name="software">The list's name for the cartridge.</param>
    [TestMethod]
    [DataRow("avenger")]
    [DataRow("ldrun")]
    [DataRow("progaid")]
    [DataRow("advland")]
    [DataRow("storymac")]
    public void ListFilesLoadByTheirNames(string software)
    {
        Vic20Cartridge expected = FromSoftwareList(software);
        Vic20Cartridge actual = Vic20Cartridge.Load([.. Files(software)]);
        actual.Blocks.Should().Be(expected.Blocks);
        for (int address = 0x2000; address < 0xC000; address++)
        {
            actual.Fills(address).Should().Be(expected.Fills(address), $"${address:X4} is filled the same");
            if (actual.Fills(address)) { actual.Read(address).Should().Be(expected.Read(address), $"${address:X4}"); }
        }
    }

    /// <summary>
    ///  A game with <c>A0CBM</c> starts itself in place of BASIC, on the unexpanded machine it was sold for.
    /// </summary>
    /// <param name="software">The list's name for the cartridge.</param>
    /// <param name="standard">The video standard.</param>
    [TestMethod]
    [DataRow("avenger", VicVideoStandard.Ntsc)]
    [DataRow("gorf", VicVideoStandard.Ntsc)]
    [DataRow("ldrun", VicVideoStandard.Pal)]
    public void GameStartsItself(string software, VicVideoStandard standard)
    {
        Vic20Cartridge cartridge = FromSoftwareList(software);
        cartridge.Autostarts.Should().BeTrue();
        Vic20Machine machine = Vic20MachineTests.Machine(standard, cartridge: cartridge);
        machine.Run(TimeSpan.FromSeconds(3));

        machine.ReadTextScreen().Should().NotContain(line => line.Contains("CBM BASIC", StringComparison.Ordinal));
        int inCartridge = 0;
        for (int i = 0; i < 1000; i++)
        {
            machine.StepInstruction();
            ushort pc = machine.Processor.Registers.ProgramCounter;
            if (machine.Bus.Area(pc) == Vic20MemoryArea.Cartridge) { inCartridge++; }
        }

        inCartridge.Should().BeGreaterThan(100, "the game runs from its ROM");
    }

    /// <summary>
    ///  The Super Expander brings 3K of RAM with its ROM, and BASIC counts it.
    /// </summary>
    [TestMethod]
    public void SuperExpanderAddsItsRam()
    {
        Vic20Cartridge cartridge = FromSoftwareList("sprexpnd");
        cartridge.Ram.Should().Be(Vic20Expansion.Ram3K);
        Vic20Machine machine = Vic20MachineTests.Machine(cartridge: cartridge);
        machine.Bus.Expansion.Should().Be(Vic20Expansion.Ram3K);
        string[] screen = Vic20MachineTests.RunToReady(machine);
        screen.Should().Contain(line => line.Contains("BYTES FREE", StringComparison.Ordinal), string.Join('\n', screen));
    }

    /// <summary>
    ///  The Programmer's Aid, at <c>$7000</c>, does not start itself; <c>SYS 28681</c> starts it, and its <c>AUTO</c>
    ///  command numbers the lines typed.
    /// </summary>
    [TestMethod]
    public void ProgrammersAidStartsWithSys()
    {
        Vic20Cartridge cartridge = FromSoftwareList("progaid");
        cartridge.Autostarts.Should().BeFalse();
        Vic20Machine machine = Vic20MachineTests.Machine(cartridge: cartridge);
        Vic20MachineTests.RunToReady(machine);
        Vic20MachineTests.Type(machine, "SYS 28681\r");
        string[] screen = machine.ReadTextScreen();
        screen.Should().Contain(line => line.StartsWith("READY.", StringComparison.Ordinal), string.Join('\n', screen));
        screen.Should().NotContain(line => line.Contains("ERROR", StringComparison.Ordinal), string.Join('\n', screen));
    }

    /// <summary>
    ///  Builds a cartridge as MAME loads one from its list: each chip at its data area's block and its offset there,
    ///  and the 3K slot's RAM where the list asks for it.
    /// </summary>
    /// <param name="software">The list's name for the cartridge.</param>
    /// <returns>The cartridge.</returns>
    internal static Vic20Cartridge FromSoftwareList(string software)
    {
        string hash = Path.Join(ExternalTestData.Root, "mame", "hash", "vic1001_cart.xml");
        if (!File.Exists(hash)) { Assert.Inconclusive("MAME's vic1001_cart hash file is missing."); }
        XElement entry = Entry(hash, software);
        Dictionary<string, byte[]> files = Files(software).ToDictionary(file => file.Name, file => file.Data);
        List<(int, byte[])> chips = [];
        Vic20Expansion ram = Vic20Expansion.None;
        foreach (XElement part in entry.Elements("part"))
        {
            if (part.Elements("feature").Any(f => (string?)f.Attribute("name") == "slot" && (string?)f.Attribute("value") == "3k"))
            {
                ram |= Vic20Expansion.Ram3K;
            }

            foreach (XElement area in part.Elements("dataarea"))
            {
                int block = (string?)area.Attribute("name") switch
                {
                    "blk1" => 0x2000,
                    "blk2" => 0x4000,
                    "blk3" => 0x6000,
                    "blk5" => 0xA000,
                    var other => throw new AssertInconclusiveException($"{software}'s {other} area is not a block.")
                };

                foreach (XElement rom in area.Elements("rom"))
                {
                    int offset = int.Parse(Text(rom, "offset")[2..], NumberStyles.HexNumber, CultureInfo.InvariantCulture);
                    chips.Add((block + offset, files[Text(rom, "name")]));
                }
            }
        }

        return new(chips, ram);
    }

    // The files of a cartridge in the list's zip, which holds its clones' too.
    private static List<(string Name, byte[] Data)> Files(string software)
    {
        string hash = Path.Join(ExternalTestData.Root, "mame", "hash", "vic1001_cart.xml");
        string zip = Path.Join(ExternalTestData.Root, "vic20-media", "extract", "vic1001_cart", "vic1001_cart", software + ".zip");
        if (!File.Exists(zip) || !File.Exists(hash))
        {
            Assert.Inconclusive("MAME's vic1001_cart list or its hash file is missing; see vic20-media's README.");
        }

        HashSet<string> names = [.. Entry(hash, software).Descendants("rom").Select(rom => Text(rom, "name"))];

        using ZipArchive archive = ZipFile.OpenRead(zip);
        List<(string, byte[])> files = [];
        foreach (ZipArchiveEntry entry in archive.Entries.Where(e => names.Contains(e.Name)))
        {
            using MemoryStream stream = new();
            using (Stream data = entry.Open()) { data.CopyTo(stream); }
            files.Add((entry.Name, stream.ToArray()));
        }

        return files;
    }

    private static XElement Entry(string hash, string software) =>
        (XDocument.Load(hash).Root ?? throw new AssertInconclusiveException("The hash file is empty."))
            .Elements("software").Single(e => (string?)e.Attribute("name") == software);

    private static string Text(XElement element, string attribute) =>
        (string?)element.Attribute(attribute) ?? throw new AssertInconclusiveException($"A rom has no {attribute}.");

    private static byte[] Chip(int length, byte value)
    {
        byte[] chip = new byte[length];
        chip.AsSpan().Fill(value);
        return chip;
    }

    // A VICE .crt of a hardware type with CHIP packets of a type (0 ROM, 1 RAM), an address and bytes.
    private static byte[] Crt(int type, params (int Type, int Address, byte[] Data)[] chips)
    {
        List<byte> crt = [.. "VIC20 CARTRIDGE "u8, 0, 0, 0, 0x40, 2, 0, (byte)(type >> 8), (byte)type];
        crt.AddRange(new byte[0x40 - crt.Count]);
        foreach ((int chipType, int address, byte[] data) in chips)
        {
            int length = 0x10 + data.Length;
            crt.AddRange("CHIP"u8.ToArray());
            crt.AddRange([(byte)(length >> 24), (byte)(length >> 16), (byte)(length >> 8), (byte)length]);
            crt.AddRange([0, (byte)chipType, 0, 0, (byte)(address >> 8), (byte)address, (byte)(data.Length >> 8), (byte)data.Length]);
            crt.AddRange(data);
        }

        return [.. crt];
    }
}
