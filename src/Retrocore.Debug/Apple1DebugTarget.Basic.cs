// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Basic;
using Retrocore.Machines.Apple1;

namespace Retrocore.Debug;

// Apple-1 BASIC: loading it into the $E000 bank as its tape would, and, while it is there, where it starts statements,
// keeps its GOSUBs and reports errors, for the BASIC thread.
//
// As in Integer BASIC, a line's first statement starts at RUNLOOP, and each one after a colon at WAITTOKEN. The line
// running is at PR, and its number follows the line's length.
internal sealed partial class Apple1DebugTarget
{
    private const string BasicDump = "basic.bin";

    // How many cycles a finding of whether BASIC is in memory stands: only a program that writes $EC00 removes it.
    private const ulong BasicCheckCycles = 2_000;

    // BASIC's VERBNOW, the token arriving at the interpreter.
    private const ushort VerbNow = 0xD6;

    // BASIC's GOSUB stack in page 1: the return token addresses' low and high bytes (STK_00, STK_08) and the return
    // lines' (STK_10, STK_18).
    private const ushort GosubTokenLow = 0x0100;
    private const ushort GosubTokenHigh = 0x0108;
    private const ushort GosubLineLow = 0x0110;
    private const ushort GosubLineHigh = 0x0118;
    private const int GosubDepth = 8;

    // The stack pointer GETNEXT gives each line, and RUNFLAG while running.
    private const byte FreshStack = 0xFF;
    private const byte Running = 0xFF;

    // BASIC's error messages, by the offset in their page that ERRMESS is given in Y.
    private static readonly Dictionary<int, string> s_basicErrors = new()
    {
        [0x00] = ">32767",
        [0x06] = "TOO LONG",
        [0x0E] = "SYNTAX",
        [0x14] = "MEM FULL",
        [0x1C] = "TOO MANY PARENS",
        [0x2B] = "STRING",
        [0x34] = "END",
        [0x37] = "BAD BRANCH",
        [0x41] = ">8 GOSUBS",
        [0x4A] = "BAD RETURN",
        [0x54] = ">8 FORS",
        [0x5B] = "BAD NEXT",
        [0x77] = ">255",
        [0x7B] = "RANGE",
        [0x80] = "DIM",
        [0x83] = "STR OVFL"
    };

    private BasicRom? _basicRom;
    private ushort _basicColon;
    private bool _basicActive;
    private ulong _basicChecked = ulong.MaxValue;

    /// <summary>
    ///  Gets whether Apple-1 BASIC is in memory now: its syntax table is at $EC00.
    /// </summary>
    internal bool BasicActive
    {
        get
        {
            ulong now = CycleCount;
            if (_basicChecked == ulong.MaxValue || now - _basicChecked > BasicCheckCycles || now < _basicChecked)
            {
                _basicChecked = now;
                byte[] table = IntegerBasicSyntax.Apple1.Table;
                _basicActive = _machine.Configuration.HighRam
                    && Peek(0xEC00) == table[0]
                    && Peek(0xEC20) == table[0x20]
                    && Peek(0xED01) == table[0x101]
                    && Peek(0xEDFF) == table[0x1FF];
            }

            return _basicActive;
        }
    }

    /// <inheritdoc/>
    public BasicDialect? Basic => BasicActive ? BasicDialect.Apple1 : null;

    /// <inheritdoc/>
    public BasicRom? BasicRom => BasicActive ? _basicRom : null;

    /// <inheritdoc/>
    public int BasicCurrentLine => Word(Word(IntegerBasicDialect.Pr) + 1);

    /// <inheritdoc/>
    public int BasicTextPointer => Word(IntegerBasicDialect.Px) - 1;

    /// <inheritdoc/>
    public (int Line, int Address)? BasicStatementStart(ushort pc)
    {
        if (BasicRom is not { } rom) { return null; }
        int token = Word(IntegerBasicDialect.Px);
        if (pc == rom.Gone)
        {
            // After RETURN or NEXT the line runs on from the colon or end after their statement, which starts nothing.
            byte first = Peek((ushort)token);
            return first is IntegerBasicDialect.EndOfLine or IntegerBasicDialect.Colon ? null : (BasicCurrentLine, token);
        }

        if (pc == _basicColon && Peek(VerbNow) == IntegerBasicDialect.Colon)
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
            if (!BasicActive) { return null; }
            int count = Math.Min((int)Peek(IntegerBasicDialect.GosubIndex), GosubDepth);
            List<(int, int)> entries = new(count);
            for (int index = count - 1; index >= 0; index--)
            {
                int line = Peek((ushort)(GosubLineLow + index)) | (Peek((ushort)(GosubLineHigh + index)) << 8);
                int token = Peek((ushort)(GosubTokenLow + index)) | (Peek((ushort)(GosubTokenHigh + index)) << 8);

                // The return is to the token after GOSUB's line number, in the GOSUB's statement.
                entries.Add((Word(line + 1), token - 1));
            }

            return entries;
        }
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Apple-1 BASIC has no ON ERROR, so no error is handled.
    ///  </para>
    /// </remarks>
    public (int Code, string Message, bool Handled) BasicError()
    {
        int code = _machine.Processor.Registers.Y;
        string message = s_basicErrors.TryGetValue(code, out string? text) ? $"*** {text} ERR" : $"error {code}";
        return (code, message, false);
    }

    /// <inheritdoc/>
    public void SetBasicStatement(int line, int textPointer)
    {
        int at = Word(IntegerBasicDialect.Pp);
        int end = Word(IntegerBasicDialect.HiMem);
        while (at < end && Peek((ushort)at) >= 4 && Word(at + 1) != line) { at += Peek((ushort)at); }
        if (at >= end || Word(at + 1) != line)
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

    /// <inheritdoc/>
    public void EnterBasicPrompt(BasicRom rom)
    {
        Poke(IntegerBasicDialect.RunFlag, 0);
        ProcessorRegisters registers = _machine.Processor.Registers;
        registers.StackPointer = FreshStack;
        registers.ProgramCounter = rom.Prompt;
        _machine.Processor.Registers = registers;
        _calls.Reset();
    }

    /// <summary>
    ///  Starts BASIC at its cold start, as E000R in the Monitor does: an empty program, at the > prompt once it runs.
    /// </summary>
    /// <exception cref="InvalidOperationException">BASIC is not in memory.</exception>
    internal void StartBasic()
    {
        if (!BasicActive)
        {
            throw new InvalidOperationException(
                "Apple-1 BASIC is not in memory: it needs the $E000 bank (highRam) and loadBasic.");
        }

        ProcessorRegisters registers = _machine.Processor.Registers;
        registers.StackPointer = FreshStack;
        registers.ProgramCounter = Apple1SdkModules.BasicOrigin;
        _machine.Processor.Registers = registers;
        _calls.Reset();
    }

    // Puts BASIC in the $E000 bank, as loading it from tape would: the dump in the ROM directory, or the SDK's build.
    private static void LoadBasic(Apple1Machine machine, string? dumps, AssemblyResult? source)
    {
        if (!machine.Configuration.HighRam)
        {
            throw new ArgumentException("Apple-1 BASIC loads into the $E000 bank, which needs highRam.");
        }

        byte[] basic = Rom(dumps, BasicDump, Apple1SdkModules.BasicSize)
            ?? (source is { } built ? Image(built) : throw new InvalidOperationException("Apple-1 BASIC's source was not found."));

        machine.Bus.Load(Apple1SdkModules.BasicOrigin, basic);
    }

    // BASIC's statement and stop addresses, from the SDK's source of it.
    private void SetBasicSymbols(IReadOnlyDictionary<string, long>? symbols)
    {
        if (symbols is null) { return; }
        string[] names = ["RUNLOOP", "WAITTOKEN", "CMDPROMPT", "ERRMESS", "RUN", "STOPPED_AT", "END", "TRYLINE_END"];
        if (names.Any(name => !symbols.ContainsKey(name))) { return; }
        _basicColon = (ushort)symbols["WAITTOKEN"];
        ushort line = (ushort)symbols["RUNLOOP"];

        // Apple-1 BASIC has no CON, so nothing resumes a stopped program: 0 is never where BASIC runs.
        _basicRom = new BasicRom(
            StatementStart: line,
            Gone: line,
            Prompt: (ushort)symbols["CMDPROMPT"],
            Error: (ushort)symbols["ERRMESS"],
            Run: (ushort)symbols["RUN"],
            Continue: 0,
            new Dictionary<ushort, string>
            {
                [(ushort)symbols["STOPPED_AT"]] = BasicRom.Apple1Stop,
                [(ushort)symbols["END"]] = BasicRom.IntegerEnd,
                [(ushort)symbols["TRYLINE_END"]] = BasicRom.IntegerRanOff
            });
    }

    private int Word(int address) => Peek((ushort)address) | (Peek((ushort)(address + 1)) << 8);

    private void PokeWord(int address, int value)
    {
        Poke((ushort)address, (byte)value);
        Poke((ushort)(address + 1), (byte)(value >> 8));
    }
}
