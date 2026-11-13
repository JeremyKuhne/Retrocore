// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Security.Cryptography;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the packed opcode layout and exact equivalence to the original symbolic maps.
/// </summary>
[TestClass]
public class OpcodeTableTests
{
    /// <summary>
    ///  Verifies each table contains the same 256 entries without allocating on access.
    /// </summary>
    /// <param name="variant">The CPU variant.</param>
    /// <param name="expectedHash">The original map's packed-byte SHA256 digest.</param>
    [TestMethod]
    [DataRow(ProcessorVariant.Mos6502, "1BB8CE9FFC7FAA4978A0145CFE45AD128E87FD08E5AC859DBA991DDA4DB31C84")]
    [DataRow(ProcessorVariant.Wdc65C02, "881FC5B29DD6E02FE0A977EB5DD77A0EBC11FD04DB14FC8865EB974267DABBEA")]
    [DataRow(ProcessorVariant.Rockwell65C02, "757C8CF8F61EF1608F287360FE8FA8BB69CFB24849FD2A909C47F3EFDF1D41A4")]
    public void PackedMapsMatchOriginalWithoutAllocation(ProcessorVariant variant, string expectedHash)
    {
        // The measured read is copied out and checked, so optimized code cannot drop it; it runs once first, so
        // what its first use loads is not counted.
        OpCode[] copy = new OpCode[256];
        int length = 0;
        void Read()
        {
            ReadOnlySpan<OpCode> measured = OpcodeTable.Get(variant);
            length = measured.Length;
            measured.TryCopyTo(copy);
        }

        Read();
        Array.Clear(copy);
        Allocations.During(Read).Should().Be(0);
        length.Should().Be(256);
        ReadOnlySpan<OpCode> table = copy;
        for (int i = 0; i < table.Length; i++)
        {
            table[i].Code.Should().Be((byte)i);
        }

        Convert.ToHexString(SHA256.HashData(MemoryMarshal.AsBytes(table))).Should().Be(expectedHash);
    }

    /// <summary>
    ///  Verifies the cast representation has no padding or reordered fields.
    /// </summary>
    [TestMethod]
    public void OpCodeLayoutIsExactlyThreeBytes()
    {
        Unsafe.SizeOf<OpCode>().Should().Be(3);
        ReadOnlySpan<OpCode> entries =
        [
            new() { Code = 0xAB, AddressMode = AddressMode.ZeroPageRelative, Instruction = Instruction.LAS }
        ];

        MemoryMarshal.AsBytes(entries).ToArray().Should().Equal((byte)0xAB, (byte)0x10, (byte)0x58);
    }

    /// <summary>
    ///  Verifies no runtime table construction or static initialization remains.
    /// </summary>
    [TestMethod]
    public void TablesHaveNoTypeInitializer()
    {
        typeof(OpcodeTable).TypeInitializer.Should().BeNull();
        // Constants, such as the description text, are metadata and need no initialization.
        typeof(OpcodeTable).GetFields(System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.NonPublic)
            .Where(field => !field.IsLiteral).Should().BeEmpty();
    }

    /// <summary>
    ///  Verifies generator tooling does not become a runtime dependency of the CPU library.
    /// </summary>
    [TestMethod]
    public void GeneratorIsNotARuntimeDependency()
    {
        typeof(OpCode).Assembly.GetReferencedAssemblies().Where(reference =>
            reference.Name == "Retrocore.Generators"
                || (reference.Name is not null && reference.Name.StartsWith("Microsoft.CodeAnalysis", StringComparison.Ordinal)))
            .Should().BeEmpty();
    }
}
