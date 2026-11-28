// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Documentation;

namespace Retrocore.Tests;

/// <summary>
///  The static <c>Keeps:</c> and <c>Uses:</c> check: a routine's code followed with the instruction-set
///  descriptions' effects, each call taking its callee's contract.
/// </summary>
[TestClass]
public class ContractAnalysisTests
{
    /// <summary>
    ///  A register saved with a push and restored with a pull is kept; one changed is a finding at the instruction
    ///  that changes it.
    /// </summary>
    [TestMethod]
    public void PushesAndPullsKeepWhatTheySave()
    {
        const string Source = """
            ;; Saves A and changes X.
            ;; Keeps: A, X
            Saver:
                pha
                lda #1
                ldx #2
                pla
                rts
            """;

        (List<string> findings, int count, _) = Check(Source, "Mos6502");
        count.Should().Be(1);
        findings.Should().Equal("Saver ($1000) documents Keeps: X, but X is changed by the instruction at $1003.");
    }

    /// <summary>
    ///  With a <c>Uses:</c> section, a register changed that it, <c>Out:</c> and <c>Keeps:</c> do not list is a
    ///  finding; flags and S are not, and what is listed is not.
    /// </summary>
    [TestMethod]
    public void UsesListsEveryChangedRegister()
    {
        const string Source = """
            ;; Changes A, X and Y.
            ;; Out:  X = a count
            ;; Uses: A
            Changer:
                lda #1
                ldx #2
                ldy #3
                rts
            """;

        Check(Source, "Mos6502").Findings.Should().Equal(
            "Changer ($1000) changes Y by the instruction at $1004, which its Uses:, Out: and Keeps: do not list.");
    }

    /// <summary>
    ///  A call takes the callee's documented contract; a call to undocumented code takes that code's analysis, and
    ///  the finding is at the call.
    /// </summary>
    [TestMethod]
    public void CallsTakeTheCalleesContract()
    {
        const string Source = """
            ;; Calls a routine that keeps X, then code that changes Y.
            ;; Keeps: X, Y
            Caller:
                jsr Kept
                jsr Plain
                rts
            ;; Promises to keep X and Y.
            ;; Keeps: X, Y
            Kept:
                lda #0
                rts
            Plain:
                ldy #0
                rts
            """;

        Check(Source, "Mos6502").Findings.Should().Equal(
            "Caller ($1000) documents Keeps: Y, but Y is changed by the instruction at $1003.");
    }

    /// <summary>
    ///  A branch or jump to another documented routine is a tail call, which takes its contract and returns.
    /// </summary>
    [TestMethod]
    public void JumpsToRoutinesAreTailCalls()
    {
        const string Source = """
            ;; Ends in a routine that keeps X, or in one that changes it.
            ;; Keeps: X
            Caller:
                lda $10
                beq Kept
                jmp Changes
            ;; Keeps X.
            ;; Keeps: X
            Kept:
                rts
            ;; Changes X.
            ;; Uses: X
            Changes:
                ldx #0
                rts
            """;

        Check(Source, "Mos6502").Findings.Should().Equal(
            "Caller ($1000) documents Keeps: X, but X is changed by the instruction at $1004.");
    }

    /// <summary>
    ///  An <c>Entry:</c> whose meaning ends in <c>; keeps ...</c> promises that from there, in place of the
    ///  routine's <c>Keeps:</c>: an entry that skips the save keeps less, and is checked for what it says.
    /// </summary>
    [TestMethod]
    public void EntriesKeepWhatTheirClauseSays()
    {
        // Narrower than Keeps: and checked for what it says: from Change A is changed and X is kept, as its clause
        // says, but Y, which the clause names, is not.
        const string Wrong = """
            ;; Returns, or from Change clears A and Y first.
            ;; Keeps: A, X, Y
            ;; Entry: Change = clears A and Y; keeps X, Y
            Saver:
                rts
            Change:
                lda #0
                ldy #0
                rts
            """;

        (List<string> findings, _, _) = Check(Wrong, "Mos6502");
        findings.Should().Equal("Saver ($1000) documents that its entry Change keeps Y, but Y is changed by the instruction at $1003.");

        const string Right = """
            ;; Returns, or from Change clears X first.
            ;; Keeps: X
            ;; Entry: Change = clears X; keeps nothing
            Saver:
                rts
            Change:
                ldx #0
                rts
            """;

        (findings, int count, _) = Check(Right, "Mos6502");
        findings.Should().BeEmpty();
        count.Should().Be(1);

        // An entry with a comment of its own is a routine of its own: the routine's Keeps: does not reach it.
        const string Own = """
            ;; Returns.
            ;; Keeps: X
            ;; Entry: Clear = clears X first
            Saver:
                rts

            ;; Clears X and returns.
            Clear:
                ldx #0
                rts
            """;

        (findings, _, _) = Check(Own, "Mos6502");
        findings.Should().BeEmpty();

        // One with a contract of its own is checked for that. TYA copies the value LDY #0 made, so A is changed
        // there.
        const string OwnContract = """
            ;; Returns.
            ;; Keeps: X
            ;; Entry: Clear = clears X and Y first
            Saver:
                rts

            ;; Clears X and Y and returns.
            ;; Keeps: A
            Clear:
                ldx #0
                ldy #0
                tya
                rts
            """;

        (findings, _, _) = Check(OwnContract, "Mos6502");
        findings.Should().Equal("Clear ($1001) documents Keeps: A, but A is changed by the instruction at $1003.");

        // A label with no comment at the same address as an entry with a clause takes the clause.
        const string Shared = """
            ;; Returns, or from Later or Clause clears X.
            ;; Keeps: X
            ;; Entry:
            ;;   Later = clears X
            ;;   Clause = clears X; keeps nothing
            Saver:
                rts
            Later:
            Clause:
                ldx #0
                rts
            """;

        (findings, _, _) = Check(Shared, "Mos6502");
        findings.Should().BeEmpty();
        Dictionary<ushort, DebugContract> contracts = DebugContracts(Shared);
        contracts.Should().NotContainKey(0x1001, "the debugger checks nothing at the shared address either");
        contracts[0x1000].Registers.Should().Equal("X");
    }

    /// <summary>
    ///  An entry that keeps its promise only with what its callers pass, as the MOS's SET_STATUS_BITS with a bit set
    ///  in A, is checked with each caller's values, from the start of each call's run of code: from Set, ORA with
    ///  A = 0 and $10 = 0 would fall into LDX #0, but every caller loads A with a bit set. One caller passing 0, a
    ///  run another way into which is not seen, or a table or number that also holds Set's address, leaves the
    ///  finding.
    /// </summary>
    [TestMethod]
    public void EntriesAreCheckedWithTheirCallersValues()
    {
        const string Callee = """

            ;; Sets bits in $10's value.
            ;; Keeps: X
            ;; Entry: Set = sets the bits set in A, which must have a bit set
            Main:
                lda #2
            Set:
                ora $10
                bne Done                ; always taken
                ldx #0
            Done:
                rts
            """;

        // A documented caller, and one no documented routine reaches.
        string good = """
            ;; Sets bit 0.
            ;; Uses: A
            Caller:
                lda #1
                jsr Set
                rts

            Unreached:
                lda #$80
                jsr Set
                rts
            """ + Callee;

        (List<string> findings, _, _) = Check(good, "Mos6502");
        findings.Should().BeEmpty();

        string zero = """
            ;; Sets nothing.
            ;; Uses: A
            Caller:
                lda #0
                jsr Set
                rts
            """ + Callee;

        (findings, _, _) = Check(zero, "Mos6502");
        findings.Should().ContainSingle().Which.Should().Contain("Main ($1006) documents Keeps: X");

        string table = """
            ;; Sets bit 0.
            ;; Uses: A
            Caller:
                lda #1
                jsr Set
                rts

            Table:
                .word Set
            """ + Callee;

        (findings, _, _) = Check(table, "Mos6502");
        findings.Should().ContainSingle().Which.Should().Contain("Main ($1008) documents Keeps: X");

        // A call whose run other code also enters, here at Mid with A = 0, is seen from the run's start, with
        // nothing known.
        string middle = """
            ;; Sets bit 0.
            ;; Uses: A
            Caller:
                lda #1
            Mid:
                jsr Set
                rts

            Vector:
                lda #0
                jmp Mid
            """ + Callee;

        (findings, _, _) = Check(middle, "Mos6502");
        findings.Should().ContainSingle().Which.Should().Contain("Main ($100B) documents Keeps: X");

        // A run that a skip may fall into, as .byte $2C hiding LDA #1 from the code before it, is not seen.
        string skip = """
            ;; Sets bit 0, or from the skip nothing.
            ;; Uses: A
            Caller:
                lda #0
                .byte $2C
            Other:
                lda #1
                jsr Set
                rts
            """ + Callee;

        (findings, _, _) = Check(skip, "Mos6502");
        findings.Should().ContainSingle().Which.Should().Contain("Main ($1009) documents Keeps: X");

        // An address written as a number may be entered or called through it: an offset into a caller's run, as
        // Caller+2, starts a run there, and the entry's own address as a plain number keeps the finding.
        string offset = """
            ;; Sets bit 0.
            ;; Uses: A
            Caller:
                lda #1
                nop
                jsr Set
                rts

            Table:
                .word Caller+2
            """ + Callee;

        (findings, _, _) = Check(offset, "Mos6502");
        findings.Should().ContainSingle().Which.Should().Contain("Main ($1009) documents Keeps: X");

        string number = """
            ;; Sets bit 0.
            ;; Uses: A
            Caller:
                lda #1
                jsr Set
                rts

            Table:
                .word $100A
            """ + Callee;

        (findings, _, _) = Check(number, "Mos6502");
        findings.Should().ContainSingle().Which.Should().Contain("Main ($1008) documents Keeps: X");

        // A caller's run a store may change is not as assembled.
        string patched = """
            ;; Sets bit 0, unless Patcher changed it.
            ;; Uses: A
            Caller:
                lda #1
                jsr Set
                rts

            ;; Changes Caller's bit.
            ;; Uses: A
            Patcher:
                lda #0
                sta Caller+1
                rts
            """ + Callee;

        (findings, _, _) = Check(patched, "Mos6502");
        findings.Should().ContainSingle().Which.Should().Contain("Main ($100C) documents Keeps: X");

        // A jump into the middle of an instruction of a caller's run, here to CMP #$EA's operand, a NOP, comes in
        // with A = 0, so that run is not seen.
        string hidden = """
            ;; Sets bit 0.
            ;; Uses: A
            Caller:
                lda #1
                cmp #$EA
                jsr Set
                rts

            Other:
                lda #0
                jmp Caller+3
            """ + Callee;

        (findings, _, _) = Check(hidden, "Mos6502");
        findings.Should().ContainSingle().Which.Should().Contain("Main ($100D) documents Keeps: X");

        // A jump to the entry from other code may follow a pushed return address, as a call: the finding stands.
        string pushed = """
            ;; Sets bit 0.
            ;; Uses: A
            Caller:
                lda #1
                jsr Set
                rts

            Back:
                rts

            Pusher:
                lda #>(Back-1)
                pha
                lda #<(Back-1)
                pha
                lda #0
                jmp Set
            """ + Callee;

        (findings, _, _) = Check(pushed, "Mos6502");
        findings.Should().ContainSingle().Which.Should().Contain("Main ($1012) documents Keeps: X");

        // Code from another routine that falls into the entry may too.
        string falls = """
            ;; Sets bit 0.
            ;; Uses: A
            Caller:
                lda #1
                jsr Set
                rts

            ;; Returns, or from Set sets bits.
            ;; Keeps: X
            ;; Entry: Set = sets the bits set in A, which must have a bit set
            Main:
                rts

            Other:
                lda #0
            Set:
                ora $10
                bne Done
                ldx #0
            Done:
                rts
            """;

        (findings, _, _) = Check(falls, "Mos6502");
        findings.Should().ContainSingle().Which.Should().Contain("Main ($1006) documents Keeps: X");

        // Text after a return, just before a caller's run, which only a label names, is no way into it; nor is an
        // equate whose value falls inside one of its instructions.
        string text = """
            Thing = $1008

            ;; Reads the text's end, which a load names but no code runs into.
            ;; Uses: A
            Peek:
                lda Message+2
                rts

            Message:
                .byte "OK", 0

            ;; Sets bit 0.
            ;; Uses: A
            Caller:
                lda #1
                jsr Set
                rts
            """ + Callee;

        (findings, _, _) = Check(text, "Mos6502");
        findings.Should().BeEmpty();

        // A number may point at data before a run, as a vector JMP (Vector) goes to, where a skip may run into it.
        string vector = """
            ;; Goes through the vector.
            ;; Uses: A
            Start:
                jmp (Vector)

            Vector:
                .word $1005
                .byte $2C

            ;; Sets bit 0.
            ;; Uses: A
            Caller:
                lda #1
                jsr Set
                rts
            """ + Callee;

        (findings, _, _) = Check(vector, "Mos6502");
        findings.Should().ContainSingle().Which.Should().Contain("Main ($100C) documents Keeps: X");

        // An exported entry may be called by programs outside the assembly, with any values.
        string exported = """
            .export Set

            ;; Sets bit 0.
            ;; Uses: A
            Caller:
                lda #1
                jsr Set
                rts
            """ + Callee;

        (findings, _, _) = Check(exported, "Mos6502");
        findings.Should().ContainSingle().Which.Should().Contain("Main ($1006) documents Keeps: X");

        // A jump to the entry is no call: the code that takes it is followed through it, with its own values, and
        // its own contract is checked.
        string jump = """
            ;; Clears nothing, but X.
            ;; Keeps: X
            Other:
                lda #0
                jmp Set
            """ + Callee;

        (findings, _, _) = Check(jump, "Mos6502");
        findings.Should().Contain(finding => finding.StartsWith("Other ($1000) documents Keeps: X", StringComparison.Ordinal));
    }

    /// <summary>
    ///  A WAI from other code goes on into the entry after it, as a fall-through does, so the entry keeps its finding.
    /// </summary>
    [TestMethod]
    public void WaitsFallIntoEntries()
    {
        const string Source = """
            ;; Sets bit 0.
            ;; Uses: A
            Caller:
                lda #1
                jsr Set
                rts

            ;; Returns, or from Set sets bits.
            ;; Keeps: X
            ;; Entry: Set = sets the bits set in A, which must have a bit set
            Main:
                rts

            Other:
                lda #0
                wai
            Set:
                ora $10
                bne Done
                ldx #0
            Done:
                rts
            """;

        (List<string> findings, _, _) = Check(Source, "Wdc65C02");
        findings.Should().ContainSingle().Which.Should().Contain("Main ($1006) documents Keeps: X");
    }

    /// <summary>
    ///  A caller's stack pointer is not passed into an entry it calls, as the call itself moves it: after LDX #$FF and
    ///  TXS, Set's TSX does not see $FF, so CPX #$FF does not decide BEQ.
    /// </summary>
    [TestMethod]
    public void CallersStackPointersAreNotPassedIn()
    {
        const string Source = """
            ;; Resets the stack and calls Set.
            ;; Uses: A, X
            Caller:
                ldx #$FF
                txs
                jsr Set
                rts

            ;; Returns, or from Set clears Y unless the stack is empty.
            ;; Keeps: Y
            ;; Entry: Set = clears Y unless S is $FF
            Main:
                rts
            Set:
                tsx
                cpx #$FF
                beq Done
                ldy #0
            Done:
                rts
            """;

        (List<string> findings, _, _) = Check(Source, "Mos6502");
        findings.Should().Contain(finding => finding.StartsWith("Main ($1007) documents Keeps: Y", StringComparison.Ordinal));
    }

    /// <summary>
    ///  A routine's own contract at its start wins over another routine's entry there, in the check and the
    ///  debugger alike, though the entry's routine comes first: Target keeps A as it says, though Saver lists the
    ///  label at its address as an entry, plain or with a clause; and Target's Keeps: none holds its address too.
    /// </summary>
    [TestMethod]
    public void RoutinesWinOverOtherRoutinesEntries()
    {
        foreach (string entry in (string[])["Alias = clears A", "Alias = clears A; keeps nothing"])
        {
            string source = $"""
                ;; Returns, or from Alias clears A.
                ;; Keeps: X
                ;; Entry: {entry}
                Saver:
                    rts

                ;; Clears A.
                ;; Keeps: A
                Target:
                Alias:
                    lda #0
                    rts
                """;

            (List<string> findings, _, _) = Check(source, "Mos6502");
            findings.Should().Equal("Target ($1001) documents Keeps: A, but A is changed by the instruction at $1001.");
            DebugContracts(source)[0x1001].Registers.Should().Equal("A");
        }

        const string None = """
            ;; Returns.
            ;; Keeps: X
            ;; Entry: Alias = clears A; keeps A
            Saver:
                rts

            ;; Clears A.
            ;; Keeps: none
            Target:
            Alias:
                lda #0
                rts
            """;

        (List<string> none, _, _) = Check(None, "Mos6502");
        none.Should().BeEmpty();
        DebugContracts(None).Should().NotContainKey(0x1001, "Target promises nothing, and holds its address");

        // A keeps clause wins over an earlier routine's plain entry at the same address.
        const string Clause = """
            ;; Returns, or from Alias clears A.
            ;; Keeps: none
            ;; Entry: Alias = clears A
            First:
                rts

            ;; Returns, or from Alias clears A.
            ;; Keeps: X
            ;; Entry: Alias = clears A; keeps A
            Second:
                rts
            Alias:
                lda #0
                rts
            """;

        // A label's own Keeps: in a branch the build leaves out leaves the clause to apply. (The parser keeps only the
        // assembled branch's comment, so this does not reach the sections' conditions, which HasContract follows.)
        const string Conditional = """
            MODEL = 3

            ;; Returns, or from Alias clears A.
            ;; Keeps: X
            ;; Entry: Alias = clears A; keeps A
            Saver:
                rts

            .if MODEL = 1
            ;; Clears A.
            ;; Keeps: A
            .else
            ;; Clears A.
            .endif
            Alias:
                lda #0
                rts
            """;

        (List<string> conditional, _, _) = Check(Conditional, "Mos6502");
        conditional.Should().Equal("Saver ($1000) documents that its entry Alias keeps A, but A is changed by the instruction at $1001.");
        DebugContracts(Conditional)[0x1001].Registers.Should().Equal("A");

        (List<string> clause, _, _) = Check(Clause, "Mos6502");
        clause.Should().Equal("Second ($1001) documents that its entry Alias keeps A, but A is changed by the instruction at $1002.");
        DebugContracts(Clause)[0x1002].Registers.Should().Equal("A");
    }

    /// <summary>
    ///  A path the analysis cannot follow, such as an indirect jump, leaves the routine unchecked, not wrong, even
    ///  where its other paths return.
    /// </summary>
    [TestMethod]
    public void IndirectJumpsLeaveRoutinesUnchecked()
    {
        const string Source = """
            ;; Jumps through a vector.
            ;; Keeps: X
            Dispatch:
                jmp ($0300)
            """;

        (List<string> findings, int count, IReadOnlyList<string> skipped) = Check(Source, "Mos6502");
        findings.Should().BeEmpty();
        count.Should().Be(0);
        skipped.Should().Equal("Dispatch ($1000): it jumps indirectly");

        // With another path that returns, the routine is followed in part: not checked, and what it keeps not
        // verified, though a sure change on the paths followed is still a finding.
        const string Partly = """
            ;; Returns, or jumps through a vector.
            ;; Keeps: X, Y
            Dispatch:
                bcc Done
                jmp ($0300)
            Done:
                ldy #0
                rts
            """;

        (findings, count, skipped) = Check(Partly, "Mos6502");
        findings.Should().ContainSingle().Which.Should().Contain("Keeps: Y");
        count.Should().Be(0);
        skipped.Should().Equal("Dispatch ($1000): followed in part, as it jumps indirectly");
    }

    /// <summary>
    ///  The Z80's PUSH and POP keep a pair, and a flag by its word is checked; the 6809's PSHS and PULS, from their
    ///  postbytes, keep what they list.
    /// </summary>
    [TestMethod]
    public void OtherCpusSaveAndRestore()
    {
        const string Z80 = """
            ;; Saves BC around a change, and changes the carry.
            ;; Keeps: BC, carry
            Saver:
                push bc
                ld b,1
                ld c,2
                pop bc
                scf
                ret
            """;

        Check(Z80, "Z80").Findings.Should().Equal(
            "Saver ($1000) documents Keeps: carry, but carry is changed by the instruction at $1006.");

        const string M6809 = """
            ;; Saves A and X around a change, but not B.
            ;; Keeps: A, X, B
            Saver:
                pshs a,x
                lda #1
                ldb #2
                ldx #3
                puls a,x
                rts
            """;

        Check(M6809, "M6809").Findings.Should().Equal(
            "Saver ($1000) documents Keeps: B, but B is changed by the instruction at $1004.");
    }

    // The debugger's contracts for a 6502 source, by address.
    private static Dictionary<ushort, DebugContract> DebugContracts(string source)
    {
        string path = Path.Join(AppContext.BaseDirectory, "ContractAnalysis.Debugger.asm");
        AssemblyResult result = new Retrocore.Assembler.Assembler().Assemble(
            new AssemblySource(source, path),
            new AssemblyOptions("Mos6502", 0x1000, 0x100));

        result.Diagnostics.Should().BeEmpty();
        DocumentationSet documentation = DocumentationSet.Create([DocumentationParser.Parse(source, path)], result);
        long? Symbol(string name) => result.Symbols.TryGetValue(name, out long value) ? value : null;
        return Retrocore.Debug.DebugContracts.Build(
            new DocumentationResolver(documentation), model: "", new DebugRegisters(M6502Isa.Description), Symbol);
    }

    private static (List<string> Findings, int Checked, IReadOnlyList<string> Skipped) Check(string source, string cpu)
    {
        string path = Path.Join(AppContext.BaseDirectory, $"ContractAnalysis.{cpu}.asm");
        AssemblyResult result = new Retrocore.Assembler.Assembler().Assemble(
            new AssemblySource(source, path),
            new AssemblyOptions(cpu, 0x1000, 0x100));

        result.Diagnostics.Should().BeEmpty();
        DocumentationSet documentation = DocumentationSet.Create([DocumentationParser.Parse(source, path)], result);
        AnalysisContracts contracts = new(result, documentation, CpuCatalog.Get(cpu));
        AnalysisContractReport report = contracts.Check();
        return ([.. report.Findings.Select(finding => finding.ToString())], report.Checked, report.Skipped);
    }
}
