// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

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
            hints.Mark("", 0x0F00, 16, "data");
            hints.Mark("", 0x0F08, 2, "code");
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
}
