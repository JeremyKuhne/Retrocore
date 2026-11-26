// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Documentation;

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
    ///  The core computes results from known inputs: a count down from a constant, a carry set and added in binary
    ///  mode, a comparison. ADC reads the decimal flag, so without CLD its result is not known.
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
                sec
                lda #$FF
                adc #0
                bcc Change
                cmp #0
                bne Change
                rts
            Change:
                ldy #0
                rts
            """;

        (List<string> findings, AnalysisContracts contracts) = Check(Source, "Mos6502");
        findings.Should().BeEmpty();
        Summary(contracts, 0x1000).FixedConditions.Values.Should().AllBeEquivalentTo(expectation: false);
        Summary(contracts, 0x1000).FixedConditions.Should().HaveCount(3);
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

    private static AnalysisRoutineSummary Summary(AnalysisContracts contracts, ushort address) =>
        contracts.Analyzed(address) ?? throw new AssertFailedException($"No analysis at ${address:X4}.");

    private static (List<string> Findings, AnalysisContracts Contracts) Check(string source, string cpu)
    {
        string path = Path.Join(AppContext.BaseDirectory, $"FlagValues.{cpu}.asm");
        AssemblyResult result = new Retrocore.Assembler.Assembler().Assemble(
            new AssemblySource(source, path),
            new AssemblyOptions(cpu, 0x1000, 0x100));

        result.Diagnostics.Should().BeEmpty();
        DocumentationSet documentation = DocumentationSet.Create([DocumentationParser.Parse(source, path)], result);
        AnalysisContracts contracts = new(result, documentation, CpuCatalog.Get(cpu));
        AnalysisContractReport report = contracts.Check();
        return ([.. report.Findings.Select(finding => finding.ToString())], contracts);
    }
}
