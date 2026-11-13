// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Cpu.M6809;
using Retrocore.Cpu.Z80;
using Retrocore.Isa;
using Retrocore.Machines.Apple2;
using System.Runtime.CompilerServices;

namespace Retrocore.Tests;

/// <summary>
///  Guards compact enum storage and the dense payloads that embed those enums.
/// </summary>
[TestClass]
public class EnumStorageTests
{
    /// <summary>
    ///  Checks control-state enums do not silently become four-byte fields or array elements.
    /// </summary>
    [TestMethod]
    public void SmallControlEnumsAreByteBacked()
    {
        AssertByteEnum<AnalysisRegionKind>();
        AssertByteEnum<AssemblyStatementKind>();
        AssertByteEnum<DisassemblyFlow>();
        AssertByteEnum<DisassemblyMode>();
        AssertByteEnum<DisassemblyReferenceKind>();
        AssertByteEnum<AddressMode>();
        AssertByteEnum<Instruction>();
        AssertByteEnum<StatusRegister>();
        AssertByteEnum<BusOperation>();
        AssertByteEnum<ProcessorExecutionStatus>();
        AssertByteEnum<ProcessorSequence>();
        AssertByteEnum<ProcessorSignals>();
        AssertByteEnum<ProcessorVariant>();
        AssertByteEnum<OperandFieldKind>();
        AssertByteEnum<M6809OffsetWidth>();
        AssertByteEnum<M6809IndexedKind>();
        AssertByteEnum<M6809ConditionCode>();
        AssertByteEnum<M6809Signals>();
        AssertByteEnum<M6809Sequence>();
        AssertByteEnum<M6809AddressPhase>();
        AssertByteEnum<M6809WaitState>();
        AssertByteEnum<M6809Operation>();
        AssertByteEnum<Z80Signals>();
        AssertByteEnum<Z80MachineCycle>();
        AssertByteEnum<Z80OpcodeGroup>();
        AssertByteEnum<Z80Operation>();
        AssertByteEnum<Apple2Model>();
        AssertByteEnum<P6PromLayout>();
    }

    /// <summary>
    ///  Checks the IIe switch flags retain the bits that do not fit in a byte.
    /// </summary>
    [TestMethod]
    public void WiderSwitchFlagsRemainWordBacked()
    {
        Enum.GetUnderlyingType(typeof(Apple2Switches)).Should().Be(typeof(ushort));
        Unsafe.SizeOf<Apple2Switches>().Should().Be(sizeof(ushort));
        ushort combined = (ushort)(Apple2Switches.DoubleHiRes | Apple2Switches.InternalCxRom | Apple2Switches.AltZeroPage);
        ((Apple2Switches)combined).Should().HaveFlag(Apple2Switches.DoubleHiRes);
        ((Apple2Switches)combined).Should().HaveFlag(Apple2Switches.InternalCxRom);
        ((Apple2Switches)combined).Should().HaveFlag(Apple2Switches.AltZeroPage);
    }

    /// <summary>
    ///  Checks enum widths remain effective after struct alignment in high-density arrays.
    /// </summary>
    [TestMethod]
    public void DensePayloadsDoNotRegressTheirStorageSize()
    {
        Unsafe.SizeOf<OpCode>().Should().Be(3 * sizeof(byte));
        Unsafe.SizeOf<DisassemblyReference>().Should().Be(3 * sizeof(ushort));
        Unsafe.SizeOf<DisassembledInstruction>().Should().BeLessThanOrEqualTo(3 * sizeof(uint));
        Unsafe.SizeOf<ProcessorCycle>().Should().BeLessThanOrEqualTo(2 * sizeof(ulong));
    }

    /// <summary>
    ///  Verifies the declared storage type as well as the managed size of an enum.
    /// </summary>
    /// <typeparam name="TEnum">The control-state enum.</typeparam>
    private static void AssertByteEnum<TEnum>() where TEnum : unmanaged, Enum
    {
        Enum.GetUnderlyingType(typeof(TEnum)).Should().Be(typeof(byte));
        Unsafe.SizeOf<TEnum>().Should().Be(sizeof(byte));
    }
}
