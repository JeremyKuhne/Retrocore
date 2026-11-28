// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers.Binary;
using Retrocore.Debug;
using Retrocore.Machines.Commodore;
using Retrocore.Machines.Commodore.Vic20;
using Retrocore.Machines.Devices;
using Retrocore.Media.Commodore;
using System.Text.Json.Nodes;

namespace Retrocore.Tests;

/// <summary>
///  T64 directory and payload validation, and playback through the PET and VIC-20 kernals.
/// </summary>
[TestClass]
public sealed class T64Tests
{
    /// <summary>
    ///  PRG types and legacy program markers play in directory order, not the physical order of the payloads.
    /// </summary>
    /// <param name="fileType">The second program's CBM file-type byte.</param>
    [TestMethod]
    [DataRow(0x01)]
    [DataRow(0x44)]
    [DataRow(0x82)]
    [DataRow(0xC2)]
    public void ReadsProgramsInDirectoryOrder(int fileType)
    {
        byte[] image = TapeImage(0x04);
        image[0x81] = (byte)fileType;
        CommodoreTape first = CommodoreTapeBuilder.FromProgram("FIRST", 0x0401, [0, 0]);
        CommodoreTape second = CommodoreTapeBuilder.FromProgram("SECOND", 0x0401, Program(0x04));
        T64Format.Read(image).Pulses.Should().Equal(first.Pulses.Concat(second.Pulses));
    }

    /// <summary>
    ///  A non-program entry in an otherwise valid archive cannot become a loadable program.
    /// </summary>
    /// <param name="fileType">The unsupported second file's CBM file-type byte.</param>
    [TestMethod]
    [DataRow(0x00)]
    [DataRow(0x81)]
    [DataRow(0x83)]
    [DataRow(0x84)]
    public void RefusesNonProgramEntries(int fileType)
    {
        byte[] image = TapeImage(0x04);
        image[0x81] = (byte)fileType;
        FluentActions.Invoking(() => T64Format.Read(image)).Should().Throw<InvalidDataException>()
            .WithMessage($"T64 entry 3 has unsupported CBM file type ${fileType:X2}; only programs can be played.");
    }

    /// <summary>
    ///  An impossible CONV64 end address can be repaired from the next physical payload, without changing file order.
    /// </summary>
    /// <param name="start">A start address that makes the placeholder length too large or empty.</param>
    [TestMethod]
    [DataRow(0x0401)]
    [DataRow(0xC3C6)]
    public void ReadsLegacyEndAddress(int start)
    {
        byte[] image = TapeImage(0x04);
        "C64S tape file"u8.CopyTo(image);
        image.AsSpan(14, 18).Clear();
        BinaryPrimitives.WriteUInt16LittleEndian(image.AsSpan(0x82), (ushort)start);
        image[0x84] = 0xC6;
        image[0x85] = 0xC3;
        CommodoreTape first = CommodoreTapeBuilder.FromProgram("FIRST", 0x0401, [0, 0]);
        CommodoreTape second = CommodoreTapeBuilder.FromProgram("SECOND", (ushort)start, Program(0x04));
        T64Format.Read(image).Pulses.Should().Equal(first.Pulses.Concat(second.Pulses));
    }

    /// <summary>
    ///  Padding before the next payload or at EOF is not imported when a valid end address equals the CONV64 placeholder.
    /// </summary>
    /// <param name="final">Whether the program with padding is the final physical payload.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void PreservesValidEndAddressWithPadding(bool final)
    {
        byte[] image = TapeImage(0x04);
        BinaryPrimitives.WriteUInt16LittleEndian(image.AsSpan(final ? 0x42 : 0x82), final ? (ushort)0xC3C4 : (ushort)0xC3BF);
        BinaryPrimitives.WriteUInt16LittleEndian(image.AsSpan(final ? 0x44 : 0x84), 0xC3C6);
        CommodoreTape first = CommodoreTapeBuilder.FromProgram("FIRST", final ? (ushort)0xC3C4 : (ushort)0x0401, [0, 0]);
        byte[] program = Program(0x04);
        CommodoreTape second = final
            ? CommodoreTapeBuilder.FromProgram("SECOND", 0x0401, program)
            : CommodoreTapeBuilder.FromProgram("SECOND", 0xC3BF, program.AsSpan(0, 7));

        T64Format.Read(image).Pulses.Should().Equal(first.Pulses.Concat(second.Pulses));
    }

    /// <summary>
    ///  Legacy single-file images can omit directory counts. The actual entry must still be valid.
    /// </summary>
    /// <param name="slots">The directory capacity in the header.</param>
    /// <param name="used">The used entry count in the header.</param>
    [TestMethod]
    [DataRow(1, 0)]
    [DataRow(0, 1)]
    [DataRow(0, 0)]
    public void ReadsSingleProgramWithMissingCounts(int slots, int used)
    {
        byte[] image = TapeImage(0x04)[..0x62];
        image[0x22] = (byte)slots;
        image[0x24] = (byte)used;
        image[0x48] = 0x60;
        CommodoreTape expected = CommodoreTapeBuilder.FromProgram("FIRST", 0x0401, [0, 0]);
        T64Format.Read(image).Pulses.Should().Equal(expected.Pulses);
    }

    /// <summary>
    ///  A program ending at $FFFF encodes an exclusive end of zero.
    /// </summary>
    [TestMethod]
    public void ReadsProgramAtTheTopOfMemory()
    {
        byte[] image = TapeImage(0x04);
        ReadOnlySpan<byte> addresses = [0xFE, 0xFF, 0, 0];
        addresses.CopyTo(image.AsSpan(0x42));
        CommodoreTape first = CommodoreTapeBuilder.FromProgram("FIRST", 0xFFFE, [0, 0]);
        CommodoreTape second = CommodoreTapeBuilder.FromProgram("SECOND", 0x0401, Program(0x04));
        T64Format.Read(image).Pulses.Should().Equal(first.Pulses.Concat(second.Pulses));
    }

    /// <summary>
    ///  Rejects malformed directory or program metadata instead of mounting a partial tape.
    /// </summary>
    /// <param name="offset">The position of the changed byte.</param>
    /// <param name="value">The value that breaks the image.</param>
    /// <param name="message">The expected diagnostic.</param>
    [TestMethod]
    [DataRow(0x22, 6, "*truncated directory*")]
    [DataRow(0x24, 3, "*used entry count*")]
    [DataRow(0x48, 0x40, "*outside the program data*")]
    [DataRow(0x4B, 0x80, "*outside the program data*")]
    [DataRow(0x84, 0x0E, "*invalid or truncated program*")]
    [DataRow(0x44, 0x08, "*invalid or truncated program*")]
    [DataRow(0x80, 3, "*not a normal tape file*")]
    public void RefusesInvalidImages(int offset, int value, string message)
    {
        byte[] image = TapeImage(0x04);
        image[offset] = (byte)value;
        FluentActions.Invoking(() => T64Format.Read(image)).Should().Throw<InvalidDataException>().WithMessage(message);
    }

    /// <summary>
    ///  An archive that expands to exactly the pulse limit is accepted; one more program byte is refused.
    /// </summary>
    /// <param name="extraBytes">The bytes beyond the archive that fills the limit.</param>
    [TestMethod]
    [DataRow(0)]
    [DataRow(1)]
    public void ChecksTapeExpansionAtThePulseLimit(int extraBytes)
    {
        const ushort files = 24;
        const int standardLength = 16_443;
        // Each file contributes 41,314 framing pulses plus 40 per program byte.
        int lastLength = standardLength + 10 + extraBytes;
        const int directoryEnd = 64 + (32 * files);
        byte[] image = new byte[directoryEnd + ((files - 1) * standardLength) + lastLength];
        "C64 tape image file"u8.CopyTo(image);
        BinaryPrimitives.WriteUInt16LittleEndian(image.AsSpan(0x22), files);
        BinaryPrimitives.WriteUInt16LittleEndian(image.AsSpan(0x24), files);
        for (int i = 0; i < files; i++)
        {
            Span<byte> entry = image.AsSpan(64 + (32 * i), 32);
            entry[0] = 1;
            entry[1] = 0x82;
            int length = i == files - 1 ? lastLength : standardLength;
            BinaryPrimitives.WriteUInt16LittleEndian(entry[4..], (ushort)length);
            BinaryPrimitives.WriteInt32LittleEndian(entry[8..], directoryEnd + (i * standardLength));
        }

        if (extraBytes == 0)
        {
            T64Format.Read(image).Pulses.Count.Should().Be(16 * 1024 * 1024);
        }
        else
        {
            FluentActions.Invoking(() => T64Format.Read(image)).Should().Throw<InvalidDataException>()
                .WithMessage("*too much program data*");
        }
    }

    /// <summary>
    ///  Launch and live insert mount T64s with PLAY down. The real kernal reads both entries from the same tape,
    ///  and a bad replacement does not dislodge it or make the source archive writable.
    /// </summary>
    /// <param name="device">The device in which the tape is mounted.</param>
    /// <param name="page">The high byte of BASIC's load address.</param>
    [TestMethod]
    [DataRow("cassette2", 0x04)]
    [DataRow("cassette", 0x10)]
    public void CassettePlaysBothPrograms(string device, int page)
    {
        string work = Directory.CreateTempSubdirectory("retrocore-t64").FullName;
        string path = Path.Join(work, "programs.T64");
        string malformed = Path.Join(work, "bad.t64");
        string saved = Path.Join(work, "programs.tap");
        byte[] image = TapeImage((byte)page);
        try
        {
            File.WriteAllBytes(path, image);
            File.WriteAllBytes(malformed, image[..0x20]);
            bool pet = device == "cassette2";
            IDebugTarget target = pet ? PetDebugTarget.Launch(new() { [device] = path }) : Vic20DebugTarget.Launch([]);
            CommodoreDatasette deck = target.Devices.OfType<CommodoreDatasette>().Single(candidate => candidate.Id == device);
            if (!pet) { target.DeviceAction(deck, "insert", new() { ["path"] = path }); }

            deck.Info.Formats.Should().Contain("t64");
            deck.Info.SaveFormats.Should().Equal("tap", "wav");
            deck.Mode.Should().Be(TapeMode.Playing);
            deck.Media.Should().Be(new MediaState(path, "T64", WriteProtected: false, Changed: false));
            JsonObject configuration = MachineConfiguration.Capture(target);
            target.DeviceAction(deck, "eject", []);
            MachineConfiguration.Restore(target, configuration).Should().BeEmpty();
            deck.Media.Should().Be(new MediaState(path, "T64", WriteProtected: false, Changed: false));
            deck.Mode.Should().Be(TapeMode.Playing);

            CommodoreTape tape = deck.Tape ?? throw new InvalidOperationException("The T64 did not mount.");
            Action replace = () => target.DeviceAction(deck, "insert", new() { ["path"] = malformed });
            replace.Should().Throw<InvalidDataException>().WithMessage("*complete T64 header*");

            JsonObject mount = configuration.Object("media")?.Object(device)
                ?? throw new InvalidOperationException("The cassette mount was not captured.");

            mount["path"] = malformed;
            MachineConfiguration.Restore(target, configuration).Should().ContainSingle(problem =>
                problem.Contains("complete T64 header", StringComparison.Ordinal));

            deck.Tape.Should().BeSameAs(tape);

            if (target is PetDebugTarget petTarget)
            {
                PetMachine machine = petTarget.Machine;
                PetMachineTests.RunToReady(machine);
                PetMachineTests.Type(machine, "LOAD \"FIRST\",2\r");
                PetTapeTests.WaitForReady(machine);
                machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == "FOUND FIRST");

                PetMachineTests.Type(machine, "LOAD \"SECOND\",2\r");
                PetTapeTests.WaitForReady(machine);
                machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == "FOUND SECOND");
            }
            else if (target is Vic20DebugTarget vicTarget)
            {
                Vic20Machine machine = vicTarget.Machine;
                Vic20MachineTests.RunToReady(machine);
                Vic20MachineTests.Type(machine, "LOAD \"FIRST\"\r");
                Vic20TapeTests.WaitForReady(machine);
                machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == "FOUND FIRST");

                Vic20MachineTests.Type(machine, "LOAD \"SECOND\"\r");
                Vic20TapeTests.WaitForReady(machine);
                machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == "FOUND SECOND");
            }

            int address = (page << 8) | 1;
            byte[] program = Program((byte)page);
            Enumerable.Range(address, program.Length).Select(at => target.Peek((ushort)at)).Should().Equal(program);

            tape.Record(tape.Pulses.Count, 352);
            JsonObject? Act(string action, JsonObject args) =>
                MediaActions.Device(deck, action, args, (what, with) => target.DeviceAction(deck, what, with));

            Act("eject", new() { ["supportsRetrocoreMedia"] = true }).String("outcome").Should().Be("changed");
            deck.Tape.Should().BeSameAs(tape);
            JsonObject? discarded = Act("eject", new() { ["discard"] = true });
            discarded.String("outcome").Should().Be("discarded");
            deck.Tape.Should().BeNull();
            Act("undo", new() { ["medium"] = discarded.String("undo") }).String("outcome").Should().Be("undone");
            deck.Tape.Should().BeSameAs(tape);

            MediaActions.Save(deck, []).String("outcome").Should().Be("readOnly");
            MediaActions.Save(deck, new() { ["path"] = saved }).String("outcome").Should().Be("saved");
            TapFormat.Read(File.ReadAllBytes(saved)).Pulses.Should().Equal(tape.Pulses);
            File.ReadAllBytes(path).Should().Equal(image);

            configuration = MachineConfiguration.Capture(target);
            target.DeviceAction(deck, "eject", []);
            MachineConfiguration.Restore(target, configuration).Should().BeEmpty();
            deck.Media.Should().Be(new MediaState(saved, "TAP", WriteProtected: false, Changed: false));
            deck.Tape?.Pulses.Should().Equal(tape.Pulses);
        }
        finally
        {
            File.Delete(saved);
            File.Delete(malformed);
            File.Delete(path);
            Directory.Delete(work);
        }
    }

    /// <summary>
    ///  The independently produced VICE autostart tapes load through the original kernals to the bytes in the
    ///  corresponding PRGs. The external files are not redistributed with the tests.
    /// </summary>
    /// <param name="machineId">The machine and fixture name.</param>
    [TestMethod]
    [DataRow("pet")]
    [DataRow("vic20")]
    public void ViceAutostartTapeLoads(string machineId)
    {
        string? folder = Environment.GetEnvironmentVariable("RETROCORE_VICE_T64");
        string fixture = Path.Join(folder, $"autostart-{machineId}-none");
        if (string.IsNullOrEmpty(folder) || !File.Exists(fixture + ".t64") || !File.Exists(fixture + ".prg"))
        {
            Assert.Inconclusive("Set RETROCORE_VICE_T64 to a folder containing VICE's PET and VIC-20 autostart T64 and PRG files.");
        }

        string path = fixture + ".t64";
        byte[] prg = File.ReadAllBytes(fixture + ".prg");
        IDebugTarget target;
        if (machineId == "pet")
        {
            PetDebugTarget pet = PetDebugTarget.Launch(new() { ["cassette1"] = path });
            target = pet;
            PetMachineTests.RunToReady(pet.Machine);
            PetMachineTests.Type(pet.Machine, "LOAD\r");
            PetTapeTests.WaitForReady(pet.Machine);
            pet.Machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == "FOUND AUTOSTART-PET-NO");
        }
        else
        {
            Vic20DebugTarget vic = Vic20DebugTarget.Launch(new() { ["cassette"] = path, ["ramExpansion"] = "8k" });
            target = vic;
            Vic20MachineTests.RunToReady(vic.Machine);
            Vic20MachineTests.Type(vic.Machine, "LOAD\r");
            Vic20TapeTests.WaitForReady(vic.Machine);
            vic.Machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == "FOUND AUTOSTART-VIC20-");
        }

        int address = BinaryPrimitives.ReadUInt16LittleEndian(prg);
        Enumerable.Range(address, prg.Length - 2).Select(at => target.Peek((ushort)at)).Should().Equal(prg[2..]);
    }

    private static byte[] Program(byte page) => [0x0B, page, 0x0A, 0, 0x99, 0x22, 0x48, 0x49, 0x22, 0, 0, 0];

    /// <summary>
    ///  Creates a two-program T64 fixture with directory order different from payload order.
    /// </summary>
    /// <param name="page">The high byte of BASIC's load address.</param>
    /// <returns>The T64 image bytes.</returns>
    internal static byte[] TapeImage(byte page)
    {
        byte[] image = new byte[0xB0];
        "C64S tape image file"u8.CopyTo(image);
        // Three directory slots, with a hole between the two files. SECOND's payload is stored first.
        ReadOnlySpan<byte> directory = [0x01, 0x01, 3, 0, 2, 0];
        directory.CopyTo(image.AsSpan(0x20));
        ReadOnlySpan<byte> first = [1, 0x82, 1, page, 3, page, 0, 0, 0xAC, 0, 0, 0];
        first.CopyTo(image.AsSpan(0x40));
        "FIRST           "u8.CopyTo(image.AsSpan(0x50));
        ReadOnlySpan<byte> second = [1, 1, 1, page, 0x0D, page, 0, 0, 0xA0, 0, 0, 0];
        second.CopyTo(image.AsSpan(0x80));
        "SECOND          "u8.CopyTo(image.AsSpan(0x90));
        Program(page).CopyTo(image.AsSpan(0xA0));
        image[0xAE] = 0xFF;
        image[0xAF] = 0xFF;
        return image;
    }
}
