// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Microsoft.CodeAnalysis.Text;
using Retrocore.Assembler;
using Retrocore.Cpu.M6502;

namespace Retrocore.Generators;

/// <summary>
///  Generator-only .rom metadata adapter; the shared assembler receives ordinary image options.
/// </summary>
internal sealed class RomDeclaration
{
    /// <summary>
    ///  Gets the generated C# type identifier.
    /// </summary>
    internal string TypeName { get; }

    /// <summary>
    ///  Gets ordinary assembler options.
    /// </summary>
    internal AssemblyOptions Options { get; }

    /// <summary>
    ///  Gets assembly text with metadata blanked but original line positions retained.
    /// </summary>
    internal string Source { get; }

    /// <summary>
    ///  Retains generator metadata separately from ordinary assembler source and image options.
    /// </summary>
    /// <param name="typeName">The qualified generated C# type.</param>
    /// <param name="options">The validated image bounds.</param>
    /// <param name="source">The position-preserving source with .rom metadata blanked.</param>
    private RomDeclaration(string typeName, AssemblyOptions options, string source)
    {
        TypeName = typeName;
        Options = options;
        Source = source;
    }

    /// <summary>
    ///  Extracts and validates exactly one generator metadata directive.
    /// </summary>
    /// <param name="text">Original annotated source.</param>
    /// <returns>Metadata and unchanged-position assembly text.</returns>
    internal static RomDeclaration Read(SourceText text)
    {
        string? name = null;
        AssemblyOptions? options = null;
        string original = text.ToString();
        char[] source = original.ToCharArray();
        for (int line = 0; line < text.Lines.Count; line++)
        {
            TextSpan span = text.Lines[line].Span;
            ReadOnlyMemory<char> contentMemory = original.AsMemory(span.Start, span.Length);
            contentMemory = contentMemory[..AssemblySyntax.WithoutComment(contentMemory.Span).Length].Trim();
            ReadOnlySpan<char> content = contentMemory.Span;
            if (!content.StartsWith(".rom", StringComparison.OrdinalIgnoreCase)) { continue; }
            if (name is not null)
            {
                throw new AssemblyError(line, "Expected one '.rom Namespace.Type, origin, size' declaration.");
            }

            RomMetadata metadata = RomMetadata.Read(contentMemory, line);
            name = metadata.TypeName;
            options = new(ProcessorVariant.Mos6502, metadata.Origin, metadata.ImageSize);
            // Deleting this line would shift source diagnostics; spaces preserve all original offsets.
            for (int offset = span.Start; offset < span.End; offset++) { source[offset] = ' '; }
        }

        return name is null || options is null
            ? throw new AssemblyError(line: 0, "Both .rom and .cpu declarations are required.")
            : new(name, options, new string(source));
    }
}
