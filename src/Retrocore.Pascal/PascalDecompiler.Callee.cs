// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  What a call calls: a procedure in the code file, a unit's, or a built-in.
    /// </summary>
    private sealed class Callee
    {
        /// <summary>
        ///  Gets a procedure in the code file.
        /// </summary>
        public Procedure? Procedure { get; init; }

        /// <summary>
        ///  Gets the unit a unit's procedure is in.
        /// </summary>
        public PascalUnit? Unit { get; init; }

        /// <summary>
        ///  Gets a unit's procedure, as its interface declares it.
        /// </summary>
        public PascalUnitProcedure? UnitProcedure { get; init; }

        /// <summary>
        ///  Gets a built-in procedure or function, such as WRITE or LENGTH.
        /// </summary>
        public string? Builtin { get; init; }

        /// <summary>
        ///  Gets the segment number of a unit's procedure, or of one the decompiler could not name.
        /// </summary>
        public int Segment { get; init; }

        /// <summary>
        ///  Gets the procedure number of a unit's procedure, or of one the decompiler could not name.
        /// </summary>
        public int Number { get; init; }

        /// <summary>
        ///  Gets a function's result type, or null for a procedure.
        /// </summary>
        public TypeNode? ResultType { get; init; }
    }
}
