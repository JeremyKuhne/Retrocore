// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  An array's element: by words (IXA), packed (IXP), or by byte (LDB and STB).
    /// </summary>
    private sealed class IndexDesignator : Designator
    {
        /// <summary>
        ///  Initializes a new instance of the <see cref="IndexDesignator"/> class.
        /// </summary>
        /// <param name="array">The array.</param>
        /// <param name="index">The index, less its range check and the lower bound the code subtracts.</param>
        /// <param name="low">The array's lower bound, where the code shows it.</param>
        /// <param name="high">The array's upper bound, from a range check, if there is one.</param>
        /// <param name="element">The element's type.</param>
        public IndexDesignator(Designator array, Expr index, int? low, int? high, TypeNode element)
        {
            Array = array;
            Index = index;
            Low = low;
            High = high;
            Type = element;
        }

        /// <summary>
        ///  Gets the array.
        /// </summary>
        public Designator Array { get; }

        /// <summary>
        ///  Gets the index, less its range check and the lower bound the code subtracts.
        /// </summary>
        public Expr Index { get; }

        /// <summary>
        ///  Gets the array's lower bound, where the code shows it.
        /// </summary>
        public int? Low { get; }

        /// <summary>
        ///  Gets the array's upper bound, from a range check, if there is one.
        /// </summary>
        public int? High { get; }

        /// <summary>
        ///  Gets a value indicating whether the code says nothing of range checking, as for MOVELEFT's byte offset;
        ///  otherwise a range check (CHK) gives the high bound, and its absence means range checking was off.
        /// </summary>
        public bool Neutral { get; init; }

        /// <inheritdoc/>
        public override TypeNode Type { get; }
    }
}
