// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    /// <summary>
    ///  A token-substitution definition; null parameters distinguish object-like definitions.
    /// </summary>
    /// <param name="parameters">Function-like formal names, or null.</param>
    /// <param name="text">The unexpanded replacement text.</param>
    private sealed class TextDefinition(string[]? parameters, string text)
    {
        /// <summary>
        ///  Gets formal parameter names.
        /// </summary>
        internal string[]? Parameters { get; } = parameters;

        /// <summary>
        ///  Gets replacement text.
        /// </summary>
        internal string Text { get; } = text;
    }
}
