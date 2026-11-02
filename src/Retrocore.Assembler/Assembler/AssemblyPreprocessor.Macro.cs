// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    /// <summary>
    ///  Definition-site syntax retained until a macro is invoked.
    /// </summary>
    /// <param name="parameters">The formal token names.</param>
    /// <param name="body">The physical definition lines.</param>
    private sealed class Macro(string[] parameters, IReadOnlyList<Line> body)
    {
        /// <summary>
        ///  Gets formal token names.
        /// </summary>
        internal string[] Parameters { get; } = parameters;

        /// <summary>
        ///  Gets definition-site source and dialect metadata.
        /// </summary>
        internal IReadOnlyList<Line> Body { get; } = body;

        /// <summary>
        ///  Gets or sets Merlin macro-body labels that receive invocation-local bindings.
        /// </summary>
        internal string[]? MerlinLocals { get; set; }
    }
}
