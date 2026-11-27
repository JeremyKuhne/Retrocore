// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;

namespace Retrocore.Debug;

// The VIC-20's BASIC, for the BASIC thread and the program document. It is Microsoft's 6502 BASIC 2, as the PET's
// BASIC 2 is: NEWSTT fetches each statement and GONE starts it, the text pointer before the statement. Its page zero
// is the PET's moved, and where its program starts depends on the expansion, so every address comes from the
// running BASIC's assembled symbols or its pointers.
internal sealed partial class Vic20DebugTarget
{
    private const byte RtiOpcode = 0x40;

    // Whether the last instruction fetched was an RTI: an interrupt taken at GONE returns there, which starts nothing
    // that GONE did not start before the interrupt.
    private bool _returnedFromInterrupt;

    private BasicRom? _basicRom;
    private IReadOnlyDictionary<string, long>? _basicSymbols;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Commodore BASIC 2, whose tokens are the PET's BASIC 2's and whose page zero is its own.
    ///  </para>
    /// </remarks>
    public BasicDialect? Basic => BasicDialect.Vic20Basic;

    /// <inheritdoc/>
    public BasicRom? BasicRom => _basicRom;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The kernal's RAM test and BASIC's start-up take under a second, even with every block expanded.
    ///  </para>
    /// </remarks>
    public double BasicBootSeconds => 3;

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
    ///   X is the error's number, from 1; ERRTAB holds each message's address, entry X at ERRTAB + 2X - 2, and a
    ///   message's last character has bit 7 set. The kernal's errors, 1 to 9, are reported through the same table.
    ///  </para>
    /// </remarks>
    public (int Code, string Message, bool Handled) BasicError()
    {
        int code = _machine.Processor.Registers.X;
        if (code == 0 || _basicSymbols?.TryGetValue("ERRTAB", out long table) != true)
        {
            return (code, $"error {code}", false);
        }

        ushort entry = (ushort)(table + (2 * code) - 2);
        ushort message = (ushort)Word(entry);
        Span<char> text = stackalloc char[40];
        int length = 0;
        int skipped = 0;
        while (length < text.Length && skipped < 4)
        {
            // BREAK's message ends in a NUL and a shifted space, which the screen shows as nothing and a space.
            byte character = Peek((ushort)(message + length + skipped));
            if ((character & 0x7F) == 0)
            {
                skipped++;
                continue;
            }

            text[length++] = (char)(character & 0x7F);
            if ((character & 0x80) != 0) { break; }
        }

        return (code, $"?{text[..length]} ERROR", false);
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
    /// <param name="symbols">BASIC's assembled symbols, with their historical names.</param>
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
