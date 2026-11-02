// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;

namespace Retrocore.Assembler;

internal static partial class AssemblyCompiler
{
    /// <summary>
    ///  What every field of one instruction is written against.
    /// </summary>
    /// <param name="OpcodeByte">Where the last opcode byte is, which an opcode field is written into.</param>
    /// <param name="Next">The address after the instruction, which relative fields count from.</param>
    /// <param name="Endianness">The byte order of a word.</param>
    /// <param name="Line">The input-model statement index for diagnostics.</param>
    private readonly record struct FieldContext(int OpcodeByte, int Next, Endianness Endianness, int Line);
}
