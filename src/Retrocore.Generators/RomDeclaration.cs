// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Cpu.M6502;
using Microsoft.CodeAnalysis.Text;

namespace Retrocore.Generators;

/// <summary>
///  Generator-only .rom metadata adapter; the shared assembler receives ordinary image options.
/// </summary>
internal sealed class RomDeclaration
{
    private static readonly AssemblySymbols s_emptySymbols = new();

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
            if (content.Length <= 4 || !char.IsWhiteSpace(content[4]) || content[4..].Trim().IsEmpty || name is not null)
            {
                throw new AssemblyError(line, "Expected one '.rom Namespace.Type, origin, size' declaration.");
            }

            AssemblyOperands args = new(contentMemory[4..], line);
            args.MoveNext();
            ReadOnlyMemory<char> typeName = args.Current;
            if (!args.MoveNext())
            {
                throw new AssemblyError(line, "Expected one '.rom Namespace.Type, origin, size' declaration.");
            }

            ReadOnlyMemory<char> originText = args.Current;
            if (!args.MoveNext())
            {
                throw new AssemblyError(line, "Expected one '.rom Namespace.Type, origin, size' declaration.");
            }

            ReadOnlyMemory<char> lengthText = args.Current;
            if (args.MoveNext())
            {
                throw new AssemblyError(line, "Expected one '.rom Namespace.Type, origin, size' declaration.");
            }

            name = typeName.ToString();
            if (!AssemblySyntax.IsQualifiedIdentifier(typeName.Span))
            {
                throw new AssemblyError(line, "ROM type must be a namespace-qualified C# identifier.");
            }

            long origin = Constant(originText, line);
            long length = Constant(lengthText, line);
            if (origin < 0
                || origin > ushort.MaxValue
                || length <= 0
                || length > InstructionEncoding.AddressSpaceSize - origin)
            {
                throw new AssemblyError(line, "ROM origin and size must fit the 16-bit address space.");
            }

            options = new(ProcessorVariant.Mos6502, (int)origin, (int)length);
            // Deleting this line would shift source diagnostics; spaces preserve all original offsets.
            for (int offset = span.Start; offset < span.End; offset++) { source[offset] = ' '; }
        }

        return name is null || options is null
            ? throw new AssemblyError(line: 0, "Both .rom and .cpu declarations are required.")
            : new(name, options, new string(source));
    }

    /// <summary>
    ///  Resolves metadata bounds before program assembly, without access to program symbols.
    /// </summary>
    /// <param name="text">The metadata expression.</param>
    /// <param name="line">The physical metadata source line for diagnostics.</param>
    /// <returns>The completely resolved integer value.</returns>
    private static long Constant(ReadOnlyMemory<char> text, int line)
    {
        try
        {
            return !new ExpressionEvaluator(text, s_emptySymbols, address: 0, line).TryEvaluate(out long value)
                ? throw new AssemblyError(line, $"Unresolved expression '{text}'.")
                : value;
        }
        catch (OverflowException)
        {
            throw new AssemblyError(line, "Expression overflow.");
        }
    }
}
