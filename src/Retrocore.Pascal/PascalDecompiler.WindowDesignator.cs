// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A file's window, F^.
    /// </summary>
    /// <param name="file">The file.</param>
    private sealed class WindowDesignator(Designator file) : Designator
    {
        /// <summary>
        ///  Gets the file.
        /// </summary>
        public Designator File { get; } = file;

        /// <inheritdoc/>
        public override TypeNode Type { get; } = file.Type.Find().Element ?? new TypeNode();
    }
}
