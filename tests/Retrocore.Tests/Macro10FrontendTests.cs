// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the MACRO-10 front end used for Microsoft's 6502 BASIC source.
/// </summary>
[TestClass]
public sealed class Macro10FrontendTests
{
    /// <summary>
    ///  M6502 instructions, data pseudo-ops and MACRO-10 structure assemble to the same bytes as native source.
    /// </summary>
    /// <param name="macro10">The MACRO-10 source, placed at $1000.</param>
    /// <param name="native">The equivalent native source.</param>
    [TestMethod]
    [DataRow(
        """
        RADIX 10
        ZP=16
        START:	LDAI	65
        	LDA	ZP
        	LDA	ZP,X
        	LDA	300,Y
        	LDADY	ZP
        	LDADX	ZP
        	JMPD	^O1000
        	ASL	A
        	ROL	A,
        	LDA	300,X,
        	STY	3,X,
        	BNE	START
        	BEQ	.+4
        	RTS

        """,
        """
        start: lda #65
          lda $10
          lda $10,x
          lda 300,y
          lda ($10),y
          lda ($10,x)
          jmp ($200)
          asl a
          rol a
          lda 300,x
          sty 3,x
          bne start
          beq *+4
          rts

        """)]
    [DataRow(
        """
        RADIX 8
        FLAG==1
        IFN FLAG,<
        	LDAI	10>IFE FLAG,<LDAI 1>
        DEFINE	LDWD	(WD),<
        	LDA	WD
        	LDY	<WD>+1>
        DEFINE	DT(Q),<
        IRPC	Q,<IFDIF <Q><">,<EXP "Q">>>
        	LDWD	20
        	DT"HI"
        	REPEAT	2,<NOP>
        Q=1
        Q=Q+1
        	EXP	Q,^D10,12.,<3_2>
        	XWD	^O1000,^O251
        	ADR(LONGNAME)
        DCI"AB"
        	BLOCK	2
        IF1,<LDAI 1>
        IF2,<LDAI 2>
        IFNDEF NONE,<LDAI 3>
        IFDEF FLAG,<LDAI 4>
        COMMENT * IGNORED <
        TEXT *
        LONGNAME: RTS
        	JMP	LONGNA

        """,
        """
          lda #8
          lda $10
          ldy $11
          .byte 'H', 'I'
          nop
          nop
          .byte 2, 10, 12, 12
          .byte $A9
          .word longna
          .byte 'A', 'B' | $80
          .res 2
          lda #2
          lda #3
          lda #4
        longna: rts
          jmp longna

        """)]
    public void ConstructsMatchNativeSource(string macro10, string native)
    {
        string source = $"DEFINE DCI(A),<DC(A)>\n\tORG\t^O10000\n{macro10}";
        AssemblyResult actual = new NativeAssembler().Assemble(
            new AssemblySource(source, "test.mac", AssemblyDialect.Macro10),
            new(ProcessorVariant.Mos6502, 0x1000, 0x100));

        AssemblyResult expected = new NativeAssembler().Assemble(new AssemblySource(native), new(ProcessorVariant.Mos6502, 0x1000, 0x100));
        actual.Diagnostics.Should().BeEmpty();
        expected.Diagnostics.Should().BeEmpty();
        Emitted(actual).Should().Equal(Emitted(expected));
    }

    /// <summary>
    ///  Conditionals may depend on label addresses, as BASIC's input buffer check does, so the expander lays code
    ///  out as the native assembler will.
    /// </summary>
    [TestMethod]
    public void ConditionalsSeeLabelAddresses()
    {
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource(
                """
                	ORG	^D250
                BUF:	BLOCK	4
                	LDA	BUF
                IFN	<<BUF+10>/^D256>-<BUF/^D256>,<
                	NOP>
                IFE	<<BUF+1>/^D256>-<BUF/^D256>,<
                	RTS>

                """,
                "test.mac",
                AssemblyDialect.Macro10),
            new(ProcessorVariant.Mos6502, 0, 0x200));

        result.Diagnostics.Should().BeEmpty();
        Emitted(result).Should().Equal(0, 0, 0, 0, 0xA5, 0xFA, 0xEA, 0x60);
    }

    /// <summary>
    ///  Lines from a DEFINE's body are macro expansions of the call, which the debugger steps through; conditional
    ///  and repeat bodies keep their own lines.
    /// </summary>
    [TestMethod]
    public void MacroBodiesAreExpansionsOfTheirCall()
    {
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource(
                """
                DEFINE	PAIR,<
                	INX
                	INY>
                	ORG	^O10000
                	PAIR
                IFE	0,<
                	NOP>

                """,
                "test.mac",
                AssemblyDialect.Macro10),
            new(ProcessorVariant.Mos6502, 0x1000, 0x100));

        result.Diagnostics.Should().BeEmpty();
        IEnumerable<AssemblySourceMapEntry> emitted = result.SourceMap.Where(entry => entry.Size != 0);
        AssemblyLocation[] locations = [.. emitted.Select(entry => entry.Location).OfType<AssemblyLocation>()];
        locations.Should().HaveCount(3);
        locations[0].IsMacroExpansion.Should().BeTrue();
        locations[0].Line.Should().Be(1);
        locations[0].ExpandedFrom?.Line.Should().Be(4);
        locations[1].Line.Should().Be(2);
        locations[2].IsMacroExpansion.Should().BeFalse();
        locations[2].Line.Should().Be(6);
    }

    /// <summary>
    ///  Names native syntax cannot spell get aliases, and symbols are significant to six characters.
    /// </summary>
    [TestMethod]
    public void NamesFollowMacro10()
    {
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource("\tORG\t^O10000\n$Z::\tNOP\nZSTORDO=$Z\n\tJMP\tZSTORD\n", "test.mac", AssemblyDialect.Macro10),
            new(ProcessorVariant.Mos6502, 0x1000, 0x100));

        result.Diagnostics.Should().BeEmpty();
        result.SymbolAliases.Should().ContainKey("$Z");
        result.Symbols["ZSTORD"].Should().Be(0x1000);
        Emitted(result).Should().Equal(0xEA, 0x4C, 0x00, 0x10);
    }

    /// <summary>
    ///  An overlay edits a pinned base, and each composed line keeps the file and line it came from.
    /// </summary>
    [TestMethod]
    public void OverlaysEditTheirBase()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-overlay-").FullName;
        try
        {
            string basePath = Path.Join(directory, "base.mac");
            string baseText = "\tORG\t^O10000\n\tLDAI\t1\n\tLDAI\t2\n\tLDAI\t3\n\tLDAI\t4";
            File.WriteAllText(basePath, baseText);
            string hash = Macro10Overlay.Hash(baseText);
            string overlay = $"""
                ; retrocore: dialect=macro10 overlay=base.mac sha256={hash}
                ; Apple's changes.
                ;@REPLACE 2-2
                	LDAI	9
                ;@END
                ;@INSERT AFTER 3
                	NOP
                ;@END
                ;@DELETE 4
                """;

            string overlayPath = Path.Join(directory, "overlay.mac");
            File.WriteAllText(overlayPath, overlay);
            AssemblyResult result = AssembleFile(overlayPath);

            result.Diagnostics.Should().BeEmpty();
            Emitted(result).Should().Equal(0xA9, 9, 0xA9, 2, 0xEA, 0xA9, 4);
            IEnumerable<AssemblySourceMapEntry> code = result.SourceMap.Where(entry => entry.Size != 0 && entry.Operation != ".ORG");
            AssemblyLocation?[] locations = [.. code.Select(entry => entry.Location)];
            locations.Select(location => (Path.GetFileName(location?.Path), location?.Line)).Should().Equal(
                ("overlay.mac", 3),
                ("base.mac", 2),
                ("overlay.mac", 6),
                ("base.mac", 4));

            File.WriteAllText(basePath, baseText + "\n\tNOP");
            AssembleFile(overlayPath).Diagnostics.Should().ContainSingle().Which.Message.Should().Contain("SHA-256");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  Errors report the line they occur on.
    /// </summary>
    [TestMethod]
    public void ErrorsReportTheirLine()
    {
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource("\tORG\t^O10000\n\tNOP\nIFE\tUNDEFD,<NOP>\n", "test.mac", AssemblyDialect.Macro10),
            new(ProcessorVariant.Mos6502, 0x1000, 0x100));

        result.Diagnostics.Should().ContainSingle().Which.Location?.Line.Should().Be(2);
    }

    /// <summary>
    ///  Microsoft's published BASIC 1.1 source builds for KIM-1 and Apple, and matches the surviving 1.1 releases
    ///  wherever the source revisions agree.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The published source is a later revision than either release: its change log adds "GO TO", the space
    ///   check in reserved words and several fixes, and AppleSoft I adds Apple's own statements. So the test
    ///   builds each release's configuration (RAM, long error messages) and requires most of the release's bytes
    ///   to appear in runs of eight or more, which only correct instruction encoding and zero-page layout give.
    ///  </para>
    /// </remarks>
    /// <param name="target">The REALIO machine number.</param>
    /// <param name="release">The msbasic reference binary.</param>
    /// <param name="origin">The release's load address.</param>
    /// <param name="coverage">The fraction of the release's bytes that must match.</param>
    [TestMethod]
    [DataRow(1, "kb9.bin", 0x2000, 0.75)]
    [DataRow(4, "applesoft.bin", 0x0800, 0.62)]
    public void MicrosoftBasicMatchesItsReleases(int target, string release, int origin, double coverage)
    {
        string root = Path.Join(ExternalTestData.Root, "m1-dependencies");
        string source = Path.Join(root, "BASIC-M6502-7460af2c03ae19c0e60ff327489229d2005b9357", "m6502.asm");
        string reference = Path.Join(root, "msbasic-2a0bc2fe", "orig", release);
        if (!File.Exists(source) || !File.Exists(reference))
        {
            Assert.Inconclusive("Run tools\\Fetch-M1Dependencies.ps1 for the BASIC source and msbasic references.");
        }

        string text = File.ReadAllText(source)
            .Replace("REALIO=4", $"REALIO={target}", StringComparison.Ordinal)
            .Replace("LNGERR==0", "LNGERR==1", StringComparison.Ordinal)
            .Replace("ROMSW==1", "ROMSW==0", StringComparison.Ordinal);

        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource(text, source, AssemblyDialect.Macro10),
            new(ProcessorVariant.Mos6502, 0, 0x10000));

        result.Diagnostics.Should().BeEmpty();
        int end = result.SourceMap.Where(entry => entry.Size != 0).Max(entry => entry.Address + entry.Size);
        byte[] ours = result.Sections[0].Bytes[origin..end].ToArray();
        byte[] expected = File.ReadAllBytes(reference);

        HashSet<ulong> windows = [];
        for (int index = 0; index + 8 <= ours.Length; index++) { windows.Add(BitConverter.ToUInt64(ours, index)); }
        bool[] covered = new bool[expected.Length];
        for (int index = 0; index + 8 <= expected.Length; index++)
        {
            if (!windows.Contains(BitConverter.ToUInt64(expected, index))) { continue; }
            Array.Fill(covered, value: true, index, 8);
        }

        ((double)covered.Count(value => value) / expected.Length).Should().BeGreaterThanOrEqualTo(coverage);
    }

    private static AssemblyResult AssembleFile(string path) =>
        new NativeAssembler().Assemble(
            new AssemblySource(File.ReadAllText(path), path),
            new(ProcessorVariant.Mos6502, 0x1000, 0x100) { SourceResolver = new FileAssemblySourceResolver() });

    private static byte[] Emitted(AssemblyResult result)
    {
        // Origin padding is not code; reserved space counts, as its bytes sit between the code.
        AssemblySourceMapEntry[] entries = [.. result.SourceMap.Where(entry => entry.Size != 0 && entry.Operation != ".ORG")];
        int start = entries.Min(entry => entry.Offset);
        int end = entries.Max(entry => entry.Offset + entry.Size);
        return result.Sections[0].Bytes[start..end].ToArray();
    }
}
