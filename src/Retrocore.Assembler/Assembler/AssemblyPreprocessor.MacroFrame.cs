// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    /// <summary>
    ///  One macro invocation's state, shared by every repeat and conditional nested in its body.
    /// </summary>
    /// <param name="invocation">The unique invocation number used in generated local names.</param>
    /// <param name="parameterCount">The number of supplied arguments, for .paramcount.</param>
    private sealed class MacroFrame(int invocation, int parameterCount)
    {
        /// <summary>
        ///  Gets the unique invocation number.
        /// </summary>
        internal int Invocation { get; } = invocation;

        /// <summary>
        ///  Gets the number of supplied arguments.
        /// </summary>
        internal int ParameterCount { get; } = parameterCount;

        /// <summary>
        ///  Gets the invocation's .local names and their generated replacements.
        /// </summary>
        internal Dictionary<string, string> Locals { get; } = new(StringComparer.Ordinal);
    }
}
