// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class Macro10Expander
{
    /// <summary>
    ///  One native line, or an assignment written once every assignment is known.
    /// </summary>
    /// <param name="Text">The native statement, or an assignment's expression.</param>
    /// <param name="Location">The source location.</param>
    /// <param name="Variable">The assigned native name, or null for a statement.</param>
    private readonly record struct Output(string Text, AssemblyLocation Location, string? Variable);
}
