// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;

namespace Retrocore.Tests;

/// <summary>
///  Retrocore Memory's marks, kept in the disassembler's hints file.
/// </summary>
[TestClass]
public sealed class MemoryHintsTests
{
    /// <summary>
    ///  A mark keeps what else the file held, a bank's marks keep its name, and the disassembler, which reads one
    ///  image, leaves the bank's out.
    /// </summary>
    [TestMethod]
    public void MarksKeepTheFileAndTheDisassemblerSkipsBanks()
    {
        string path = Path.Join(Path.GetTempPath(), $"{Guid.NewGuid():N}.hints.json");
        File.WriteAllText(path, """{ "noReturn": ["$0900"], "names": { "$0812": "ReadImage" } }""");
        try
        {
            MemoryHints hints = MemoryHints.Read(path);
            hints.Name("aux", 0x0400, "AuxText");
            hints.Mark("", 0x0F00, 16, "data", _ => 1);
            hints.Mark("", 0x0F08, 1, "code", _ => 2);
            hints.Write(path);

            string text = File.ReadAllText(path);
            text.Should().Contain("noReturn").And.Contain("\"aux:$0400\": \"AuxText\"");
            MemoryHints.Read(path).Data("").Should().Equal((0x0F00, 8), (0x0F0A, 6));

            DisassemblyHints disassembly = DisassemblyHints.Read(path);
            disassembly.Names.Should().ContainSingle().Which.Should().Be(new KeyValuePair<ushort, string>(0x0812, "ReadImage"));
            disassembly.Entries.Should().Equal((ushort)0x0F08);
            disassembly.Calls.Should().ContainKey(0x0900);
        }
        finally
        {
            File.Delete(path);
        }
    }

    /// <summary>
    ///  Code marked takes its whole instruction out of data, and data marked takes out code whose instruction runs
    ///  into it.
    /// </summary>
    [TestMethod]
    public void MarksReconcileWholeInstructions()
    {
        MemoryHints hints = MemoryHints.Empty;
        hints.Mark("", 0x6500, 8, "data", _ => 1);
        hints.Mark("", 0x6502, 1, "code", _ => 3);
        hints.Data("").Should().Equal((0x6500, 2), (0x6505, 3));
        hints.Code("").Should().Equal(0x6502);

        hints.Mark("", 0x6503, 1, "data", _ => 3);
        hints.Code("").Should().BeEmpty();
        hints.Data("").Should().Equal((0x6500, 2), (0x6503, 1), (0x6505, 3));
    }

    /// <summary>
    ///  A name must be one the disassembler takes, and only one address in a space has it.
    /// </summary>
    [TestMethod]
    public void NamesAreTheDisassemblersIdentifiers()
    {
        MemoryHints hints = MemoryHints.Empty;
        hints.Name("", 0x6500, "MYTABLE");
        Action spaced = () => hints.Name("", 0x6600, "my table");
        spaced.Should().Throw<ArgumentException>();
        Action twice = () => hints.Name("", 0x6600, "MYTABLE");
        twice.Should().Throw<ArgumentException>().WithMessage("*$6500*");
        hints.Name("aux", 0x6600, "MYTABLE");
        hints.Name("", 0x6500, "MYTABLE");
        hints.Names("").Should().ContainSingle();
    }

    /// <summary>
    ///  The disassembler takes only the hints in its image, and an origin marked as data is no entry point.
    /// </summary>
    [TestMethod]
    public void TheDisassemblerTakesTheImagesHints()
    {
        string path = Path.Join(Path.GetTempPath(), $"{Guid.NewGuid():N}.hints.json");
        string entries = """ "entries": ["$0802", "$FDED"] """;
        string data = """ "data": [{ "start": "$07F0", "length": 18 }, { "start": "$C000", "length": 4 }] """;
        string comments = """ "comments": { "$0803": "Here", "$FDED": "COUT" } """;
        File.WriteAllText(path, "{" + entries + "," + data + "," + comments + "}");
        try
        {
            DisassemblyProgram program = new(new byte[16], 0x0800, "test", "Mos6502", DisassemblyHints.Read(path));
            AnalysisProject project = program.Project(new Dictionary<ushort, string>());
            AnalysisRegion region = project.Regions.Where(region => region.Kind == AnalysisRegionKind.Data).Should().ContainSingle().Which;
            (region.Address, region.Length, region.Kind).Should().Be(((ushort)0x0800, 2, AnalysisRegionKind.Data));
            project.EntryPoints.Should().StartWith((ushort)0x0802);
            project.Comments.Keys.Should().Equal((ushort)0x0803);
            Disassembler.Analyze(project).Diagnostics.Should().NotContain(diagnostic => diagnostic.IsError);
        }
        finally
        {
            File.Delete(path);
        }
    }

    /// <summary>
    ///  A file whose parts are not the shapes the disassembler takes is refused rather than read as empty, and a
    ///  write leaves no temporary file behind.
    /// </summary>
    [TestMethod]
    public void MalformedFilesAreRefused()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-hints-").FullName;
        string path = Path.Join(directory, "bad.hints.json");
        try
        {
            foreach (string text in (string[])["""{ "entries": { "$0800": true } }""", """{ "data": [1] }""", """{ "names": { "$0800": 1 } }"""])
            {
                File.WriteAllText(path, text);
                Action read = () => MemoryHints.Read(path);
                read.Should().Throw<InvalidDataException>(text);
            }

            MemoryHints hints = MemoryHints.Empty;
            hints.Name("", 0x0800, "Start");
            hints.Write(path);
            Directory.GetFiles(directory).Should().Equal(path);
            MemoryHints.Read(path).Names("").Should().ContainKey(0x0800);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  Code marked at a CPU vector's bytes disassembles as the instruction, not the vector.
    /// </summary>
    [TestMethod]
    public void CodeMarksWinOverVectors()
    {
        string path = Path.Join(Path.GetTempPath(), $"{Guid.NewGuid():N}.hints.json");
        File.WriteAllText(path, """{ "entries": ["$FFFA"] }""");
        try
        {
            byte[] image = new byte[6];
            image[0] = 0xEA;
            image[1] = 0xEA;
            DisassemblyProgram program = new(image, 0xFFFA, "test", "Mos6502", DisassemblyHints.Read(path));
            DisassemblyResult result = Disassembler.Analyze(program.Project(new Dictionary<ushort, string>()));
            result.Diagnostics.Should().NotContain(diagnostic => diagnostic.IsError);
            result.Instructions.Select(instruction => (int)instruction.Address).Should().Contain([0xFFFA, 0xFFFB]);
        }
        finally
        {
            File.Delete(path);
        }
    }

    /// <summary>
    ///  Banks are named without regard to case.
    /// </summary>
    [TestMethod]
    public void SpacesIgnoreCase()
    {
        MemoryHints hints = MemoryHints.Empty;
        hints.Name("AUX", 0x0400, "AuxText");
        hints.Names("aux").Should().ContainKey(0x0400);
    }

    /// <summary>
    ///  Analysis goes on after a marked call as its subroutine's hint says: past inline bytes, or not at all.
    /// </summary>
    [TestMethod]
    public void MarkedCallsFollowCallHints()
    {
        string path = Path.Join(Path.GetTempPath(), $"{Guid.NewGuid():N}.hints.json");
        File.WriteAllText(path, """{ "entries": ["$0801", "$0806"], "inline": { "$0900": 1 }, "noReturn": ["$0A00"] }""");
        try
        {
            // $0800 BRK, $0801 JSR $0900 .byte 1, $0805 NOP, $0806 JSR $0A00, $0809 .byte $FF
            byte[] image = [0x00, 0x20, 0x00, 0x09, 0x01, 0xEA, 0x20, 0x00, 0x0A, 0xFF];
            DisassemblyProgram program = new(image, 0x0800, "test", "Mos6502", DisassemblyHints.Read(path));
            AnalysisProject project = program.Project(new Dictionary<ushort, string>());
            project.EntryPoints.Should().Contain((ushort)0x0805).And.NotContain((ushort)0x0804).And.NotContain((ushort)0x0809);
        }
        finally
        {
            File.Delete(path);
        }
    }
}
