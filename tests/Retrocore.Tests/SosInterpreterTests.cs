// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Machines.Apple3;
using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  Verifies SOS.INTERP files and the boot disks built from the SDK's sources around one: the file reads back, Apple's
///  interpreters read, and under emulation a disk with a small interpreter boots SOS 1.3 and runs it.
/// </summary>
/// <remarks>
///  <para>
///   The emulation test needs the Apple III's boot ROM dump (<c>RETROCORE_APPLE3_ROMS</c>), and the tests that read
///   Apple's interpreters need its disks (<c>RETROCORE_APPLE3_DISKS</c>); each is inconclusive without them.
///  </para>
/// </remarks>
[TestClass]
public sealed class SosInterpreterTests
{
    // Where the test interpreter runs: the bottom of the system bank, as the SDK's sos environment places a program.
    private const int LoadAddress = 0x2000;

    // A program that opens .CONSOLE, writes a line to it and waits, through SOS calls: BRK, the call number and the
    // address of its parameters.
    private const string Program = """
        .cpu Mos6502

        OPEN = $C8
        WRITE = $CB

        Start:
            brk
            .byte OPEN
            .word OpenParameters
            bne Stop
            lda OpenReference
            sta WriteReference
            brk
            .byte WRITE
            .word WriteParameters
        Stop:
            jmp Stop

        OpenParameters:
            .byte 4
            .word Console
        OpenReference:
            .byte 0
            .word 0
            .byte 0

        Console:
            .byte ConsoleEnd - Console - 1
            .byte ".CONSOLE"
        ConsoleEnd:

        WriteParameters:
            .byte 3
        WriteReference:
            .byte 0
            .word Text
            .word TextEnd - Text

        Text:
            .byte "HELLO FROM THE SDK'S SOS"
        TextEnd:
        """;

    /// <summary>
    ///  A written interpreter reads back: its address, code and header.
    /// </summary>
    [TestMethod]
    public void WrittenInterpreterReadsBack()
    {
        byte[] code = [0xA9, 0x01, 0x60];
        byte[] file = SosInterpreterFile.Write(0x5200, code);
        file.Should().Equal([.. "SOS NTRP"u8, 0, 0, 0x00, 0x52, 3, 0, .. code]);

        SosInterpreterFile read = SosInterpreterFile.Read(file);
        (read.LoadAddress, read.Code, read.Header).Should().BeEquivalentTo((0x5200, code, Array.Empty<byte>()));

        SosInterpreterFile headed = SosInterpreterFile.Read(SosInterpreterFile.Write(0xA000, code, [1, 2]));
        headed.Header.Should().Equal(1, 2);
        headed.LoadAddress.Should().Be(0xA000);
        headed.Code.Should().Equal(code);
    }

    /// <summary>
    ///  The writer refuses code that is empty, starts below <c>$2000</c> or runs past the kernel at <c>$B800</c>; code
    ///  that ends at the kernel fits. The reader refuses another file's label, and a file cut short in its header or
    ///  code.
    /// </summary>
    [TestMethod]
    public void WriterRefusesWhatDoesNotFit()
    {
        Action empty = () => SosInterpreterFile.Write(0x2000, []);
        empty.Should().Throw<ArgumentException>().WithParameterName("code");
        Action low = () => SosInterpreterFile.Write(0x1FFF, [0x60]);
        low.Should().Throw<ArgumentOutOfRangeException>();
        Action high = () => SosInterpreterFile.Write(0xB800 - 2, [0x60, 0x60, 0x60]);
        high.Should().Throw<ArgumentOutOfRangeException>();
        SosInterpreterFile.Read(SosInterpreterFile.Write(0xB800 - 3, [0x60, 0x60, 0x60])).Code.Should().HaveCount(3);

        Action label = () => SosInterpreterFile.Read("SOS DRVR\0\0"u8);
        label.Should().Throw<InvalidDataException>();
        Action cut = () => SosInterpreterFile.Read([.. "SOS NTRP"u8, 0, 0, 0x00, 0x20, 9, 0, 0x60]);
        cut.Should().Throw<InvalidDataException>();
        Action cutHeader = () => SosInterpreterFile.Read([.. "SOS NTRP"u8, 4, 0, 1, 2, 3]);
        cutHeader.Should().Throw<InvalidDataException>();
    }

    /// <summary>
    ///  With Apple's disks, their interpreters read: Business BASIC 1.23 at <c>$5200</c> and the System Utilities at
    ///  <c>$830E</c>, each with no header, and the reader takes only the code its length counts.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <param name="address">The interpreter's load address.</param>
    /// <param name="length">Its code's length.</param>
    [TestMethod]
    [DataRow("Apple3BusBasic1.23.dsk", 0x5200, 0x6548)]
    [DataRow("Apple3SOS1.3SysUtils.dsk", 0x830E, 0x3422)]
    public void ApplesInterpretersRead(string disk, int address, int length)
    {
        byte[] data = SosVolumeTests.Volume(disk).ReadFile("SOS.INTERP");
        SosInterpreterFile file = SosInterpreterFile.Read(data);
        file.LoadAddress.Should().Be(address);
        file.Code.Should().HaveCount(length);
        file.Header.Should().BeEmpty();
        SosInterpreterFile.Write(file.LoadAddress, file.Code).Should().Equal(data[..(14 + length)]);
    }

    /// <summary>
    ///  A boot disk built from the SDK's sources reads back: block 0 is the loader, and SOS.KERNEL, SOS.DRIVER and
    ///  SOS.INTERP come first as system files, the driver file with the console alone, then the extra file.
    /// </summary>
    [TestMethod]
    public void BootDiskReadsBack()
    {
        byte[] code = AssembleProgram();
        SosVolumeBuilder builder = Apple3SdkModules.BuildSosBootDisk(SosBootDiskTests.SdkDirectory, "HELLO", LoadAddress, code);
        builder.Add("DATA", 0x06, 0, "data"u8);
        SosVolume volume = SosVolume.Read(builder.Build(proDosOrder: false), proDosOrder: false);

        volume.Name.Should().Be("HELLO");
        volume.Block(0).Should().Equal(Apple3SdkModules.BuildSosBoot(SosBootDiskTests.SdkDirectory));
        (string, int)[] files = [("SOS.KERNEL", 0x0C), ("SOS.DRIVER", 0x0C), ("SOS.INTERP", 0x0C), ("DATA", 0x06)];
        volume.Files.Select(file => (file.Name, file.FileType)).Should().Equal(files);
        volume.ReadFile("SOS.KERNEL").Should().Equal(Apple3SdkModules.BuildSosKernel(SosBootDiskTests.SdkDirectory));

        SosDriverFile drivers = SosDriverFile.Read(volume.ReadFile("SOS.DRIVER"));
        drivers.Drives.Should().Be(1);
        drivers.Drivers.Select(driver => driver.Name).Should().Equal(".CONSOLE");

        SosInterpreterFile interpreter = SosInterpreterFile.Read(volume.ReadFile("SOS.INTERP"));
        interpreter.LoadAddress.Should().Be(LoadAddress);
        interpreter.Code.Should().Equal(code);
        volume.ReadFile("DATA").Should().Equal("data"u8.ToArray());
    }

    /// <summary>
    ///  The boot disk takes the drive count and the drivers asked for, and refuses a file that lacks its label.
    /// </summary>
    [TestMethod]
    public void BootDiskTakesDrivesAndDrivers()
    {
        string[] folders = ["Console", "Printer"];
        SosVolumeBuilder builder = Apple3SdkModules.BuildSosBootDisk(SosBootDiskTests.SdkDirectory, "TWO", LoadAddress, [0x60], 2, folders);
        SosDriverFile drivers = SosDriverFile.Read(SosVolume.Read(builder.Build(proDosOrder: true), proDosOrder: true).ReadFile("SOS.DRIVER"));
        drivers.Drives.Should().Be(2);
        drivers.Drivers.Select(driver => driver.Name).Should().Equal(".CONSOLE", ".PRINTER");

        byte[] boot = Apple3SdkModules.BuildSosBoot(SosBootDiskTests.SdkDirectory);
        byte[] kernel = Apple3SdkModules.BuildSosKernel(SosBootDiskTests.SdkDirectory);
        byte[] interp = SosInterpreterFile.Write(LoadAddress, [0x60]);
        Action wrong = () => SosBootDisk.Create("BAD", boot, kernel, interp, interp);
        wrong.Should().Throw<ArgumentException>().WithParameterName("drivers");
    }

    /// <summary>
    ///  Under emulation, the boot disk built from the SDK's sources boots SOS 1.3, which loads the console driver and
    ///  starts the interpreter, and the interpreter's line appears on the console.
    /// </summary>
    [TestMethod]
    public void BootDiskBootsAndRunsTheInterpreter()
    {
        Apple3Machine machine = Apple3MachineTests.Machine();
        SosVolumeBuilder builder = Apple3SdkModules.BuildSosBootDisk(SosBootDiskTests.SdkDirectory, "HELLO", LoadAddress, AssembleProgram());
        byte[] image = builder.Build(proDosOrder: false);
        machine.Drives[0].Insert(SectorDiskConverter.Convert(image, proDosOrder: false), "sdk", "DSK");
        SosBootDiskTests.RunUntil(machine, "HELLO FROM THE SDK'S SOS", seconds: 60);
    }

    private static byte[] AssembleProgram()
    {
        AssemblyOptions options = new(ProcessorVariant.Mos6502, LoadAddress, 0x100);
        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource(Program, "Hello.asm"), options);
        result.Diagnostics.Should().BeEmpty();
        int end = result.SourceMap.Max(entry => entry.Offset + entry.Size);
        return result.Sections[0].Bytes[..end].ToArray();
    }
}
