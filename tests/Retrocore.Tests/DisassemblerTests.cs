// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Machines.Apple2;
using System.Buffers;
using System.Runtime.CompilerServices;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  Canonical metadata, complete encoding coverage, byte-exact export and editable analysis behavior.
/// </summary>
[TestClass]
public class DisassemblerTests
{
    /// <summary>
    ///  Checks address ordering and independent snapshots after repeated ownership-map reuse.
    /// </summary>
    [TestMethod]
    public void OwnershipReconstructionIsSortedAndDoesNotRetainScratchStorage()
    {
        AnalysisProject project = new(
            [0xEA, 0x60, 0xEA, 0x60, 0xEA, 0x60],
            origin: 0x2000,
            ProcessorVariant.Mos6502);

        project.EntryPoints.Clear();
        project.EntryPoints.Add(0x2002);
        project.EntryPoints.Add(0x2004);
        project.EntryPoints.Add(0x2000);
        DisassemblyResult original = Disassembler.Analyze(project);
        original.Instructions.Select(instruction => instruction.Address).Should()
            .Equal(0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005);

        for (int length = 17; length < 100; length++)
        {
            byte[] image = new byte[length];
            Array.Fill(image, InstructionEncoding.OfficialNop);
            DisassemblyResult current = Disassembler.Disassemble(image, origin: 0x4000, ProcessorVariant.Wdc65C02);
            current.Instructions.Count.Should().Be(length);
            current.Regions.Sum(region => region.Length).Should().Be(length);
        }

        original.Instructions[0].OpCode.Instruction.Should().Be(Instruction.NOP);
        original.Instructions[^1].OpCode.Instruction.Should().Be(Instruction.RTS);
        original.Regions.Sum(region => region.Length).Should().Be(project.Image.Length);
        AssertRoundTrip(original);
        project.EntryPoints.Clear();
        DisassemblyResult noEntries = Disassembler.Analyze(project);
        noEntries.Instructions.Should().BeEmpty();
        noEntries.Regions.Should().ContainSingle(region => region.Kind == AnalysisRegionKind.Unexplored);
    }

    /// <summary>
    ///  Checks cancellation after scratch allocation releases state and does not poison subsequent analyses.
    /// </summary>
    [TestMethod]
    public void CanceledAnalysisDoesNotLeakScratchState()
    {
        AnalysisProject project = new([0xEA, 0x60], origin: 0x2000, ProcessorVariant.Mos6502);
        using CancellationTokenSource cancellation = new();
        AnalysisEngine engine = new(project, cancellation.Token);
        cancellation.Cancel();
        Action analyze = () => engine.Run();
        analyze.Should().Throw<OperationCanceledException>();
        DisassemblyResult result = Disassembler.Analyze(project);
        result.Instructions.Count.Should().Be(2);
        AssertRoundTrip(result);
    }

    /// <summary>
    ///  Checks warmed full-image analysis allocates output plus compact flags, not another decoded list or owner map.
    /// </summary>
    [TestMethod]
    public void FullImageAnalysisAllocatesOnlyOutputAndCompactFlags()
    {
        const int FixedMetadataBudget = 4096;
        byte[] image = new byte[InstructionEncoding.AddressSpaceSize];
        Array.Fill(image, InstructionEncoding.OfficialNop);
        // Vectors would turn the final six bytes into data; this measures a full code decode.
        AnalysisProject project = new(image, origin: 0, ProcessorVariant.Mos6502) { FollowVectors = false };
        Disassembler.Analyze(project);
        DisassemblyResult? result = null;
        long allocated = Allocations.During(() => result = Disassembler.Analyze(project));
        result?.Instructions.Count.Should().Be(image.Length);
        // Output entries and two byte-wide flag arrays dominate; the allowance covers fixed result metadata.
        long budget = (long)image.Length * (Unsafe.SizeOf<DisassembledInstruction>() + (2 * sizeof(byte))) + FixedMetadataBudget;
        allocated.Should().BeLessThanOrEqualTo(budget);
    }

    /// <summary>
    ///  Checks interpolated builder appends retain exact native syntax, span comments and LF line endings.
    /// </summary>
    [TestMethod]
    public void NativeExportFormattingRemainsExact()
    {
        AnalysisProject project = new(
            [0xA9, 0x42, 0x8D, 0x00, 0xC0, 0x60, 0xAF, 0xF5],
            origin: 0x2000,
            ProcessorVariant.Mos6502);

        project.Symbols.Add(0x2000, "Entry");
        project.Symbols.Add(0xC000, "Keyboard");
        project.Comments.Add(0x2000, "Read key\r\nRetain notes");
        DisassemblyResult result = Disassembler.Analyze(project);
        string expected = """
            .cpu Mos6502
            Keyboard = $C000
            .org $2000
            ; Read key
            ; Retain notes
            Entry:
                LDA #$42
                STA Keyboard
                RTS
                .byte $AF, $F5
            """.ReplaceLineEndings("\n") + "\n";

        result.ExportSource().Should().Be(expected);
        AssertRoundTrip(result);
    }

    /// <summary>
    ///  Checks every explicit pin kind reserves its range, including the default-valued Unexplored kind.
    /// </summary>
    /// <param name="firstKind">The classification of the first reservation.</param>
    [TestMethod]
    [DataRow(AnalysisRegionKind.Unexplored)]
    [DataRow(AnalysisRegionKind.Code)]
    [DataRow(AnalysisRegionKind.Data)]
    public void ExplicitPinKindsAllDetectOverlappingReservations(AnalysisRegionKind firstKind)
    {
        AnalysisProject project = new([0xEA, 0xEA, 0xEA, 0xEA], origin: 0x2000, ProcessorVariant.Mos6502)
        {
            Mode = DisassemblyMode.Linear
        };

        project.Regions.Add(new(0x2000, length: 2, firstKind));
        project.Regions.Add(new(0x2001, length: 2, AnalysisRegionKind.Data));
        DisassemblyResult result = Disassembler.Analyze(project);
        result.Success.Should().BeFalse();
        result.Diagnostics.Should().Contain(diagnostic => diagnostic.Code == "RCDIS004" && diagnostic.IsError);
    }

    /// <summary>
    ///  Checks explicit Unexplored reserves a range without being mistaken for a data pin.
    /// </summary>
    [TestMethod]
    public void ExplicitUnexploredPinsStillAllowCodeDiscovery()
    {
        AnalysisProject project = new([0xEA, 0x60], origin: 0x2000, ProcessorVariant.Mos6502);
        project.Regions.Add(new(0x2000, length: 2, AnalysisRegionKind.Unexplored));
        DisassemblyResult result = Disassembler.Analyze(project);
        result.Success.Should().BeTrue();
        result.Instructions.Count.Should().Be(2);
        result.Regions.Should().ContainSingle(region => region.Kind == AnalysisRegionKind.Code);
        AssertRoundTrip(result);
    }

    /// <summary>
    ///  Checks every byte in every CPU table, including aliases and deliberately wide low-address operands.
    /// </summary>
    /// <param name="variant">The CPU encoding set.</param>
    [TestMethod]
    [DataRow(ProcessorVariant.Mos6502)]
    [DataRow(ProcessorVariant.Wdc65C02)]
    [DataRow(ProcessorVariant.Rockwell65C02)]
    public void EveryEncodingDecodesAndRoundTripsExactly(ProcessorVariant variant)
    {
        ReadOnlySpan<OpCode> table = OpcodeTable.Get(variant);
        int undocumented = 0;
        for (int code = 0; code < 256; code++)
        {
            OpCode expected = table[code];
            int size = expected.AddressMode switch
            {
                AddressMode.Accumulator or AddressMode.Implied or AddressMode.Stack => 1,
                AddressMode.Absolute
                    or AddressMode.AbsoluteIndexedIndirect
                    or AddressMode.AbsoluteIndexedX
                    or AddressMode.AbsoluteIndexedY
                    or AddressMode.AbsoluteIndirect
                    or AddressMode.ZeroPageRelative => 3,
                _ => 2
            };

            byte[] encoded = [(byte)code, 0x42, 0xA5];
            Disassembler.TryDecode(encoded, address: 0x3000, variant, out DisassembledInstruction decoded).Should().BeTrue();
            decoded.Size.Should().Be(size);
            decoded.OpCode.Code.Should().Be(expected.Code);
            decoded.OpCode.Instruction.Should().Be(expected.Instruction);
            decoded.OpCode.AddressMode.Should().Be(expected.AddressMode);
            decoded.Mnemonic.Should().NotBeNullOrEmpty();
            if (decoded.IsUndocumented) { undocumented++; }
            for (int index = 0; index < size; index++) { decoded.GetByte(index).Should().Be(encoded[index]); }
            AssertRoundTrip(Disassembler.Disassemble(encoded.AsSpan(0, size), origin: 0x3000, variant));
            encoded[1] = 1;
            encoded[2] = 0;
            AssertRoundTrip(Disassembler.Disassemble(encoded.AsSpan(0, size), origin: 0x3000, variant));
        }

        undocumented.Should().Be(variant == ProcessorVariant.Mos6502 ? 105 : 0);
    }

    /// <summary>
    ///  Checks exact syntax and signed displacement wrapping for representative modes and bit operations.
    /// </summary>
    /// <param name="variant">The CPU variant.</param>
    /// <param name="encoding">The opcode.</param>
    /// <param name="operandLow">The first operand byte.</param>
    /// <param name="operandHigh">The second operand byte.</param>
    /// <param name="address">The instruction address.</param>
    /// <param name="expected">The exact instruction text.</param>
    [TestMethod]
    [DataRow(ProcessorVariant.Mos6502, (byte)0xA9, (byte)0x42, (byte)0, (ushort)0x2000, "LDA #$42")]
    [DataRow(ProcessorVariant.Mos6502, (byte)0x6C, (byte)0x34, (byte)0x12, (ushort)0x2000, "JMP ($1234)")]
    [DataRow(ProcessorVariant.Mos6502, (byte)0xA1, (byte)0x42, (byte)0, (ushort)0x2000, "LDA ($42,X)")]
    [DataRow(ProcessorVariant.Mos6502, (byte)0xB1, (byte)0x42, (byte)0, (ushort)0x2000, "LDA ($42),Y")]
    [DataRow(ProcessorVariant.Mos6502, (byte)0xB9, (byte)0x34, (byte)0x12, (ushort)0x2000, "LDA $1234,Y")]
    [DataRow(ProcessorVariant.Mos6502, (byte)0x0A, (byte)0, (byte)0, (ushort)0x2000, "ASL A")]
    [DataRow(ProcessorVariant.Mos6502, (byte)0xD0, (byte)0, (byte)0, (ushort)0xFFFE, "BNE $0000")]
    [DataRow(ProcessorVariant.Mos6502, (byte)0xD0, (byte)0xFF, (byte)0, (ushort)0xFFFF, "BNE $0000")]
    [DataRow(ProcessorVariant.Wdc65C02, (byte)0x7C, (byte)0x34, (byte)0x12, (ushort)0x2000, "JMP ($1234,X)")]
    [DataRow(ProcessorVariant.Wdc65C02, (byte)0xB2, (byte)0x42, (byte)0, (ushort)0x2000, "LDA ($42)")]
    [DataRow(ProcessorVariant.Wdc65C02, (byte)0x07, (byte)0x42, (byte)0, (ushort)0x2000, "RMB0 $42")]
    [DataRow(ProcessorVariant.Rockwell65C02, (byte)0xFF, (byte)0x42, (byte)0x80, (ushort)0xFFFD, "BBS7 $42, $FF80")]
    public void FormatsAddressingModesAndWrappedTargets(
        ProcessorVariant variant,
        byte encoding,
        byte operandLow,
        byte operandHigh,
        ushort address,
        string expected)
    {
        Disassembler.TryDecode([encoding, operandLow, operandHigh], address, variant, out DisassembledInstruction instruction)
            .Should().BeTrue();

        instruction.ToString().Should().Be(expected);
        Span<char> destination = stackalloc char[32];
        instruction.TryFormat(destination, out int count).Should().BeTrue();
        destination[..count].ToString().Should().Be(expected);
        destination.Fill('!');
        instruction.TryFormat(destination[..1], out count).Should().BeFalse();
        count.Should().Be(0);
        destination[0].Should().Be('!');
    }

    /// <summary>
    ///  Checks streaming capacity and truncation statuses never consume an incomplete instruction.
    /// </summary>
    [TestMethod]
    public void BulkDecodeReportsCapacityAndTruncationPrecisely()
    {
        Span<DisassembledInstruction> destination = stackalloc DisassembledInstruction[2];
        Disassembler.Decode(
            [0xEA, 0xAD, 0x34],
            address: 0xFFFF,
            ProcessorVariant.Mos6502,
            destination,
            out int consumed,
            out int count).Should().Be(OperationStatus.NeedMoreData);

        consumed.Should().Be(1);
        count.Should().Be(1);
        destination[0].Address.Should().Be(0xFFFF);
        Disassembler.Decode(
            [0xEA, 0xEA],
            address: 0xFFFF,
            ProcessorVariant.Mos6502,
            destination[..1],
            out consumed,
            out count).Should().Be(OperationStatus.DestinationTooSmall);

        consumed.Should().Be(1);
        count.Should().Be(1);
        Disassembler.Decode(
            [0xEA, 0xEA],
            address: 0xFFFF,
            ProcessorVariant.Mos6502,
            destination,
            out consumed,
            out count).Should().Be(OperationStatus.Done);

        destination[1].Address.Should().Be(0);
        consumed.Should().Be(2);
        count.Should().Be(2);
        Disassembler.TryDecode([0xAD, 0x34], address: 0, ProcessorVariant.Mos6502, out DisassembledInstruction missing)
            .Should().BeFalse();

        missing.Size.Should().Be(0);
    }

    /// <summary>
    ///  Checks flow follows branches/calls but leaves data, returns and indirect targets alone.
    /// </summary>
    [TestMethod]
    public void FlowAnalysisBuildsRegionsSymbolsAndCrossReferences()
    {
        AnalysisProject project = new(
            [0x20, 0x09, 0x20, 0xD0, 0x03, 0x60, 0xAA, 0xBB, 0x60, 0xAD, 0x34, 0x12, 0x60],
            origin: 0x2000,
            ProcessorVariant.Mos6502);

        DisassemblyResult result = Disassembler.Analyze(project);
        result.Success.Should().BeTrue();
        result.Instructions.Select(instruction => instruction.Address).Should().Equal(0x2000, 0x2003, 0x2005, 0x2008, 0x2009, 0x200C);
        result.Regions.Select(region => (region.Address, region.Length, region.Kind))
            .Should().Equal(
                ((ushort)0x2000, 6, AnalysisRegionKind.Code),
                ((ushort)0x2006, 2, AnalysisRegionKind.Unexplored),
                ((ushort)0x2008, 5, AnalysisRegionKind.Code));

        result.GetReferencesTo(0x2009).Length.Should().Be(1);
        result.GetReferencesTo(0x2009)[0].Kind.Should().Be(DisassemblyReferenceKind.Call);
        result.GetReferencesTo(0x2008)[0].Kind.Should().Be(DisassemblyReferenceKind.Branch);
        result.GetReferencesTo(0x1234)[0].Kind.Should().Be(DisassemblyReferenceKind.Read);
        result.Symbols[0x1234].Should().Be("D_1234");
        project.Symbols.Should().BeEmpty();
        AssertRoundTrip(result);
    }

    /// <summary>
    ///  Checks indirect jumps are not dereferenced and terminal/waiting instructions have explicit flow behavior.
    /// </summary>
    [TestMethod]
    public void IndirectStopsWaitsAndBreakSignaturesHaveCorrectFlow()
    {
        AnalysisProject indirect = new([0x6C, 0x03, 0x20, 0xEA, 0x60], origin: 0x2000, ProcessorVariant.Mos6502);
        DisassemblyResult jump = Disassembler.Analyze(indirect);
        jump.Instructions.Should().ContainSingle();
        jump.GetReferencesTo(0x2003)[0].Kind.Should().Be(DisassemblyReferenceKind.IndirectJump);
        AssertRoundTrip(jump);
        AnalysisProject waiting = new([0xCB, 0xEA, 0xDB, 0xEA], origin: 0x2000, ProcessorVariant.Wdc65C02);
        DisassemblyResult stopped = Disassembler.Analyze(waiting);
        stopped.Instructions.Select(instruction => instruction.Flow)
            .Should().Equal(DisassemblyFlow.Wait, DisassemblyFlow.Next, DisassemblyFlow.Stop);

        AssertRoundTrip(stopped);
        AnalysisProject softwareInterrupt = new([0x00, 0x42, 0xEA, 0x60], origin: 0x2000, ProcessorVariant.Mos6502);
        Disassembler.Analyze(softwareInterrupt).Instructions.Should().ContainSingle();
        softwareInterrupt.StopOnBreak = false;
        DisassemblyResult resumed = Disassembler.Analyze(softwareInterrupt);
        resumed.Instructions.Select(instruction => instruction.Address).Should().Equal(0x2000, 0x2002, 0x2003);
        AssertRoundTrip(resumed);
    }

    /// <summary>
    ///  Checks caller-pinned data wins over flow targets and code/data references keep their semantics.
    /// </summary>
    [TestMethod]
    public void PinnedDataAndBitBranchReferencesAreNotOverwritten()
    {
        AnalysisProject project = new([0x0F, 0x42, 0x01, 0x60, 0xEA], origin: 0x2000, ProcessorVariant.Rockwell65C02);
        project.Regions.Add(new(0x2004, length: 1, AnalysisRegionKind.Data));
        DisassemblyResult result = Disassembler.Analyze(project);
        result.Instructions.Select(instruction => instruction.Address).Should().Equal(0x2000, 0x2003);
        result.GetReferencesTo(0x0042)[0].Kind.Should().Be(DisassemblyReferenceKind.Read);
        result.GetReferencesTo(0x2004)[0].Kind.Should().Be(DisassemblyReferenceKind.Branch);
        result.Regions.Last().Kind.Should().Be(AnalysisRegionKind.Data);
        result.Diagnostics.Should().Contain(diagnostic => diagnostic.Code == "RCDIS007");
        project.Regions.Single().Kind.Should().Be(AnalysisRegionKind.Data);
        AssertRoundTrip(result);
    }

    /// <summary>
    ///  Checks pinned classifications and caller annotations survive reanalysis and old snapshots remain independent.
    /// </summary>
    [TestMethod]
    public void AnnotationsPinsAndSnapshotsRemainCallerControlled()
    {
        byte[] image = [0xAD, 0x00, 0xC0, 0x60, 0xEA, 0x60];
        AnalysisProject project = new(image, origin: 0x2000, ProcessorVariant.Mos6502);
        image[0] = 0xFF;
        project.Symbols.Add(0xC000, "Keyboard");
        project.Comments.Add(0x2000, "Read key\nRetained annotation");
        project.Regions.Add(new(0x2004, length: 2, AnalysisRegionKind.Code));
        DisassemblyResult first = Disassembler.Analyze(project);
        first.Instructions.Count.Should().Be(4);
        first.Instructions[0].OpCode.Instruction.Should().Be(Instruction.LDA);
        first.ExportSource().Should().Contain("LDA Keyboard").And.Contain("; Retained annotation");
        project.Symbols[0xC000] = "Key";
        project.Comments[0x2000] = "Changed";
        DisassemblyResult second = Disassembler.Analyze(project);
        second.Symbols[0xC000].Should().Be("Key");
        first.Symbols[0xC000].Should().Be("Keyboard");
        first.Comments[0x2000].Should().Be("Read key\nRetained annotation");
        project.Regions.Count.Should().Be(1);
        AssertRoundTrip(first);
        AssertRoundTrip(second);
    }

    /// <summary>
    ///  Checks branch targets in operands diagnose ambiguity and export every original byte.
    /// </summary>
    [TestMethod]
    public void ConflictsTruncatedTailsAndOperandAnnotationsUseByteFallbacks()
    {
        AnalysisProject branch = new([0xD0, 0xFF], origin: 0x2000, ProcessorVariant.Mos6502);
        DisassemblyResult conflict = Disassembler.Analyze(branch);
        conflict.Success.Should().BeTrue();
        conflict.Diagnostics.Should().Contain(diagnostic => diagnostic.Code == "RCDIS007");
        AssertRoundTrip(conflict);
        DisassemblyResult truncated = Disassembler.Disassemble([0xAD, 0x34], origin: 0x2000, ProcessorVariant.Mos6502);
        truncated.Diagnostics.Should().ContainSingle(diagnostic => diagnostic.Code == "RCDIS006");
        truncated.Instructions.Should().BeEmpty();
        AssertRoundTrip(truncated);
        AnalysisProject annotated = new([0xAD, 0x01, 0x02], origin: 0x2000, ProcessorVariant.Mos6502)
        {
            Mode = DisassemblyMode.Linear
        };

        annotated.Symbols.Add(0x2001, "LowByte");
        annotated.Comments.Add(0x2002, "High byte");
        DisassemblyResult result = Disassembler.Analyze(annotated);
        result.ExportSource().Should().Contain("LowByte:").And.Contain("; High byte").And.Contain(".byte");
        AssertRoundTrip(result);
    }

    /// <summary>
    ///  Checks symbol spelling cannot accidentally select accumulator addressing during export.
    /// </summary>
    [TestMethod]
    public void SymbolNamedACannotChangeTheAddressingMode()
    {
        AnalysisProject project = new([0x06, 0x10], origin: 0x2000, ProcessorVariant.Mos6502);
        project.Symbols.Add(0x0010, "a");
        DisassemblyResult result = Disassembler.Analyze(project);
        result.ExportSource().Should().Contain("ASL a+0");
        AssertRoundTrip(result);
        project.Symbols[0x0010] = "Byte_\u00E9";
        AssertRoundTrip(Disassembler.Analyze(project));
    }

    /// <summary>
    ///  Checks the NMI, RESET and IRQ vectors become data whose targets are traced as entry points.
    /// </summary>
    [TestMethod]
    public void HardwareVectorsSeedFlowAnalysis()
    {
        byte[] image =
        [
            0xEA, 0x40,                 // $FFF0 NMI: NOP, RTI
            0x58, 0x4C, 0xF3, 0xFF,     // $FFF2 RESET: CLI, JMP $FFF3
            0x40,                       // $FFF6 IRQ: RTI
            0x00, 0x00, 0x00,
            0xF0, 0xFF, 0xF2, 0xFF, 0xF6, 0xFF
        ];

        AnalysisProject project = new(image, origin: 0xFFF0, ProcessorVariant.Mos6502);
        project.EntryPoints.Clear();
        DisassemblyResult result = Disassembler.Analyze(project);

        result.Instructions.Select(instruction => (int)instruction.Address).Should().Equal(0xFFF0, 0xFFF1, 0xFFF2, 0xFFF3, 0xFFF6);
        result.Regions.Should().ContainSingle(region => region.Kind == AnalysisRegionKind.Data && region.Address == 0xFFFA);
        result.GetReferencesTo(0xFFF2).ToArray().Should().ContainSingle(
            reference => reference.Kind == DisassemblyReferenceKind.Vector && reference.Source == 0xFFFC);

        result.Symbols[0xFFF2].Should().Be("L_FFF2");
        AssertRoundTrip(result);

        project.FollowVectors = false;
        Disassembler.Analyze(project).Instructions.Should().BeEmpty();
    }

    /// <summary>
    ///  Checks a JMP (abs) pointer inside the image is followed, using the NMOS page wrap where it applies.
    /// </summary>
    [TestMethod]
    public void IndirectJumpPointersInsideTheImageAreFollowed()
    {
        AnalysisProject project = new([0x6C, 0x05, 0x20, 0x00, 0x00, 0x08, 0x20, 0x00, 0x60], origin: 0x2000, ProcessorVariant.Mos6502);
        DisassemblyResult result = Disassembler.Analyze(project);
        result.TryGetInstruction(0x2008, out DisassembledInstruction target).Should().BeTrue();
        target.Flow.Should().Be(DisassemblyFlow.Return);
        result.Regions.Should().Contain(region => region.Kind == AnalysisRegionKind.Data && region.Address == 0x2005);
        result.GetReferencesTo(0x2008).ToArray().Should().ContainSingle(reference => reference.Source == 0x2005);
        AssertRoundTrip(result);

        // NMOS JMP ($20FF) reads its high byte from $2000, which holds the JMP opcode itself.
        byte[] wrap = new byte[0x100];
        wrap[0] = 0x6C;
        wrap[1] = 0xFF;
        wrap[2] = 0x20;
        wrap[0xFF] = 0x34;
        DisassemblyResult nmos = Disassembler.Analyze(new(wrap, origin: 0x2000, ProcessorVariant.Mos6502));
        nmos.Diagnostics.Should().ContainSingle(diagnostic => diagnostic.Code == "RCDIS008");
        nmos.References.Should().NotContain(reference => reference.Kind == DisassemblyReferenceKind.Vector);

        // 65C02 parts carry into the high byte, which here is the first byte past the page.
        byte[] carry = new byte[0x102];
        Array.Copy(wrap, carry, 3);
        carry[0xFF] = 0x34;
        carry[0x100] = 0x12;
        DisassemblyResult cmos = Disassembler.Analyze(new(carry, origin: 0x2000, ProcessorVariant.Wdc65C02));
        cmos.Diagnostics.Should().NotContain(diagnostic => diagnostic.Code == "RCDIS008");
        cmos.GetReferencesTo(0x1234).ToArray().Should().ContainSingle(reference => reference.Kind == DisassemblyReferenceKind.Vector);
    }

    /// <summary>
    ///  Checks subroutine hints skip inline arguments and stop at calls that never return.
    /// </summary>
    [TestMethod]
    public void SubroutineHintsDescribeTheBytesAfterJsr()
    {
        byte[] image =
        [
            0x20, 0x00, 0x30, 0xC5, 0x07, 0x20,     // JSR $3000 with three inline bytes
            0x20, 0x10, 0x30, 0x48, 0x49, 0x00,     // JSR $3010 with "HI" and a terminator
            0x20, 0x20, 0x30, 0xEA                  // JSR $3020, which never returns
        ];

        AnalysisProject project = new(image, origin: 0x2000, ProcessorVariant.Mos6502);
        project.Calls.Add(0x3000, AnalysisCall.InlineBytes(3));
        project.Calls.Add(0x3010, AnalysisCall.InlineZeroTerminated);
        project.Calls.Add(0x3020, AnalysisCall.NoReturn);
        DisassemblyResult result = Disassembler.Analyze(project);

        result.Instructions.Select(instruction => (int)instruction.Address).Should().Equal(0x2000, 0x2006, 0x200C);
        result.Regions.Where(region => region.Kind == AnalysisRegionKind.Data).Select(region => (int)region.Address)
            .Should().Equal(0x2003, 0x2009);

        result.Regions[^1].Kind.Should().Be(AnalysisRegionKind.Unexplored);
        AssertRoundTrip(result);
    }

    /// <summary>
    ///  Checks invalid subroutine hints are model errors and unterminated inline strings are conflicts.
    /// </summary>
    [TestMethod]
    public void InvalidSubroutineHintsAreDiagnosed()
    {
        AnalysisProject project = new([0x20, 0x00, 0x30, 0x41, 0x42], origin: 0x2000, ProcessorVariant.Mos6502);
        project.Calls.Add(0x3000, AnalysisCall.InlineZeroTerminated);
        DisassemblyResult unterminated = Disassembler.Analyze(project);
        unterminated.Success.Should().BeTrue();
        unterminated.Diagnostics.Should().ContainSingle(diagnostic => diagnostic.Code == "RCDIS007");

#pragma warning disable CS8625 // Exercise the model's null validation.
        project.Calls[0x3000] = null;
#pragma warning restore CS8625
        Disassembler.Analyze(project).Diagnostics.Should().ContainSingle(diagnostic => diagnostic.Code == "RCDIS010");

        Action zero = () => AnalysisCall.InlineBytes(0);
        zero.Should().Throw<ArgumentOutOfRangeException>();
    }

    /// <summary>
    ///  Checks absolute encodings of zero-page values export as instructions with an explicit width.
    /// </summary>
    [TestMethod]
    public void AbsoluteEncodingsOfZeroPageValuesExportWithWidthPrefix()
    {
        AnalysisProject project = new([0xAD, 0x12, 0x00, 0xBD, 0x34, 0x00, 0x60], origin: 0x2000, ProcessorVariant.Mos6502);
        project.Symbols.Add(0x0012, "Zero");
        DisassemblyResult result = Disassembler.Analyze(project);
        result.ExportSource().Should().Contain("LDA a:Zero\n").And.Contain("LDA a:D_0034,X\n").And.NotContain(".byte");
        AssertRoundTrip(result);
    }

    /// <summary>
    ///  Checks invalid input remains explicit errors and cancellation retains normal exception semantics.
    /// </summary>
    [TestMethod]
    public void InvalidModelsAndArgumentsNeverProduceSuccessfulEmptyOutput()
    {
        AnalysisProject project = new([0xEA, 0x60], origin: 0x2000, ProcessorVariant.Mos6502);
        project.EntryPoints.Add(0x1000);
        project.Symbols.Add(0x2000, "Duplicate");
        project.Symbols.Add(0x2001, "Duplicate");
        project.Regions.Add(new(0x2000, length: 2, AnalysisRegionKind.Data));
        DisassemblyResult invalid = Disassembler.Analyze(project);
        invalid.Success.Should().BeFalse();
        invalid.Diagnostics.Should().Contain(diagnostic => diagnostic.IsError);
        Action export = () => invalid.ExportSource();
        export.Should().Throw<InvalidOperationException>();
        Action cancel = () => Disassembler.Analyze(project, new CancellationToken(canceled: true));
        cancel.Should().Throw<OperationCanceledException>();
        Action variant = () => Disassembler.TryDecode([], address: 0, variant: (ProcessorVariant)99, out _);
        variant.Should().Throw<ArgumentOutOfRangeException>();
        Action empty = () => new AnalysisProject([], origin: 0, ProcessorVariant.Mos6502);
        empty.Should().Throw<ArgumentException>();
    }

    /// <summary>
    ///  Checks arbitrary streams survive both text and typed native-model round trips.
    /// </summary>
    /// <param name="variant">The CPU encoding set.</param>
    [TestMethod]
    [DataRow(ProcessorVariant.Mos6502)]
    [DataRow(ProcessorVariant.Wdc65C02)]
    [DataRow(ProcessorVariant.Rockwell65C02)]
    public void ArbitraryByteStreamsRoundTripExactly(ProcessorVariant variant)
    {
        Random random = new(Seed: 6502);
        for (int index = 0; index < 8; index++)
        {
            byte[] image = new byte[1 + (index * 127)];
            random.NextBytes(image);
            AssertRoundTrip(Disassembler.Disassemble(image, origin: 0x4000, variant));
        }
    }

    /// <summary>
    ///  Checks the real self-hosted slot-seven firmware round-trips through linear and flow analysis.
    /// </summary>
    [TestMethod]
    public void ActualFirmwareRoundTripsThroughBothAnalysisModes()
    {
        ReadOnlySpan<byte> image = Slot7Rom.Bytes;
        AnalysisProject project = new(image, Slot7Rom.Origin, ProcessorVariant.Mos6502);
        AssertRoundTrip(Disassembler.Analyze(project));
        project.Mode = DisassemblyMode.Linear;
        AssertRoundTrip(Disassembler.Analyze(project));
    }

    /// <summary>
    ///  Checks an optional caller-supplied ROM without bundling or downloading firmware.
    /// </summary>
    [TestMethod]
    public void CallerSuppliedRomRoundTripsWhenConfigured()
    {
        string? path = Environment.GetEnvironmentVariable("RETROCORE_DISASSEMBLY_ROM");
        if (path is null) { Assert.Inconclusive("Set RETROCORE_DISASSEMBLY_ROM to an externally supplied ROM."); }
        byte[] image = File.ReadAllBytes(path);
        image.Length.Should().BeInRange(1, 65536);
        AssertRoundTrip(Disassembler.Disassemble(image, 65536 - image.Length, ProcessorVariant.Wdc65C02));
    }

    /// <summary>
    ///  Checks warmed decoding, formatting and cross-reference queries allocate no temporary objects.
    /// </summary>
    [TestMethod]
    public void SpanDecodingAndFormattingAllocateNothing()
    {
        // Arrays made before the measurement, as spans over them, since the measured work is a lambda.
        byte[] image = [0xA9, 0x42, 0x8D, 0x00, 0x20, 0xD0, 0xF9];
        DisassembledInstruction[] output = new DisassembledInstruction[3];
        char[] text = new char[32];
        DisassemblyResult analysis = Disassembler.Disassemble(image, origin: 0x2000, ProcessorVariant.Mos6502);
        Disassembler.Decode(image, address: 0x2000, ProcessorVariant.Mos6502, output, out _, out _);
        foreach (DisassembledInstruction instruction in output) { instruction.TryFormat(text, out _); }
        _ = analysis.GetReferencesTo(0x2000);
        int count = 0;
        long allocated = Allocations.During(() =>
        {
            count = 0;
            for (int iteration = 0; iteration < 1000; iteration++)
            {
                if (Disassembler.Decode(image, address: 0x2000, ProcessorVariant.Mos6502, output, out _, out int written)
                    != OperationStatus.Done)
                {
                    throw new InvalidOperationException("The instruction stream was not completely decoded.");
                }

                count += written;
                count += analysis.GetReferencesTo(0x2000).Length;
                foreach (DisassembledInstruction instruction in output)
                {
                    if (!instruction.TryFormat(text, out int length))
                    {
                        throw new InvalidOperationException("Formatting failed.");
                    }

                    count += length;
                }
            }
        });

        count.Should().BeGreaterThan(3000);
        allocated.Should().Be(0);
    }

    private static void AssertRoundTrip(DisassemblyResult result)
    {
        result.Success.Should().BeTrue();
        NativeAssembler assembler = new();
        AssemblyResult text = assembler.Assemble(new AssemblySource(result.ExportSource()), result.Options);
        text.Diagnostics.Select(diagnostic => diagnostic.Message).Should().BeEmpty();
        text.Sections[0].Bytes.ToArray().Should().Equal(result.Image.ToArray());
        AssemblyResult model = assembler.Assemble(result.ToAssemblyProject(), result.Options);
        model.Diagnostics.Select(diagnostic => diagnostic.Message).Should().BeEmpty();
        model.Sections[0].Bytes.ToArray().Should().Equal(result.Image.ToArray());
    }
}
