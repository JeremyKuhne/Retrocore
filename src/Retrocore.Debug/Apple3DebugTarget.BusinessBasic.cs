// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using Touki.Text;

namespace Retrocore.Debug;

internal sealed partial class Apple3DebugTarget
{
    // How many of GONE's bytes say Business BASIC is in memory.
    private const int BusinessGoneLength = 8;

    // Business BASIC's zero page, at $1A00 while it runs, and its stack, in the page after.
    private const ushort CurrentLineAddress = BusinessBasicDialect.ZeroPage + 0x4B;
    private const ushort TextPointerAddress = BusinessBasicDialect.ZeroPage + 0xBC;
    private const ushort ErrorFlagAddress = BusinessBasicDialect.ZeroPage + 0x96;
    private const ushort StatementStackAddress = BusinessBasicDialect.ZeroPage + 0x97;
    private const int BasicStackPage = BusinessBasicDialect.ZeroPage + 0x100;

    // The stack entries' tokens and sizes: FOR's 20 bytes, and GOSUB's six.
    private const byte ForToken = 0x81;
    private const byte GosubToken = 0xBE;
    private const int ForSize = 20;
    private const int GosubSize = 6;
    private const byte OnErrActive = 0x80;

    // TEMPPT and the first of the string temporaries, TEMPST; SUBFLG; and STKEND, where STKINI leaves the stack.
    private const ushort TemporaryPointerAddress = BusinessBasicDialect.ZeroPage + 0x26;
    private const byte FirstTemporary = 0x29;
    private const ushort SubscriptFlagAddress = BusinessBasicDialect.ZeroPage + 0x0A;
    private const byte EmptyStack = 0xFE;

    // The first address past the interpreter, and the start of SOS's kernel in the system bank.
    private const int BusinessBasicEnd = Apple3SdkModules.BusinessBasicOrigin + Apple3SdkModules.BusinessBasicSize;
    private const int SosKernelStart = 0xB800;

    // The end of the switchable banks' window.
    private const int SwitchableEnd = 0xA000;

    // Business BASIC 1.23, from the SDK's source: its hooks, the bytes at GONE that say it is in memory, and its error
    // messages' table.
    private BasicRom? _businessRom;
    private byte[] _businessGone = [];
    private int _businessErrors;

    // Where BASIC keeps the bank register value it runs with, BASICBNK.
    private int _businessBank;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Business BASIC 1.23, while its interpreter is in memory where SOS loads it: at <c>$5200</c> in the bank
    ///   the window shows.
    ///  </para>
    /// </remarks>
    public BasicDialect? Basic => BusinessBasicActive ? BasicDialect.BusinessBasic : null;

    /// <inheritdoc/>
    public BasicRom? BasicRom => BusinessBasicActive ? _businessRom : null;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Business BASIC's source, before SOS has loaded it from the disk.
    ///  </para>
    /// </remarks>
    public bool HasBasicSource => _businessRom is not null;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   SOS boots from the disk, loads BASIC, and BASIC runs the disk's HELLO before its prompt.
    ///  </para>
    /// </remarks>
    public double BasicBootSeconds => 120;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   A key would reach the disk's HELLO, which may have ON KBD.
    ///  </para>
    /// </remarks>
    public bool PressesReturnForPrompt => false;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   As BASIC's error handler does on its way to MAIN: the string temporaries are freed, subscripts allowed,
    ///   ON ERR turned off, direct mode marked, and the stack emptied but for the zero at its bottom, which FNDFOR
    ///   stops at.
    ///  </para>
    /// </remarks>
    public void EnterBasicPrompt(BasicRom rom)
    {
        Poke(TemporaryPointerAddress, FirstTemporary);
        Poke(SubscriptFlagAddress, 0);
        Poke(CurrentLineAddress + 1, 0xFF);
        Poke(ErrorFlagAddress, 0);
        Poke(BasicStackPage + 0xFF, 0);
        ProcessorRegisters registers = _machine.Processor.Registers;
        registers.StackPointer = EmptyStack;
        registers.ProgramCounter = rom.Prompt;
        _machine.Processor.Registers = registers;
        _calls.Reset();
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   TXTPTR with its X-byte, as a flat address (<see cref="BusinessBasicDialect.Flat(byte, int)"/>).
    ///  </para>
    /// </remarks>
    public int BasicTextPointer => FlatPointer(TextPointerAddress);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Each statement starts at GONE, with TXTPTR before its first byte. GONE also runs for an empty statement, a
    ///   colon followed by another or by the line's end, and goes straight back to NEWSTT without running anything;
    ///   that is no statement.
    ///  </para>
    /// </remarks>
    public (int Line, int Address)? BasicStatementStart(ushort pc)
    {
        if (BasicRom is not { } rom || pc != rom.Gone) { return null; }
        int address = BasicTextPointer + 1;
        (byte xByte, int at) = BusinessBasicDialect.Split(address);
        byte first = ReadFar(xByte, (ushort)at);
        return first is (byte)':' or 0 ? null : (Peek(CurrentLineAddress) | (Peek(CurrentLineAddress + 1) << 8), address);
    }

    /// <inheritdoc/>
    public int BasicStack => BasicStackPage + Peek(StatementStackAddress) + 1;

    /// <inheritdoc/>
    public int BasicLiveStack => BasicStackPage + _machine.Processor.Registers.StackPointer + 1;

    /// <inheritdoc/>
    public int BasicForSize => ForSize;

    /// <inheritdoc/>
    public int BasicGosubSize => GosubSize;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Each GOSUB entry holds the line it was in and its text pointer as an offset from TXTTAB: a bank, which may
    ///   be negative, and a 16-bit offset. The pointer is at the colon or zero after the GOSUB, where RETURN goes on
    ///   from; the address given is the byte before it, in the GOSUB statement.
    ///  </para>
    /// </remarks>
    public IReadOnlyList<(int Line, int TextPointer)>? BasicGosubs
    {
        get
        {
            List<(int, int)> entries = [];
            int start = FlatPointer(BusinessBasicDialect.ZeroPage + 0x39);
            for (int at = StackTop; at <= BasicStackPage + 0x100 - GosubSize;)
            {
                byte token = Peek((ushort)at);
                if (token == ForToken)
                {
                    at += ForSize;
                }
                else if (token == GosubToken)
                {
                    int line = Peek((ushort)(at + 1)) | (Peek((ushort)(at + 2)) << 8);
                    int bank = (sbyte)Peek((ushort)(at + 3));
                    int offset = (Peek((ushort)(at + 4)) << 8) | Peek((ushort)(at + 5));
                    entries.Add((line, start + (bank * 0x8000) + offset - 1));
                    at += GosubSize;
                }
                else
                {
                    break;
                }
            }

            return entries;
        }
    }

    // BASIC's most recent stack entry. At GONE, before it saves the stack pointer in REMSTK, the stack pointer itself:
    // RETURN goes on at NWSTT, past NEWSTT's save, so REMSTK still holds the subroutine's depth there.
    private int StackTop => BasicRom is { } rom && _machine.Processor.Registers.ProgramCounter == rom.Gone
        ? BasicLiveStack
        : BasicStack;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   At ERROR, X is the error's place in ERRTAB, from 1; the message is read from there.
    ///  </para>
    /// </remarks>
    public (int Code, string Message, bool Handled) BasicError()
    {
        int code = _machine.Processor.Registers.X;
        string message = ErrorMessage(code) is { } text ? $"?{text} ERROR" : $"error {code}";
        return (code, message, (Peek(ErrorFlagAddress) & OnErrActive) != 0);
    }

    /// <inheritdoc/>
    public void SetBasicStatement(int line, int textPointer)
    {
        (byte xByte, int address) = BusinessBasicDialect.Split(textPointer);
        Poke(CurrentLineAddress, (byte)line);
        Poke(CurrentLineAddress + 1, (byte)(line >> 8));
        Poke(TextPointerAddress, (byte)address);
        Poke(TextPointerAddress + 1, (byte)(address >> 8));
        Poke(TextPointerAddress - BusinessBasicDialect.XByteOffset, xByte);
    }

    // Whether Business BASIC's interpreter is in memory: GONE's bytes are where its source puts them, in the bank
    // BASIC recorded at its start. That bank is not always the one the window shows: SOS shows its drivers' banks
    // while they run, as the console's does while BASIC waits for a key.
    private bool BusinessBasicActive
    {
        get
        {
            if (_businessRom is not { } rom || _businessGone.Length == 0) { return false; }
            byte bank = Peek((ushort)_businessBank);
            for (int index = 0; index < _businessGone.Length; index++)
            {
                if (_machine.Bus.PeekBank(bank, (ushort)(rom.Gone + index)) != _businessGone[index]) { return false; }
            }

            return true;
        }
    }

    // Whether the bank in the $2000-$9FFF window now is BASIC's: GONE's bytes are there.
    private bool BusinessBasicInWindow
    {
        get
        {
            if (_businessRom is not { } rom) { return false; }
            for (int index = 0; index < _businessGone.Length; index++)
            {
                if (Peek((ushort)(rom.Gone + index)) != _businessGone[index]) { return false; }
            }

            return true;
        }
    }

    // Takes the interpreter's hooks from its assembled source. STOP, END (which runs into STOP) and CONTROL-C all stop
    // at STOP2, then run into ENDCON, as running off the program's end does.
    private void AddBusinessBasic(Assembler.AssemblyResult business)
    {
        _businessRom = BasicRom.From(
            business.Symbols,
            "MAIN",
            run: "RUN",
            resume: "CONT",
            [("STOP2", "STOP"), ("ENDCON", "ENDCON")]);

        if (_businessRom is not { } rom) { return; }
        int gone = rom.Gone - Apple3SdkModules.BusinessBasicOrigin;
        _businessGone = business.Sections[0].Bytes.Slice(gone, BusinessGoneLength).ToArray();
        _businessErrors = (int)business.Symbols["ERRTAB"];
        _businessBank = (int)business.Symbols["BASICBNK"];
    }

    // One of BASIC's pointers in its zero page, as a flat address.
    private int FlatPointer(int pointer)
    {
        byte xByte = Peek((ushort)(pointer - BusinessBasicDialect.XByteOffset));
        return BusinessBasicDialect.Flat(xByte, Peek((ushort)pointer) | (Peek((ushort)(pointer + 1)) << 8));
    }

    // The message of an error, the code'th of ERRTAB's words, each ending with bit 7 set; null past its end.
    private string? ErrorMessage(int code)
    {
        if (code < 1 || _businessErrors == 0) { return null; }
        using ValueStringBuilder text = new(stackalloc char[64]);
        int found = 1;
        for (int at = _businessErrors; at < _businessErrors + 0x400; at++)
        {
            byte value = Peek((ushort)at);
            if (found == code) { text.Append((char)(value & 0x7F)); }
            if ((value & 0x80) == 0) { continue; }
            if (found == code) { return text.ToString(); }
            found++;
        }

        return null;
    }
}
