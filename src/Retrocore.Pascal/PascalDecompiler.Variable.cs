// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A parameter or variable, at its frame's word offset.
    /// </summary>
    /// <param name="frame">The frame it is in.</param>
    /// <param name="offset">Its word offset in the frame, from 1.</param>
    /// <param name="kind">What it is to its procedure.</param>
    private sealed class Variable(Frame frame, int offset, VariableKind kind)
    {
        /// <summary>
        ///  Gets the frame it is in.
        /// </summary>
        public Frame Frame { get; } = frame;

        /// <summary>
        ///  Gets its word offset in the frame, from 1.
        /// </summary>
        public int Offset { get; } = offset;

        /// <summary>
        ///  Gets or sets what it is to its procedure.
        /// </summary>
        public VariableKind Kind { get; set; } = kind;

        /// <summary>
        ///  Gets or sets its inferred type.
        /// </summary>
        public TypeNode Type { get; set; } = new();

        /// <summary>
        ///  Gets or sets how many words it takes, once laid out.
        /// </summary>
        public int Words { get; set; } = 1;

        /// <summary>
        ///  Gets or sets whether it is a parameter whose arguments are addresses.
        /// </summary>
        public bool IsReference { get; set; }

        /// <summary>
        ///  Gets or sets a value parameter's copy, which stands for it.
        /// </summary>
        public Variable? Copy { get; set; }

        /// <summary>
        ///  Gets or sets whether its value or address is used by the code, so it is declared.
        /// </summary>
        public bool Used { get; set; }

        /// <summary>
        ///  Gets or sets whether the code uses it as a scalar word.
        /// </summary>
        public bool LoadedAsWord { get; set; }

        /// <summary>
        ///  Gets or sets whether the code uses it by address.
        /// </summary>
        public bool AddressTaken { get; set; }

        /// <summary>
        ///  Gets or sets the name the writer gives it.
        /// </summary>
        public string Name { get; set; } = "";

        /// <summary>
        ///  Gets or sets the most words a whole-variable operation (MOV, LDM, STM, SAS) shows it has.
        /// </summary>
        public int BlockWords { get; set; }

        /// <summary>
        ///  Gets or sets the record variable it is a field of, where the code reaches a record's field at its own offset.
        /// </summary>
        public Variable? Container { get; set; }

        /// <summary>
        ///  Gets or sets its word offset in its <see cref="Container"/>.
        /// </summary>
        public int FieldOffset { get; set; }

        /// <summary>
        ///  Gets or sets the order FINIT opens a file variable in, from 1.
        /// </summary>
        public int Opened { get; set; }
    }
}
