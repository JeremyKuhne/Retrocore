// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  An argument: a value with a WRITE's width and decimals, or a file.
    /// </summary>
    /// <param name="Value">The value.</param>
    /// <param name="Width">A WRITE's field width, if given.</param>
    /// <param name="Decimals">A WRITE's decimal places for a real, if given.</param>
    private sealed record Argument(Expr Value, Expr? Width = null, Expr? Decimals = null);
}
