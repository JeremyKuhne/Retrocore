// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.Text;
using System.Collections.Immutable;
using System.Globalization;
using System.Text;

namespace Retrocore.Generators;

/// <summary>
///  Generates allocation-free opcode spans from symbolic definitions and the compilation's enum values.
/// </summary>
[Generator]
public sealed class OpcodeTableGenerator : IIncrementalGenerator
{
    private static readonly DiagnosticDescriptor s_invalidDefinition = new(
        id: "RCGEN001",
        title: "Invalid opcode definitions",
        messageFormat: "{0}",
        category: "Build",
        defaultSeverity: DiagnosticSeverity.Error,
        isEnabledByDefault: true);

    /// <summary>
    ///  Registers the definition-file and compilation inputs.
    /// </summary>
    /// <param name="context">The incremental generator initialization context.</param>
    public void Initialize(IncrementalGeneratorInitializationContext context)
    {
        IncrementalValueProvider<(ImmutableArray<AdditionalText> Left, Compilation Right)> input =
            context.AdditionalTextsProvider
                .Where(static file => System.IO.Path.GetFileName(file.Path).Equals(
                    "OpcodeTables.txt",
                    StringComparison.OrdinalIgnoreCase))
                .Collect()
                .Combine(context.CompilationProvider);

        context.RegisterSourceOutput(input, static (output, value) => Generate(output, value.Left, value.Right));
    }

    private static void Generate(
        SourceProductionContext context,
        ImmutableArray<AdditionalText> files,
        Compilation compilation)
    {
        // Only the assembly that declares OpcodeTable receives it; machines read the same file for ROM assembly.
        INamedTypeSymbol? table = compilation.GetTypeByMetadataName("Retrocore.Cpu.M6502.OpcodeTable");
        if (table is null || !SymbolEqualityComparer.Default.Equals(table.ContainingAssembly, compilation.Assembly))
        {
            return;
        }

        Dictionary<string, OpcodeMap>? maps = ReadMaps(context, files, compilation);
        if (maps is not null)
        {
            string description = files[0].GetText(context.CancellationToken)?.ToString() ?? "";
            context.AddSource("OpcodeTable.g.cs", SourceText.From(Emit(maps, description), Encoding.UTF8));
        }
    }

    /// <summary>
    ///  Reads and validates the canonical opcode definitions shared with the firmware assembler.
    /// </summary>
    /// <param name="context">The diagnostic and cancellation context.</param>
    /// <param name="files">The opcode definition input.</param>
    /// <param name="compilation">The enum declarations.</param>
    /// <returns>Validated maps, or null after reporting an input error.</returns>
    internal static Dictionary<string, OpcodeMap>? ReadMaps(
        SourceProductionContext context,
        ImmutableArray<AdditionalText> files,
        Compilation compilation)
    {
        if (files.Length != 1)
        {
            Error(context, file: null, text: null, line: -1, "Exactly one OpcodeTables.txt additional file is required.");
            return null;
        }

        AdditionalText file = files[0];
        SourceText? text = file.GetText(context.CancellationToken);
        if (text is null)
        {
            Error(context, file, text: null, line: -1, "OpcodeTables.txt could not be read.");
            return null;
        }

        Dictionary<string, byte>? instructions = EnumValues(compilation, "Retrocore.Cpu.M6502.Instruction");
        Dictionary<string, byte>? modes = EnumValues(compilation, "Retrocore.Cpu.M6502.AddressMode");
        INamedTypeSymbol? variantType = compilation.GetTypeByMetadataName("Retrocore.Cpu.M6502.ProcessorVariant");
        if (instructions is null || modes is null || variantType?.TypeKind != TypeKind.Enum)
        {
            Error(
                context,
                file,
                text,
                line: -1,
                "Instruction and AddressMode must be byte enums with unique values; ProcessorVariant must be an enum.");

            return null;
        }

        HashSet<string> variants = new(
            variantType.GetMembers().OfType<IFieldSymbol>().Where(field => field.HasConstantValue).Select(field => field.Name),
            StringComparer.Ordinal);

        Dictionary<string, OpcodeMap> maps = new(StringComparer.Ordinal);
        OpcodeMap? current = null;
        bool description = false;
        for (int lineNumber = 0; lineNumber < text.Lines.Count; lineNumber++)
        {
            context.CancellationToken.ThrowIfCancellationRequested();
            string line = text.Lines[lineNumber].ToString();
            int comment = line.IndexOf('#');
            if (comment >= 0) { line = line[..comment]; }
            line = line.Trim();
            if (line.Length == 0) { continue; }

            if (line.StartsWith("[", StringComparison.Ordinal) && line.EndsWith("]", StringComparison.Ordinal))
            {
                string[] section = line[1..^1].Split(':');
                string name = section[0].Trim();

                // The instruction-set description's own sections are for the assembler (see IsaParser).
                description = name is "isa" or "forms";
                if (description) { continue; }
                if (section.Length > 2 || !variants.Contains(name) || maps.ContainsKey(name))
                {
                    Error(context, file, text, lineNumber, $"Unknown, malformed, or duplicate CPU section '{line}'.");
                    return null;
                }

                current = new OpcodeMap(lineNumber);
                if (section.Length == 2)
                {
                    string baseName = section[1].Trim();
                    if (!maps.TryGetValue(baseName, out OpcodeMap? inherited) || inherited.Defined.Any(defined => !defined))
                    {
                        Error(
                            context,
                            file,
                            text,
                            lineNumber,
                            $"Base section '{baseName}' must appear earlier and define all 256 opcodes.");

                        return null;
                    }

                    inherited.Data.CopyTo(current.Data, index: 0);
                    inherited.Defined.CopyTo(current.Defined, index: 0);
                }

                maps.Add(name, current);
                continue;
            }

            if (description) { continue; }
            string[] entry = line.Split(separator: (char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            // A trailing 'undocumented' marks an encoding for the assembler and disassembler; the core ignores it.
            if (current is null
                || entry.Length is not (3 or 4)
                || (entry.Length == 4 && entry[3] != "undocumented")
                || entry[0].Length != 2
                || !byte.TryParse(entry[0], NumberStyles.HexNumber, CultureInfo.InvariantCulture, out byte code))
            {
                Error(
                    context,
                    file,
                    text,
                    lineNumber,
                    "Expected a CPU section followed by 'XX Instruction AddressMode [undocumented]' entries.");

                return null;
            }

            if (current.Overridden[code])
            {
                Error(context, file, text, lineNumber, $"Opcode {code:X2} is defined more than once in this section.");
                return null;
            }

            if (!instructions.TryGetValue(entry[1], out byte instruction) || !modes.TryGetValue(entry[2], out byte mode))
            {
                Error(context, file, text, lineNumber, $"Unknown Instruction or AddressMode in '{line}'.");
                return null;
            }

            int offset = code * InstructionEncoding.PackedOpcodeSize;
            current.Data[offset] = code;
            current.Data[offset + InstructionEncoding.AddressModeFieldOffset] = mode;
            current.Data[offset + InstructionEncoding.InstructionFieldOffset] = instruction;
            current.Defined[code] = true;
            current.Overridden[code] = true;
        }

        foreach (string variant in variants.OrderBy(name => name, StringComparer.Ordinal))
        {
            if (!maps.TryGetValue(variant, out OpcodeMap? map))
            {
                Error(context, file, text, line: -1, $"CPU section '{variant}' is missing.");
                return null;
            }

            int missing = Array.FindIndex(map.Defined, defined => !defined);
            if (missing >= 0)
            {
                Error(context, file, text, map.Line, $"CPU section '{variant}' is missing opcode {missing:X2}.");
                return null;
            }
        }

        return maps;
    }

    /// <summary>
    ///  Gets unique byte-valued enum members for opcode encoders.
    /// </summary>
    /// <param name="compilation">The enum declarations.</param>
    /// <param name="metadataName">The enum's fully qualified metadata name.</param>
    /// <returns>The name/value map, or null for an unsupported enum.</returns>
    internal static Dictionary<string, byte>? EnumValues(Compilation compilation, string metadataName)
    {
        INamedTypeSymbol? symbol = compilation.GetTypeByMetadataName(metadataName);
        if (symbol?.TypeKind != TypeKind.Enum || symbol.EnumUnderlyingType?.SpecialType != SpecialType.System_Byte)
        {
            return null;
        }

        Dictionary<string, byte> result = new(StringComparer.Ordinal);
        HashSet<byte> values = [];
        foreach (IFieldSymbol field in symbol.GetMembers().OfType<IFieldSymbol>().Where(field => field.HasConstantValue))
        {
            if (field.ConstantValue is not byte value || !values.Add(value)) { return null; }
            result.Add(field.Name, value);
        }

        return result;
    }

    private static string Emit(Dictionary<string, OpcodeMap> maps, string description)
    {
        List<string> lines =
        [
            "// <auto-generated/>",
            "// Copyright (c) 2025 Jeremy W Kuhne",
            "// SPDX-License-Identifier: MIT",
            "// See LICENSE file in the project root for full license information",
            "",
            "namespace Retrocore.Cpu.M6502;",
            "",
            "internal static partial class OpcodeTable",
            "{"
        ];

        foreach (KeyValuePair<string, OpcodeMap> map in maps.OrderBy(pair => pair.Key, StringComparer.Ordinal))
        {
            lines.Add($"    private static global::System.ReadOnlySpan<byte> {map.Key} =>");
            lines.Add("    [");
            for (int row = 0; row < 16; row++)
            {
                IEnumerable<string> bytes = map.Value.Data.Skip(row * 48).Take(48)
                    .Select(value => $"0x{value:X2}");

                lines.Add(row == 15 ? $"        {string.Join(", ", bytes)}" : $"        {string.Join(", ", bytes)},");
            }

            lines.Add("    ];");
            lines.Add("");
        }

        // The whole file, for the instruction-set description the assembler and tools parse at run time.
        lines.Add($"    internal const string DescriptionText = @\"{description.Replace("\"", "\"\"")}\";");
        lines.Add("}");
        return string.Join("\n", lines);
    }

    private static void Error(
        SourceProductionContext context,
        AdditionalText? file,
        SourceText? text,
        int line,
        string message)
    {
        Location location = Location.None;
        if (file is not null && text is not null)
        {
            TextSpan span = text.Lines[Math.Max(line, 0)].Span;
            location = Location.Create(file.Path, span, text.Lines.GetLinePositionSpan(span));
        }

        context.ReportDiagnostic(Diagnostic.Create(s_invalidDefinition, location, message));
    }

}
