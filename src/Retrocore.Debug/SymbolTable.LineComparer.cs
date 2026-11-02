// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

internal sealed partial class SymbolTable
{
    /// <summary>
    ///  Compares source lines with case-insensitive paths, as Windows file names are.
    /// </summary>
    private sealed class LineComparer : IEqualityComparer<(string Path, int Line)>
    {
        /// <summary>
        ///  Gets the shared instance.
        /// </summary>
        internal static LineComparer Instance { get; } = new();

        /// <inheritdoc/>
        public bool Equals((string Path, int Line) x, (string Path, int Line) y) =>
            x.Line == y.Line && string.Equals(x.Path, y.Path, StringComparison.OrdinalIgnoreCase);

        /// <inheritdoc/>
        public int GetHashCode((string Path, int Line) obj) =>
            HashCode.Combine(StringComparer.OrdinalIgnoreCase.GetHashCode(obj.Path), obj.Line);
    }
}
