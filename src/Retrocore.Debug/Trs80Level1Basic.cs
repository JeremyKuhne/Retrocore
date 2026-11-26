// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using Retrocore.Cpu.Z80;

namespace Retrocore.Debug;

/// <summary>
///  Level I BASIC as the BASIC thread sees it, on the Model I and the Model III: where it starts statements, keeps its
///  GOSUBs and reports errors, from <c>Level1.asm</c>'s symbols for the model's build.
/// </summary>
/// <remarks>
///  <para>
///   Every statement starts at <c>ST_RUN_4</c>, with DE at its first character, after the line's number or a colon.
///   <c>ST_RUN_4</c> also runs the statement after an IF's condition, which starts no statement of the line, and is
///   told apart by what is before DE. <c>CURRNT</c> holds the address of the line running, not its number; while INPUT
///   reads the keyboard it holds a stand-in, and the line is on the stack (<see cref="Level1Dialect.LineAddress"/>).
///  </para>
///  <para>
///   A GOSUB's frame on the Z80's stack, from <c>STKGOS</c>, is the previous frame, the calling line's address and the
///   text after the GOSUB's line number, or for ON GOSUB the end of its statement. Level I's errors are three messages,
///   HOW?, WHAT? and SORRY, which <c>ERROR</c> is given in DE; an error in what INPUT reads asks for it again, so INPUT
///   takes it as a handler would.
///  </para>
/// </remarks>
internal sealed class Trs80Level1Basic
{
    private const int MaximumGosubs = 128;
    private const ushort StackTop = Level1Dialect.ProgramStart;
    private const int ForFrameSize = 10;

    private readonly IDebugTarget _target;
    private readonly Func<Z80Registers> _registers;
    private readonly Action<Z80Registers> _setRegisters;
    private readonly Action _resetCalls;
    private readonly Dictionary<ushort, (int Code, string Message)> _errors;
    private readonly ushort _ready;

    private Trs80Level1Basic(
        IDebugTarget target,
        Func<Z80Registers> registers,
        Action<Z80Registers> setRegisters,
        Action resetCalls,
        BasicRom rom,
        ushort ready,
        Dictionary<ushort, (int Code, string Message)> errors)
    {
        _target = target;
        _registers = registers;
        _setRegisters = setRegisters;
        _resetCalls = resetCalls;
        Rom = rom;
        _ready = ready;
        _errors = errors;
    }

    /// <summary>
    ///  Gets the ROM's statement start, prompt, RUN, CONT, error and stops.
    /// </summary>
    internal BasicRom Rom { get; }

    /// <summary>
    ///  Finds Level I's routines in a build of <c>Level1.asm</c>.
    /// </summary>
    /// <param name="symbols">The build's symbols.</param>
    /// <param name="target">The machine's target, for its memory.</param>
    /// <param name="registers">Reads the Z80's registers.</param>
    /// <param name="setRegisters">Writes them.</param>
    /// <param name="resetCalls">Forgets the CPU's call stack, as moving the stack does.</param>
    /// <returns>The BASIC, or null when the symbols lack a routine.</returns>
    internal static Trs80Level1Basic? From(
        IReadOnlyDictionary<string, long> symbols,
        IDebugTarget target,
        Func<Z80Registers> registers,
        Action<Z80Registers> setRegisters,
        Action resetCalls)
    {
        string[] names =
        [
            "ST_RUN_4", "RSTART", "RSTART_2", "ERROR", "ST_RUN", "ST_CONT", "ST_STOP", "ST_END",
            "HOW_MSG", "WHAT_MSG", "SORRY_MSG"
        ];

        if (names.Any(name => !symbols.ContainsKey(name))) { return null; }
        ushort Address(string name) => (ushort)symbols[name];
        ushort statement = Address("ST_RUN_4");

        // STOP and BREAK both stop at ST_STOP; END runs into ST_NEW_2 and RSTART, which a program that runs off its
        // last line reaches too, by ST_NEW_2 or, from a false IF or a REM, straight from FNDSKP. Every way back to
        // reading lines, STOP's included, which prints no READY, comes to RSTART_2.
        BasicRom rom = new(
            StatementStart: statement,
            Gone: statement,
            Prompt: Address("RSTART_2"),
            Error: Address("ERROR"),
            Run: Address("ST_RUN"),
            Continue: Address("ST_CONT"),
            new Dictionary<ushort, string>
            {
                [Address("ST_STOP")] = "BREAK",
                [Address("ST_END")] = "END",
                [Address("RSTART")] = "PRGEND"
            });

        // Level I's errors have no codes; they are numbered here in the order the ROM keeps their messages.
        Dictionary<ushort, (int, string)> errors = new()
        {
            [Address("HOW_MSG")] = (1, "HOW?"),
            [Address("WHAT_MSG")] = (2, "WHAT?"),
            [Address("SORRY_MSG")] = (3, "SORRY")
        };

        return new(target, registers, setRegisters, resetCalls, rom, Address("RSTART"), errors);
    }

    private TargetBasicMemory Memory => new(_target);

    /// <summary>
    ///  Gets DE less one: the text pointer before the statement at <c>ST_RUN_4</c>.
    /// </summary>
    internal int TextPointer => _registers().DE - 1;

    /// <summary>
    ///  Gets the stack pointer, where the frames start at <c>ST_RUN_4</c>.
    /// </summary>
    internal int Stack => _registers().SP;

    /// <summary>
    ///  Gets the size of the frame PUSHA saves a FOR loop in.
    /// </summary>
    internal static int ForSize => ForFrameSize;

    /// <summary>
    ///  Gets the statement that starts at an instruction: at <c>ST_RUN_4</c>, the line's first or one after a colon.
    /// </summary>
    /// <param name="pc">The instruction's address.</param>
    /// <returns>The statement's line number and first byte, or null.</returns>
    internal (int Line, int Address)? StatementStart(ushort pc)
    {
        if (pc != Rom.Gone) { return null; }
        int line = Level1Dialect.LineAddress(Memory);
        if (line == 0) { return null; }
        int text = _registers().DE;
        bool starts = text == line + 2 || (text > line + 2 && _target.Peek((ushort)(text - 1)) == ':');
        return starts ? (Word(line), text) : null;
    }

    /// <summary>
    ///  Gets the GOSUBs in progress, most recent first: the calling line and the address before the text the GOSUB
    ///  returns to, after its line number, or for ON GOSUB the end of its statement.
    /// </summary>
    internal IReadOnlyList<(int Line, int TextPointer)> Gosubs
    {
        get
        {
            List<(int, int)> entries = [];
            for (int frame = Word(Level1Dialect.GosubFrame);
                frame is >= 0x4000 and < StackTop && entries.Count < MaximumGosubs;
                frame = Word(frame))
            {
                int caller = Word(frame + 2);
                if (caller < Level1Dialect.ProgramStart) { break; }
                entries.Add((Word(caller), Word(frame + 4) - 1));
            }

            return entries;
        }
    }

    /// <summary>
    ///  Describes the error <c>ERROR</c> is reporting: its message, by the address DE gives it.
    /// </summary>
    /// <returns>
    ///  The error's number, 1 for HOW?, 2 for WHAT? and 3 for SORRY; the message; and whether INPUT will ask again.
    /// </returns>
    internal (int Code, string Message, bool Handled) Error()
    {
        int message = _registers().DE;
        (int code, string text) = _errors.TryGetValue((ushort)message, out (int, string) known)
            ? known
            : (0, $"the message at ${message:X4}");

        return (code, text, Level1Dialect.InputWaiting(Memory));
    }

    /// <summary>
    ///  Moves BASIC to another statement at <c>ST_RUN_4</c>, as GOTO does: <c>CURRNT</c> to the line, DE to the
    ///  statement, the GOSUBs and FOR loops kept.
    /// </summary>
    /// <param name="line">The line number.</param>
    /// <param name="textPointer">The address before the statement.</param>
    /// <exception cref="InvalidOperationException">There is no such line.</exception>
    internal void SetStatement(int line, int textPointer)
    {
        int end = Word(Level1Dialect.TextEnd);
        int at = Level1Dialect.ProgramStart;
        while (at < end && Word(at) != line)
        {
            at += 2;
            while (at < end && _target.Peek((ushort)at) != Level1Dialect.EndOfLine) { at++; }
            at++;
        }

        if (at >= end) { throw new InvalidOperationException($"There is no line {line}."); }
        _target.Poke(Level1Dialect.CurrentLine, (byte)at);
        _target.Poke(Level1Dialect.CurrentLine + 1, (byte)(at >> 8));
        Z80Registers registers = _registers();
        registers.DE = (ushort)(textPointer + 1);
        registers.PC = Rom.Gone;
        _setRegisters(registers);
    }

    /// <summary>
    ///  Puts BASIC at READY, as an error does: direct mode, the stack at <c>$4200</c>, at <c>RSTART</c>, which prints
    ///  READY.
    /// </summary>
    internal void EnterPrompt()
    {
        _target.Poke(Level1Dialect.CurrentLine, 0);
        _target.Poke(Level1Dialect.CurrentLine + 1, 0);
        Z80Registers registers = _registers();
        registers.SP = StackTop;
        registers.PC = _ready;
        _setRegisters(registers);
        _resetCalls();
    }

    private int Word(int address) => _target.Peek((ushort)address) | (_target.Peek((ushort)(address + 1)) << 8);
}
