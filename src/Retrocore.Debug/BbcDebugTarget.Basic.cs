// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using Touki.Text;

namespace Retrocore.Debug;

// BBC BASIC II, for the BASIC thread and the program document, from the SDK's BbcBasic.asm.
//
// Every statement starts at EXECUTE_STATEMENT, with PTRA's base and offset at its first character: after a colon or
// at a line's start the offset is 1, from the colon or the line's length byte. EXECUTE_STATEMENT also loops back to
// itself past each space before the statement, and IF, THEN and ELSE enter it part way along a line. BASIC keeps no
// current line number: the line is the one PTRA is in. FOR, REPEAT and GOSUB have their own stacks in page five;
// PROC and FN move the 6502 stack onto BASIC's stack and start it afresh, which the target follows as they run.
internal sealed partial class BbcDebugTarget
{
    // The MOS's pointer to the error number after a BRK, which BASIC's error handler reads.
    private const ushort ErrorPointer = 0xFD;

    // The 6502 stack BASIC starts each line, and each FN and PROC, with.
    private const byte EmptyStack = 0xFF;

    // PTRB, the base of the text expressions are read from, and its offset (BasicEquates.asm's PTR_B, PTR_B_OFFSET).
    private const int PtrB = 0x19;
    private const int PtrBOffset = 0x1B;

    // BASIC II's hooks, from the SDK's source, and the socket it is in; none without them.
    private BasicRom? _basicRom;
    private int _basicSocket = -1;
    private ushort _defaultErrorHandler;
    private ushort _callStart;
    private ushort _callReturn;
    private ushort _executeLine;

    // The FN and PROC calls in progress, oldest first: the line and text pointer each was called from, and the GOSUBs
    // open when it was.
    private readonly List<(int Line, int TextPointer, int Gosubs, string Kind)> _basicCalls = [];

    // The statement start reported last, at EXECUTE_STATEMENT, so a space EXECUTE_STATEMENT passes is not another.
    private int _lastStart = -1;
    private (int Line, int Address)? _lastResult;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   BBC BASIC II, when a socket holds the ROM the SDK's source builds.
    ///  </para>
    /// </remarks>
    public BasicDialect? Basic => _basicSocket >= 0 ? BasicDialect.BbcBasic : null;

    /// <inheritdoc/>
    public BasicRom? BasicRom => _basicRom;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   While ROMSEL has BASIC's socket paged in: BASIC's addresses are another ROM's while a filing system runs.
    ///  </para>
    /// </remarks>
    public bool BasicPagedIn => _machine.Bus.Socket == _basicSocket;

    /// <inheritdoc/>
    public bool HasBasicSource => _basicRom is not null;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The MOS starts BASIC within a second, or a little more with the DFS, and needs no key pressed.
    ///  </para>
    /// </remarks>
    public double BasicBootSeconds => 3;

    /// <inheritdoc/>
    public bool PressesReturnForPrompt => false;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The line PTRA is in.
    ///  </para>
    /// </remarks>
    public int BasicCurrentLine => BbcBasicDialect.LineAt(new TargetBasicMemory(this), BasicTextPointer + 1) ?? 0;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   PTRA's base and offset, less one: at a statement's start, the colon or the line's length byte before it.
    ///  </para>
    /// </remarks>
    public int BasicTextPointer => Word(BbcBasicDialect.PtrA) + Peek(BbcBasicDialect.PtrAOffset) - 1;

    /// <inheritdoc/>
    public (int Line, int Address)? BasicStatementStart(ushort pc)
    {
        if (_basicRom is not { } rom || pc != rom.Gone || !BasicPagedIn) { return null; }
        int address = BasicTextPointer + 1;
        if (address == _lastStart) { return _lastResult; }

        // A space EXECUTE_STATEMENT has just passed: the same statement.
        bool space = address == _lastStart + 1 && Peek((ushort)(address - 1)) == ' ';
        _lastStart = address;
        _lastResult = space ? null : (BbcBasicDialect.LineAt(new TargetBasicMemory(this), address) ?? 0, address);
        return _lastResult;
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The GOSUBs from their stack in page five, each at the colon or carriage return that ended its statement, and
    ///   the FN and PROC calls the target has seen made, most recent first.
    ///  </para>
    /// </remarks>
    public IReadOnlyList<(int Line, int TextPointer, string Kind)>? BasicCalls
    {
        get
        {
            TargetBasicMemory memory = new(this);
            int gosubs = Math.Min((int)Peek(BbcBasicDialect.GosubLevel), BbcBasicDialect.GosubStackHigh - BbcBasicDialect.GosubStackLow);
            List<(int Order, int Line, int TextPointer, string Kind)> entries = [];
            for (int index = 0; index < gosubs; index++)
            {
                int pointer = Peek((ushort)(BbcBasicDialect.GosubStackLow + index))
                    | (Peek((ushort)(BbcBasicDialect.GosubStackHigh + index)) << 8);

                entries.Add(((2 * index) + 1, BbcBasicDialect.LineAt(memory, pointer) ?? 0, pointer - 1, "GOSUB"));
            }

            // Newest first, so calls at the same GOSUB depth stay most recent first through the stable sort.
            foreach ((int line, int pointer, int open, string kind) in Enumerable.Reverse(_basicCalls))
            {
                entries.Add((2 * Math.Min(open, gosubs), line, pointer, kind));
            }

            return [.. entries.OrderByDescending(entry => entry.Order).Select(entry => (entry.Line, entry.TextPointer, entry.Kind))];
        }
    }

    /// <inheritdoc/>
    public int BasicForSize => BbcBasicDialect.ForEntrySize;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   At the error handler, the MOS's pointer at &amp;FD is the error's number; its message follows, with BASIC's
    ///   own messages holding tokens. ON ERROR takes it when its text is not the ROM's default.
    ///  </para>
    /// </remarks>
    public (int Code, string Message, bool Handled) BasicError()
    {
        int at = Word(ErrorPointer);
        int code = Peek((ushort)at);
        using ValueStringBuilder message = new(stackalloc char[64]);
        for (int index = at + 1; index < at + 256 && Peek((ushort)index) is byte value and not 0; index++)
        {
            if (BasicDialect.BbcBasic.Keyword(value) is { Length: > 0 } word) { message.Append(word); }
            else { message.Append(value is >= 0x20 and < 0x7F ? (char)value : '?'); }
        }

        return (code, message.ToString(), Word(BbcBasicDialect.OnError) != _defaultErrorHandler);
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   At EXECUTE_STATEMENT: PTRA's base goes to the address before the statement and its offset to 1, as after a
    ///   colon or at a line's start. The line goes with it, as BASIC keeps none of its own.
    ///  </para>
    /// </remarks>
    public void SetBasicStatement(int line, int textPointer)
    {
        PokeWord(BbcBasicDialect.PtrA, textPointer);
        Poke(BbcBasicDialect.PtrAOffset, 1);
        _lastStart = -1;
        _lastResult = null;
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   As BASIC's error handler does on its way back to immediate mode: the 6502 stack is emptied and BASIC goes on
    ///   at IMMEDIATE_MODE, which puts PTRA in the line buffer and resets ON ERROR; the line typed next resets the
    ///   stacks.
    ///  </para>
    /// </remarks>
    public void EnterBasicPrompt(BasicRom rom)
    {
        ProcessorRegisters registers = _machine.Processor.Registers;
        registers.StackPointer = EmptyStack;
        registers.ProgramCounter = rom.Prompt;
        _machine.Processor.Registers = registers;
        _basicCalls.Clear();
        _calls.Reset();
    }

    // Takes BASIC's hooks from its assembled source.
    private void SetBasic(Assembler.AssemblyResult basic, int socket)
    {
        _basicSocket = socket;
        IReadOnlyDictionary<string, long> symbols = basic.Symbols;
        string[] labels =
        [
            "EXECUTE_STATEMENT", "IMMEDIATE_MODE", "BRK_HANDLER", "RUN_PROGRAM", "STOP_STATEMENT", "END_STATEMENT",
            "MOVE_TO_NEXT_LINE_END_OF_PROGRAM", "DEFAULT_ERROR_HANDLER", "CALL_FN_PROC", "CALL_FN_PROC_RETURN",
            "EXECUTE_LINE"
        ];

        if (!labels.All(symbols.ContainsKey)) { return; }
        ushort At(string label) => (ushort)symbols[label];

        // BBC BASIC has no CONT; a program starts only with RUN or CHAIN.
        _basicRom = new BasicRom(
            StatementStart: At("EXECUTE_STATEMENT"),
            Gone: At("EXECUTE_STATEMENT"),
            Prompt: At("IMMEDIATE_MODE"),
            Error: At("BRK_HANDLER"),
            Run: At("RUN_PROGRAM"),
            Continue: At("RUN_PROGRAM"),
            Stops: new Dictionary<ushort, string>
            {
                [At("STOP_STATEMENT")] = "STOP",
                [At("END_STATEMENT")] = "END",
                [At("MOVE_TO_NEXT_LINE_END_OF_PROGRAM")] = "PRGEND"
            });

        _defaultErrorHandler = At("DEFAULT_ERROR_HANDLER");
        _callStart = At("CALL_FN_PROC");
        _callReturn = At("CALL_FN_PROC_RETURN");
        _executeLine = At("EXECUTE_LINE");
    }

    // Follows FN and PROC calls before an instruction runs: a call starts at CALL_FN_PROC with A the FN or PROC token
    // and PTRB just past it, and ends at CALL_FN_PROC_RETURN. PTRB, not PTRA, is the caller's text: PROC copies PTRA
    // to it, and an FN in an argument, as in PROCouter(FNinner), is read through it while PTRA is in the outer DEF's
    // parameters. An error, a typed line or RUN starts BASIC's stacks afresh.
    private void ObserveBasicCall(ushort pc)
    {
        if (_basicRom is not { } rom || _machine.Bus.Socket != _basicSocket) { return; }
        if (pc == _callStart)
        {
            int pointer = Word(PtrB) + Peek(PtrBOffset) - 1;
            int line = Peek(PtrB + 1) == BbcBasicDialect.LineBufferPage
                ? 0
                : BbcBasicDialect.LineAt(new TargetBasicMemory(this), pointer + 1) ?? 0;

            string kind = _machine.Processor.Registers.Accumulator == 0xA4 ? "FN" : "PROC";
            _basicCalls.Add((line, pointer, Peek(BbcBasicDialect.GosubLevel), kind));
        }
        else if (pc == _callReturn && _basicCalls.Count != 0)
        {
            _basicCalls.RemoveAt(_basicCalls.Count - 1);
        }
        else if (pc == rom.Error || pc == _executeLine || pc == rom.Prompt)
        {
            _basicCalls.Clear();
        }
    }

    private int Word(int address) => Peek((ushort)address) | (Peek((ushort)(address + 1)) << 8);

    private void PokeWord(int address, int value)
    {
        Poke((ushort)address, (byte)value);
        Poke((ushort)(address + 1), (byte)(value >> 8));
    }
}
