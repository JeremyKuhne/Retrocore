// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

public static partial class DocumentationParser
{
    /// <summary>
    ///  A definition found on a source line.
    /// </summary>
    /// <param name="Name">The name, qualified by its enumeration or structure for a member.</param>
    /// <param name="Kind">What it is; a label is a routine until its code is seen.</param>
    /// <param name="Rest">For a label, the code after it on the same line.</param>
    /// <param name="Parameters">Macro or <c>.define</c> parameters.</param>
    private sealed record Definition(string Name, DocumentationKind Kind, string Rest, IReadOnlyList<string> Parameters);
}
