// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Documentation;
using Retrocore.Machines;

namespace Retrocore.Tests;

/// <summary>
///  Flag values in the routine analysis: constants the effects lines and the CPU's core give, the branches they
///  decide, and what each way a branch goes tells of the flags.
/// </summary>
[TestClass]
public class FlagValueAnalysisTests
{
    /// <summary>
    ///  A branch after a load of a constant always goes one way, so the code only the other way reaches is not
    ///  followed, as the MOS's <c>bne ... ; always</c>.
    /// </summary>
    [TestMethod]
    public void LoadedConstantsDecideBranches()
    {
        const string Source = """
            ;; Always branches past the change.
            ;; Keeps: X
            Skipper:
                lda #1
                bne Done
                ldx #0
            Done:
                rts
            """;

        (List<string> findings, AnalysisContracts contracts) = Check(Source, "Mos6502");
        findings.Should().BeEmpty();
        Summary(contracts, 0x1000).FixedConditions.Should().Equal(new Dictionary<ushort, bool> { [0x1002] = true });
    }

    /// <summary>
    ///  The core computes results from known inputs: a count down from a constant, a sum in binary mode, a
    ///  comparison. ADC reads the decimal flag, so without CLD it is run both ways, and only what both give is known.
    /// </summary>
    [TestMethod]
    public void TheCoreComputesKnownResults()
    {
        const string Source = """
            ;; Never reaches the change.
            ;; Keeps: Y
            Counter:
                ldx #2
                dex
                dex
                bne Change
                cld
                clc
                lda #$09
                adc #$01
                bcs Change
                cmp #$0A
                bne Change
                rts
            Change:
                ldy #0
                rts
            """;

        (List<string> findings, AnalysisContracts contracts) = Check(Source, "Mos6502");
        findings.Should().BeEmpty();
        Summary(contracts, 0x1000).FixedConditions.Should().Equal(
            new Dictionary<ushort, bool> { [0x1004] = false, [0x100C] = false, [0x1010] = false });

        // Without CLD, decimal mode may be on, and $09 + $01 is $10 there: the carry is clear either way, but the
        // sum is not known, so the last branch is not either.
        Source.Should().Contain("    cld\n");
        (_, contracts) = Check(Source.Replace("    cld\n", "", StringComparison.Ordinal), "Mos6502");
        Summary(contracts, 0x1000).FixedConditions.Should().Equal(
            new Dictionary<ushort, bool> { [0x1004] = false, [0x100B] = false });
    }

    /// <summary>
    ///  Each way a branch goes tells of its flags: past a BCS not taken, carry is clear, so a BCC there is always
    ///  taken.
    /// </summary>
    [TestMethod]
    public void BranchesTellOfTheirFlags()
    {
        const string Source = """
            ;; Changes X only when carry is set, and branches on it twice.
            ;; Keeps: Y
            Twice:
                bcs Set
                bcc Clear
                ldy #0
            Clear:
                rts
            Set:
                ldx #0
                rts
            """;

        (List<string> findings, AnalysisContracts contracts) = Check(Source, "Mos6502");
        findings.Should().BeEmpty();
        Summary(contracts, 0x1000).FixedConditions.Should().Equal(new Dictionary<ushort, bool> { [0x1002] = true });
    }

    /// <summary>
    ///  The other CPUs: the Z80's XOR A sets zero, so JR NZ is never taken and RET Z always returns; the 6809's
    ///  conditions on two flags are decided when both are known, from A, a part of D.
    /// </summary>
    [TestMethod]
    public void OtherCpusDecideConditions()
    {
        const string Z80 = """
            ;; Returns before the change.
            ;; Keeps: BC
            Clear:
                xor a
                jr nz,Change
                ret z
            Change:
                ld b,0
                ret
            """;

        (List<string> findings, AnalysisContracts contracts) = Check(Z80, "Z80");
        findings.Should().BeEmpty();
        Summary(contracts, 0x1000).FixedConditions.Should().Equal(
            new Dictionary<ushort, bool> { [0x1001] = false, [0x1003] = true });

        const string M6809 = """
            ;; Compares 7 with 5, so BLS is not taken and BHI is.
            ;; Keeps: B
            Compare:
                lda #7
                cmpa #5
                bls Change
                bhi Done
            Change:
                ldb #0
            Done:
                rts
            """;

        (findings, contracts) = Check(M6809, "M6809");
        findings.Should().BeEmpty();
        Summary(contracts, 0x1000).FixedConditions.Should().Equal(
            new Dictionary<ushort, bool> { [0x1004] = false, [0x1006] = true });
    }

    /// <summary>
    ///  A flag from hidden state is not known: LD A,I copies IFF2 into the parity, which the core running the
    ///  instruction has at its own value, so JP PE after it can go either way; after XOR A, which sets the parity,
    ///  it is always taken. A register from hidden state is not known either, as A after the 8085's RIM.
    /// </summary>
    [TestMethod]
    public void FlagsFromHiddenStateAreNotKnown()
    {
        const string Source = """
            ;; Jumps while interrupts are on.
            Interrupts:
                ld a,i
                jp pe,Done
                xor a
                jp pe,Done
                nop
            Done:
                ret
            """;

        (List<string> findings, AnalysisContracts contracts) = Check(Source, "Z80");
        findings.Should().BeEmpty();
        Summary(contracts, 0x1000).FixedConditions.Should().Equal(new Dictionary<ushort, bool> { [0x1006] = true });

        // The 8085's RIM reads the interrupt masks and the serial input into A.
        const string Masks = """
            ;; Jumps while the serial input is 0.
            Serial:
                rim
                ani $80
                jz Done
                nop
            Done:
                ret
            """;

        (findings, contracts) = Check(Masks, "I8085");
        findings.Should().BeEmpty();
        Summary(contracts, 0x1000).FixedConditions.Should().BeEmpty();
    }

    /// <summary>
    ///  Some bits known decide a branch: ORA with a constant that has a bit set leaves a non-zero result whatever
    ///  memory held, as the MOS's <c>lda #CFS_AT_EOF</c> then <c>ora CFS_STATUS</c>; AND with $0F leaves bit 7 clear
    ///  whatever A was; a byte read from memory alone decides nothing.
    /// </summary>
    [TestMethod]
    public void SomeKnownBitsDecideBranches()
    {
        const string Source = """
            ;; Branches on results with only some bits known.
            ;; Keeps: X
            Partial:
                lda #$04
                ora $10
                beq Change
                and #$0F
                bmi Change
                ora #$80
                bpl Change
                lda $11
                bne Done
            Change:
                ldx #0
            Done:
                rts
            """;

        (List<string> findings, AnalysisContracts contracts) = Check(Source, "Mos6502");
        findings.Should().Equal("Partial ($1000) documents Keeps: X, but X is changed by the instruction at $1012.");
        Summary(contracts, 0x1000).FixedConditions.Should().Equal(
            new Dictionary<ushort, bool> { [0x1004] = false, [0x1008] = false, [0x100C] = false });
    }

    /// <summary>
    ///  Known bits on the Z80 and the 6809: OR 1 leaves A non-zero, ANDA #$0F leaves it positive.
    /// </summary>
    [TestMethod]
    public void OtherCpusUseKnownBits()
    {
        const string Z80 = """
            ;; A is not zero after OR 1.
            ;; Keeps: BC
            NotZero:
                or 1
                ret nz
                ld b,0
                ret
            """;

        (List<string> findings, AnalysisContracts contracts) = Check(Z80, "Z80");
        findings.Should().BeEmpty();
        Summary(contracts, 0x1000).FixedConditions.Should().Equal(new Dictionary<ushort, bool> { [0x1002] = true });

        const string M6809 = """
            ;; A is positive after ANDA #$0F.
            ;; Keeps: B
            Positive:
                anda #$0F
                bmi Change
                rts
            Change:
                ldb #0
                rts
            """;

        (findings, contracts) = Check(M6809, "M6809");
        findings.Should().BeEmpty();
        Summary(contracts, 0x1000).FixedConditions.Should().Equal(new Dictionary<ushort, bool> { [0x1002] = false });
    }

    /// <summary>
    ///  A part the core does not name, as the Z80's IXH, is run through its pair, the first part high.
    /// </summary>
    [TestMethod]
    public void PartsRunThroughTheirPairs()
    {
        const string Source = """
            ;; Loads IX and tests its halves, which match.
            ;; Keeps: BC
            Halves:
                ld ix,$1234
                ld a,ixh
                cp $12
                jr nz,Change
                ld a,ixl
                cp $34
                ret z
            Change:
                ld b,0
                ret
            """;

        (List<string> findings, AnalysisContracts contracts) = Check(Source, "Z80");
        findings.Should().BeEmpty();
        Summary(contracts, 0x1000).FixedConditions.Values.Should().HaveCount(2);
    }

    /// <summary>
    ///  A conditional call that is never taken applies nothing of its callee.
    /// </summary>
    [TestMethod]
    public void UntakenCallsChangeNothing()
    {
        const string Source = """
            ;; Calls the change only when carry is set, and it is clear.
            ;; Keeps: BC
            Maybe:
                or a
                call c,Change
                ret
            ;; Changes B.
            ;; Uses: B
            Change:
                ld b,0
                ret
            """;

        (List<string> findings, AnalysisContracts contracts) = Check(Source, "Z80");
        findings.Should().BeEmpty();
        Summary(contracts, 0x1000).FixedConditions.Should().Equal(new Dictionary<ushort, bool> { [0x1001] = false });
    }

    /// <summary>
    ///  With a memory map, a ROM table the source assembles reads as its bytes: an index known to be 0 to 3 picks
    ///  entries that all have bit 7 set. Without a map, or where the bytes are code, nothing is known.
    /// </summary>
    [TestMethod]
    public void RomTablesReadAsTheirBytes()
    {
        const string Source = """
            ;; Looks an entry up in a table whose entries are all negative.
            ;; Keeps: Y
            Lookup:
                txa
                and #3
                tax
                lda Table,x
                bmi Done
                ldy #0
            Done:
                lda Lookup
                bmi Change
                rts
            Change:
                ldy #1
                rts
            Table:
                .byte $80, $90, $A0, $FF
            """;

        MemoryMap rom = MemoryMap.FromRanges([(0x0000, 0x0FFF, MemoryKind.Ram), (0x1000, 0x1FFF, MemoryKind.Rom)]);
        (List<string> findings, AnalysisContracts contracts) = Check(Source, "Mos6502", rom);

        // The table decides its branch; the code byte at Lookup (TXA, $8A) does not decide the other.
        findings.Should().Equal("Lookup ($1000) documents Keeps: Y, but Y is changed by the instruction at $1011.");
        Summary(contracts, 0x1000).FixedConditions.Should().Equal(new Dictionary<ushort, bool> { [0x1007] = true });

        (findings, contracts) = Check(Source, "Mos6502");
        Summary(contracts, 0x1000).FixedConditions.Should().BeEmpty();
    }

    /// <summary>
    ///  A value stored in RAM reads back, but not from a device, and not round a loop, which may be waiting for an
    ///  interrupt to change it.
    /// </summary>
    [TestMethod]
    public void RamKeepsWhatIsStoredButDevicesAndLoopsDoNot()
    {
        const string Stored = """
            ;; Stores 1 and tests it.
            ;; Keeps: X
            Stored:
                lda #1
                sta $C000
                lda #0
                lda $C000
                bne Done
                ldx #0
            Done:
                rts
            """;

        MemoryMap ram = MemoryMap.AllRam;
        MemoryMap device = MemoryMap.FromRanges([(0x0000, 0xBFFF, MemoryKind.Ram), (0xC000, 0xC0FF, MemoryKind.Io), (0x1000, 0x1FFF, MemoryKind.Rom)]);
        (List<string> findings, AnalysisContracts contracts) = Check(Stored, "Mos6502", ram);
        findings.Should().BeEmpty();
        Summary(contracts, 0x1000).FixedConditions.Should().Equal(new Dictionary<ushort, bool> { [0x100A] = true });

        (findings, contracts) = Check(Stored, "Mos6502", device);
        findings.Should().HaveCount(1);
        Summary(contracts, 0x1000).FixedConditions.Should().BeEmpty();

        const string Waits = """
            ;; Clears a flag and waits for an interrupt to set it.
            ;; Keeps: X
            Waits:
                lda #0
                sta $10
            Wait:
                lda $10
                beq Wait
                ldx #0
                rts
            """;

        (findings, contracts) = Check(Waits, "Mos6502", ram);
        findings.Should().Equal("Waits ($1000) documents Keeps: X, but X is changed by the instruction at $1008.");
        Summary(contracts, 0x1000).FixedConditions.Should().BeEmpty();
    }

    /// <summary>
    ///  Paths that meet with the same registers and flags but different memory are joined and followed again: the
    ///  path that stores 0 reaches Common first, and the one that stores an unknown byte must still be seen there.
    /// </summary>
    [TestMethod]
    public void JoinsThatChangeOnlyMemoryAreFollowed()
    {
        const string Source = """
            ;; Stores 0 or an unknown byte, then tests it.
            ;; Keeps: X
            Joins:
                lda $12
                beq Known
                lda $11
                sta $10
                lda #0
                jmp Common
            Known:
                lda #0
                sta $10
                jmp Common
            Common:
                lda $10
                bmi Change
                rts
            Change:
                ldx #0
                rts
            """;

        (List<string> findings, AnalysisContracts contracts) = Check(Source, "Mos6502", MemoryMap.AllRam);
        findings.Should().HaveCount(1);
        Summary(contracts, 0x1000).FixedConditions.Should().BeEmpty();
    }

    private static AnalysisRoutineSummary Summary(AnalysisContracts contracts, ushort address) =>
        contracts.Analyzed(address) ?? throw new AssertFailedException($"No analysis at ${address:X4}.");

    private static (List<string> Findings, AnalysisContracts Contracts) Check(string source, string cpu, MemoryMap? map = null)
    {
        string path = Path.Join(AppContext.BaseDirectory, $"FlagValues.{cpu}.asm");
        AssemblyResult result = new Retrocore.Assembler.Assembler().Assemble(
            new AssemblySource(source, path),
            new AssemblyOptions(cpu, 0x1000, 0x100));

        result.Diagnostics.Should().BeEmpty();
        DocumentationSet documentation = DocumentationSet.Create([DocumentationParser.Parse(source, path)], result);
        AnalysisContracts contracts = new(result, documentation, CpuCatalog.Get(cpu), map: map);
        AnalysisContractReport report = contracts.Check();
        return ([.. report.Findings.Select(finding => finding.ToString())], contracts);
    }
}
