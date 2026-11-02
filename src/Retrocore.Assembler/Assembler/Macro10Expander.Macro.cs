// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class Macro10Expander
{
    /// <summary>
    ///  A <c>DEFINE</c>d macro.
    /// </summary>
    /// <param name="Parameters">The dummy argument names, uppercase.</param>
    /// <param name="Body">The body text.</param>
    /// <param name="Location">The definition's source location of each body line, by line index.</param>
    private sealed record Macro(string[] Parameters, string Body, Func<int, AssemblyLocation> Location);
}
