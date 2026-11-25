// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;

namespace Retrocore.Debug;

// Atari BASIC, for the BASIC thread and the program document. Every statement starts at EXECUTE_STATEMENT, which the
// execution loop calls with the statement's token in A: STMCUR holds the line, TOKEN_OFFSET the place after the token,
// and NEXT_STATEMENT the offset of the statement after it. A statement's address, as the debugger keeps it, is its
// offset byte's, two before the token's place. GOSUBs and FORs are on the run-time stack, each with a four-byte
// header: a FOR's variable's token or 0 for a GOSUB, the line's number and the statement's token's offset.
internal sealed partial class AtariDebugTarget
{
    // Atari BASIC's page zero, from BasicEquates.asm.
    private const ushort Stmcur = 0x8A;
    private const ushort Runstk = 0x8E;
    private const ushort BasicMemtop = 0x90;
    private const ushort LineLength = 0x9F;
    private const ushort NextStatement = 0xA7;
    private const ushort TokenOffset = 0xA8;
    private const ushort ErrorNumber = 0xB9;
    private const ushort TrapLine = 0xBC;
    private const int RunStackHeader = 4;
    private const int ForValues = 12;

    // The errors' messages, by number from 2, as Atari's BASIC Reference Manual gives them.
    private static readonly string[] s_errors =
    [
        "memory insufficient", "value error", "too many variables", "string length error", "out of data",
        "number greater than 32767", "input statement error", "array or string DIM error", "argument stack overflow",
        "floating point overflow/underflow error", "line not found", "no matching FOR statement", "line too long error",
        "GOSUB or FOR line deleted", "RETURN error", "garbage error", "invalid string character",
        "LOAD program too long", "device number larger than 7 or equal to 0", "LOAD file error"
    ];

    private BasicRom? _basicRom;

    /// <inheritdoc/>
    public BasicDialect? Basic => _basicRom is null ? null : BasicDialect.AtariBasic;

    /// <inheritdoc/>
    public BasicRom? BasicRom => _basicRom;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Atari BASIC prints READY at power-on itself.
    ///  </para>
    /// </remarks>
    public bool PressesReturnForPrompt => false;

    /// <inheritdoc/>
    public double BasicBootSeconds => 5;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The number of the line STMCUR points at.
    ///  </para>
    /// </remarks>
    public int BasicCurrentLine => Word(Word(Stmcur));

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   One before the statement's offset byte.
    ///  </para>
    /// </remarks>
    public int BasicTextPointer => Word(Stmcur) + Peek(TokenOffset) - 3;

    /// <inheritdoc/>
    public (int Line, int Address)? BasicStatementStart(ushort pc) =>
        _basicRom is { } rom && pc == rom.Gone ? (BasicCurrentLine, BasicTextPointer + 1) : null;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The GOSUB entries on the run-time stack, from its top; a FOR's are passed over. LIST and READ push GOSUB
    ///   entries too, which RETURN tells apart by the statement's own token.
    ///  </para>
    /// </remarks>
    public IReadOnlyList<(int Line, int TextPointer)>? BasicGosubs
    {
        get
        {
            List<(int, int)> gosubs = [];
            int bottom = Word(Runstk);
            int at = Word(BasicMemtop);
            while (at - RunStackHeader >= bottom && gosubs.Count < 256)
            {
                at -= RunStackHeader;
                int line = Word((ushort)(at + 1));
                if (Peek((ushort)at) != 0)
                {
                    at -= ForValues;
                    continue;
                }

                if (FindLine(line) is { } address) { gosubs.Add((line, address + Peek((ushort)(at + 3)) - 2)); }
            }

            return gosubs;
        }
    }

    /// <inheritdoc/>
    public (int Code, string Message, bool Handled) BasicError()
    {
        int code = Peek(ErrorNumber);
        string message = code is >= 2 and < 2 + 20
            ? $"ERROR- {code}: {s_errors[code - 2]}"
            : code >= 128 ? $"ERROR- {code}: an input/output error" : $"ERROR- {code}";

        return (code, message, (Peek((ushort)(TrapLine + 1)) & 0x80) == 0);
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   At EXECUTE_STATEMENT the statement's token is in A, about to be dispatched: STMCUR and LINE_LENGTH move to the
    ///   new line, NEXT_STATEMENT and TOKEN_OFFSET to the new statement, and A takes its token.
    ///  </para>
    /// </remarks>
    public void SetBasicStatement(int line, int textPointer)
    {
        if (FindLine(line) is not { } address) { throw new ArgumentException($"There is no line {line}."); }
        int offset = textPointer + 1 - address;
        PokeWord(Stmcur, address);
        Poke(LineLength, Peek((ushort)(address + 2)));
        Poke(NextStatement, Peek((ushort)(address + offset)));
        Poke(TokenOffset, (byte)(offset + 2));
        Machines.Atari.AtariMachine machine = _machine;
        ProcessorRegisters registers = machine.Processor.Registers;
        registers.Accumulator = Peek((ushort)(address + offset + 1));
        machine.Processor.Registers = registers;
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The line editor resets the 6502's stack itself and reads the next line; the line STOP or the error kept is
    ///   left for CONT.
    ///  </para>
    /// </remarks>
    public void EnterBasicPrompt(BasicRom rom)
    {
        ProcessorRegisters registers = _machine.Processor.Registers;
        registers.StackPointer = 0xFF;
        registers.ProgramCounter = rom.Prompt;
        _machine.Processor.Registers = registers;
        _calls.Reset();
    }

    // Where Atari BASIC runs statements, stops and reports errors, from its source's symbols.
    private void SetBasic(IReadOnlyDictionary<string, long> symbols)
    {
        string[] labels =
        [
            "EXECUTE_NEXT_STATEMENT", "EXECUTE_STATEMENT", "EDIT_LINE", "HANDLE_ERROR", "STATEMENT_RUN",
            "STATEMENT_CONT", "STATEMENT_STOP", "STATEMENT_END"
        ];

        if (!labels.All(symbols.ContainsKey)) { return; }
        ushort At(string label) => (ushort)symbols[label];
        _basicRom = new BasicRom(
            StatementStart: At("EXECUTE_NEXT_STATEMENT"),
            Gone: At("EXECUTE_STATEMENT"),
            Prompt: At("EDIT_LINE"),
            Error: At("HANDLE_ERROR"),
            Run: At("STATEMENT_RUN"),
            Continue: At("STATEMENT_CONT"),
            Stops: new Dictionary<ushort, string>
            {
                [At("STATEMENT_STOP")] = BasicRom.StopOrBreak,
                [At("STATEMENT_END")] = "END"
            });
    }

    // The address of a program line, by its number, or null when there is none.
    private int? FindLine(int number)
    {
        int at = Word(AtariBasicDialect.Stmtab);
        int end = Word(AtariBasicDialect.Starp);
        while (at + AtariBasicDialect.Header <= end)
        {
            int found = Word((ushort)at);
            if (found == number) { return at; }
            if (found > number || found >= AtariBasicDialect.ImmediateLine) { return null; }
            int length = Peek((ushort)(at + 2));
            if (length < AtariBasicDialect.Header) { return null; }
            at += length;
        }

        return null;
    }

    private int Word(int address) => Peek((ushort)address) | (Peek((ushort)(address + 1)) << 8);

    private void PokeWord(ushort address, int value)
    {
        Poke(address, (byte)value);
        Poke((ushort)(address + 1), (byte)(value >> 8));
    }
}
