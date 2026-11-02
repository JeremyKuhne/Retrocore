// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    /// <summary>
    ///  Physical identity and syntax carried through expansion.
    /// </summary>
    /// <param name="text">The line text, a range of its source or of a translated line.</param>
    /// <param name="location">The physical location and parent chain.</param>
    /// <param name="dialect">The defining dialect.</param>
    private readonly struct Line(ReadOnlyMemory<char> text, AssemblyLocation location, AssemblyDialect dialect)
    {
        /// <summary>
        ///  Creates a line from translated text.
        /// </summary>
        /// <param name="text">The line text.</param>
        /// <param name="location">The physical location and parent chain.</param>
        /// <param name="dialect">The defining dialect.</param>
        internal Line(string text, AssemblyLocation location, AssemblyDialect dialect)
            : this(text.AsMemory(), location, dialect)
        {
        }

        /// <summary>
        ///  Gets line text.
        /// </summary>
        internal ReadOnlyMemory<char> Text { get; } = text;

        /// <summary>
        ///  Gets the physical location.
        /// </summary>
        internal AssemblyLocation Location { get; } = location;

        /// <summary>
        ///  Gets the defining dialect.
        /// </summary>
        internal AssemblyDialect Dialect { get; } = dialect;
    }
}
