// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;

namespace Retrocore.Tests;

public sealed partial class DebugModuleTests
{
    /// <summary>
    ///  Memory that does not change while it is read, as a Retrocore Memory listing's, keeps whether a statement
    ///  holds, so finding the position at each byte of a long data statement compares its bytes once, not at each.
    /// </summary>
    [TestMethod]
    public void StableMemoryChecksAStatementOnce()
    {
        const int Length = 200;
        AssemblyResult result = Assemble(
            ".cpu Mos6502\nTABLE:\n    .byte " + string.Join(", ", Enumerable.Range(0, Length).Select(index => $"${index:X2}")));

        SourceMapModule module = new(result, area: null);
        DebugTestMemory changing = new();
        changing.Set(0x6000, [.. result.Sections[0].Bytes.Span]);
        DebugTestMemory stable = new(stable: true);
        stable.Set(0x6000, [.. result.Sections[0].Bytes.Span]);
        for (int offset = 0; offset < Length; offset++)
        {
            module.Position(changing, (ushort)(0x6000 + offset)).Should().NotBeNull();
            module.Position(stable, (ushort)(0x6000 + offset)).Should().NotBeNull();
        }

        changing.Reads.Should().Be(Length * Length, "memory that can change is compared again at each byte");
        stable.Reads.Should().Be(Length, "stable memory compares the statement once");
    }
}
