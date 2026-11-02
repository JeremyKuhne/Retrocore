// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  Merlin 8/Pro source and byte comparisons with the approved Merlin32 reference.
/// </summary>
[TestClass]
public partial class MerlinFrontendTests
{
    /// <summary>
    ///  Arithmetic, string modes, local labels and expansion retain real reference bytes.
    /// </summary>
    /// <param name="body">The common reference syntax.</param>
    [TestMethod]
    [DataRow("""
        Entry   LDA #1+2*3
                DFB 1, 2
                ASC "AB"00
                DCI 'AB'
                INV 'AB'
                FLS 'AB'
                REV 'AB'
                STR 'AB'
                DFB "A",'A'
                RTS
        """)]
    [DataRow("""
        Entry   NOP
        :loop   LDA #<Entry+256
                LDX #>Entry+256
                LDY #^Entry
                BNE :loop
                DA Entry
                DDB Entry
                HEX 012345,6789AB
        """)]
    [DataRow("""
        Emit    MAC
        Again   LDA #]1
                BNE Again
                EOM
        Entry   PMC Emit,1
                PMC Emit,2
                LUP 3
                DFB 4
                --^
        """)]
    [DataRow("""
        ]count  = 2
        Entry   DFB ]count
        ]count  = ]count+1
                DO ]count=3
                DFB ]count
                ELSE
                ERR 1
                FIN
                DUM $20
        Buffer  DS 4
                DEND
                LDA Buffer
                CHK
        """)]
    [DataRow("""
        Entry   NOP
        ?table  DFB $12
                DA ?table
                ASC "A",'B',27,'C',00
                DCI 'AB',00
                INV "AB"
                FLS "AB"
                REV "AB"
                STR "AB"
                IF A=A
                DFB 1
                ELSE
                DFB 2
                FIN
                XC
                STZ $20
        """)]
    [DataRow("""
        Entry   LDX Stack
        Stack   EQU #$FF
        Unused  EQU 0D
                DFB 1
        """)]
    [DataRow("""
        Entry   REV 'AB'
                STR 'AB',00
                STR 'A','B'
                DCI 'A',"B",00
        """)]
    [DataRow("""
        Entry   NOP
        Here    EQU *
                NOP
                JMP Here
                JMP Later
        Later   EQU *+2
                DA Later
        """)]
    [DataRow("""
        Load    MAC
                LDA ]1
                DFB ]0
                EOM
        Entry   Load ($06),Y
                Load #5;2;3
                LDA: $10
                STA~ $10,X
                JMP: $10
        """)]
    [DataRow("""
        Entry   DFB -1,$1234,<$1234+1,>$1234+1,^$123456
                LDA #$1234
                LDA #-1
                DA $12345,-1,>Entry,<Entry
                DW $1234
                DDB -1
                ADR $123456
                ADRL $12345678
                BRK
                BRK $12
                BRK #$34
                XCE
        """)]
    [DataRow("""
        Entry   LUP 3
        Step@   NOP
                --^
        Unused  EQU $1234
        Missing EQU Undefined
        """)]
    public void MerlinSourcesMatchReference(string body)
    {
        MerlinAssembly reference = MerlinToolchain.Assemble(body);
        AssemblyResult actual = new NativeAssembler().Assemble(
            new AssemblySource(body, "main.s"),
            new(ProcessorVariant.Mos6502, 0x1000, 0x1000) { Dialect = AssemblyDialect.Merlin });

        actual.Diagnostics.Should().BeEmpty();
        actual.Files.Single().Value.ToArray().Should().Equal(reference.Bytes);
        actual.Symbols["Entry"].Should().Be(reference.Symbols["Entry"]);
    }

    /// <summary>
    ///  As in Merlin 32, only the master file's PUT and USE lines include files: PUT inserts its file each time,
    ///  USE loads a macro file once, nested ones are ignored, and a name without .s finds the .s file.
    /// </summary>
    [TestMethod]
    public void IncludesFollowMerlin32()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-merlin-include-").FullName;
        try
        {
            File.WriteAllText(Path.Join(directory, "part.s"), "        DFB $AA\n        PUT missing\n        PUT inner\n");
            File.WriteAllText(Path.Join(directory, "inner.s"), "        DFB $CC\n");
            File.WriteAllText(Path.Join(directory, "lib.Macs.s"), "Twice   MAC\n        DFB ]1,]1\n        EOM\n");
            string main = Path.Join(directory, "main.s");
            File.WriteAllText(main, """
                        ORG $1000
                        DSK output.bin
                        TYP $06
                        USE lib.Macs
                        USE lib.Macs
                Entry   PUT part
                        PUT part.s
                        Twice $BB
                """);

            MerlinAssembly reference = MerlinToolchain.AssembleFile(main, "output.bin");
            AssemblyResult actual = new NativeAssembler().Assemble(
                new AssemblySource(File.ReadAllText(main), main),
                new(ProcessorVariant.Mos6502, 0x1000, 0x1000)
                {
                    Dialect = AssemblyDialect.Merlin,
                    SourceResolver = new FileAssemblySourceResolver()
                });

            actual.Diagnostics.Should().BeEmpty();
            actual.Files["output.bin"].ToArray().Should().Equal(reference.Bytes);
            reference.Bytes.Should().Equal(0xAA, 0xAA, 0xBB, 0xBB);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  An unused EQU is published when it compiles and dropped when it cannot, as Merlin 32 accepts either.
    /// </summary>
    [TestMethod]
    public void UnusedEquatesArePublishedWhenTheyCompile()
    {
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource("Entry   NOP\nUnused  EQU $1234\nChained EQU Unused+1\nText    EQU 0D\nMissing EQU Undefined"),
            new(ProcessorVariant.Mos6502, 0x1000, 16) { Dialect = AssemblyDialect.Merlin });

        result.Diagnostics.Should().BeEmpty();
        result.Symbols["Unused"].Should().Be(0x1234);
        result.Symbols["Chained"].Should().Be(0x1235);
        result.Symbols.Should().NotContainKey("Text").And.NotContainKey("Missing");
    }

    /// <summary>
    ///  The approved, source-only BIOS/JMON corpus is compared without downloading a ROM or BASIC.
    /// </summary>
    [TestMethod]
    public void ApprovedBiosAndMonitorCorpusMatchesReference()
    {
        string source = Environment.GetEnvironmentVariable("RETROCORE_MERLIN_CORPUS")
            ?? Path.Join(
                ExternalTestData.Root,
                "m1-dependencies",
                "merlin-sbc-a487813378a05d7230326373fdee77cb8e1f7613");

        if (!Directory.Exists(source))
        {
            Assert.Inconclusive("Set RETROCORE_MERLIN_CORPUS to the approved source-only corpus.");
        }

        string stage = Directory.CreateTempSubdirectory("retrocore-merlin-corpus-").FullName;
        try
        {
            foreach (string file in Directory.GetFiles(source, "*", SearchOption.AllDirectories))
            {
                string destination = Path.Join(stage, Path.GetRelativePath(source, file));
                Directory.CreateDirectory(Path.GetDirectoryName(destination) ?? throw new InvalidOperationException());
                File.Copy(file, destination);
            }

            File.Copy(Path.Join(stage, "jmon.Macs.s"), Path.Join(stage, "Monitor", "jmon.Macs.s"));
            Directory.CreateDirectory(Path.Join(stage, "BASIC"));
            File.WriteAllText(Path.Join(stage, "BASIC", "Basic.s"), "");
            MerlinAssembly reference = MerlinToolchain.AssembleFile(Path.Join(stage, "ROM.s"), "JAVA1.bin");
            // The monitor probes for a 65816 with XCE, which Merlin 32 assembles in every mode.
            AssemblyResult actual = new NativeAssembler().Assemble(
                new AssemblySource(File.ReadAllText(Path.Join(stage, "ROM.s")), Path.Join(stage, "ROM.s")),
                new(ProcessorVariant.Wdc65C02, 0xD000, 0x3000)
                {
                    Dialect = AssemblyDialect.Merlin,
                    SourceResolver = new FileAssemblySourceResolver()
                });

            actual.Diagnostics.Should().BeEmpty();
            IEnumerable<string> differences = reference.Symbols.Where(
                pair => actual.Symbols.TryGetValue(
                    pair.Key,
                    out long value) && value != pair.Value)
                .OrderBy(pair => pair.Value).Take(12).Select(pair => $"{pair.Key}: ${pair.Value:X}/${actual.Symbols[pair.Key]:X}");

            actual.Files["JAVA1.bin"].ToArray().Should().Equal(reference.Bytes, string.Join("; ", differences));
            reference.Bytes.Length.Should().Be(0x3000);
            actual.Symbols["RESET"].Should().Be(reference.Symbols["RESET"]);
        }
        finally
        {
            Directory.Delete(stage, recursive: true);
        }
    }

    /// <summary>
    ///  High-bit text decoding preserves CR source lines and the explicit dialect.
    /// </summary>
    [TestMethod]
    public void DiskTextClearsHighBitsAndPadding()
    {
        AssemblySource source = MerlinText.Decode([0xA0, 0xCE, 0xCF, 0xD0, 0x8D, 0, 0], "disk.S");
        source.Text.Should().Be(" NOP\r");
        source.Dialect.Should().Be(AssemblyDialect.Merlin);
    }

    /// <summary>
    ///  Unsupported CPU modes and malformed source produce physical diagnostics, not partial files.
    /// </summary>
    /// <param name="text">Invalid Merlin source.</param>
    /// <param name="message">The required error text.</param>
    [TestMethod]
    [DataRow("        XC\n        XC", "65816")]
    [DataRow("        MX %11", "65816")]
    [DataRow("        XCE $12", "no operand")]
    [DataRow("        LDAL $1234", "long addressing")]
    [DataRow("        IF MX=1\n        FIN", "65816")]
    [DataRow("        HEX 0", "pairs")]
    [DataRow("        ASC 'unterminated", "Unterminated")]
    [DataRow("        ERR 1", "assertion")]
    [DataRow("        LUP 999999999\n        NOP\n        --^", "Repeat")]
    public void InvalidMerlinSourceIsDiagnosed(string text, string message)
    {
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource(text, "bad.S"),
            new(ProcessorVariant.Mos6502, 0x1000, 0x1000) { Dialect = AssemblyDialect.Merlin });

        result.Success.Should().BeFalse();
        result.Files.Should().BeEmpty();
        result.Diagnostics.Should().Contain(diagnostic => diagnostic.Message.Contains(message, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>
    ///  Alias and output snapshots stay independent of subsequent model edits.
    /// </summary>
    [TestMethod]
    public void AliasesAndFilesAreIndependentSnapshots()
    {
        AssemblyOptions options = new(ProcessorVariant.Mos6502, 0x1000, 16) { Dialect = AssemblyDialect.Merlin };
        AssemblyProject project = NativeAssembler.Parse(new AssemblySource("Entry NOP\n?data DFB 1\n      DA ?data"), options).Project;
        NativeAssembler assembler = new();
        AssemblyResult first = assembler.Assemble(project, options);
        first.Diagnostics.Should().BeEmpty();
        string alias = first.SymbolAliases["?data"];
        first.Symbols[alias].Should().Be(0x1001);
        project.Statements.Single(node => node.Kind == AssemblyStatementKind.Data && node.Operand.Text == "<(1)").Operand = new("2");
        AssemblyResult second = assembler.Assemble(project, options);
        second.Diagnostics.Should().BeEmpty();
        first.Files["output.bin"].Span[1].Should().Be(1);
        second.Files["output.bin"].Span[1].Should().Be(2);
        first.SymbolAliases["?data"].Should().Be(alias);
    }

    /// <summary>
    ///  The legacy bank-byte slash spelling has the same value as Merlin32's caret spelling.
    /// </summary>
    [TestMethod]
    public void LegacyBankByteSpellingMatchesReferenceValue()
    {
        MerlinAssembly reference = MerlinToolchain.Assemble("Entry   LDY #^$123456");
        AssemblyResult actual = new NativeAssembler().Assemble(
            new AssemblySource("Entry   LDY #/$123456"),
            new(ProcessorVariant.Mos6502, 0x1000, 16) { Dialect = AssemblyDialect.Merlin });

        actual.Diagnostics.Should().BeEmpty();
        actual.Files.Single().Value.ToArray().Should().Equal(reference.Bytes);
    }
}
