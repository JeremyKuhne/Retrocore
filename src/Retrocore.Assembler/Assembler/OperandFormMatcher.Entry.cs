// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class OperandFormMatcher
{
    /// <summary>
    ///  One pattern to try, in declaration order.
    /// </summary>
    /// <param name="kind">How the pattern matches.</param>
    /// <param name="form">The form that declared the pattern.</param>
    /// <param name="pattern">The pattern.</param>
    private sealed class Entry(EntryKind kind, ushort form, Pattern pattern)
    {
        /// <summary>
        ///  Gets how the pattern matches.
        /// </summary>
        internal EntryKind Kind { get; } = kind;

        /// <summary>
        ///  Gets the form that declared the pattern.
        /// </summary>
        internal ushort Form { get; } = form;

        /// <summary>
        ///  Gets the pattern.
        /// </summary>
        internal Pattern Pattern { get; } = pattern;

        /// <summary>
        ///  Gets the forms that share a syntax pattern, in declaration order.
        /// </summary>
        internal List<ushort> Group { get; } = [];

        /// <summary>
        ///  Gets or sets the group's wide form when it has a narrow alternative; -1 otherwise.
        /// </summary>
        internal int Wide { get; set; } = -1;

        /// <summary>
        ///  Gets or sets the narrow alternative of <see cref="Wide"/>.
        /// </summary>
        internal int Narrow { get; set; } = -1;
    }
}
