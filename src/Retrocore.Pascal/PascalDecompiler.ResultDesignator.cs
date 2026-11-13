// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A function's result, its name inside it.
    /// </summary>
    /// <param name="procedure">The function.</param>
    private sealed class ResultDesignator(Procedure procedure) : Designator
    {
        /// <summary>
        ///  Gets the function.
        /// </summary>
        public Procedure Procedure { get; } = procedure;

        /// <inheritdoc/>
        public override TypeNode Type => Procedure.ResultType;
    }
}
