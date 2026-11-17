// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A string's length: its byte 0.
    /// </summary>
    /// <param name="text">The string.</param>
    private sealed class LengthDesignator(Designator text) : Designator
    {
        /// <summary>
        ///  Gets the string.
        /// </summary>
        public Designator Text { get; } = text;

        /// <inheritdoc/>
        public override TypeNode Type { get; } = TypeNode.Scalar(ScalarKind.Integer);
    }
}
