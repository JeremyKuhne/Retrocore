// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using Retrocore.Machines.Commodore;

namespace Retrocore.Debug;

// The PET's BASIC, for the BASIC thread and the program document. It is Microsoft's 6502 BASIC, as AppleSoft is:
// NEWSTT fetches each statement and GONE starts it with JSR CHRGET, the text pointer before the statement. BASIC 1,
// 2 and 4 keep page zero in different places, so every address comes from the running BASIC's assembled symbols.
internal sealed partial class PetDebugTarget
{
    // Where every PET's BASIC program starts.
    private const ushort BasicStart = 0x0401;

    private const byte RtiOpcode = 0x40;

    // Whether the last instruction fetched was an RTI: an interrupt taken at GONE returns there, which starts nothing
    // that GONE did not start before the interrupt.
    private bool _returnedFromInterrupt;

    private BasicRom? _basicRom;
    private IReadOnlyDictionary<string, long>? _basicSymbols;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Commodore BASIC 1 on the 2001, BASIC 2 on the 2001 with the upgrade ROMs, BASIC 4 on the 4032.
    ///  </para>
    /// </remarks>
    public BasicDialect? Basic => BasicDialect.PetBasicVersion(_machine.Model.BasicVersion());

    /// <inheritdoc/>
    public BasicRom? BasicRom => _basicRom;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   BASIC's RAM test takes a second or two with 32K.
    ///  </para>
    /// </remarks>
    public double BasicBootSeconds => 4;

    /// <inheritdoc/>
    public bool PressesReturnForPrompt => false;

    /// <inheritdoc/>
    public int BasicCurrentLine => Word(Symbol("CURLIN"));

    // Whether an address is in BASIC's CHRGET, from CHRGET to its RTS at CHRRTS, in page zero.
    private bool InChrget(ushort address) =>
        _basicSymbols is { } symbols
            && symbols.TryGetValue("CHRGET", out long first)
            && symbols.TryGetValue("CHRRTS", out long last)
            && address >= first
            && address <= last;

    /// <inheritdoc/>
    public (int Line, int Address)? BasicStatementStart(ushort pc) =>
        !_returnedFromInterrupt && _basicRom is { } rom && pc == rom.Gone ? (BasicCurrentLine, BasicTextPointer + 1) : null;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   TXTPTR, inside CHRGET in page zero.
    ///  </para>
    /// </remarks>
    public int BasicTextPointer => Word(Symbol("TXTPTR"));

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   This BASIC saves no stack pointer for each statement; at GONE its entries are right above the stack pointer.
    ///  </para>
    /// </remarks>
    public int BasicStack => BasicLiveStack;

    /// <inheritdoc/>
    public int BasicLiveStack => 0x0100 + _machine.Processor.Registers.StackPointer + 1;

    /// <inheritdoc/>
    public int BasicForSize => 18;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   GOSUB pushes its five bytes over the statement fetcher's return address, which RETURN uses.
    ///  </para>
    /// </remarks>
    public int BasicGosubSize => 7;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   X is the message's offset in ERRTAB, whose last character has bit 7 set.
    ///  </para>
    /// </remarks>
    public (int Code, string Message, bool Handled) BasicError()
    {
        int code = _machine.Processor.Registers.X;
        if (_basicSymbols?.TryGetValue("ERRTAB", out long table) != true) { return (code, $"error {code}", false); }
        Span<char> message = stackalloc char[40];
        int length = 0;
        while (length < message.Length)
        {
            byte character = Peek((ushort)(table + code + length));
            message[length++] = (char)(character & 0x7F);
            if ((character & 0x80) != 0) { break; }
        }

        return (code, $"?{message[..length]} ERROR", false);
    }

    /// <inheritdoc/>
    public void SetBasicStatement(int line, int textPointer)
    {
        PokeWord(Symbol("CURLIN"), line);
        PokeWord(Symbol("TXTPTR"), textPointer);
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   As STKINI does: the string temporaries are emptied, subscripts allowed, CONT disallowed and the stack reset,
    ///   with a zero over its bottom entry for FNDFOR; then CURLIN marks direct mode and the command loop, MAIN, reads a
    ///   line.
    ///  </para>
    /// </remarks>
    public void EnterBasicPrompt(BasicRom rom)
    {
        Poke(Symbol("TEMPPT"), (byte)Symbol("TEMPST"));
        Poke(Symbol("SUBFLG"), 0);
        Poke((ushort)(Symbol("OLDTXT") + 1), 0);
        Poke((ushort)(Symbol("CURLIN") + 1), 0xFF);
        byte stack = (byte)(Symbol("STKEND") - 257);
        Poke((ushort)(0x0101 + stack), 0);
        ProcessorRegisters registers = _machine.Processor.Registers;
        registers.StackPointer = stack;
        registers.ProgramCounter = rom.Prompt;
        _machine.Processor.Registers = registers;
        _calls.Reset();
    }

    /// <summary>
    ///  Takes the running BASIC's addresses from its assembly: its page zero, and where it runs statements, stops and
    ///  reports errors.
    /// </summary>
    /// <param name="symbols">The BASIC overlay's assembled symbols.</param>
    internal void SetBasicSymbols(IReadOnlyDictionary<string, long> symbols)
    {
        _basicSymbols = symbols;
        _basicRom = BasicRom.From(
            symbols,
            "MAIN",
            run: "RUN",
            resume: "CONT",
            [("STOP", "STOP"), ("END", "END"), ("ENDCON", "ENDCON")]);
    }

    // Sets the end of a BASIC program loaded at BasicStart, as LOAD does: the variables, arrays and free space start
    // past it.
    private void SetProgramEnd(int end)
    {
        foreach (string pointer in (string[])["VARTAB", "ARYTAB", "STREND"])
        {
            PokeWord(Symbol(pointer), end);
        }
    }

    private ushort Symbol(string name) => _basicSymbols?.TryGetValue(name, out long value) == true
        ? (ushort)value
        : throw new InvalidOperationException($"BASIC's {name} is not known without the SDK's BASIC source.");

    private int Word(ushort address) => Peek(address) | (Peek((ushort)(address + 1)) << 8);

    private void PokeWord(ushort address, int value)
    {
        Poke(address, (byte)value);
        Poke((ushort)(address + 1), (byte)(value >> 8));
    }
}
