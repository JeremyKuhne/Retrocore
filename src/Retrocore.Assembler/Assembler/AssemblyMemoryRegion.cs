// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Load-region settings shared by sections of one single-object link.
/// </summary>
/// <remarks>
///  <para>
///   As in ld65, the start and size are expressions that may read SYMBOLS values and earlier regions' defined
///   symbols such as <c>__MAIN_LAST__</c>, so the compiler evaluates them at the start of each layout pass.
///  </para>
/// </remarks>
/// <param name="name">The MEMORY name.</param>
/// <param name="start">The first load address expression.</param>
/// <param name="size">The size expression.</param>
/// <param name="file">The output filename, or empty for no file output.</param>
/// <param name="fill">Whether the entire region appears in the output.</param>
/// <param name="fillByte">The gap and tail fill byte.</param>
/// <param name="define">Whether the region defines its start, size, last and file-offset symbols.</param>
internal sealed class AssemblyMemoryRegion(string name, string start, string size, string file, bool fill, byte fillByte, bool define)
{
    /// <summary>
    ///  Gets the MEMORY name.
    /// </summary>
    internal string Name { get; } = name;

    /// <summary>
    ///  Gets the start address expression.
    /// </summary>
    internal string StartExpression { get; } = start;

    /// <summary>
    ///  Gets the size expression.
    /// </summary>
    internal string SizeExpression { get; } = size;

    /// <summary>
    ///  Gets the output filename.
    /// </summary>
    internal string File { get; } = file;

    /// <summary>
    ///  Gets whether the entire region is emitted.
    /// </summary>
    internal bool Fill { get; } = fill;

    /// <summary>
    ///  Gets the fill byte.
    /// </summary>
    internal byte FillByte { get; } = fillByte;

    /// <summary>
    ///  Gets whether <c>__NAME_START__</c>, <c>__NAME_SIZE__</c>, <c>__NAME_LAST__</c> and
    ///  <c>__NAME_FILEOFFS__</c> are defined.
    /// </summary>
    internal bool Define { get; } = define;

    /// <summary>
    ///  Gets or sets the first load address evaluated for the current layout pass.
    /// </summary>
    internal int Start { get; set; }

    /// <summary>
    ///  Gets or sets the size evaluated for the current layout pass.
    /// </summary>
    internal int Size { get; set; }

    /// <summary>
    ///  Gets the exclusive memory bound.
    /// </summary>
    internal int End => Start + Size;

    /// <summary>
    ///  Gets or sets whether the start and size were evaluated this pass rather than provisionally assumed.
    /// </summary>
    internal bool Resolved { get; set; }

    /// <summary>
    ///  Gets or sets the <c>__NAME_START__</c> symbol, when defined.
    /// </summary>
    internal int StartSymbol { get; set; } = AssemblySymbols.Undeclared;

    /// <summary>
    ///  Gets or sets the <c>__NAME_SIZE__</c> symbol, when defined.
    /// </summary>
    internal int SizeSymbol { get; set; } = AssemblySymbols.Undeclared;

    /// <summary>
    ///  Gets or sets the <c>__NAME_LAST__</c> symbol: the start plus the highest fill level of its sections.
    /// </summary>
    internal int LastSymbol { get; set; } = AssemblySymbols.Undeclared;

    /// <summary>
    ///  Gets or sets the <c>__NAME_FILEOFFS__</c> symbol: the region's offset within its output file.
    /// </summary>
    internal int FileOffsetSymbol { get; set; } = AssemblySymbols.Undeclared;
}
