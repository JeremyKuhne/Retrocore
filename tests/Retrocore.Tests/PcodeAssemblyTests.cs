// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Media;
using Retrocore.Pascal;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  Apple Pascal's p-code as source: <c>Pcode.asm</c>'s macros, under <c>.cpu Pcode</c>, assemble a whole code file.
/// </summary>
[TestClass]
public class PcodeAssemblyTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  P1's code file (see <see cref="PascalDecompilerTests"/>) written as p-code source assembles back to the same
    ///  bytes: the segment dictionary, each procedure's p-code, jump tables, attributes and the procedure dictionary,
    ///  with offsets and pointers as label arithmetic.
    /// </summary>
    [TestMethod]
    public void ACodeFileAssemblesFromPcode()
    {
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource(P1Source, Path.Join(s_inputs, "p1.asm")),
            Options());

        result.Diagnostics.Should().BeEmpty();
        byte[] expected = PascalDecompilerTests.P1Bytes;
        result.Sections[0].Bytes.Span[..expected.Length].ToArray().Should().Equal(expected);
    }

    /// <summary>
    ///  Each operand form assembles: big numbers of one and two bytes, a jump forward, a string, a comparison with a
    ///  size, a standard procedure by name, and a case jump's alignment byte.
    /// </summary>
    [TestMethod]
    public void OperandFormsAssemble()
    {
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource("""
                .include "Pcode.asm"
                        LDL 5
                        LDL 300
                        LOD 1, 3
                        FJP Next
                        LSA "HI"
                Next:   NEQBYT 6
                        CSP IOC
                        SLDC 0
                        XJP 1, 2, $EE
                """, Path.Join(s_inputs, "forms.asm")),
            Options());

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..26].ToArray().Should().Equal(
            202, 5,
            202, 0x81, 0x2C,
            182, 1, 3,
            161, 4,
            166, 2, (byte)'H', (byte)'I',
            183, 10, 6,
            158, 0,
            0,
            172, 0xEE, 1, 0, 2, 0);
    }

    /// <summary>
    ///  P1's code file, written by <see cref="PcodeSourceWriter"/>, assembles back to the same bytes.
    /// </summary>
    [TestMethod]
    public void WrittenSourceAssemblesBack()
    {
        byte[] original = PascalDecompilerTests.P1Bytes;
        PcodeSource source = PcodeSourceWriter.Write(original, include: "\"Pcode.asm\"");

        source.Notes.Should().BeEmpty();
        source.Text.Should().Contain(".scope P2").And.Contain("Attributes: .byte 2, 1");
        Assemble(source.Text).Should().Equal(original);
    }

    /// <summary>
    ///  An assembled procedure is written as 6502 code under <c>.cpu Mos6502</c>: an operand its procedure-relative
    ///  relocation list names is an offset from its entry, by label, and the list names the operand's instruction.
    /// </summary>
    [TestMethod]
    public void AssembledProceduresAreWrittenAs6502()
    {
        byte[] original = Assemble(MixedSource);
        PascalCodeFile.Read(original).Segments.Single().Procedure(2).Should().Match<PascalProcedure>(procedure => procedure.IsNative);

        PcodeSource source = PcodeSourceWriter.Write(original, include: "\"Pcode.asm\"");

        source.Notes.Should().BeEmpty();
        string text = source.Text;
        text.Should().Contain("        .cpu Mos6502");
        text.Should().Contain("lda.w L0004 - Entry", "the operand is relocated: an offset from the entry");
        text.Should().Contain(".word * - (Entry + 1)", "the relocation list names the operand's instruction");
        text.Should().Contain("        .cpu Pcode");
        Assemble(source.Text).Should().Equal(original);
    }

    /// <summary>
    ///  Calls of the system's procedures and PASCALIO's are written by <c>Pcode.asm</c>'s names for them, and a real
    ///  constant has its value beside it; two words that read as no real a source would write have none.
    /// </summary>
    [TestMethod]
    public void SystemCallsAndRealsAreNamed()
    {
        PcodeSource p1 = PcodeSourceWriter.Write(PascalDecompilerTests.P1Bytes, include: "\"Pcode.asm\"");
        p1.Text.Should().Contain("CXP 0, Pascalsy::FWRITEINT").And.Contain("CXP PascalIo::Segment, PascalIo::FWRITEREAL");

        PcodeSource mixed = PcodeSourceWriter.Write(Assemble(MixedSource), include: "\"Pcode.asm\"");
        mixed.Text.Should().Contain("; 0.5 as a real");
        mixed.Text.Split("as a real").Should().HaveCount(2, "the second constant's words are a set's");
        Assemble(p1.Text).Should().Equal(PascalDecompilerTests.P1Bytes);
    }

    /// <summary>
    ///  Hints name a segment's and procedure's scopes and a place in a procedure, by offset from its entry, and put
    ///  comments above them; a call names the scope it calls.
    /// </summary>
    [TestMethod]
    public void HintsNameAndComment()
    {
        byte[] original = Assemble(MixedSource);
        PcodeSource source = PcodeSourceWriter.Write(original, Options("\"Pcode.asm\"") with
        {
            Names = new Dictionary<string, string>
            {
                ["mixed"] = "Mixed",
                ["MIXED.2"] = "Load",
                ["MIXED.2+$4"] = "Value"
            },
            Comments = new Dictionary<string, string>
            {
                ["MIXED.2"] = "Loads a word of its own.",
                ["MIXED.2+4"] = "The word"
            }
        });

        string text = source.Text;
        text.Should().Contain(".scope Mixed").And.Contain(".scope Load");
        text.Should().Contain(";; Loads a word of its own.").And.Contain(";; The word\nValue:");
        text.Should().Contain("lda.w Value - Entry");
        text.Should().MatchRegex(@"CLP 2 +; Mixed::Load");
        Assemble(text).Should().Equal(original);
    }

    /// <summary>
    ///  A compiler listing names segments and procedures by their headings, and puts each statement's source line
    ///  above its p-code.
    /// </summary>
    [TestMethod]
    public void AListingNamesAndPlacesSourceLines()
    {
        PascalListing listing = PascalListing.Parse("""
                 1   1    1:D     1 PROGRAM MIXED;
                 2   1    2:D     1 PROCEDURE LOAD; EXTERNAL;
                 3   1    1:0     0 BEGIN
                 4   1    1:1     0 LOAD;
                 5   1    1:1     2 X := 0.5
                 6   1    1:0    13 END.
            """);

        byte[] original = Assemble(MixedSource);
        string text = PcodeSourceWriter.Write(original, Options("\"Pcode.asm\"") with { Listing = listing }).Text;

        text.Should().Contain(".scope MIXED").And.Contain(".scope LOAD");
        text.Should().MatchRegex(@";    4: LOAD;\n(\w+:\n)? *CLP 2 +; MIXED::LOAD");
        text.Should().MatchRegex(@";    5: X := 0.5\n(\w+:\n)? *LDC 2");
        Assemble(text).Should().Equal(original);
    }

    /// <summary>
    ///  A call of a unit in the library names the unit's segment and procedure, from its interface, and the source
    ///  defines the unit's scope.
    /// </summary>
    [TestMethod]
    public void UnitCallsAreNamedFromTheLibrary()
    {
        string samples = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.1_3.dsk");
        string boot = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.1_1.dsk");
        if (!File.Exists(samples) || !File.Exists(boot))
        {
            Assert.Inconclusive("Set RETROCORE_APPLE2_PASCAL_DISKS to a folder with Apple Pascal 1.1's disks.");
        }

        byte[] original = PascalVolume.Read(File.ReadAllBytes(samples), proDosOrder: false).ReadFile("HILBERT.CODE");
        PascalLibrary library = PascalLibrary.Read(PascalVolume.Read(File.ReadAllBytes(boot), proDosOrder: false).ReadFile("SYSTEM.LIBRARY"));
        string text = PcodeSourceWriter.Write(original, Options("\"Pcode.asm\"") with { Library = library }).Text;

        text.Should().Contain(".scope TURTLEGR").And.Contain("CXP TURTLEGR::Segment, TURTLEGR::TURN");
        Assemble(text).Should().Equal(original);
    }

    /// <summary>
    ///  Every code file on Apple Pascal's disks is written as source that assembles back to the same bytes; a system
    ///  segment whose procedures are elsewhere is written as data.
    /// </summary>
    [TestMethod]
    public void EveryCodeFileOnTheDisksAssemblesBack()
    {
        EnumerationOptions anyCase = new() { MatchCasing = MatchCasing.CaseInsensitive };
        string[] disks = Directory.Exists(PascalMediaTests.Apple2Disks) ? Directory.GetFiles(PascalMediaTests.Apple2Disks, "*.dsk", anyCase) : [];
        if (disks.Length == 0)
        {
            Assert.Inconclusive("Set RETROCORE_APPLE2_PASCAL_DISKS to a folder with Apple Pascal's disks.");
        }


        int files = 0;
        foreach (string disk in disks)
        {
            PascalVolume volume = PascalVolume.Read(File.ReadAllBytes(disk), proDosOrder: false);
            foreach (PascalFileEntry entry in volume.Files.Where(file => file.Kind == PascalFileKind.Code))
            {
                byte[] original = volume.ReadFile(entry);
                if (!PascalCodeFile.IsCodeFile(original)) { continue; }

                PcodeSource source = PcodeSourceWriter.Write(original, include: "\"Pcode.asm\"");
                Assemble(source.Text).Should().Equal(original, $"{Path.GetFileName(disk)} {entry.Name} assembles back");
                files++;
            }
        }

        files.Should().BeGreaterThan(0);
    }

    // A code file's source assembled, to the last byte it writes.
    private static byte[] Assemble(string text)
    {
        AssemblyResult result = new NativeAssembler().Assemble(new AssemblySource(text, Path.Join(s_inputs, "code.asm")), Options());
        result.Diagnostics.Should().BeEmpty();
        int end = result.SourceMap.Where(entry => entry.Size != 0).Max(entry => entry.Offset + entry.Size);
        return result.Sections[0].Bytes.Span[..end].ToArray();
    }

    // A code file of one segment: procedure 1, p-code, calls procedure 2, assembled 6502 code that loads a word of its
    // own through a procedure-relative operand, and keeps a procedure-relative word as data.
    private const string MixedSource = """
                .include "Pcode.asm"
                .word Segment0 / 512, Segment0End - Segment0
                .res 60, 0
                .byte "MIXED   "
                .res 120, 0
                .res 64, 0
                .word (2 << 13) | (2 << 8) | 1
                .res 254, 0
        Segment0:
        .scope Seg0
                .cpu Mos6502
        .scope P2
        Entry:  lda.w Value - Entry
                rts
        Value:  .word Value - Entry
                .word 0
                .word * - (Entry + 1), * - Value
                .word 2
                .word 0
                .word 0
                .word * - Entry
        Attributes: .byte 0, 1
        .endscope
                .cpu Pcode
        .scope P1
        Entry:  CLP 2
                LDC 2, 0
                .word $3F00, $0000
                LDC 2, 0
                .word $0001, $0002
        Exit:   RBP 0
                .word 4, 0
                .word * - Exit, * - Entry
        Attributes: .byte 1, 0
        .endscope
                .word * - P2::Attributes
                .word * - P1::Attributes
                .byte 1, 2
        .endscope
        Segment0End:
                .align 512, 0
        """;

    private static PcodeSourceOptions Options(string include) => new() { Include = include };

    // The whole 64K from address 0, so blocks and words align as the code file's do, with Pcode.asm from Inputs.
    private static AssemblyOptions Options() => new(ProcessorVariant.Mos6502, origin: 0, imageSize: 0x10000)
    {
        IncludePaths = [s_inputs],
        SourceResolver = new FileAssemblySourceResolver()
    };

    private const string P1Source = """
                    .include "Pcode.asm"

            ;; The segment dictionary.
                    .word Segment0 / 512, Segment0End - Segment0
                    .word 0, 0
                    .word 0, 0
                    .word 0, 0
                    .word 0, 0
                    .word 0, 0
                    .word 0, 0
                    .word 0, 0
                    .word 0, 0
                    .word 0, 0
                    .word 0, 0
                    .word 0, 0
                    .word 0, 0
                    .word 0, 0
                    .word 0, 0
                    .word 0, 0
                    .byte "P1      "
                    .byte "        "
                    .byte "        "
                    .byte "        "
                    .byte "        "
                    .byte "        "
                    .byte "        "
                    .byte "        "
                    .byte "        "
                    .byte "        "
                    .byte "        "
                    .byte "        "
                    .byte "        "
                    .byte "        "
                    .byte "        "
                    .byte "        "
                    .word $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000
                    .word $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000
                    .word $4201, $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000
                    .byte $00, $00, $00, $80, $2A, $00, $1F, $06, $00, $00, $00, $00
                    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
                    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
                    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
                    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
                    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
                    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
                    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
                    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
                    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
                    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
                    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
                    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
                    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
                    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
                    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
                    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
                    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
                    .byte $00, $00, $00, $00, $00, $00, $00, $00
            Segment0:
            .scope Seg0
            .scope P2
            Entry:
                    SLDL3
                    SLDC 1
                    ADI
                    STL 1
            Exit:
                    RNP 1
                    .byte $00
                    .word 0, 6
                    .word * - Exit, * - Entry
            Attributes: .byte 2, 1
            .endscope
            .scope P3
            Entry:
                    SLDC 1
                    STL 1
            Exit:
                    RNP 1
                    .byte $00
                    .word 0, 4
                    .word * - Exit, * - Entry
            Attributes: .byte 3, 1
            .endscope
            .scope P4
            Entry:
                    LLA 1
                    LLA 5
                    LDM 2
                    LLA 3
                    LDM 2
                    MPR
                    STM 2
            Exit:
                    RNP 2
                    .byte $00
                    .word 0, 12
                    .word * - Exit, * - Entry
            Attributes: .byte 4, 1
            .endscope
            .scope P1
            Entry:
                    UJPT T016C
            L003E:
                    SLDC 3
                    SLDC 0
                    SLDC 0
                    CLP 2
                    SRO 4
            L0045:
                    SLDO4
                    SLDC 10
                    LESI
                    FJP L0051
                    SLDO4
                    SLDC 2
                    ADI
                    SRO 4
                    UJPT T0170
            L0051:
                    SLDC 10
                    SRO 3
                    SLDC 1
                    SRO 9
            L0057:
                    SLDO3
                    SLDO9
                    GEQI
                    FJP L0068
                    SLDO4
                    SLDO3
                    SBI
                    SRO 4
                    SLDO3
                    SLDC 1
                    SBI
                    SRO 3
                    UJPT T016E
            L0068:
                    SLDO4
                    UJP L007D
            L006B:
                    SLDC 5
                    SRO 3
                    UJP L0092
            L0070:
                    SLDC 6
                    SRO 3
                    UJP L0092
            L0075:
                    SLDC 7
                    SRO 3
                    SLDC 0
                    SRO 4
                    UJP L0092
            L007D:
                    XJP 1, 7, $00
            L0082: UJP L0092
                    .word * - L006B
                    .word * - L0082
                    .word * - L0070
                    .word * - L0070
                    .word * - L0082
                    .word * - L0082
                    .word * - L0075
            L0092:
                    SLDC 0
                    SLDC 0
                    CLP 3
                    SLDO4
                    SLDC 0
                    GRTI
                    LAND
                    SLDO3
                    SLDC 5
                    EQUI
                    LNOT
                    LOR
                    SRO 5
                    SLDO5
                    FJP L00A9
                    SLDC 65
                    SRO 6
                    UJP L00AC
            L00A9:
                    SLDO4
                    SRO 6
            L00AC:
                    LAO 7
                    LDC 2, $00
                    .word $3FC0, $0000
                    SLDO4
                    FLT
                    SLDC 0
                    SLDC 0
                    CLP 4
                    STM 2
                    LOD 1, 3
                    SLDO4
                    SLDC 4
                    CXP 0, 13
                    CSP IOC
                    LOD 1, 3
                    SLDO6
                    SLDC 0
                    CXP 0, 17
                    CSP IOC
                    LOD 1, 3
                    LAO 7
                    LDM 2
                    SLDC 6
                    SLDC 2
                    CXP 31, 4
                    CSP IOC
                    LOD 1, 3
                    SLDC 32
                    SLDC 0
                    CXP 0, 17
                    CSP IOC
                    LOD 1, 3
                    SLDO6
                    SLDC 0
                    CXP 0, 13
                    CSP IOC
                    LOD 1, 3
                    CXP 0, 22
                    CSP IOC
                    LOD 1, 2
                    LAO 6
                    CXP 0, 16
                    CSP IOC
                    LOD 1, 2
                    LAO 4
                    CXP 0, 12
                    CSP IOC
                    LOD 1, 2
                    LAO 3
                    CXP 0, 12
                    CSP IOC
                    LOD 1, 2
                    CXP 0, 21
                    CSP IOC
                    SLDO4
                    SLDC 3
                    DVI
                    SLDC 2
                    MODI
                    SRO 4
                    SLDO4
                    NGI
                    SRO 4
                    SLDO4
                    ABI
                    SRO 4
                    SLDO4
                    SQI
                    SRO 4
                    LAO 7
                    LAO 7
                    LDM 2
                    SLDC 2
                    FLT
                    DVR
                    STM 2
                    LAO 7
                    LDM 2
                    CSP TNC
                    SRO 4
                    LAO 7
                    LDM 2
                    CSP RND
                    SRO 4
                    SLDO4
                    FJP L0158
                    SLDO4
                    SLDC 1
                    ADI
                    SRO 4
                    UJP L015D
            L0158:
                    SLDO4
                    SLDC 1
                    SBI
                    SRO 4
            L015D:
            Exit:
                    SLDC 31
                    CSP RSEG
                    UJP L0167
            L0162:
                    SLDC 31
                    CSP GSEG
                    UJPT T016A
            L0167:
                    RBP 0
                    .byte $00
            T016A:  .word * - L003E
            T016C:  .word * - L0162
            T016E:  .word * - L0057
            T0170:  .word * - L0045
                    .word 14, 4
                    .word * - Exit, * - Entry
            Attributes: .byte 1, 0
            .endscope
                    .word * - P4::Attributes
                    .word * - P3::Attributes
                    .word * - P2::Attributes
                    .word * - P1::Attributes
                    .byte 1, 4
            .endscope
            Segment0End:
                    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
                    .byte $00, $00, $00, $00, $00, $00, $11, $41, $50, $50, $4C, $45
                    .byte $31, $3A, $53, $59, $53, $54, $45, $4D, $2E, $57, $52, $4B
                    .byte $2E, $54, $45, $58, $54, $00, $00, $00, $00, $00, $00, $00
                    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
                    .byte $13, $2A, $53, $59, $53, $54, $45, $4D, $2E, $57, $52, $4B
                    .byte $2E, $43, $4F, $44, $45, $5B, $2A, $5D, $00, $00, $00, $00
                    .byte $12, $00, $01, $00, $16, $41, $50, $50, $4C, $45, $32, $3A
                    .byte $53, $59, $53, $54, $45, $4D, $2E, $53, $57, $41, $50, $44
                    .byte $49, $53, $4B, $00, $00, $00, $00, $00, $00, $00, $00, $00
                    .byte $00, $00
            """;
}
