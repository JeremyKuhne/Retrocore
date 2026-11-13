// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A procedure's activation record: its parameters and variables, by word offset from 1.
    /// </summary>
    /// <param name="owner">The procedure, or null for the system's frame.</param>
    /// <param name="level">The procedure's lexical level.</param>
    /// <param name="parameterWords">The words its parameters take.</param>
    /// <param name="dataWords">The words its variables take.</param>
    private sealed class Frame(Procedure? owner, int level, int parameterWords, int dataWords)
    {
        /// <summary>
        ///  Gets the procedure, or null for the system's frame.
        /// </summary>
        public Procedure? Owner { get; } = owner;

        /// <summary>
        ///  Gets the procedure's lexical level.
        /// </summary>
        public int Level { get; } = level;

        /// <summary>
        ///  Gets the words its parameters take, which come first.
        /// </summary>
        public int ParameterWords { get; } = parameterWords;

        /// <summary>
        ///  Gets the words its variables take, after the parameters.
        /// </summary>
        public int DataWords { get; } = dataWords;

        /// <summary>
        ///  Gets the words the frame takes: its parameters' and its variables'.
        /// </summary>
        public int Words => ParameterWords + DataWords;

        /// <summary>
        ///  Gets the parameters and variables the code reaches, by word offset.
        /// </summary>
        public SortedDictionary<int, Variable> Variables { get; } = [];

        /// <summary>
        ///  Gets the variable at a word offset, adding it the first time the code reaches it.
        /// </summary>
        /// <param name="offset">The word offset, from 1.</param>
        /// <returns>
        ///  The variable: a parameter within the parameters' words, a declared variable after them, or a system
        ///  variable in the system's frame.
        /// </returns>
        public Variable At(int offset)
        {
            if (!Variables.TryGetValue(offset, out Variable? variable))
            {
                VariableKind kind = Owner is null
                    ? VariableKind.System
                    : offset <= ParameterWords ? VariableKind.Parameter : VariableKind.Variable;

                variable = new Variable(this, offset, kind);
                Variables[offset] = variable;
            }

            return variable;
        }
    }
}
