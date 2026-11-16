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
            DisassemblyProgram program = new(new byte[16], 0x0800, "test", ProcessorVariant.Mos6502, DisassemblyHints.Read(path));
            AnalysisProject project = program.Project(new Dictionary<ushort, string>());
            AnalysisRegion region = project.Regions.Should().ContainSingle().Which;
            (region.Address, region.Length, region.Kind).Should().Be(((ushort)0x0800, 2, AnalysisRegionKind.Data));
            project.EntryPoints.Should().Equal((ushort)0x0802);
            project.Comments.Keys.Should().Equal((ushort)0x0803);
            Disassembler.Analyze(project).Diagnostics.Should().NotContain(diagnostic => diagnostic.IsError);
        }
        finally
        {
            File.Delete(path);
        }
    }
}
