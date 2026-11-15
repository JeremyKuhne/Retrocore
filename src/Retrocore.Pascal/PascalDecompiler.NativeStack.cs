// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Cpu.M6502;
using Retrocore.Media;

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    private const byte Pla = 0x68;
    private const byte Pha = 0x48;
    private const byte Tsx = 0xBA;
    private const byte Txs = 0x9A;

    // The bytes an assembled procedure takes off the stack, past those it puts back, before it returns: its parameters'
    // words, and a function's two words of room, less its result's word. It follows the code from the entry through
    // each branch's next instruction to the first RTS, counting PLA and PHA; null where the code moves the stack
    // pointer, jumps, or does not decode, so that its calls sign it.
    private static int? NativeStackBytes(PascalSegment segment, PascalProcedure procedure)
    {
        byte[] code = segment.Code;
        int pointer = procedure.Attributes - 2;
        if (pointer < 0 || pointer + 1 >= code.Length) { return null; }

        int at = pointer - (code[pointer] | (code[pointer + 1] << 8));
        int taken = 0;
        HashSet<int> seen = [];
        while (at >= 0 && at < pointer && seen.Add(at))
        {
            if (!Disassembler.TryDecode(code.AsSpan(at, pointer - at), (ushort)at, ProcessorVariant.Mos6502, out DisassembledInstruction instruction)
                || instruction.IsUndocumented)
            {
                return null;
            }

            switch (code[at])
            {
                case Pla:
                    taken++;
                    break;
                case Pha:
                    taken--;
                    break;
                case Tsx or Txs:
                    return null;
            }

            switch (instruction.Flow)
            {
                case DisassemblyFlow.Return:
                    return taken;
                case DisassemblyFlow.Jump or DisassemblyFlow.IndirectJump or DisassemblyFlow.Break:
                    return null;
            }

            at += instruction.Size;
        }

        return null;
    }

    // The parameters' words an assembled procedure's code shows it takes, as a function or a procedure; null where it
    // does not show.
    private static int? NativeParameterWords(Procedure procedure, bool function)
    {
        if (procedure.NativeBytes is not { } bytes || bytes % 2 != 0) { return null; }

        int words = (bytes / 2) - (function ? 1 : 0);
        return words >= 0 ? words : null;
    }
}
