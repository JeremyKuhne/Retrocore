// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A whole variable.
    /// </summary>
    /// <param name="variable">The variable.</param>
    private sealed class VariableDesignator(Variable variable) : Designator
    {
        /// <summary>
        ///  Gets the variable.
        /// </summary>
        public Variable Variable { get; } = variable;

        /// <inheritdoc/>
        public override TypeNode Type => Variable.Type;
    }
}
