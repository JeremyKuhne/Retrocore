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
        return Retrocore.Debug.DebugContracts.Build(
            new DocumentationResolver(documentation), model: "", new DebugRegisters(M6502Isa.Description));
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
