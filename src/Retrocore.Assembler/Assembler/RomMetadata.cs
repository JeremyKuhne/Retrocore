// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  The source generator's ROM type and fixed image bounds, shared with editor analysis.
/// </summary>
/// <param name="TypeName">The qualified generated C# type.</param>
/// <param name="Origin">The image's first address.</param>
/// <param name="ImageSize">The image's size in bytes.</param>
internal readonly record struct RomMetadata(string TypeName, int Origin, int ImageSize)
{
    private static readonly AssemblySymbols s_emptySymbols = new();

    /// <summary>
    ///  Recognizes a complete metadata directive, not a longer name beginning with <c>.rom</c>.
    /// </summary>
    /// <param name="content">The trimmed, uncommented line.</param>
    /// <returns>Whether the line starts with the directive.</returns>
    internal static bool IsDeclaration(ReadOnlySpan<char> content) =>
        content.StartsWith(".rom", StringComparison.OrdinalIgnoreCase)
            && (content.Length == 4 || char.IsWhiteSpace(content[4]));

    /// <summary>
    ///  Reads one trimmed, uncommented <c>.rom</c> line.
    /// </summary>
    /// <param name="content">The declaration.</param>
    /// <param name="line">Its zero-based source line for diagnostics.</param>
    /// <returns>The validated metadata.</returns>
    internal static RomMetadata Read(ReadOnlyMemory<char> content, int line)
    {
        ReadOnlySpan<char> span = content.Span;
        if (!IsDeclaration(span) || span.Length == 4 || span[4..].Trim().IsEmpty)
        {
            throw new AssemblyError(line, "Expected one '.rom Namespace.Type, origin, size' declaration.");
        }

        AssemblyOperands arguments = new(content[4..], line);
        arguments.MoveNext();
        ReadOnlyMemory<char> typeName = arguments.Current;
        if (!arguments.MoveNext())
        {
            throw new AssemblyError(line, "Expected one '.rom Namespace.Type, origin, size' declaration.");
        }

        ReadOnlyMemory<char> originText = arguments.Current;
        if (!arguments.MoveNext())
        {
            throw new AssemblyError(line, "Expected one '.rom Namespace.Type, origin, size' declaration.");
        }

        ReadOnlyMemory<char> sizeText = arguments.Current;
        if (arguments.MoveNext())
        {
            throw new AssemblyError(line, "Expected one '.rom Namespace.Type, origin, size' declaration.");
        }

        if (!AssemblySyntax.IsQualifiedIdentifier(typeName.Span))
        {
            throw new AssemblyError(line, "ROM type must be a namespace-qualified C# identifier.");
        }

        long origin = Constant(originText, line);
        long size = Constant(sizeText, line);
        bool invalid = origin < 0
            || origin > ushort.MaxValue
            || size <= 0
            || size > InstructionEncoding.AddressSpaceSize - origin;

        return invalid ? throw new AssemblyError(line, "ROM origin and size must fit the 16-bit address space.")
            : new(typeName.ToString(), (int)origin, (int)size);
    }

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
