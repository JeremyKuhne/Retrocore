// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the debug host's command-line tools for agents and people: reading a DOS disk's files, and
///  disassembling a program with the machine's names from the SDK sources.
/// </summary>
[TestClass]
public sealed class DisassembleCommandTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    // A program that clears the screen, prints from a table until a zero, and returns:
    //   $0800 JSR HOME; LDX #0; loop: LDA $0810,X; BEQ done; JSR COUT; INX; BNE loop; done: RTS; table "HI", 0
    private static readonly byte[] s_program =
    [
        0x20, 0x58, 0xFC, 0xA2, 0x00, 0xBD, 0x10, 0x08, 0xF0, 0x06, 0x20, 0xED, 0xFD, 0xE8, 0xD0, 0xF5,
        0xC8, 0xC9, 0x00
    ];

    /// <summary>
    ///  A disk's files read back as they were written, from DOS order and ProDOS order, with a binary file's
    ///  address and length and a program's length taken apart.
    /// </summary>
    [TestMethod]
    public void DiskFilesReadBack()
    {
        byte[] dos = new byte[DosDisk.DosTrackCount * 16 * DosDisk.SectorSize];
        DosFile binary = DosFile.Binary("PRINT HI", 0x0800, s_program);
        DosFile program = DosFile.AppleSoft("HELLO", [0x00, 0x00]);
        byte[] disk = DosDisk.Create(dos, [binary, program with { Locked = true }]);

        IReadOnlyList<DosFile> files = DosDisk.ReadFiles(disk);
        files.Select(file => file.Name).Should().Equal("PRINT HI", "HELLO");
        files[1].Locked.Should().BeTrue();
        files[0].TryGetBinary(out int address, out ReadOnlyMemory<byte> data).Should().BeTrue();
        address.Should().Be(0x0800);
        data.ToArray().Should().Equal(s_program);
        files[1].TryGetProgram(out ReadOnlyMemory<byte> basic).Should().BeTrue();
        basic.ToArray().Should().Equal([0x00, 0x00]);
        files[1].TryGetBinary(out _, out _).Should().BeFalse("it is not a binary file");

        DosDisk.ReadFiles(ProDosOrder(disk), proDosOrder: true).Select(file => file.Name).Should().Equal("PRINT HI", "HELLO");
    }

    /// <summary>
    ///  The disassembly names the Monitor's routines, keeps the hints' names, comments and data, and assembles back
    ///  to the program's bytes.
    /// </summary>
    [TestMethod]
    public void DisassemblyNamesTheMachineAndReassembles()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-disassemble-").FullName;
        try
        {
            string input = Path.Join(directory, "print.bin");
            string hints = Path.Join(directory, "hints.json");
            string output = Path.Join(directory, "print.asm");
            File.WriteAllBytes(input, s_program);
            File.WriteAllText(hints, """
                {
                  "names": { "$0805": "PrintLoop", "$0810": "Message" },
                  "comments": { "$0800": "Prints the message." },
                  "data": [{ "start": "$0810", "end": "$0812" }]
                }
                """);

            DisassembleCommand.Run([input, output, "--origin", "$0800", "--hints", hints, "--sdk-roms", s_inputs]).Should().Be(0);
            string source = File.ReadAllText(output);
            source.Should().Contain("; From Monitor.asm.").And.Contain("HOME = $FC58").And.Contain("COUT = $FDED");
            source.Should().Contain("JSR HOME").And.Contain("JSR COUT").And.Contain("PrintLoop:").And.Contain("LDA Message,X");
            source.Should().Contain("; Prints the message.");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  With the 1980 System Master, MASTER CREATE comes straight off the disk, names DOS's and the Monitor's
    ///  addresses, and assembles back to the same bytes.
    /// </summary>
    [TestMethod]
    public void MasterCreateDisassemblesFromTheSystemMaster()
    {
        string disk = Path.Join(ExternalTestData.Root, "iie-disks", "DOS 3.3 System Master - 680-0051-01 (1980).dsk");
        if (!File.Exists(disk)) { Assert.Inconclusive($"The DOS 3.3 System Master ({disk}) is missing."); }

        string directory = Directory.CreateTempSubdirectory("retrocore-disassemble-").FullName;
        try
        {
            string output = Path.Join(directory, "MasterCreate.asm");
            string[] args = ["--disk", disk, "--file", "MASTER CREATE", output, "--dos", "3.3-1980", "--sdk-roms", s_inputs];
            DisassembleCommand.Run(args).Should().Be(0);
            File.ReadAllText(output).Should().Contain("JSR GETLN").And.Contain("STA PWREDUP");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    // The same disk with each track's sectors in ProDOS's order.
    private static byte[] ProDosOrder(byte[] disk)
    {
        byte[] reordered = new byte[disk.Length];
        for (int track = 0; track < DosDisk.TrackCount; track++)
        {
            for (int physical = 0; physical < 16; physical++)
            {
                int dos = physical == 15 ? 15 : physical * 7 % 15;
                int proDos = physical == 15 ? 15 : physical * 8 % 15;
                disk.AsSpan(((track * 16) + dos) * DosDisk.SectorSize, DosDisk.SectorSize)
                    .CopyTo(reordered.AsSpan(((track * 16) + proDos) * DosDisk.SectorSize));
            }
        }

        return reordered;
    }
}
