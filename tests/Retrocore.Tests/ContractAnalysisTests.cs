// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
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
        findings.Should().Equal("Saver ($1000) documents Keeps: Y, but Y is changed by the instruction at $1003.");

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
