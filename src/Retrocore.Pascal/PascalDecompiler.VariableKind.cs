// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  What a variable is to its procedure.
    /// </summary>
    private enum VariableKind
    {
        /// <summary>
        ///  A declared variable.
        /// </summary>
        Variable,

        /// <summary>
        ///  A parameter.
        /// </summary>
        Parameter,

        /// <summary>
        ///  A function's result, which the function's name stands for.
        /// </summary>
        Result,

        /// <summary>
        ///  A word the compiler keeps for itself: a FOR loop's limit, a WITH statement's record, a string expression.
        /// </summary>
        Temporary,

        /// <summary>
        ///  A system variable: INPUT, OUTPUT or KEYBOARD.
        /// </summary>
        System,

        /// <summary>
        ///  A value parameter's copy, which the parameter's name stands for in the procedure.
        /// </summary>
        Copy
    }
}
