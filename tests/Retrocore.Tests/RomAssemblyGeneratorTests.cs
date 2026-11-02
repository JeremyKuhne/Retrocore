// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

extern alias Generator;
using Generator::Retrocore.Generators;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using System.Reflection;

namespace Retrocore.Tests;

/// <summary>
///  Tests actual assembly encoding, label layout, build diagnostics, and incremental generation.
/// </summary>
[TestClass]
public class RomAssemblyGeneratorTests
{
    private const string Header = ".rom TestFirmware.Rom, $C700, $100\n.cpu Mos6502\n";

    /// <summary>
    ///  The <c>;;</c> summaries of exported symbols become the generated members' XML documentation, with links
    ///  to other exports as cref links and inherited summaries resolved.
    /// </summary>
    [TestMethod]
    public void ExportSummariesBecomeXmlDocumentation()
    {
        GeneratorDriver driver = Driver(new InMemoryAdditionalText(Header + """
            .export Entry, Other, Second, Mask
            Mask = 4                            ;; A mask & more.
            ;; Starts here; see <Other> and <Elsewhere>, `code` and {A}.
            ;; Entry: Second = skips a byte
            Entry:
                nop
            Second:
                rts
            ;; The other one.
            Other:
                rts
            """, path: "Test.rom.asm"))
            .RunGenerators(Compilation());

        string generated = driver.GetRunResult().GeneratedTrees.Single().ToString();
        generated.Should().Contain(
            "    /// <summary>\n    ///  Starts here; see <see cref=\"Other\"/> and <c>Elsewhere</c>, <c>code</c> and <c>A</c>.\n    /// </summary>\n    internal const int Entry");

        generated.Should().Contain("///  A mask &amp; more.");
        generated.Should().Contain("///  The other one.");
        generated.Should().Contain("///  Starts here;", Exactly.Twice(), "an entry label shares its routine's summary");
    }

    /// <summary>
    ///  Merlin source uses the ROM header's padded image and the source generator's declared include resolver.
    /// </summary>
    [TestMethod]
    public void MerlinGeneratesPaddedRomWithIncludesAndMacros()
    {
        GeneratorDriver driver = Driver(
            new InMemoryAdditionalText("""
                ; retrocore: dialect=merlin
                .rom TestFirmware.Rom, $C700, $100
                        PUT "macros.S"
                Entry   PMC EMIT,3
                        ENT Entry
                        ASC "A"00
                """, path: "Test.rom.asm"),
            new InMemoryAdditionalText("EMIT MAC\n     LDA #]1\n     EOM", path: "macros.S"))
            .RunGenerators(Compilation());

        byte[] bytes = Bytes(driver);
        bytes.Take(4).Should().Equal((byte)0xA9, (byte)3, (byte)0xC1, (byte)0);
        bytes.Length.Should().Be(256);
        bytes.Skip(4).Should().OnlyContain(value => value == 0);
        driver.GetRunResult().GeneratedTrees.Single().ToString().Should().Contain("const int Entry = 50944");
    }

    /// <summary>
    ///  Shared ca65 types, character maps and extended data directives work in the netstandard generator.
    /// </summary>
    [TestMethod]
    public void Ca65BreadthGeneratesPaddedRom()
    {
        GeneratorDriver driver = Run("; retrocore: dialect=ca65\n" + Header + """
            .struct Packet
            Count .byte
            Address .word
            .endstruct
            .charmap 'A',$C1
            .byte Packet::Address
            .asciiz "A"
            .faraddr $123456
            .define Value 5
            .byte Value
            Entry:nop
            .export Entry
            """);

        byte[] bytes = Bytes(driver);
        bytes.Take(8).Should().Equal((byte)1, (byte)0xC1, (byte)0, (byte)0x56, (byte)0x34, (byte)0x12, (byte)5, (byte)0xEA);
        bytes.Length.Should().Be(256);
        bytes.Skip(8).Should().OnlyContain(value => value == 0);
    }

    /// <summary>
    ///  The actual linked ca65 front end emits one bounded, padded ROM with plain exported members.
    /// </summary>
    [TestMethod]
    public void Ca65SourcesGenerateByteExactPaddedRom()
    {
        GeneratorDriver driver = Run("; retrocore: dialect=ca65\n" + Header + """
            .setcpu "65C02"
            .code
            .macro Emit arg
            :lda #arg
            bne :-
            .endmac
            Emit $42
            .addr ::Entry
            .proc Entry
            stz $20
            rts
            .endproc
            .export Entry
            """);

        byte[] bytes = Bytes(driver);
        bytes.Length.Should().Be(256);
        bytes.Take(
            9).Should().Equal(
                (byte)0xA9,
                (byte)0x42,
                (byte)0xD0,
                (byte)0xFC,
                (byte)6,
                (byte)0xC7,
                (byte)0x64,
                (byte)0x20,
                (byte)0x60);

        bytes.Skip(9).Should().OnlyContain(value => value == 0);
        driver.GetRunResult().GeneratedTrees.Single().ToString().Should().Contain("const int Entry = 50950");
    }

    /// <summary>
    ///  Includes and native macros are resolved from AdditionalFiles without filesystem fallback.
    /// </summary>
    [TestMethod]
    public void IncludesAndMacrosUseDeclaredAdditionalFiles()
    {
        GeneratorDriver driver = Driver(
            new InMemoryAdditionalText(Header + ".include \"sdk.inc\"\nEmit Value", path: "Test.rom.asm"),
            new InMemoryAdditionalText("Value = $42\n.macro Emit arg\nlda #arg\n.endmacro", path: "sdk.inc"))
            .RunGenerators(Compilation());

        Bytes(driver).Take(2).Should().Equal((byte)0xA9, (byte)0x42);
    }

    /// <summary>
    ///  Scopes, plain export aliases and anonymous macro branches work in the linked generator.
    /// </summary>
    [TestMethod]
    public void ScopedIncludesAndMacrosGenerateCompilableExports()
    {
        GeneratorDriver driver = Driver(
            new InMemoryAdditionalText(Header + """
                Value = 1
                .scope Firmware
                Value = $42
                .proc Entry
                .include "body.inc"
                Emit Value
                Emit $43
                Read Firmware
                @done: rts
                .export Entry, Value
                .endproc
                .endscope
                .word Firmware::Entry, ::Value
                """, path: "Test.rom.asm"),
            new InMemoryAdditionalText(
                ".macro Emit arg\n:lda #arg\nbne :-\n.endmacro\n.macro Read Namespace\n.byte Namespace::Value\n.endmacro",
                path: "body.inc"));

        driver = driver.RunGeneratorsAndUpdateCompilation(Compilation(), out Compilation output, out var diagnostics);
        diagnostics.Should().BeEmpty();
        output.GetDiagnostics().Where(diagnostic => diagnostic.Severity == DiagnosticSeverity.Error).Should().BeEmpty();
        Bytes(driver).Take(14).Should().Equal(
            (byte)0xA9,
            (byte)0x42,
            (byte)0xD0,
            (byte)0xFC,
            (byte)0xA9,
            (byte)0x43,
            (byte)0xD0,
            (byte)0xFC,
            (byte)0x42,
            (byte)0x60,
            (byte)0,
            (byte)0xC7,
            (byte)1,
            (byte)0);

        string generated = driver.GetRunResult().GeneratedTrees.Single().ToString();
        generated.Should().Contain("const int Entry = 50944");
        generated.Should().Contain("const int Value = 66");
    }

    /// <summary>
    ///  Scope-resolution errors retain the included macro's physical and expansion locations.
    /// </summary>
    [TestMethod]
    public void ScopeDiagnosticsRetainExpansionLocations()
    {
        GeneratorDriverRunResult result = Driver(
            new InMemoryAdditionalText(Header + ".include \"scope.inc\"\nBroken", path: "Test.rom.asm"),
            new InMemoryAdditionalText(
                ".macro Broken\n.scope Inner\n.byte Missing\n.endscope\n.endmacro",
                path: "scope.inc"))
            .RunGenerators(Compilation()).GetRunResult();

        result.GeneratedTrees.Should().BeEmpty();
        Diagnostic error = result.Diagnostics.Single();
        error.GetMessage().Should().Contain("Unresolved");
        error.Location.GetLineSpan().Path.Should().Be("scope.inc");
        error.Location.GetLineSpan().StartLinePosition.Line.Should().Be(2);
        error.AdditionalLocations.Should().Contain(location => location.GetLineSpan().Path == "Test.rom.asm");
    }

    /// <summary>
    ///  An edit to an included AdditionalFile invalidates the ROM output.
    /// </summary>
    [TestMethod]
    public void IncludeEditsInvalidateIncrementalOutput()
    {
        InMemoryAdditionalText include = new("Value = 1", path: "values.inc");
        GeneratorDriver driver = Driver(
            new InMemoryAdditionalText(Header + ".include \"values.inc\"\n.byte Value", path: "Test.rom.asm"),
            include).RunGenerators(Compilation());

        Bytes(driver)[0].Should().Be(1);
        driver = driver.ReplaceAdditionalText(include, new InMemoryAdditionalText("Value = 2", path: "values.inc"))
            .RunGenerators(Compilation());

        Bytes(driver)[0].Should().Be(2);
    }

    /// <summary>
    ///  Macro-body errors identify the include and expose invocation sites as additional locations.
    /// </summary>
    [TestMethod]
    public void ExpansionDiagnosticsHavePhysicalAndAdditionalLocations()
    {
        GeneratorDriverRunResult result = Driver(
            new InMemoryAdditionalText(Header + ".include \"bad.inc\"\nBroken", path: "Test.rom.asm"),
            new InMemoryAdditionalText(".macro Broken\nlda #$100\n.endmacro", path: "bad.inc"))
            .RunGenerators(Compilation()).GetRunResult();

        Diagnostic error = result.Diagnostics.Single();
        error.Location.GetLineSpan().Path.Should().Be("bad.inc");
        error.Location.GetLineSpan().StartLinePosition.Line.Should().Be(1);
        error.AdditionalLocations.Should().Contain(location => location.GetLineSpan().Path == "Test.rom.asm");
    }

    /// <summary>
    ///  Binary includes are explicitly unsupported in the generator's text-only resolver.
    /// </summary>
    [TestMethod]
    public void BinaryIncludesProduceAnExplicitGeneratorError()
    {
        GeneratorDriverRunResult result = Run(Header + ".incbin \"binary.bin\"").GetRunResult();
        result.GeneratedTrees.Should().BeEmpty();
        result.Diagnostics.Single().GetMessage().Should().Contain("Binary includes");
    }

    /// <summary>
    ///  Verifies compiler primitives also work in the actual netstandard generator.
    /// </summary>
    [TestMethod]
    public void SharedPrimitivesGenerateByteExactRomOutput()
    {
        GeneratorDriver driver = Run(Header + """
            .set N, 1
            .dum $20
            Work: .res 4
            .dend
            .logicalorg $8000
            .byte N
            .set N, N + 1
            .byte N
            .align 4, $EA
            .dword $12345678
            .cpu Wdc65C02
            stz z:Work
            .export N, Work
            """);

        Bytes(driver).Take(10).Should().Equal(
            (byte)1,
            (byte)2,
            (byte)0xEA,
            (byte)0xEA,
            (byte)0x78,
            (byte)0x56,
            (byte)0x34,
            (byte)0x12,
            (byte)0x64,
            (byte)0x20);

        driver.GetRunResult().GeneratedTrees[0].ToString().Should().Contain("const int N = 2");
    }

    /// <summary>
    ///  Verifies labels, forward low/high extraction, directives, padding and exported constants.
    /// </summary>
    [TestMethod]
    public void AssemblesForwardLabelsAndDataIntoStaticSpan()
    {
        string source = Header + """
            .export Driver
            Mailbox = $42
            lda #<Driver
            ldx #>Driver
            sta Mailbox
            jsr Driver
            .org $C710
            Driver:
            rts
            .byte ' ', ';', %01010101
            .word Driver
            .res 2, $AA
            .assert * == $C718
            """;

        GeneratorDriver driver = Run(source);
        byte[] bytes = Bytes(driver);
        bytes.Length.Should().Be(256);
        bytes.Take(
            9).Should().Equal(
                (byte)0xA9,
                (byte)0x10,
                (byte)0xA2,
                (byte)0xC7,
                (byte)0x85,
                (byte)0x42,
                (byte)0x20,
                (byte)0x10,
                (byte)0xC7);

        bytes.Skip(9).Take(7).Should().OnlyContain(value => value == 0);
        bytes.Skip(
            16).Take(
                8).Should().Equal(
                    (byte)0x60,
                    (byte)0x20,
                    (byte)0x3B,
                    (byte)0x55,
                    (byte)0x10,
                    (byte)0xC7,
                    (byte)0xAA,
                    (byte)0xAA);

        driver.GetRunResult().GeneratedTrees[0].ToString().Should().Contain("const int Driver = 50960");
    }

    /// <summary>
    ///  Verifies automatic zero-page layout converges for forward symbols.
    /// </summary>
    [TestMethod]
    public void ForwardZeroPageLabelsStabilizeBeforeEmission()
    {
        byte[] bytes = Bytes(Run(".rom TestFirmware.Rom, $00, $100\n.cpu Mos6502\nlda Target\nTarget:\n.byte 5"));
        bytes.Take(3).Should().Equal((byte)0xA5, (byte)2, (byte)5);
    }

    /// <summary>
    ///  Verifies immediate, indexed, indirect, accumulator and branch encodings are mnemonic based.
    /// </summary>
    [TestMethod]
    public void EncodesDocumentedAddressingModesAndBranches()
    {
        string source = Header + """
            Start:
            lda #1
            sta $10,X
            ldx $10,Y
            lda $1234,X
            sta $1234,Y
            lda ($20,X)
            lda ($20),Y
            asl A
            nop
            bne Start
            jmp ($1234)
            """;

        Bytes(Run(source)).Take(23).Should().Equal(
            (byte)0xA9,
            (byte)1,
            (byte)0x95,
            (byte)0x10,
            (byte)0xB6,
            (byte)0x10,
            (byte)0xBD,
            (byte)0x34,
            (byte)0x12,
            (byte)0x99,
            (byte)0x34,
            (byte)0x12,
            (byte)0xA1,
            (byte)0x20,
            (byte)0xB1,
            (byte)0x20,
            (byte)0x0A,
            (byte)0xEA,
            (byte)0xD0,
            (byte)0xEC,
            (byte)0x6C,
            (byte)0x34,
            (byte)0x12);
    }

    /// <summary>
    ///  Verifies CMOS and numbered bit instructions use the selected CPU's canonical map.
    /// </summary>
    [TestMethod]
    public void SelectsCmosAndBitOperationEncodings()
    {
        byte[] bytes = Bytes(Run(Header.Replace("Mos6502", "Wdc65C02") + "stz $10\nrmb3 $11\nbbs2 $12,Done\nDone:\nwai"));
        bytes.Take(8).Should().Equal((byte)0x64,(byte)0x10,(byte)0x37,(byte)0x11,(byte)0xAF,(byte)0x12,(byte)0,(byte)0xCB);
    }

    /// <summary>
    ///  Verifies branch offsets wrap the program counter at the 16-bit boundary.
    /// </summary>
    [TestMethod]
    public void RelativeBranchUsesWrappedNextInstructionAddress()
    {
        Bytes(Run(".rom TestFirmware.Rom, $FFFE, 2\n.cpu Mos6502\nbne $0000"))
            .Should().Equal((byte)0xD0, (byte)0);
    }

    /// <summary>
    ///  Verifies the exact signed branch range, including both accepted endpoints.
    /// </summary>
    /// <param name="target">The absolute branch target.</param>
    /// <param name="displacement">The encoded displacement.</param>
    [TestMethod]
    [DataRow("$C781", (byte)0x7F)]
    [DataRow("$C682", (byte)0x80)]
    public void BranchRangeEndpointsAreEncodedExactly(string target, byte displacement)
    {
        Bytes(Run(Header + "bne " + target)).Take(2).Should().Equal((byte)0xD0, displacement);
    }

    /// <summary>
    ///  Verifies editing only the assembly input regenerates the stream.
    /// </summary>
    [TestMethod]
    public void AssemblyEditsInvalidateIncrementalOutput()
    {
        CSharpCompilation compilation = Compilation();
        InMemoryAdditionalText original = new(Header + "lda #1", path: "Test.rom.asm");
        GeneratorDriver driver = Driver(original).RunGenerators(compilation);
        Bytes(driver)[1].Should().Be(1);
        driver = driver.ReplaceAdditionalText(original, new InMemoryAdditionalText(Header + "lda #2", path: "Test.rom.asm"))
            .RunGenerators(compilation);

        Bytes(driver)[1].Should().Be(2);
    }

    /// <summary>
    ///  Verifies the generated ROM is valid C# code, not only a syntactically inspected byte list.
    /// </summary>
    [TestMethod]
    public void GeneratedRomCompilesWithExportedSymbols()
    {
        GeneratorDriver driver = Driver(new InMemoryAdditionalText(
            Header + ".export Entry\nEntry:\nlda #1\nrts",
            path: "Test.rom.asm"));

        driver.RunGeneratorsAndUpdateCompilation(Compilation(), out Compilation output, out var diagnostics);
        diagnostics.Should().BeEmpty();
        output.GetDiagnostics().Where(diagnostic => diagnostic.Severity == DiagnosticSeverity.Error).Should().BeEmpty();
    }

    /// <summary>
    ///  Checks pooled source emission covers partial rows and the entire 16-bit image space.
    /// </summary>
    /// <param name="size">The exact padded byte count.</param>
    [TestMethod]
    [DataRow(1)]
    [DataRow(16)]
    [DataRow(17)]
    [DataRow(65536)]
    public void EmittedImagesHaveTheExactRequestedSize(int size)
    {
        string source = $".rom TestFirmware.Rom, 0, {size}\n.cpu Mos6502\nnop";
        byte[] bytes = Bytes(Run(source));
        bytes.Length.Should().Be(size);
        bytes[0].Should().Be(0xEA);
        bytes.Skip(1).Should().OnlyContain(value => value == 0);
    }

    /// <summary>
    ///  Verifies an unreadable assembly input produces an explicit build error.
    /// </summary>
    [TestMethod]
    public void UnreadableAssemblyReportsDiagnostic()
    {
        GeneratorDriverRunResult result = Driver(new InMemoryAdditionalText(text: null, path: "Test.rom.asm"))
            .RunGenerators(Compilation()).GetRunResult();

        result.GeneratedTrees.Should().BeEmpty();
        result.Diagnostics.Should().ContainSingle(error => error.Id == "RCGEN002");
        result.Diagnostics[0].GetMessage().Should().Contain("could not be read");
    }

    /// <summary>
    ///  Verifies one build reports every independent error, each at its own source line.
    /// </summary>
    [TestMethod]
    public void EveryIndependentErrorIsReported()
    {
        GeneratorDriverRunResult result = Run(Header + "lda #$100\nnop\n.assert 0\nlda? 1").GetRunResult();
        result.GeneratedTrees.Should().BeEmpty();
        result.Diagnostics.Should().ContainSingle(error => error.GetMessage().Contains("Invalid assembly statement"));

        result = Run(Header + "lda #$100\nnop\n.assert 0").GetRunResult();
        result.Diagnostics.Select(error => error.Location.GetLineSpan().StartLinePosition.Line).Should().Equal(2, 4);
    }

    /// <summary>
    ///  Verifies bad operands, labels, layout and directives produce source-located compile errors.
    /// </summary>
    /// <param name="source">The invalid assembly body.</param>
    /// <param name="message">The expected diagnostic fragment.</param>
    [TestMethod]
    [DataRow("lda #256", "byte range")]
    [DataRow("lda #-1", "byte range")]
    [DataRow("lda Missing", "Unresolved")]
    [DataRow("lda ($1234),Y", "byte range")]
    [DataRow("stz $10", "unsupported")]
    [DataRow("bogus", "Unknown")]
    [DataRow("bne $D000", "signed 8-bit")]
    [DataRow("A:\nA:", "Duplicate")]
    [DataRow("Value = 1\nValue = 2", "Duplicate")]
    [DataRow(".org $C600", "backwards")]
    [DataRow(".org $C900", "exceeds")]
    [DataRow(".res 257", "exceeds")]
    [DataRow(".res -1", "exceeds")]
    [DataRow(".res 2,$100", "byte range")]
    [DataRow(".word $10000", "16-bit")]
    [DataRow(".byte 1,", "Empty")]
    [DataRow(".assert 0", "assertion failed")]
    [DataRow(".include \"other.s\"", "was not found")]
    [DataRow(".export Missing", "unresolved")]
    [DataRow(".export Bytes", "Invalid")]
    [DataRow("lda #(1/0)", "Division by zero")]
    [DataRow("lda #(1<<64)", "shift")]
    [DataRow("lda #9223372036854775808", "overflow")]
    [DataRow("lda #'AB'", "one character")]
    [DataRow(".section Extra, $D000, 1", "single section")]
    public void InvalidAssemblyProducesDiagnostics(string source, string message)
    {
        GeneratorDriverRunResult result = Run(Header + source).GetRunResult();
        result.GeneratedTrees.Should().BeEmpty();
        result.Diagnostics.Should().ContainSingle();
        Diagnostic error = result.Diagnostics[0];
        error.Id.Should().Be("RCGEN002");
        error.Severity.Should().Be(DiagnosticSeverity.Error);
        error.GetMessage().Should().Contain(message);
        error.Location.GetLineSpan().Path.Should().Be("Test.rom.asm");
    }

    /// <summary>
    ///  Verifies malformed ROM metadata fails before allocation or code emission.
    /// </summary>
    /// <param name="source">The malformed source.</param>
    [TestMethod]
    [DataRow(".cpu Mos6502\nnop")]
    [DataRow(".rom TestFirmware.Rom,$C700,$100\nnop")]
    [DataRow(".rom TestFirmware.Rom,$10000,1\n.cpu Mos6502")]
    [DataRow(".rom TestFirmware.Rom,$C700,0\n.cpu Mos6502")]
    [DataRow(".rom TestFirmware.Rom,$C700,9223372036854775807\n.cpu Mos6502")]
    [DataRow(".rom TestFirmware.class,$C700,256\n.cpu Mos6502")]
    [DataRow(".rom TestFirmware.Rom,$C700,256\n.cpu UnknownCpu")]
    public void InvalidMetadataProducesBuildError(string source)
    {
        GeneratorDriverRunResult result = Run(source).GetRunResult();
        result.GeneratedTrees.Should().BeEmpty();
        result.Diagnostics.Should().ContainSingle(error => error.Id == "RCGEN002");
    }

    private static GeneratorDriver Run(string source) =>
        Driver(new InMemoryAdditionalText(source, path: "Test.rom.asm")).RunGenerators(Compilation());

    private static CSharpGeneratorDriver Driver(AdditionalText assembly, params AdditionalText[] includes) => CSharpGeneratorDriver.Create(
        generators: [new RomAssemblyGenerator().AsSourceGenerator()],
        additionalTexts:
        [
            new InMemoryAdditionalText(File.ReadAllText(Path.Join(AppContext.BaseDirectory, "Inputs", "OpcodeTables.txt"))),
            assembly,
            .. includes
        ],
        parseOptions: new CSharpParseOptions(LanguageVersion.CSharp12));

    private static CSharpCompilation Compilation() => CSharpCompilation.Create(
        "RomAssemblyFixture",
        syntaxTrees: [CSharpSyntaxTree.ParseText("namespace TestFirmware;", new CSharpParseOptions(LanguageVersion.CSharp12))],
        references:
        [
            MetadataReference.CreateFromFile(typeof(object).Assembly.Location),
            MetadataReference.CreateFromFile(Assembly.Load("System.Runtime").Location),
            MetadataReference.CreateFromFile(typeof(OpCode).Assembly.Location)
        ],
        options: new CSharpCompilationOptions(OutputKind.DynamicallyLinkedLibrary));

    private static byte[] Bytes(GeneratorDriver driver)
    {
        GeneratorDriverRunResult result = driver.GetRunResult();
        result.Diagnostics.Should().BeEmpty();
        result.GeneratedTrees.Should().ContainSingle();
        PropertyDeclarationSyntax property = result.GeneratedTrees[0].GetRoot().DescendantNodes()
            .OfType<PropertyDeclarationSyntax>().Single(node => node.Identifier.ValueText == "Bytes");

        if (property.ExpressionBody?.Expression is not CollectionExpressionSyntax collection)
        {
            throw new InvalidOperationException("The assembled output must be a constant byte-span collection.");
        }

        List<byte> bytes = [];
        foreach (CollectionElementSyntax element in collection.Elements)
        {
            if (element is not ExpressionElementSyntax { Expression: LiteralExpressionSyntax literal }
                || literal.Token.Value is not int value
                || value is < 0 or > 255)
            {
                throw new InvalidOperationException("ROM output contains a nonconstant byte.");
            }

            bytes.Add((byte)value);
        }

        return [.. bytes];
    }
}
