// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A call of an intrinsic unit's procedure that no library at hand declares, whose words tell its parameters.
    /// </summary>
    /// <param name="callee">The call's callee, whose procedure is declared once every call is seen.</param>
    /// <param name="arguments">The words it pushes, as the call's arguments.</param>
    /// <param name="isFunction">Whether it leaves room for a result.</param>
    private sealed class UnitCall(Callee callee, List<Expr> arguments, bool isFunction)
    {
        /// <summary>
        ///  Gets the call's callee.
        /// </summary>
        public Callee Callee { get; } = callee;

        /// <summary>
        ///  Gets its arguments, a value string's turned to its value once the parameter is known to be one.
        /// </summary>
        public List<Expr> Arguments { get; } = arguments;

        /// <summary>
        ///  Gets whether it leaves room for a result.
        /// </summary>
        public bool IsFunction { get; } = isFunction;
    }
}
