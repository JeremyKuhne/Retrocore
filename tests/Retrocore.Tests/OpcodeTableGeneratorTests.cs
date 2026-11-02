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
///  Tests symbolic opcode generation, build diagnostics, and incremental input changes.
/// </summary>
[TestClass]
public class OpcodeTableGeneratorTests
{
    private const string EnumSource = """
        namespace Retrocore.Cpu.M6502;
        public enum ProcessorVariant { Mos6502, Wdc65C02, Rockwell65C02 }
        public enum Instruction : byte { NOP = 0x24, LDA = 0x20 }
        public enum AddressMode : byte { Implied = 0x07, Immediate = 0x06 }
        internal static partial class OpcodeTable { }
        """;

    private static string BaseDefinitions => "[Mos6502]\n" + string.Join(
        "\n",
        Enumerable.Range(0, 256).Select(code => $"{code:X2} NOP Implied"));

    private static string Definitions => BaseDefinitions
        + "\n[Wdc65C02 : Mos6502]\n[Rockwell65C02 : Wdc65C02]\nCB LDA Immediate";

    /// <summary>
    ///  Verifies byte values come from enums, inherited tables are independent, and output compiles.
    /// </summary>
    [TestMethod]
    public void GeneratesConstantSpansAndInheritedOverrides()
    {
        GeneratorDriver driver = Driver(new InMemoryAdditionalText(Definitions));
        driver = driver.RunGeneratorsAndUpdateCompilation(Compilation(), out Compilation output, out var diagnostics);
        diagnostics.Should().BeEmpty();
        output.GetDiagnostics().Where(diagnostic => diagnostic.Severity == DiagnosticSeverity.Error).Should().BeEmpty();
        byte[] nmos = Bytes(driver, "Mos6502");
        byte[] wdc = Bytes(driver, "Wdc65C02");
        byte[] rockwell = Bytes(driver, "Rockwell65C02");
        nmos.Length.Should().Be(768);
        wdc.Should().Equal(nmos);
        for (int code = 0; code < 256; code++)
        {
            int start = code * 3;
            nmos[start..(start + 3)].Should().Equal((byte)code, (byte)0x07, (byte)0x24);
            rockwell[start..(start + 3)].Should().Equal(
                (byte)code,
                code == 0xCB ? (byte)0x06 : (byte)0x07,
                code == 0xCB ? (byte)0x20 : (byte)0x24);
        }
    }

    /// <summary>
    ///  Verifies definition edits invalidate generated output without changing the compilation.
    /// </summary>
    [TestMethod]
    public void AdditionalTextChangesRegenerateTables()
    {
        InMemoryAdditionalText original = new(Definitions);
        CSharpCompilation compilation = Compilation();
        GeneratorDriver driver = Driver(original).RunGenerators(compilation);
        Bytes(driver, "Mos6502")[2].Should().Be(0x24);
        InMemoryAdditionalText updated = new(Definitions.Replace("00 NOP Implied", "00 LDA Immediate"));
        driver = driver.ReplaceAdditionalText(original, updated).RunGenerators(compilation);
        Bytes(driver, "Mos6502").Take(3).Should().Equal((byte)0, (byte)0x06, (byte)0x20);
        Bytes(driver, "Wdc65C02").Take(3).Should().Equal((byte)0, (byte)0x06, (byte)0x20);
    }

    /// <summary>
    ///  Verifies enum value edits invalidate output even when the definition file is unchanged.
    /// </summary>
    [TestMethod]
    public void EnumValueChangesRegenerateEncoding()
    {
        GeneratorDriver driver = Driver(new InMemoryAdditionalText(Definitions)).RunGenerators(Compilation());
        string updated = EnumSource.Replace("NOP = 0x24", "NOP = 0x35").Replace("Implied = 0x07", "Implied = 0x0A");
        driver = driver.RunGenerators(Compilation(updated));
        Bytes(driver, "Mos6502").Take(3).Should().Equal((byte)0, (byte)0x0A, (byte)0x35);
        Bytes(driver, "Rockwell65C02").Skip(0xCB * 3).Take(3).Should().Equal((byte)0xCB, (byte)0x06, (byte)0x20);
    }

    /// <summary>
    ///  Verifies malformed, unknown, duplicate, incomplete, and invalid inheritance inputs fail at build time.
    /// </summary>
    /// <param name="scenario">The invalid input scenario.</param>
    /// <param name="message">The expected diagnostic message fragment.</param>
    [TestMethod]
    [DataRow("entry-before-section", "Expected a CPU section")]
    [DataRow("bad-opcode", "Expected a CPU section")]
    [DataRow("bad-entry", "Expected a CPU section")]
    [DataRow("unknown-instruction", "Unknown Instruction")]
    [DataRow("unknown-mode", "Unknown Instruction")]
    [DataRow("duplicate-entry", "defined more than once")]
    [DataRow("missing-opcode", "missing opcode 00")]
    [DataRow("missing-section", "CPU section 'Wdc65C02' is missing")]
    [DataRow("unknown-section", "Unknown, malformed, or duplicate")]
    [DataRow("duplicate-section", "Unknown, malformed, or duplicate")]
    [DataRow("malformed-section", "Unknown, malformed, or duplicate")]
    [DataRow("unknown-base", "must appear earlier")]
    [DataRow("incomplete-base", "must appear earlier")]
    [DataRow("forward-base", "must appear earlier")]
    [DataRow("duplicate-override", "defined more than once")]
    public void InvalidDefinitionsReportBuildErrors(string scenario, string message)
    {
        string invalid = scenario switch
        {
            "entry-before-section" => "00 NOP Implied",
            "bad-opcode" => Definitions.Replace("00 NOP", "GG NOP"),
            "bad-entry" => Definitions.Replace("00 NOP Implied", "00 NOP"),
            "unknown-instruction" => Definitions.Replace("00 NOP", "00 UNKNOWN"),
            "unknown-mode" => Definitions.Replace("00 NOP Implied", "00 NOP UNKNOWN"),
            "duplicate-entry" => Definitions.Replace("01 NOP", "00 NOP"),
            "missing-opcode" => BaseDefinitions.Replace("00 NOP Implied\n", ""),
            "missing-section" => BaseDefinitions + "\n[Rockwell65C02 : Mos6502]",
            "unknown-section" => Definitions.Replace("[Mos6502]", "[UnknownCpu]"),
            "duplicate-section" => Definitions + "\n[Mos6502]",
            "malformed-section" => "[Mos6502 : Wdc65C02 : Rockwell65C02]",
            "unknown-base" => BaseDefinitions + "\n[Wdc65C02 : UnknownCpu]",
            "incomplete-base" => "[Mos6502]\n00 NOP Implied\n[Wdc65C02 : Mos6502]",
            "forward-base" => "[Rockwell65C02 : Wdc65C02]\n" + Definitions,
            "duplicate-override" => Definitions + "\nCB LDA Immediate",
            _ => throw new ArgumentOutOfRangeException(nameof(scenario))
        };

        GeneratorDriver driver = Driver(new InMemoryAdditionalText(invalid)).RunGenerators(Compilation());
        Diagnostic diagnostic = Error(driver);
        diagnostic.GetMessage().Should().Contain(message);
        diagnostic.Location.GetLineSpan().Path.Should().Be("OpcodeTables.txt");
    }

    /// <summary>
    ///  Verifies input discovery handles missing, duplicate, unrelated, and unreadable additional files.
    /// </summary>
    /// <param name="scenario">The input discovery scenario.</param>
    [TestMethod]
    [DataRow("missing")]
    [DataRow("duplicate")]
    [DataRow("unrelated")]
    [DataRow("unreadable")]
    public void InputDiscoveryFailuresAreExplicit(string scenario)
    {
        AdditionalText[] files = scenario switch
        {
            "missing" => [],
            "duplicate" => [new InMemoryAdditionalText(Definitions), new InMemoryAdditionalText(Definitions)],
            "unrelated" => [new InMemoryAdditionalText(Definitions, path: "Other.txt")],
            "unreadable" => [new InMemoryAdditionalText(text: null)],
            _ => throw new ArgumentOutOfRangeException(nameof(scenario))
        };

        Error(Driver(files).RunGenerators(Compilation())).GetMessage().Should().Contain(
            scenario == "unreadable" ? "could not be read" : "Exactly one");
    }

    /// <summary>
    ///  Verifies unsupported enum layouts, aliases, and missing enum types fail explicitly.
    /// </summary>
    /// <param name="scenario">The invalid enum scenario.</param>
    [TestMethod]
    [DataRow("wrong-underlying-type")]
    [DataRow("duplicate-values")]
    [DataRow("missing-type")]
    public void InvalidEnumsReportBuildErrors(string scenario)
    {
        string source = scenario switch
        {
            "wrong-underlying-type" => EnumSource.Replace("Instruction : byte", "Instruction : int"),
            "duplicate-values" => EnumSource.Replace("Immediate = 0x06", "Immediate = 0x07"),
            "missing-type" => EnumSource.Replace("enum AddressMode", "enum OtherType"),
            _ => throw new ArgumentOutOfRangeException(nameof(scenario))
        };

        Error(Driver(new InMemoryAdditionalText(Definitions)).RunGenerators(Compilation(source)))
            .GetMessage().Should().Contain("byte enums with unique values");
    }

    /// <summary>
    ///  Verifies comments, whitespace, and lowercase opcode digits do not alter generated bytes.
    /// </summary>
    [TestMethod]
    public void DefinitionFormattingDoesNotChangeOutput()
    {
        string formatted = Definitions.Replace("CB LDA Immediate", "cb\tLDA  Immediate # override");
        GeneratorDriver driver = Driver(new InMemoryAdditionalText("# header\n\n" + formatted)).RunGenerators(Compilation());
        Bytes(driver, "Rockwell65C02").Skip(0xCB * 3).Take(3).Should().Equal((byte)0xCB, (byte)0x06, (byte)0x20);
    }

    private static CSharpCompilation Compilation(string source = EnumSource) => CSharpCompilation.Create(
        "OpcodeGeneratorFixture",
        syntaxTrees: [CSharpSyntaxTree.ParseText(source, new CSharpParseOptions(LanguageVersion.CSharp12))],
        references:
        [
            MetadataReference.CreateFromFile(typeof(object).Assembly.Location),
            MetadataReference.CreateFromFile(Assembly.Load("System.Runtime").Location)
        ],
        options: new CSharpCompilationOptions(OutputKind.DynamicallyLinkedLibrary));

    private static CSharpGeneratorDriver Driver(params AdditionalText[] files) => CSharpGeneratorDriver.Create(
        generators: [new OpcodeTableGenerator().AsSourceGenerator()],
        additionalTexts: files,
        parseOptions: new CSharpParseOptions(LanguageVersion.CSharp12));

    private static Diagnostic Error(GeneratorDriver driver)
    {
        GeneratorDriverRunResult result = driver.GetRunResult();
        result.GeneratedTrees.Should().BeEmpty();
        result.Diagnostics.Should().ContainSingle();
        Diagnostic diagnostic = result.Diagnostics[0];
        diagnostic.Id.Should().Be("RCGEN001");
        diagnostic.Severity.Should().Be(DiagnosticSeverity.Error);
        return diagnostic;
    }

    private static byte[] Bytes(GeneratorDriver driver, string property)
    {
        GeneratorDriverRunResult result = driver.GetRunResult();
        result.Diagnostics.Should().BeEmpty();
        result.GeneratedTrees.Should().ContainSingle();
        PropertyDeclarationSyntax declaration = result.GeneratedTrees[0].GetRoot().DescendantNodes()
            .OfType<PropertyDeclarationSyntax>().Single(node => node.Identifier.ValueText == property);

        if (declaration.ExpressionBody?.Expression is not CollectionExpressionSyntax collection)
        {
            throw new InvalidOperationException("The generated property must be a constant byte-span collection.");
        }

        List<byte> bytes = [];
        foreach (CollectionElementSyntax element in collection.Elements)
        {
            if (element is not ExpressionElementSyntax { Expression: LiteralExpressionSyntax literal }
                || literal.Token.Value is not int value
                || value is < 0 or > 255)
            {
                throw new InvalidOperationException("Generated opcode data must contain constant byte literals.");
            }

            bytes.Add((byte)value);
        }

        return [.. bytes];
    }
}
