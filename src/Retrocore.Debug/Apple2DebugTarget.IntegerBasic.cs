// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;

namespace Retrocore.Debug;

// Integer BASIC on the Apple II: which BASIC is in memory, and where Integer BASIC starts statements, keeps its
// GOSUBs and reports errors, for the BASIC thread.
//
// Integer BASIC has no one place where every statement starts. A line's first statement starts at RUNLOOP, which runs a
// line from PX; each one after a colon starts at WAITTOKEN, where the colon, arriving after the statement before it has
// run, steps PX on. The line running is at PR, and its number follows the line's length.
internal sealed partial class Apple2DebugTarget
{
    // How many cycles a finding of which BASIC is in memory stands: the language card and the firmware card switch it
    // only on a DOS command or a reset.
    private const ulong BasicCheckCycles = 2_000;

    // Integer BASIC's VERBNOW, the token arriving at the interpreter.
    private const ushort VerbNow = 0xD6;

    // Integer BASIC's GOSUB stack in page 1: the return token addresses' low and high bytes (STK_00, STK_10) and the
    // return lines' (STK_20, STK_30).
    private const ushort GosubTokenLow = 0x0100;
    private const ushort GosubTokenHigh = 0x0110;
    private const ushort GosubLineLow = 0x0120;
    private const ushort GosubLineHigh = 0x0130;

    // The stack pointer GETNEXT gives each line, and RUNFLAG while running.
    private const byte FreshStack = 0xFF;
    private const byte Running = 0xFF;

    // Integer BASIC's error messages, by the offset in their page that ERRMESS is given in Y.
    private static readonly Dictionary<int, string> s_integerErrors = new()
    {
        [0x00] = ">32767",
        [0x06] = "TOO LONG",
        [0x0E] = "SYNTAX",
        [0x14] = "MEM FULL",
        [0x1C] = "TOO MANY PARENS",
        [0x2B] = "STRING",
        [0x31] = "NO END",
        [0x37] = "BAD BRANCH",
        [0x41] = "16 GOSUBS",
        [0x4A] = "BAD RETURN",
        [0x54] = "16 FORS",
        [0x5B] = "BAD NEXT",
        [0x77] = ">255",
        [0x7B] = "RANGE",
        [0x80] = "DIM",
        [0x83] = "STR OVFL"
    };

    private BasicRom? _integerRom;
    private ushort _integerColon;
    private bool _integerActive;
    private ulong _integerChecked = ulong.MaxValue;

    /// <summary>
    ///  Gets whether Integer BASIC is in memory now: its syntax tables are at $EC00.
    /// </summary>
    internal bool IntegerActive
    {
        get
        {
            ulong now = CycleCount;
            if (_integerChecked == ulong.MaxValue || now - _integerChecked > BasicCheckCycles || now < _integerChecked)
            {
                _integerChecked = now;
                _integerActive = Peek(0xEC00) == IntegerBasicSyntax.Integer.Table[0]
                    && Peek(0xEC01) == IntegerBasicSyntax.Integer.Table[1]
                    && Peek(0xEC02) == IntegerBasicSyntax.Integer.Table[2]
                    && Peek(0xEC03) == IntegerBasicSyntax.Integer.Table[3];
            }

            return _integerActive;
        }
    }

    /// <inheritdoc/>
    public int BasicCurrentLine
    {
        get
        {
            if (IntegerActive)
            {
                int line = IntegerWord(IntegerBasicDialect.Pr);
                return IntegerWord(line + 1);
            }

            return Basic is { } dialect ? IntegerWord(dialect.Pointers.CurrentLine) : 0;
        }
    }

    /// <inheritdoc/>
    public (int Line, int Address)? BasicStatementStart(ushort pc)
    {
        if (BasicRom is not { } rom) { return null; }
        if (!IntegerActive) { return AppleSoftStatementStart(rom, pc); }

        int token = IntegerWord(IntegerBasicDialect.Px);
        if (pc == rom.Gone)
        {
            // After RETURN or NEXT the line runs on from the colon or end after their statement, which starts nothing.
            byte first = Peek((ushort)token);
            return first is IntegerBasicDialect.EndOfLine or IntegerBasicDialect.Colon ? null : (BasicCurrentLine, token);
        }

        if (pc == _integerColon && Peek(VerbNow) == IntegerBasicDialect.Colon)
        {
            byte next = Peek((ushort)(token + 1));
            return next is IntegerBasicDialect.EndOfLine or IntegerBasicDialect.Colon ? null : (BasicCurrentLine, token + 1);
        }

        return null;
    }

    /// <inheritdoc/>
    public IReadOnlyList<(int Line, int TextPointer)>? BasicGosubs
    {
        get
        {
            if (!IntegerActive) { return null; }
            int count = Math.Min((int)Peek(IntegerBasicDialect.GosubIndex), 16);
            List<(int, int)> entries = new(count);
            for (int index = count - 1; index >= 0; index--)
            {
                int line = Peek((ushort)(GosubLineLow + index)) | (Peek((ushort)(GosubLineHigh + index)) << 8);
                int token = Peek((ushort)(GosubTokenLow + index)) | (Peek((ushort)(GosubTokenHigh + index)) << 8);

                // The return is to the token after GOSUB's line number, in the GOSUB's statement.
                entries.Add((IntegerWord(line + 1), token - 1));
            }

            return entries;
        }
    }

    // Integer BASIC's statement and stop addresses, from the SDK's source of it.
    private BasicRom? IntegerBasicRom(IReadOnlyDictionary<string, long>? symbols)
    {
        if (symbols is null) { return null; }
        string[] names = ["RUNLOOP", "WAITTOKEN", "CMDPROMPT", "ERRMESS", "RUN", "CON", "STOPPED_AT", "END"];
        if (names.Any(name => !symbols.ContainsKey(name))) { return null; }
        _integerColon = (ushort)symbols["WAITTOKEN"];
        ushort line = (ushort)symbols["RUNLOOP"];
        return new BasicRom(
            StatementStart: line,
            Gone: line,
            Prompt: (ushort)symbols["CMDPROMPT"],
            Error: (ushort)symbols["ERRMESS"],
            Run: (ushort)symbols["RUN"],
            Continue: (ushort)symbols["CON"],
            new Dictionary<ushort, string>
            {
                [(ushort)symbols["STOPPED_AT"]] = BasicRom.IntegerStop,
                [(ushort)symbols["END"]] = BasicRom.IntegerEnd
            });
    }

    // The error ERRMESS reports: its message's offset is in Y.
    private (int Code, string Message, bool Handled) IntegerError()
    {
        int code = _machine.Processor.Registers.Y;
        string message = s_integerErrors.TryGetValue(code, out string? text) ? $"*** {text} ERR" : $"error {code}";
        return (code, message, false);
    }

    // Runs a statement next: the line it is in at PR, its first token at PX, and the CPU where GETNEXT runs a line,
    // with the fresh stack GETNEXT gives it.
    private void SetIntegerStatement(int line, int textPointer)
    {
        int at = IntegerWord(IntegerBasicDialect.Pp);
        int end = IntegerWord(IntegerBasicDialect.HiMem);
        while (at < end && Peek((ushort)at) >= 4 && IntegerWord(at + 1) != line) { at += Peek((ushort)at); }
        if (at >= end || IntegerWord(at + 1) != line)
        {
            throw new InvalidOperationException($"There is no line {line}.");
        }


        PokeWord(IntegerBasicDialect.Pr, at);
        PokeWord(IntegerBasicDialect.Px, textPointer + 1);
        Poke(IntegerBasicDialect.RunFlag, Running);
        ProcessorRegisters registers = _machine.Processor.Registers;
        registers.StackPointer = FreshStack;
        registers.ProgramCounter = BasicRom?.Gone ?? registers.ProgramCounter;
        _machine.Processor.Registers = registers;
        _calls.Reset();
    }

    // Puts Integer BASIC at its prompt: not running, a fresh stack, at the command loop.
    private void EnterIntegerPrompt(BasicRom rom)
    {
        Poke(IntegerBasicDialect.RunFlag, 0);
        ProcessorRegisters registers = _machine.Processor.Registers;
        registers.StackPointer = FreshStack;
        registers.ProgramCounter = rom.Prompt;
        _machine.Processor.Registers = registers;
        _calls.Reset();
    }

    private int IntegerWord(int address) => Peek((ushort)address) | (Peek((ushort)(address + 1)) << 8);

    private void PokeWord(int address, int value)
    {
        Poke((ushort)address, (byte)value);
        Poke((ushort)(address + 1), (byte)(value >> 8));
    }
}
