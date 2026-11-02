// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  A value defined by an ld65 SYMBOLS entry.
/// </summary>
/// <param name="name">The symbol name.</param>
/// <param name="expression">The value expression, which may read earlier linker symbols.</param>
/// <param name="weak">Whether a definition in the source takes precedence.</param>
internal sealed class AssemblyLinkerSymbol(string name, string expression, bool weak)
{
    /// <summary>
    ///  Gets the symbol name.
    /// </summary>
    internal string Name { get; } = name;

    /// <summary>
    ///  Gets the value expression.
    /// </summary>
    internal string Expression { get; } = expression;

    /// <summary>
    ///  Gets whether the source may define the symbol instead.
    /// </summary>
    internal bool Weak { get; } = weak;

    /// <summary>
    ///  Gets or sets the declared symbol, or <see cref="AssemblySymbols.Undeclared"/> when the source defines it.
    /// </summary>
    internal int Id { get; set; } = AssemblySymbols.Undeclared;
}
