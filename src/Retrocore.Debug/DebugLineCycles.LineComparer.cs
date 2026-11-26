// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Runtime.CompilerServices;

namespace Retrocore.Debug;

internal sealed partial class DebugLineCycles
{
    /// <summary>
    ///  Compares source lines as tuples do, with ordinal paths, but hashes each path string once: a module's lines
    ///  share their file's path, and hashing it again at every line change costs more than the counting.
    /// </summary>
    private sealed class LineComparer : IEqualityComparer<(string Path, int Line)>
    {
        // Paths hashed recently, by identity. An entry is replaced whole, so another thread never sees a torn one.
        private readonly Tuple<string, int>?[] _paths = new Tuple<string, int>?[16];

        /// <inheritdoc/>
        public bool Equals((string Path, int Line) x, (string Path, int Line) y) =>
            x.Line == y.Line && string.Equals(x.Path, y.Path);

        /// <inheritdoc/>
        public int GetHashCode((string Path, int Line) obj)
        {
            ref Tuple<string, int>? slot = ref _paths[RuntimeHelpers.GetHashCode(obj.Path) & (_paths.Length - 1)];
            Tuple<string, int>? path = slot;
            if (path is null || !ReferenceEquals(path.Item1, obj.Path))
            {
                slot = path = new(obj.Path, obj.Path.GetHashCode());
            }

            return HashCode.Combine(path.Item2, obj.Line);
        }
    }
}
