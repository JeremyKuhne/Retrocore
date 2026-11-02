// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Isa;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.Text;
using System.Collections.Immutable;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Text;

namespace Retrocore.Generators;

/// <summary>
///  Compiles .rom.asm additional files into constant byte spans and exported firmware symbols.
/// </summary>
[Generator]
public sealed class RomAssemblyGenerator : IIncrementalGenerator
{
    private const int BytesPerSourceLine = 16;
    private const int CharactersPerEncodedByte = 7;
    private const int SourcePrologueBudget = 512;
    private const int ExportDeclarationBudget = 64;

    private static readonly DiagnosticDescriptor s_error = new(
        id: "RCGEN002",
        title: "Invalid ROM assembly",
        messageFormat: "{0}",
        category: "Build",
        defaultSeverity: DiagnosticSeverity.Error,
        isEnabledByDefault: true);

    /// <summary>
    ///  Registers assembly, canonical opcode definitions, and enum declarations as build inputs.
    /// </summary>
    /// <param name="context">The generator initialization context.</param>
    public void Initialize(IncrementalGeneratorInitializationContext context)
    {
        var files = context.AdditionalTextsProvider.Collect();
        var inputs = files.Combine(context.AnalyzerConfigOptionsProvider).Combine(context.CompilationProvider);
        context.RegisterSourceOutput(inputs, static (output, input) =>
        {
            ImmutableArray<AdditionalText> allFiles = input.Left.Left;
            ImmutableArray<AdditionalText> assembly = [.. allFiles.Where(
                file => file.Path.EndsWith(".rom.asm", StringComparison.OrdinalIgnoreCase))];

            if (assembly.Length == 0) { return; }
            ImmutableArray<AdditionalText> opcodes = [.. allFiles.Where(
                file => Path.GetFileName(file.Path).Equals("OpcodeTables.txt", StringComparison.OrdinalIgnoreCase))];

            var maps = OpcodeTableGenerator.ReadMaps(output, opcodes, input.Right);
            if (maps is null) { return; }
            // Read the description itself rather than referencing the product's not-yet-generated OpcodeTable.
            IReadOnlyDictionary<string, InstructionSet> sets;
            try
            {
                sets = IsaParser.Parse(opcodes[0].GetText(output.CancellationToken)?.ToString() ?? "").InstructionSets;
            }
            catch (FormatException error)
            {
                output.ReportDiagnostic(Diagnostic.Create(s_error, Location.None, $"OpcodeTables.txt: {error.Message}"));
                return;
            }

            HashSet<string> names = new(StringComparer.Ordinal);
            AdditionalAssemblySourceResolver resolver = new(allFiles, input.Left.Right, output.CancellationToken);
            foreach (AdditionalText file in assembly.OrderBy(file => file.Path, StringComparer.Ordinal))
            {
                SourceText? text = file.GetText(output.CancellationToken);
                if (text is null)
                {
                    output.ReportDiagnostic(Diagnostic.Create(s_error, Location.None, $"ROM assembly could not be read: {file.Path}"));
                    continue;
                }

                try
                {
                    RomDeclaration declaration = RomDeclaration.Read(text);
                    AssemblyOptions options = new(declaration.Options.Variant, declaration.Options.Origin, declaration.Options.ImageSize)
                    {
                        SourceResolver = resolver,
                        IncludePaths = IncludePaths(input.Left.Right.GlobalOptions, "RetrocoreIncludePaths"),
                        SdkPaths = IncludePaths(input.Left.Right.GlobalOptions, "RetrocoreSdkPaths"),
                        BuildTime = BuildTime(input.Left.Right.GlobalOptions)
                    };

                    var assembler = new global::Retrocore.Assembler.Assembler(sets);
                    AssemblyParseResult parsed = global::Retrocore.Assembler.Assembler.Parse(
                        new AssemblySource(declaration.Source, file.Path, resolver.Dialect(file)),
                        options,
                        output.CancellationToken);

                    if (!parsed.Success)
                    {
                        Report(output, file, text, parsed.Diagnostics, allFiles);
                        continue;
                    }

                    bool merlin = parsed.Project.MerlinOutput is not null;
                    if (!merlin && !parsed.Project.Statements.Any(node => node.Kind == AssemblyStatementKind.Cpu))
                    {
                        throw new AssemblyError(line: 0, "Both .rom and .cpu declarations are required.");
                    }

                    // These names belong to generated C# members, not to the public assembler language.
                    foreach (AssemblyStatement node in parsed.Project.Statements.Where(node => node.Kind == AssemblyStatementKind.Export))
                    {
                        foreach (ReadOnlyMemory<char> name in new AssemblyOperands(node.Operand.Text.AsMemory(), node.Location?.Line ?? 0))
                        {
                            if (name.Span is "Origin" or "Bytes")
                            {
                                throw new AssemblyError(node.Location?.Line ?? 0, $"Invalid or duplicate exported symbol '{name}'.");
                            }
                        }
                    }

                    if (parsed.Project.Statements.Any(node => node.Dialect == AssemblyDialect.Ca65))
                    {
                        options = new(options.Variant, options.Origin, options.ImageSize)
                        {
                            LinkerConfiguration = AssemblyLinker.ImageConfiguration(options.Origin, options.ImageSize)
                        };
                    }

                    AssemblyResult rom = assembler.Assemble(parsed.Project, options, output.CancellationToken);
                    if (!rom.Success)
                    {
                        Report(output, file, text, rom.Diagnostics, allFiles);
                        continue;
                    }

                    if (rom.Files.Count == 0 ? rom.Sections.Count != 1 : rom.Files.Count != 1)
                    {
                        throw new AssemblyError(line: 0, "A generated ROM must assemble to a single section.");
                    }

                    if (!QualifiedIdentifier(declaration.TypeName)
                        || rom.Exports.Keys.Any(name => !Identifier(name) || name is "Origin" or "Bytes"))
                    {
                        throw new AssemblyError(line: 0, "Generated ROM type and exports must be valid C# identifiers.");
                    }

                    if (!names.Add(declaration.TypeName))
                    {
                        throw new AssemblyError(line: 0, $"Duplicate generated ROM type '{declaration.TypeName}'.");
                    }

                    output.AddSource(
                        $"{declaration.TypeName.Replace('.', '_')}.g.cs",
                        SourceText.From(
                            Emit(declaration, rom, ExportDocumentation.Summaries(text.ToString(), file.Path, rom)),
                            Encoding.UTF8));
                }
                catch (AssemblyError error)
                {
                    Report(output, file, text, error.Line, error.Message);
                }
            }

        });
    }

    /// <summary>
    ///  Selects a reproducible build timestamp, so generated ROM bytes never depend on the wall clock.
    /// </summary>
    /// <param name="options">The global analyzer options.</param>
    /// <returns>RetrocoreBuildTime or SOURCE_DATE_EPOCH in Unix seconds, otherwise the Unix epoch.</returns>
    private static DateTimeOffset BuildTime(Microsoft.CodeAnalysis.Diagnostics.AnalyzerConfigOptions options)
    {
        foreach (string name in (string[])["RetrocoreBuildTime", "SOURCE_DATE_EPOCH"])
        {
            if (options.TryGetValue($"build_property.{name}", out string? text)
                && long.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out long seconds))
            {
                return DateTimeOffset.FromUnixTimeSeconds(seconds);
            }
        }

        return DateTimeOffset.FromUnixTimeSeconds(0);
    }

    private static IReadOnlyList<string> IncludePaths(
        Microsoft.CodeAnalysis.Diagnostics.AnalyzerConfigOptions options,
        string name)
    {
        return options.TryGetValue($"build_property.{name}", out string? paths)
            ? paths.Split([';'], StringSplitOptions.RemoveEmptyEntries) : [];
    }

    /// <summary>
    ///  Reports every assembler diagnostic so one build shows all independent source errors.
    /// </summary>
    /// <param name="output">The generator output.</param>
    /// <param name="file">The ROM assembly file.</param>
    /// <param name="text">The file's text, used to locate source lines.</param>
    /// <param name="diagnostics">The parse or assembly diagnostics.</param>
    /// <param name="files">Declared sources, including includes.</param>
    private static void Report(
        SourceProductionContext output,
        AdditionalText file,
        SourceText text,
        IReadOnlyList<AssemblyDiagnostic> diagnostics,
        ImmutableArray<AdditionalText> files)
    {
        foreach (AssemblyDiagnostic diagnostic in diagnostics)
        {
            if (diagnostic.Location is not { } physical)
            {
                Report(output, file, text, line: 0, diagnostic.Message);
                continue;
            }

            Location location = SourceLocation(physical, files, file, text, output.CancellationToken);
            List<Location> parents = [];
            for (AssemblyLocation? parent = physical.ExpandedFrom; parent is not null; parent = parent.ExpandedFrom)
            {
                parents.Add(SourceLocation(parent, files, file, text, output.CancellationToken));
            }

            output.ReportDiagnostic(Diagnostic.Create(
                s_error,
                location,
                additionalLocations: parents,
                properties: null,
                diagnostic.Message));
        }
    }

    private static Location SourceLocation(
        AssemblyLocation location,
        ImmutableArray<AdditionalText> files,
        AdditionalText root,
        SourceText rootText,
        CancellationToken cancellationToken)
    {
        AdditionalText? file = files.FirstOrDefault(file => file.Path.Equals(location.Path, StringComparison.OrdinalIgnoreCase));
        SourceText? text = file?.GetText(cancellationToken);
        if (text is null)
        {
            file = root;
            text = rootText;
        }

        TextSpan span = text.Lines[Math.Max(0, Math.Min(location.Line, text.Lines.Count - 1))].Span;
        return Location.Create(file?.Path ?? root.Path, span, text.Lines.GetLinePositionSpan(span));
    }

    /// <summary>
    ///  Reports one error at a source line, clamped to the file.
    /// </summary>
    /// <param name="output">The generator output.</param>
    /// <param name="file">The ROM assembly file.</param>
    /// <param name="text">The file's text, used to locate source lines.</param>
    /// <param name="line">The zero-based source line.</param>
    /// <param name="message">The error message.</param>
    private static void Report(SourceProductionContext output, AdditionalText file, SourceText text, int line, string message)
    {
        TextSpan span = text.Lines[Math.Max(0, Math.Min(line, text.Lines.Count - 1))].Span;
        output.ReportDiagnostic(Diagnostic.Create(
            s_error,
            Location.Create(file.Path, span, text.Lines.GetLinePositionSpan(span)),
            message));
    }

    /// <summary>
    ///  Renders resolved ROM bytes and exports as a C# static-data span without per-byte formatting strings.
    /// </summary>
    /// <param name="declaration">The generated type name and image declaration.</param>
    /// <param name="rom">The successfully assembled image.</param>
    /// <param name="summaries">XML summaries of documented exports, by name.</param>
    /// <returns>The complete generated C# source.</returns>
    private static string Emit(RomDeclaration declaration, AssemblyResult rom, Dictionary<string, string> summaries)
    {
        ReadOnlySpan<char> typeName = declaration.TypeName;
        int separator = typeName.LastIndexOf('.');
        int origin = declaration.Options.Origin;
        ReadOnlySpan<byte> bytes = rom.Sections.Count == 1 ? rom.Sections[0].Bytes.Span : rom.Files.Values.Single().Span;
        // Conservatively budget hex bytes/row layout, the fixed prologue, and each exported declaration.
        int capacity = checked(bytes.Length * CharactersPerEncodedByte + typeName.Length + SourcePrologueBudget);
        foreach (var symbol in rom.Exports)
        {
            capacity = checked(capacity + symbol.Key.Length + ExportDeclarationBudget);
            if (summaries.TryGetValue(symbol.Key, out string? summary))
            {
                capacity = checked(capacity + summary.Length + ExportDeclarationBudget);
            }
        }

        // Export values may be negative, so they are written in the invariant culture.
        DefaultInterpolatedStringHandler source = new(capacity, formattedCount: 0, CultureInfo.InvariantCulture);
        source.AppendLiteral("// <auto-generated/>\n"
            + "// Copyright (c) 2025 Jeremy W Kuhne\n"
            + "// SPDX-License-Identifier: MIT\n"
            + "// See LICENSE file in the project root for full license information\n"
            + "// Edit the annotated .rom.asm source, not this generated byte stream.\n\n"
            + "namespace ");

        source.AppendFormatted(typeName[..separator]);
        source.AppendLiteral(";\n\ninternal static class ");
        source.AppendFormatted(typeName[(separator + 1)..]);
        source.AppendLiteral("\n{\n    internal const int Origin = 0x");
        source.AppendFormatted(origin, "X4");
        source.AppendLiteral(";\n");
        foreach (var symbol in rom.Exports.OrderBy(pair => pair.Key, StringComparer.Ordinal))
        {
            if (summaries.TryGetValue(symbol.Key, out string? summary))
            {
                source.AppendLiteral("    /// <summary>\n    ///  ");
                source.AppendLiteral(summary);
                source.AppendLiteral("\n    /// </summary>\n");
            }

            source.AppendLiteral("    internal const int ");
            source.AppendFormatted(symbol.Key);
            source.AppendLiteral(" = ");
            source.AppendFormatted(symbol.Value);
            source.AppendLiteral(";\n");
        }

        // Bytes are written digit by digit, since formatting each one would allocate a string per byte here.
        const string HexDigits = "0123456789ABCDEF";
        source.AppendLiteral("    internal static global::System.ReadOnlySpan<byte> Bytes =>\n    [\n");
        for (int offset = 0; offset < bytes.Length; offset += BytesPerSourceLine)
        {
            source.AppendLiteral("        ");
            int end = Math.Min(offset + BytesPerSourceLine, bytes.Length);
            for (int index = offset; index < end; index++)
            {
                if (index != offset) { source.AppendLiteral(", "); }
                source.AppendLiteral("0x");
                source.AppendFormatted(HexDigits[bytes[index] >> 4]);
                source.AppendFormatted(HexDigits[bytes[index] & 15]);
            }

            source.AppendLiteral(end < bytes.Length ? ",\n" : "\n");
        }

        source.AppendLiteral("    ];\n}");
        return source.ToStringAndClear();
    }

    /// <summary>
    ///  Applies C# identifier and reserved-keyword checks to every namespace/type segment.
    /// </summary>
    /// <param name="name">The qualified name already checked for native lexical shape.</param>
    /// <returns>Whether every segment is legal in the generated C# declaration.</returns>
    private static bool QualifiedIdentifier(string name)
    {
        ReadOnlyMemory<char> remaining = name.AsMemory();
        while (true)
        {
            int separator = remaining.Span.IndexOf('.');
            if (separator < 0) { return Identifier(remaining.ToString()); }
            if (!Identifier(remaining[..separator].ToString())) { return false; }
            remaining = remaining[(separator + 1)..];
        }
    }

    /// <summary>
    ///  Rejects reserved C# keywords that the assembler's ordinary symbol grammar permits.
    /// </summary>
    /// <param name="name">The candidate type, namespace or export name.</param>
    /// <returns>Whether it is a valid, non-reserved C# identifier.</returns>
    private static bool Identifier(string name) =>
        SyntaxFacts.IsValidIdentifier(name) && SyntaxFacts.GetKeywordKind(name) == SyntaxKind.None;
}