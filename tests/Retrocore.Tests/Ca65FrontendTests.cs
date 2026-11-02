// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  Actual ca65 sources through the shared compiler and single-object linker.
/// </summary>
[TestClass]
public class Ca65FrontendTests
{
    /// <summary>
    ///  The actual sample and its unchanged ld65 config assemble byte- and symbol-identically.
    /// </summary>
    [TestMethod]
    public void ActualIIeSampleMatchesCa65AndLd65()
    {
        string directory = Path.Join(AppContext.BaseDirectory, "Inputs", "IIe");
        string path = Path.Join(directory, "main.s");
        string config = Path.Join(directory, "link.cfg");
        Ca65Assembly reference = Ca65Toolchain.Require().Assemble(path, config);
        AssemblyResult actual = new NativeAssembler().Assemble(
            new AssemblySource(File.ReadAllText(path), path),
            Options(new(File.ReadAllText(config), config)));

        actual.Diagnostics.Should().BeEmpty();
        reference.AssertMatches(actual.Files["output.bin"].Span, actual.Exports);
        actual.Symbols["counter"].Should().Be(0x6016);
        actual.Sections.Single(section => section.Name == "BSS").Bytes.Length.Should().Be(0);
    }

    /// <summary>
    ///  ca65-only expressions, aliases, scoping and CPU switches match the real assembler.
    /// </summary>
    /// <param name="body">The ca65 syntax to compare.</param>
    [TestMethod]
    [DataRow("""
        .setcpu "6502"
        .code
        .word <$12FF+1, >$12FE+1, ^$FFFE+1
        .word .lobyte($12FF+1),.hibyte($12FE+1),.bankbyte($FFFE+1)
        .byte 1<>0, !0, 3 .mod 2
        .addr Entry
        """)]
    [DataRow("""
        .code
        .org $8000
        .proc Subroutine
        @loop:nop
        bne @loop
        bne :+
        :rts
        .endproc
        .addr Subroutine
        .assert *=$8008,error,"unexpected layout"
        """)]
    [DataRow("""
        .macro Emit value
        lda #value
        .endmac
        .repeat 3, Index
        Emit Index
        .endrepeat
        .pc02
        stz $20
        .psc02
        bra :+
        :rts
        """)]
    [DataRow("""
        .byte .not ^$123456, ^.bankbyte($123456), ^($123456+$10000), <($12FF+1)
        .byte "time.version%^", %1010
        Alias:=Entry
        .word Alias, .version
        """)]
    [DataRow("""
        .word ^:+, ^.hibyte ($123456), ^.not 0
        :nop
        """)]
    [DataRow("""
        .byte 2 | 1 + 1, 1 << 2 + 1, 6 & 3 * 2, 3 ^ 1 + 1, 1 + 4 >> 1, 2 * 3 | 1
        .byte 1 + !0 + 1, .not 1 || 1, 1 .xor 1 .and 0, ! 0 + 1, 1 || 0 && 0
        .byte 1 .shl 2 + 1, 5 .bitand 3 + 1, 5 .bitor 2 * 2, (.bitnot 1 + 1) & $ff, 3 .mod 2 * 2
        .byte <$1234 .shl 1, -<$1234 & $ff, 1 < 2 = 1, (1 <> 2) + 1
        Combined = 2 | 1 + 1
        Assigned := 3 ^ 1 + 1
        .if 2 | 1 + 1 = 4
        .byte Combined, Assigned
        .endif
        .res 2 | 1, $EA
        lda #2 | 1 + 1
        lda ($10 + 1 | 2), y
        lda ($10 | 1 + 1, x)
        """)]
    [DataRow("""
        .mac Twice value
        .byte value * 2
        .endmac
        Twice 1 + 2
        .import __BSS_SIZE__
        .importzp __ZP_START__
        .exportzp ZeroValue
        ZeroValue = $12
        .global GlobalValue
        GlobalValue = 5
        .segment "RODATA": absolute
        .byte <__BSS_SIZE__, __ZP_START__, ZeroValue, GlobalValue
        .assert 1, warning, "never reported"
        .assert 1, ldwarning
        .setcpu "65C02"
        rmb0 $12
        bbr0 $12, *+3
        .bss
        .res 3
        """)]
    [DataRow("""
        .code
        .byte 1
        .org $2001
        Logical: .align 4
        .byte 2
        .reloc
        .align 4
        Relocated: .byte 3
        .word Logical, Relocated
        """)]
    [DataRow("""
        .struct Packet
        Count .byte
        Inner .struct
        Low .byte
        High .word
        .endstruct
        .union
        Small .byte
        Large .word
        .endunion
        .endstruct
        .enum Mode
        Off
        On = 4
        Done
        .endenum
        .byte Packet::Inner, Packet::High, .sizeof(Packet), Mode::Done
        .tag Packet
        """)]
    [DataRow("""
        .define Twice(arg) arg * 2
        .define Value 1 + 2
        .byte Twice(Value)
        .undefine Value
        .define Value 7
        .byte Value
        """)]
    [DataRow("""
        .charmap 'A',$C1
        .byte "A",'A'
        .asciiz "AB","C"
        .dbyt $1234,$ABCD
        .faraddr $123456
        .lobytes $1234,$5678
        .hibytes $1234,$5678
        """)]
    [DataRow("""
        .ident(.concat("Value",.string(1))) = 7
        .byte .ident("Value1"),.strlen(.concat("AB","C"))
        .byte .concat("A",.string(2+3)), .string(Value1)
        """)]
    [DataRow("""
        Known=3
        .ifconst Entry
        .error "not constant"
        .elseif .defined(Known)
        .byte 1
        .endif
        .ifconst Known+1
        .byte 2
        .endif
        .ifp02
        .byte 3
        .endif
        .scope Size
        nop
        nop
        .endscope
        .byte .sizeof(Size)
        Alias: .proc Worker
        rts
        .endproc
        .word Alias, Worker
        """)]
    [DataRow("""
        .charmap 'A',$C1
        lda #'A'
        .word 'A', 'A'+1
        .if 'A' = $C1
        .byte 1
        .else
        .byte 0
        .endif
        """)]
    [DataRow("""
        .define Pair(first,second) first,second
        .byte Pair {2+3}, {4*2}
        .enum Value
        First=-2
        Second
        .endenum
        .word Value::First & $FFFF,Value::Second & $FFFF
        """)]
    [DataRow("""
        .struct Offsets
        .org $20
        Field .byte
        .endstruct
        .byte Offsets::Field,.sizeof(Offsets)
        """)]
    [DataRow("""
        .global ByteValue:zp
        ByteValue=$20
        .byte "", ByteValue
        .byte ""
        .byte 1
        """)]
    [DataRow("""
        .charmap ('A'),($C1)
        .byte "A"
        """)]
    [DataRow("""
        .byte .match(1, 2), .match(foo, bar), .match(a, x), .match(x, x), .match({1 + 2}, {3 - 4})
        .byte .match(, ), .match({}, 1), .match("a", "b"), .match(.byte, .word)
        .byte .xmatch(1, 1), .xmatch(1, 2), .xmatch(foo, foo), .xmatch(foo, Foo), .xmatch({a, x}, {A, X})
        .byte .tcount({}), .tcount({a, b}), .tcount(foo::bar), .left(1, {3 4 5}), .right(1, {3 4 5}), .mid(1, 1, {3 4 5})
        .byte .blank(), .blank({ }), .blank(1), .strat("abc", 1)
        Known = 1
        .byte .const(Known), .const(Later), .const(*), .const(Known + 1)
        Later_SMC = 9
        .byte .ident(.concat(.string(.right(1, Later)), "_SMC"))
        Later: nop
        """)]
    [DataRow("""
        .dword CPU_NONE, CPU_6502, CPU_6502X, CPU_65SC02, CPU_65C02, CPU_65816, CPU_W65C02, CPU_4510
        .dword CPU_ISET_6502, CPU_ISET_65SC02, CPU_ISET_65C02, CPU_ISET_W65C02, CPU_ISET_65CE02
        .macro Macro
        .endmacro
        .byte .definedmacro(Macro), .definedmacro(Missing), .defined(Macro), .def(Entry)
        .ifndef Macro
        .byte 1
        .endif
        .global Missing, Entry
        .globalzp ZeroMissing
        """)]
    [DataRow("""
        Bytes: .byte 1, 2, 3
        Words: .word 1, 2
        Reserved: .res 5
        Code: nop
        nop
        Alone:
        .asciiz "ab"
        Text: .asciiz "ab"
        .byte .sizeof(Bytes), .sizeof(Words), .sizeof(Reserved), .sizeof(Code), .sizeof(Alone), .sizeof(Text)
        """)]
    [DataRow("""
        .byte .strlen(.sprintf("%02X-%d%s|%-3d|%3d|%x|%o|%c", 10, 7, "ab", 5, 6, 255, 8, 65))
        .byte .strat(.sprintf("%04x", $AB), 2), .strat(.sprintf("%+d", 5), 0)
        .byte .max(3, 9), .min(3, 9), .max(-1, 1) & $FF
        .word .min(Entry, $FFFF), .max(Entry, 2)
        .word .loword($123456), .hiword($123456), .loword(Entry)
        .scope Scoped
        nop
        .byte 1, 2
        .endscope
        Label: .proc Procedure
        nop
        .endproc
        .byte .sizeof(Scoped), .sizeof(Procedure)
        .define Text .sprintf("L%d", 3)
        L3 = 4
        .byte .ident(Text)
        """)]
    public void FrontendMatchesRealTools(string body)
    {
        Ca65Toolchain tools = Ca65Toolchain.Require();
        string directory = Directory.CreateTempSubdirectory("retrocore-frontend-").FullName;
        try
        {
            string path = Path.Join(directory, "main.s");
            string text = ".export Entry\nEntry:\n" + body;
            File.WriteAllText(path, text);
            Ca65Assembly reference = tools.Assemble(path);
            AssemblyResult result = new NativeAssembler().Assemble(new AssemblySource(text, path), Options());
            result.Diagnostics.Should().BeEmpty();
            reference.AssertMatches(result.Files["output.bin"].Span, result.Exports);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  Logical origins do not insert file gaps and timestamps use the explicit build time.
    /// </summary>
    [TestMethod]
    public void OriginsAndBuildTimeAreIndependentOfFileOffsets()
    {
        AssemblyResult result = Assemble(".code\n.org $C000\nEntry:nop\n.dword .time\n.export Entry");
        result.Diagnostics.Should().BeEmpty();
        result.Files["output.bin"].ToArray().Should().Equal(0xEA, 0x78, 0x56, 0x34, 0x12);
        result.Exports["Entry"].Should().Be(0xC000);
        result.SourceMap.Single(entry => entry.Label == "Entry").Offset.Should().Be(0);
    }

    /// <summary>
    ///  Regions are placed independently and files concatenate their regions in declaration order.
    /// </summary>
    [TestMethod]
    public void MultipleRegionsFilesAndAlignmentHaveExactOutput()
    {
        AssemblyResult result = Assemble("""
            .segment "CODE"
            .byte 1
            .segment "DATA"
            .byte 2
            .segment "CODE"
            .byte 3
            .segment "WORK"
            Buffer: .res 3
            .segment "OTHER"
            .byte 4
            """, """
            SEGMENTS {
                CODE: load=ROM,type=ro;
                DATA: load=ROM,type=rw,align=4;
                WORK: load=RAM,type=bss;
                OTHER: load=SECOND,type=ro;
            }
            MEMORY {
                ROM: start=$2000,size=8,fill=yes,fillval=$AA,file=%O;
                RAM: start=$80,size=16,file="";
                SECOND: start=$3000,size=2,file="other.bin";
            }
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Files["output.bin"].ToArray().Should().Equal(1, 3, 0xAA, 0xAA, 2, 0xAA, 0xAA, 0xAA);
        result.Files["other.bin"].ToArray().Should().Equal(4);
        result.Symbols["Buffer"].Should().Be(0x80);
        result.Sections.Single(section => section.Name == "WORK").Size.Should().Be(3);
    }

    /// <summary>
    ///  The entire optional rom4x/rom5x corpus uses the actual front end, masking only .time payloads.
    /// </summary>
    [TestMethod]
    public void Rom4xAndRom5xCorpusMatchesRealTools()
    {
        string root = Environment.GetEnvironmentVariable("RETROCORE_CA65_CORPUS") ?? @"N:\repos\rom4x";
        if (!Directory.Exists(root))
        {
            Assert.Inconclusive("Set RETROCORE_CA65_CORPUS to the optional rom4x checkout.");
        }

        Ca65Toolchain tools = Ca65Toolchain.Require();
        string[] paths = Directory.GetFiles(root, "*.s", SearchOption.AllDirectories);
        paths.Length.Should().Be(37);
        string[] includes = [Path.Join(root, "rom4x"), Path.Join(root, "rom5x")];
        string temporary = Directory.CreateTempSubdirectory("retrocore-rom4x-").FullName;
        try
        {
            foreach (string originalPath in paths)
            {
                string path = originalPath;
                string[] search = includes;
                if (Path.GetFileName(path) == "xmodem.s")
                {
                    path = Path.Join(temporary, "standalone.s");
                    File.WriteAllText(path, ".pc02\nSTANDALONE=1\n.include \"iic.defs\"\n.include \"xmodem.s\"");
                    search = [Path.GetDirectoryName(originalPath) ?? throw new InvalidOperationException(), .. includes];
                }

                Ca65Assembly reference = tools.Assemble(path, includePaths: search);
                AssemblyResult result = new NativeAssembler().Assemble(
                    new AssemblySource(File.ReadAllText(path), path),
                    new(ProcessorVariant.Mos6502, 0x1000, 0x6800)
                    {
                        Dialect = AssemblyDialect.Ca65,
                        SourceResolver = new FileAssemblySourceResolver(),
                        IncludePaths = search,
                        BuildTime = DateTimeOffset.FromUnixTimeSeconds(0x12345678)
                    });

                result.Diagnostics.Should().BeEmpty(originalPath);
                byte[] actual = result.Files["output.bin"].ToArray();
                Dictionary<string, string[]> documents = new(StringComparer.Ordinal);
                foreach (AssemblySourceMapEntry entry in result.SourceMap)
                {
                    if (entry.Location is not { } location) { continue; }
                    if (!documents.TryGetValue(location.Path, out string[]? lines))
                    {
                        lines = File.ReadAllLines(location.Path);
                        documents.Add(location.Path, lines);
                    }

                    AssemblyStatement? original = NativeAssembler.ParseLine(lines[location.Line].AsMemory(), location.Line, out _, out _);
                    if (original?.Operation.Equals(".dword", StringComparison.OrdinalIgnoreCase) == true
                        && original.Operand.Text.Equals(".time", StringComparison.OrdinalIgnoreCase))
                    {
                        entry.Size.Should().Be(4);
                        int offset = result.Sections[entry.Section].Origin - 0x1000 + entry.Offset;
                        reference.Bytes.AsSpan(offset, 4).CopyTo(actual.AsSpan(offset));
                    }
                }

                actual.Should().Equal(reference.Bytes, originalPath);
                actual.Should().NotBeEmpty(originalPath);
            }
        }
        finally
        {
            Directory.Delete(temporary, recursive: true);
        }
    }

    /// <summary>
    ///  Unsupported syntax and link failures never expose successful file images.
    /// </summary>
    /// <param name="source">The ca65 source.</param>
    /// <param name="config">An optional configuration.</param>
    /// <param name="message">The required failure text.</param>
    [TestMethod]
    [DataRow(".setcpu \"65816\"\nnop", null, "CPU")]
    [DataRow(".assert 0,error,\"message from source\"", null, "message from source")]
    [DataRow(".assert 0,warning,\"warning text\"", null, "warning text")]
    [DataRow(".proc Entry\nnop\n.org $4000\nnop\n.endproc\n.byte .sizeof(Entry)", null, "contiguous")]
    [DataRow(".segment \"MISSING\"\nnop", null, "section")]
    [DataRow(".res 3", "MEMORY{RAM:start=0,size=2;}SEGMENTS{CODE:load=RAM,type=ro;}", "exceeds")]
    [DataRow("nop", "MEMORY{RAM:start=0,size=2;}SEGMENTS{CODE:load=RAM,type=ro,run=RAM;}", "Unsupported linker attribute")]
    [DataRow("nop", "MEMORY{RAM:start=0,size=2;}SEGMENTS{CODE:load=RAM,type=ro,align=0;}", "alignment")]
    [DataRow("nop", "MEMORY{RAM:start=0,size=2;}SEGMENTS{DATA:load=RAM,type=rw;}", "CODE")]
    [DataRow("nop", "MEMORY{RAM:start=1<<63,size=2;}SEGMENTS{CODE:load=RAM,type=ro;}", "must fit")]
    [DataRow("nop\n.export __CODE_SIZE__", "MEMORY{ROM:start=$2000,size=16;}SEGMENTS{CODE:load=ROM,type=ro;}", "unresolved")]
    public void InvalidSourcesAndConfigurationsAreDiagnosed(string source, string? config, string message)
    {
        AssemblyResult result = Assemble(source, config);
        result.Success.Should().BeFalse();
        result.Files.Should().BeEmpty();
        result.Diagnostics.Should().Contain(diagnostic => diagnostic.Message.Contains(message, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>
    ///  Repeated compilation neither configures caller-owned syntax nor changes earlier file snapshots.
    /// </summary>
    [TestMethod]
    public void LinkingPreservesModelAndOutputSnapshots()
    {
        AssemblyProject project = NativeAssembler.Parse(new AssemblySource(".byte 1", "source.s"), Options()).Project;
        NativeAssembler assembler = new();
        AssemblyResult first = assembler.Assemble(project, Options());
        project.SectionDefinitions.Should().BeEmpty();
        project.Statements[0].Operand = new("2");
        AssemblyResult second = assembler.Assemble(project, Options());
        first.Diagnostics.Should().BeEmpty();
        second.Diagnostics.Should().BeEmpty();
        first.Files["output.bin"].ToArray().Should().Equal(1);
        second.Files["output.bin"].ToArray().Should().Equal(2);
    }

    /// <summary>
    ///  Empty trailing segments can sit at the exclusive 64 KiB boundary.
    /// </summary>
    [TestMethod]
    public void FullMemoryRegionAllowsEmptyTrailingBss()
    {
        AssemblyResult result = Assemble(
            "nop",
            "MEMORY{ROM:start=$FFFF,size=1;}SEGMENTS{CODE:load=ROM,type=ro;BSS:load=ROM,type=bss;}");

        result.Diagnostics.Should().BeEmpty();
        result.Files["output.bin"].ToArray().Should().Equal(0xEA);
    }

    /// <summary>
    ///  Uninitialized ca65 fragments and alignment use the load region's fill value.
    /// </summary>
    [TestMethod]
    public void ReservedBytesAndAlignmentMatchLd65Fill()
    {
        Ca65Toolchain tools = Ca65Toolchain.Require();
        const string Text = ".export Entry\nEntry:\n.byte 1\n.res 2\n.align 4\n.byte 2\n.res 1,$55";
        const string Config = "MEMORY{ROM:start=$2000,size=16,fill=yes,fillval=$AA,file=%O;}SEGMENTS{CODE:load=ROM,type=ro;}";
        string directory = Directory.CreateTempSubdirectory("retrocore-link-fill-").FullName;
        try
        {
            string path = Path.Join(directory, "main.s");
            string config = Path.Join(directory, "link.cfg");
            File.WriteAllText(path, Text);
            File.WriteAllText(config, Config);
            Ca65Assembly reference = tools.Assemble(path, config);
            AssemblyResult result = Assemble(Text, Config);
            result.Diagnostics.Should().BeEmpty();
            reference.AssertMatches(result.Files["output.bin"].Span, result.Exports);
            result.SourceMap.Single(entry => entry.Operation == ".RES" && entry.Operand == "2").Operand.Should().Be("2");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  Separate load banks may use identical CPU addresses and distinct files.
    /// </summary>
    [TestMethod]
    public void IndependentMemoryBanksMayOverlap()
    {
        AssemblyResult result = Assemble("""
            .segment "CODE"
            .byte 1
            .segment "BANK"
            .byte 2
            """, """
            MEMORY{FIRST:start=$E000,size=1,file=%O;SECOND:start=$E000,size=1,file="bank.bin";}
            SEGMENTS{CODE:load=FIRST,type=ro;BANK:load=SECOND,type=ro;}
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Files["output.bin"].ToArray().Should().Equal(1);
        result.Files["bank.bin"].ToArray().Should().Equal(2);
    }

    /// <summary>
    ///  Segment define=yes publishes size/load/run symbols without enabling them for every other segment.
    /// </summary>
    [TestMethod]
    public void SegmentSymbolsRequireDefineAttribute()
    {
        AssemblyResult result = Assemble(
            "nop\n.export __CODE_SIZE__, __CODE_LOAD__, __CODE_RUN__",
            "MEMORY{ROM:start=$2000,size=16;}SEGMENTS{CODE:load=ROM,type=ro,define=yes;DATA:load=ROM,type=rw;}");

        result.Diagnostics.Should().BeEmpty();
        result.Exports["__CODE_SIZE__"].Should().Be(1);
        result.Exports["__CODE_LOAD__"].Should().Be(0x2000);
        result.Exports["__CODE_RUN__"].Should().Be(0x2000);
        result.Symbols.Keys.Should().NotContain("__DATA_SIZE__");
    }

    /// <summary>
    ///  cc65's own assembly configurations link the same file as ld65, including a region placed at another
    ///  region's last address and alignment relative to an unaligned segment start. The C configurations need
    ///  the runtime's startup segments, so ld65 rejects a plain assembly program for them.
    /// </summary>
    /// <param name="config">The stock configuration file.</param>
    /// <param name="symbols">Linker symbols the configuration defines.</param>
    [TestMethod]
    [DataRow("none.cfg", "__ZP_START__, __ZP_SIZE__, __ZP_LAST__, __ZP_FILEOFFS__, __BSS_LOAD__, __BSS_SIZE__, __STACKSIZE__")]
    [DataRow("apple2-asm.cfg", "__MAIN_START__, __MAIN_LAST__, __MAIN_SIZE__, __MAIN_FILEOFFS__, __BSS_RUN__, __BSS_SIZE__")]
    public void StockConfigurationsLinkLikeLd65(string config, string symbols)
    {
        Ca65Toolchain tools = Ca65Toolchain.Require();
        string configPath = Path.Join(tools.ConfigDirectory, config);
        string directory = Directory.CreateTempSubdirectory("retrocore-stock-config-").FullName;
        try
        {
            string path = Path.Join(directory, "main.s");
            string text = $"""
                .export Start, Buffer
                .import {symbols}
                .code
                Start: lda #1
                jmp Start
                .byte 1
                .align 4
                .byte 2
                lda Buffer
                .word {symbols}
                .rodata
                .byte 9
                .data
                .byte 3
                .bss
                Buffer: .res 4
                """;

            File.WriteAllText(path, text);
            Ca65Assembly reference = tools.Assemble(path, configPath);
            AssemblyResult result = new NativeAssembler().Assemble(
                new AssemblySource(text, path),
                Options(new(File.ReadAllText(configPath), configPath)));

            result.Diagnostics.Should().BeEmpty();
            reference.AssertMatches(result.Files["output.bin"].Span, result.Exports);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  ca65 precedence and the Rockwell 65C02 set hold without the external tools.
    /// </summary>
    /// <param name="source">The ca65 source.</param>
    /// <param name="expected">The expected bytes, or null when assembly must fail.</param>
    [TestMethod]
    [DataRow(".byte 2 | 1 + 1, 1 + !0 + 1, 1 .xor 1 .and 0", new byte[] { 4, 1, 0 })]
    [DataRow(".mac Twice value\n.byte value * 2\n.endmac\nTwice 1 + 2", new byte[] { 5 })]
    [DataRow(".pc02\nrmb0 $12", new byte[] { 0x07, 0x12 })]
    [DataRow(".pc02\nstp", null)]
    [DataRow(".byte 7 % 3", null)]
    [DataRow(" lda (1 + 2) * 2", null)]
    [DataRow(".segment \"CODE\": far\nnop", null)]
    [DataRow(".import 1bad", null)]
    public void Ca65SemanticsHoldWithoutTools(string source, byte[]? expected)
    {
        AssemblyResult result = Assemble(".code\n" + source);
        if (expected is null)
        {
            result.Success.Should().BeFalse();
            return;
        }

        result.Diagnostics.Should().BeEmpty();
        result.Files["output.bin"].ToArray().Should().Equal(expected);
    }

    /// <summary>
    ///  Region symbols, SYMBOLS values, FEATURES, optional commas and fixed segment placement follow ld65.
    /// </summary>
    [TestMethod]
    public void LinkerConfigurationsFollowLd65Placement()
    {
        AssemblyResult chained = Assemble(
            "lda Buffer\n.byte 1\n.bss\nBuffer: .res 2\n.export Buffer",
            """
            MEMORY {
                MAIN: start = $1000 size = $1010 - __MAIN_START__, define = yes;
                RAM: file = "", start = __MAIN_LAST__, size = $100;
            }
            SEGMENTS { CODE: load = MAIN type = ro; BSS: load = RAM, type = bss; }
            """);

        chained.Diagnostics.Should().BeEmpty();
        chained.Exports["Buffer"].Should().Be(0x1004);
        chained.Files["output.bin"].ToArray().Should().Equal(0xAD, 4, 0x10, 1);

        AssemblyResult placed = Assemble(
            ".byte 1\n.data\n.byte 2\n.export Weak, Strong, Legacy\nWeak = 7",
            """
            FEATURES { STARTADDRESS: default = $2000; }
            SYMBOLS { Weak: type = weak, value = 1; Strong: value = %S + 1; Legacy = 3; Imported: type = import; }
            MEMORY { RAM: start = %S, size = $100, file = %O; }
            SEGMENTS { CODE: load = RAM, type = ro, align = 3; DATA: load = RAM, type = rw, offset = $10; }
            """);

        placed.Diagnostics.Should().BeEmpty();
        placed.Exports["Weak"].Should().Be(7);
        placed.Exports["Strong"].Should().Be(0x2001);
        placed.Exports["Legacy"].Should().Be(3);
        byte[] expected = new byte[0x11];
        expected[1] = 1;
        expected[0x10] = 2;
        placed.Files["output.bin"].ToArray().Should().Equal(expected);

        Assemble(".res 17", "MEMORY{MAIN:start=$1000,size=$1010-__MAIN_START__,define=yes;}SEGMENTS{CODE:load=MAIN,type=ro;}")
            .Success.Should().BeFalse();
    }

    /// <summary>
    ///  A label on a control command's line is defined when the line before it is assembled, as ca65 does.
    /// </summary>
    [TestMethod]
    public void LabelsOnControlCommandsMatchCa65()
    {
        AssemblyResult result = Assemble("""
            .byte 9
            L: .if 1
            .byte 1
            .endif
            .if 0
            M: .else
            .byte 2
            N: .endif
            R: .repeat 2
            .byte 4
            .endrepeat
            D: .define FIVE 5
            .byte FIVE
            .if 0
            Z: .if 1
            .endif
            .endif
            .word L, N, R, D
            .ifndef M
            .byte $EE
            .endif
            .ifndef Z
            .byte $EF
            .endif
            """);

        result.Diagnostics.Should().BeEmpty();
        byte[] expected = [9, 1, 2, 4, 4, 5, 0x01, 0x10, 0x03, 0x10, 0x03, 0x10, 0x05, 0x10, 0xEE, 0xEF];
        result.Sections.Single(section => section.Name == "CODE").Bytes.Span[..16].ToArray().Should().Equal(expected);
    }

    private static AssemblyOptions Options(AssemblySource? config = null) => new(ProcessorVariant.Mos6502, 0x1000, 0x6800)
    {
        Dialect = AssemblyDialect.Ca65,
        LinkerConfiguration = config,
        BuildTime = DateTimeOffset.FromUnixTimeSeconds(0x12345678)
    };

    private static AssemblyResult Assemble(string source, string? config = null) =>
        new NativeAssembler().Assemble(new AssemblySource(source, "source.s"), Options(config is null ? null : new(config, "link.cfg")));
}
