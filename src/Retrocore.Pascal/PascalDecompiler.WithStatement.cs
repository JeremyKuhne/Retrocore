// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A WITH statement, whose record's address the compiler keeps in a temporary.
    /// </summary>
    /// <param name="record">The record.</param>
    /// <param name="temporary">The temporary that holds the record's address.</param>
    /// <param name="body">The statements that reach the record's fields by name.</param>
    private sealed class WithStatement(Designator record, Variable temporary, List<Statement> body) : Statement
    {
        /// <summary>
        ///  Gets the record.
        /// </summary>
        public Designator Record { get; } = record;

        /// <summary>
        ///  Gets the temporary that holds the record's address.
        /// </summary>
        public Variable Temporary { get; } = temporary;

        /// <summary>
        ///  Gets the statements that reach the record's fields by name.
        /// </summary>
        public List<Statement> Body { get; } = body;
    }
}
