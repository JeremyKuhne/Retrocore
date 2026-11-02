// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    /// <summary>
    ///  Source-ordered conditional selection.
    /// </summary>
    /// <param name="location">The opening location.</param>
    /// <param name="parent">Whether the enclosing branch is active.</param>
    /// <param name="active">Whether this branch is selected.</param>
    /// <param name="order">The opening expansion position.</param>
    private sealed class Conditional(AssemblyLocation location, bool parent, bool active, int order)
    {
        /// <summary>
        ///  Gets the opening location.
        /// </summary>
        internal AssemblyLocation Location { get; } = location;

        /// <summary>
        ///  Gets the enclosing branch state.
        /// </summary>
        internal bool Parent { get; } = parent;

        /// <summary>
        ///  Gets or sets the current branch state.
        /// </summary>
        internal bool Active { get; set; } = active;

        /// <summary>
        ///  Gets or sets whether an earlier branch was selected.
        /// </summary>
        internal bool Taken { get; set; } = active;

        /// <summary>
        ///  Gets or sets whether .else has occurred.
        /// </summary>
        internal bool ElseSeen { get; set; }

        /// <summary>
        ///  Gets the opening expansion position.
        /// </summary>
        internal int Order { get; } = order;
    }
}
