// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A call of a procedure, or a built-in one such as WRITE, whose arguments may have widths.
    /// </summary>
    /// <param name="callee">The procedure.</param>
    /// <param name="arguments">Its arguments.</param>
    private sealed class CallStatement(Callee callee, List<Argument> arguments) : Statement
    {
        /// <summary>
        ///  Gets the procedure.
        /// </summary>
        public Callee Callee { get; } = callee;

        /// <summary>
        ///  Gets its arguments.
        /// </summary>
        public List<Argument> Arguments { get; } = arguments;

        /// <summary>
        ///  Gets or sets a value indicating whether it is an I/O statement whose result is checked (CSP IOC after it).
        /// </summary>
        public bool Checked { get; set; }
    }
}
