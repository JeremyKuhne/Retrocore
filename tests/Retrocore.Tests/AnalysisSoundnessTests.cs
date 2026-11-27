// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Documentation;
using Retrocore.Machines;

namespace Retrocore.Tests;

/// <summary>
///  The routine analysis never claims what the code does not do: a register kept that a path changes, a branch
///  fixed that can go the other way, or a return the stack does not allow. Each case is code that once fooled it.
/// </summary>
[TestClass]
public class AnalysisSoundnessTests
{
    /// <summary>
    ///  A store through a pointer may change any byte of memory, as the Z80's <c>LD [HL],B</c> does.
    /// </summary>
    [TestMethod]
    public void StoresThroughPointersForgetMemory()
    {
        const string Source = """
            ;; Saves A in memory, then stores B over it through HL.
            ;; Keeps: A
            Pointer:
                ld [$4000],a
                ld hl,$4000
                ld [hl],b
                ld a,[$4000]
                ret
            """;

        NotKept(Source, "Z80", "A");
    }

    /// <summary>
    ///  An indexed store may land on any byte from its base, not just the base.
    /// </summary>
    [TestMethod]
    public void IndexedStoresAreNotFixed()
    {
        const string Source = """
            ;; Saves A at $11, then stores Y at $10 plus X, which may be $11.
            ;; Keeps: A
            Indexed:
                sta $11
                sty $10,x
                lda $11
                rts
            """;

        NotKept(Source, "Mos6502", "A");
    }

    /// <summary>
    ///  A 16-bit store writes two bytes, and a 16-bit load reads two.
    /// </summary>
    [TestMethod]
    public void WideStoresWriteTwoBytes()
    {
        NotKept("""
            ;; Saves A at $2011, then stores X over it at $2010.
            ;; Keeps: A
            Wide:
                sta $2011
                stx $2010
                lda $2011
                rts
            """, "M6809", "A");

        NotKept("""
            ;; Saves A at $4001, then stores HL over it at $4000.
            ;; Keeps: A
            Wide:
                ld [$4001],a
                ld [$4000],hl
                ld a,[$4001]
                ret
            """, "Z80", "A");

        // The 6809 stores X high byte first: $2000 holds $12, so A is $12 and BEQ is never taken; were the bytes the
        // other way round, A would be $34 and BEQ always taken.
        (AnalysisContracts contracts, _) = Analyze("""
            ;; Stores X and compares its first byte with the low byte.
            ;; Keeps: B
            BigEndian:
                ldx #$1234
                stx $2000
                lda $2000
                cmpa #$34
                beq Change
                rts
            Change:
                ldb #0
                rts
            """, "M6809", MemoryMap.AllRam);

        Fixed(contracts, 0x1000).Should().Contain(new KeyValuePair<ushort, bool>(0x100B, value: false));
    }

    /// <summary>
    ///  Paths that meet with different stacks lose the stack, whichever arrives first.
    /// </summary>
    [TestMethod]
    public void StacksThatDifferLoseTheStack()
    {
        NotKept("""
            ;; Pushes A on one path only, then pulls it.
            ;; Keeps: A
            Joiner:
                bcs Push
                jmp Join
            Push:
                pha
            Join:
                pla
                rts
            """, "Mos6502", "A");
    }

    /// <summary>
    ///  A pull of other bytes than the push saved does not return normally.
    /// </summary>
    [TestMethod]
    public void PullsOfOtherBytesLoseTheStack()
    {
        NotKept("""
            ;; Pushes A and B but pulls only A.
            ;; Keeps: B
            Short:
                pshs a,b
                puls a
                rts
            """, "M6809", "B");

        NotKept("""
            ;; Pushes A but pulls A and B.
            ;; Keeps: X
            Long:
                pshs a
                puls a,b
                rts
            """, "M6809", "X");
    }

    /// <summary>
    ///  A write into stacked data changes what a pull restores.
    /// </summary>
    [TestMethod]
    public void WritesIntoTheStackChangeWhatIsPulled()
    {
        NotKept("""
            ;; Pushes A, stores B over it, and pulls it.
            ;; Keeps: A
            Over:
                pshs a
                stb ,s
                puls a
                rts
            """, "M6809", "A");

        NotKept("""
            ;; Pushes BC, swaps HL into its place, and pulls it.
            ;; Keeps: BC
            Swap:
                push bc
                ex [sp],hl
                pop bc
                ret
            """, "Z80", "B");

        NotKept("""
            ;; Swaps HL with the return address.
            ;; Keeps: A
            Return:
                ex [sp],hl
                ret
            """, "Z80", "A");
    }

    /// <summary>
    ///  A block move runs until BC is 0, not once.
    /// </summary>
    [TestMethod]
    public void BlockInstructionsAreNotOneStep()
    {
        (AnalysisContracts contracts, _) = Analyze("""
            ;; Moves three bytes, then tests P/V, which LDIR leaves clear.
            ;; Keeps: B
            Move:
                xor a
                ld hl,$5000
                ld de,$6000
                ld bc,3
                ldir
                jp pe,Change
                ret
            Change:
                ld b,0
                ret
            """, "Z80", MemoryMap.AllRam);

        Fixed(contracts, 0x1000).Should().NotContainKey(0x100C);
    }

    /// <summary>
    ///  A callee the analysis could not follow to its end keeps nothing it can vouch for.
    /// </summary>
    [TestMethod]
    public void IncompleteCalleesKeepNothing()
    {
        NotKept("""
            ;; Calls a helper that may jump anywhere.
            ;; Keeps: A
            Caller:
                jsr Helper
                rts
            Helper:
                bcc Ok
                jmp ($0300)
            Ok:
                rts
            """, "Mos6502", "A");
    }

    /// <summary>
    ///  Code that stores into the code after it changes what that code does.
    /// </summary>
    [TestMethod]
    public void PatchedCodeIsNotItsAssembledBytes()
    {
        (AnalysisContracts contracts, _) = Analyze("""
            ;; Stores A into the operand of the load after it, so the load loads A.
            ;; Keeps: X
            Patcher:
                sta Patch+1
                lda Patch+1
            Patch:
                lda #0
                beq Done
                ldx #0
            Done:
                rts
            """, "Mos6502", MemoryMap.AllRam);

        Fixed(contracts, 0x1000).Should().BeEmpty();
    }

    /// <summary>
    ///  An instruction a store changes is not the one assembled: storing CLC's opcode over SEC leaves carry clear,
    ///  through a fixed address, or through an index that reaches past the base.
    /// </summary>
    [TestMethod]
    public void PatchedInstructionsAreNotTheirAssembledEffects()
    {
        NotKept("""
            ;; Stores CLC over the SEC below, so BCS is not taken.
            ;; Keeps: X
            Holder:
                lda #$18
                sta Patch
            Patch:
                sec
                bcs Done
                ldx #0
            Done:
                rts
            """, "Mos6502", "X");

        NotKept("""
            ;; Stores CLC over the SEC two bytes on through an index, and goes straight there.
            ;; Keeps: X
            Holder:
                ldy #2
                lda #$18
                sta Patch,y
                jmp Patch+2
            Patch:
                nop
                nop
                sec
                bcs Done
                ldx #0
            Done:
                rts
            """, "Mos6502", "X");
    }

    /// <summary>
    ///  Code a table points into may be entered there with any flags.
    /// </summary>
    [TestMethod]
    public void TablesEnterCodeAnywhere()
    {
        (_, AnalysisContractReport report) = Analyze("""
            ;; Loads 1 and branches on it, but a vector enters at Inner.
            ;; Keeps: X
            Routine:
                lda #1
            Inner:
                bne Skip
                ldx #0
            Skip:
                rts
            Vector:
                .word Inner
            """, "Mos6502", MemoryMap.AllRam);

        report.FixedConditions.Should().BeEmpty();

        // A table naming a local label reaches every label of that name, whichever scope the name means.
        (_, report) = Analyze("""
            .proc Other
            Loop:
                rts
            .endproc

            ;; Loads 1 and branches on it, but its own table enters at Loop.
            ;; Keeps: X
            .proc Routine
                lda #1
            Loop:
                bne Skip
                ldx #0
            Skip:
                rts
            Vector:
                .word Loop
            .endproc
            """, "Mos6502", MemoryMap.AllRam);

        report.FixedConditions.Should().BeEmpty();
    }

    /// <summary>
    ///  A write of the program counter other than a return is a jump the analysis cannot see, as the 6809's
    ///  <c>TFR X,PC</c>, or its <c>PULU PC</c> through the user stack.
    /// </summary>
    [TestMethod]
    public void WritesOfThePcAreJumps()
    {
        NotKept("""
            ;; Jumps through X to the change.
            ;; Keeps: B
            Transfer:
                ldx #Change
                tfr x,pc
                rts
            Change:
                ldb #0
                rts
            """, "M6809", "B");

        NotKept("""
            ;; Jumps through the user stack.
            ;; Keeps: B
            UserStack:
                pulu pc
            """, "M6809", "B");
    }

    /// <summary>
    ///  A pointer worked out from the stack pointer addresses the stack, as the Z80's <c>ADD HL,SP</c>, also where a
    ///  callee works it out or steps one it is given.
    /// </summary>
    [TestMethod]
    public void PointersFromTheStackPointerWriteTheStack()
    {
        NotKept("""
            ;; Saves BC, then clears its low byte on the stack through HL.
            ;; Keeps: BC
            Slot:
                push bc
                ld hl,0
                add hl,sp
                ld [hl],0
                pop bc
                ret
            """, "Z80", "BC");

        NotKept("""
            ;; Saves A, then writes over it a byte above S.
            ;; Keeps: A
            Above:
                pha
                tsx
                inx
                lda #0
                sta $0100,x
                pla
                rts
            """, "Mos6502", "A");

        // A callee that leaves such an address, as one returning SP plus 2, the caller's pushed C.
        NotKept("""
            ;; Saves BC, then clears its low byte through the address a helper gives.
            ;; Keeps: BC
            Caller:
                push bc
                call Helper
                ld [hl],0
                pop bc
                ret
            Helper:
                ld hl,2
                add hl,sp
                ret
            """, "Z80", "BC");

        // And one that adjusts an address the caller passes, as INX on the X that TSX gave.
        NotKept("""
            ;; Saves A, then clears it on the stack through the X a helper steps.
            ;; Keeps: A
            Caller:
                pha
                tsx
                jsr Bump
                lda #0
                sta $0100,x
                pla
                rts
            Bump:
                inx
                rts
            """, "Mos6502", "A");
    }

    /// <summary>
    ///  A write into the stack with data pushed may land under it, on the return address, as
    ///  <c>PHA; TSX; INC $0102,X</c> does to skip inline data.
    /// </summary>
    [TestMethod]
    public void WritesUnderPushedDataChangeTheReturn()
    {
        NotReturning("""
            ;; Saves A and writes over the return address under it.
            ;; Keeps: Y
            Under:
                pha
                tsx
                lda #$FF
                sta $0103,x
                pla
                rts
            """, "Mos6502");

        NotReturning("""
            ;; Saves A and writes over the return address under it.
            ;; Keeps: Y
            Under:
                pshs a
                stb 2,s
                puls a
                rts
            """, "M6809");
    }

    /// <summary>
    ///  The 6809 pulls a list in its own order, CC first, so a pull of other registers than were pushed gives each
    ///  another's value: after <c>PSHS A,DP</c>, <c>PULS A,CC</c> puts A in CC and DP in A.
    /// </summary>
    [TestMethod]
    public void PullsOfOtherListsRestoreNothing()
    {
        NotKept("""
            ;; Pushes A and DP and pulls A and CC.
            ;; Keeps: A
            Lists:
                pshs a,dp
                puls a,cc
                rts
            """, "M6809", "A");
    }

    /// <summary>
    ///  A call to an <c>Entry:</c> label takes what the code from there does, not from the routine's start, and the
    ///  routine's <c>Keeps:</c> is checked from there too.
    /// </summary>
    [TestMethod]
    public void EntriesAreTheirOwnCode()
    {
        NotKept("""
            ;; Calls the second entry.
            ;; Keeps: X
            Caller:
                jsr Alternate
                rts

            ;; Copies X to A, or from Alternate clears X.
            ;; Keeps: Y
            ;; Entry: Alternate = clears X first
            Main:
                txa
                jmp Common
            Alternate:
                ldx #0
            Common:
                rts
            """, "Mos6502", "X");

        // And the routine's Keeps: holds from each entry: X is kept from the start, but not from Alternate.
        (_, AnalysisContractReport report) = Analyze("""
            ;; Copies X to A, or from Alternate clears X.
            ;; Keeps: X
            ;; Entry: Alternate = clears X first
            Main:
                txa
                jmp Common
            Alternate:
                ldx #0
            Common:
                rts
            """, "Mos6502", MemoryMap.AllRam);

        report.Findings.Should().ContainSingle().Which.ToString().Should().Contain("Keeps: X");
        report.Checked.Should().Be(1);
    }

    // The routine at $1000 is not reported to return normally to its caller.
    private static void NotReturning(string source, string cpu)
    {
        (AnalysisContracts contracts, _) = Analyze(source, cpu, MemoryMap.AllRam);
        AnalysisRoutineSummary summary = contracts.Analyzed(0x1000) ?? throw new AssertFailedException("No analysis.");
        bool claimed = summary is { Returns: true, Incomplete: null, ChangesCallerStack: false };
        claimed.Should().BeFalse("the stack under the return address changes, but the analysis returns normally");
    }

    // The routine at $1000 is not reported complete with the register kept.
    private static void NotKept(string source, string cpu, string register)
    {
        (AnalysisContracts contracts, _) = Analyze(source, cpu, MemoryMap.AllRam);
        AnalysisRoutineSummary summary = contracts.Analyzed(0x1000) ?? throw new AssertFailedException("No analysis.");
        uint mask = CpuCatalog.Get(cpu).Description.RegisterMask(register);
        bool claimed = summary is { Returns: true, Incomplete: null } && (summary.KeptRegisters & mask) == mask;
        claimed.Should().BeFalse($"{register} is not kept, but the analysis says so");

        (contracts, _) = Analyze(source, cpu, map: null);
        summary = contracts.Analyzed(0x1000) ?? throw new AssertFailedException("No analysis.");
        claimed = summary is { Returns: true, Incomplete: null } && (summary.KeptRegisters & mask) == mask;
        claimed.Should().BeFalse($"{register} is not kept, but the analysis without a map says so");
    }

    private static IReadOnlyDictionary<ushort, bool> Fixed(AnalysisContracts contracts, ushort address) =>
        (contracts.Analyzed(address) ?? throw new AssertFailedException("No analysis.")).FixedConditions;

    private static (AnalysisContracts Contracts, AnalysisContractReport Report) Analyze(string source, string cpu, MemoryMap? map)
    {
        string path = Path.Join(AppContext.BaseDirectory, $"Soundness.{cpu}.asm");
        AssemblyResult result = new Retrocore.Assembler.Assembler().Assemble(
            new AssemblySource(source, path),
            new AssemblyOptions(cpu, 0x1000, 0x100));

        result.Diagnostics.Should().BeEmpty();
        DocumentationSet documentation = DocumentationSet.Create([DocumentationParser.Parse(source, path)], result);
        AnalysisContracts contracts = new(result, documentation, CpuCatalog.Get(cpu), map: map);
        return (contracts, contracts.Check());
    }
}
