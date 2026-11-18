// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Basic;
using Retrocore.Cpu.Z80;
using Retrocore.Machines.Kaypro;

namespace Retrocore.Debug;

// MBASIC on the Kaypro II: the BASIC thread, while MBASIC.COM is in memory as the SDK's source assembles it.
internal sealed partial class KayproDebugTarget
{
    // MBASIC's stack entries: FOR's token, variable, text pointer, step's sign, type, step, limit, line and text
    // pointer; GOSUB's token, line and text pointer; WHILE's token, text pointers and line.
    private const int ForEntrySize = 19;
    private const int GosubEntrySize = 5;
    private const int WhileEntrySize = 7;
    private const byte ForToken = 0x82;
    private const byte GosubToken = 0x8D;
    private const byte WhileToken = 0xB4;
    private const int MaximumStackEntries = 256;

    // GONE's first bytes, which say MBASIC is in memory.
    private const int GoneLength = 8;

    // MBASIC's messages by error code: 1-30, then the disk's from 50.
    private static readonly Dictionary<int, string> s_errors = new()
    {
        [1] = "NEXT without FOR", [2] = "Syntax error", [3] = "RETURN without GOSUB", [4] = "Out of DATA",
        [5] = "Illegal function call", [6] = "Overflow", [7] = "Out of memory", [8] = "Undefined line number",
        [9] = "Subscript out of range", [10] = "Duplicate Definition", [11] = "Division by zero", [12] = "Illegal direct",
        [13] = "Type mismatch", [14] = "Out of string space", [15] = "String too long",
        [16] = "String formula too complex", [17] = "Can't continue", [18] = "Undefined user function",
        [19] = "No RESUME", [20] = "RESUME without error", [21] = "Unprintable error", [22] = "Missing operand",
        [23] = "Line buffer overflow", [26] = "FOR Without NEXT", [29] = "WHILE without WEND",
        [30] = "WEND without WHILE", [50] = "FIELD overflow", [51] = "Internal error", [52] = "Bad file number",
        [53] = "File not found", [54] = "Bad file mode", [55] = "File already open", [57] = "Disk I/O error",
        [58] = "File already exists", [61] = "Disk full", [62] = "Input past end", [63] = "Bad record number",
        [64] = "Bad file name", [66] = "Direct statement in file", [67] = "Too many files"
    };

    private BasicRom? _mbasicRom;
    private byte[] _gone = [];

    /// <inheritdoc/>
    public BasicDialect? Basic => BasicDialect.Mbasic;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Only while MBASIC is in memory: CP/M loads it from a disk, and other programs use the same memory.
    ///  </para>
    /// </remarks>
    public BasicRom? BasicRom => MbasicActive ? _mbasicRom : null;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   <see cref="BasicRom"/> checks GONE's bytes in RAM, where MBASIC stays while the BIOS banks the ROM in.
    ///  </para>
    /// </remarks>
    public bool BasicRomInMemory => true;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   From RAM, as the BIOS may have the ROM banked over CURLIN.
    ///  </para>
    /// </remarks>
    public int BasicCurrentLine => Word(MbasicMemory.CURLIN);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   MBASIC's source, before CP/M has loaded it from the disk.
    ///  </para>
    /// </remarks>
    public bool HasBasicSource => _mbasicRom is not null;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   CP/M boots, and the launch's command starts MBASIC from a disk.
    ///  </para>
    /// </remarks>
    public double BasicBootSeconds => 60;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   A key would reach CP/M's command line before MBASIC starts.
    ///  </para>
    /// </remarks>
    public bool PressesReturnForPrompt => false;

    /// <inheritdoc/>
    public int BasicTextPointer => _machine.Processor.Registers.HL;

    /// <inheritdoc/>
    public int BasicStack => Word(MbasicMemory.SAVSTK);

    /// <inheritdoc/>
    public int BasicLiveStack => _machine.Processor.Registers.SP;

    /// <inheritdoc/>
    public int BasicForSize => ForEntrySize;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   From the stack NEWSTT saved as the statement began, past FOR's and WHILE's entries.
    ///  </para>
    /// </remarks>
    public IReadOnlyList<(int Line, int TextPointer)>? BasicGosubs
    {
        get
        {
            List<(int, int)> gosubs = [];
            int at = BasicStack;
            for (int count = 0; count < MaximumStackEntries && at < 0xFFFA; count++)
            {
                switch (BasicPeek((ushort)at))
                {
                    case ForToken:
                        at += ForEntrySize;
                        break;
                    case WhileToken:
                        at += WhileEntrySize;
                        break;
                    case GosubToken:
                        gosubs.Add((Word(at + 1), Word(at + 3)));
                        at += GosubEntrySize;
                        break;
                    default:
                        return gosubs;
                }
            }

            return gosubs;
        }
    }

    /// <inheritdoc/>
    public (int Code, string Message, bool Handled) BasicError()
    {
        int code = _machine.Processor.Registers.E;
        string message = s_errors.TryGetValue(code, out string? text) ? text : "Unprintable error";
        bool handled = Word(MbasicMemory.ONELIN) != 0 && BasicPeek(MbasicMemory.ONEFLG) == 0;
        return (code, message, handled);
    }

    /// <inheritdoc/>
    public void SetBasicStatement(int line, int textPointer)
    {
        BasicPoke(MbasicMemory.CURLIN, (byte)line);
        BasicPoke(MbasicMemory.CURLIN + 1, (byte)(line >> 8));
        Z80Registers registers = _machine.Processor.Registers;
        registers.HL = (ushort)textPointer;
        _machine.Processor.Registers = registers;
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   As STKINI does: the stack starts at TOPMEM with a zero word at its base, which FNDFOR stops at, and the
    ///   string temporaries are freed; direct mode is marked. The ROM is banked out, as the BIOS leaves it.
    ///  </para>
    /// </remarks>
    public void EnterBasicPrompt(BasicRom rom)
    {
        ushort stack = (ushort)(Word(MbasicMemory.TOPMEM) - 2);
        BasicPoke(stack, 0);
        BasicPoke((ushort)(stack + 1), 0);
        BasicPoke(MbasicMemory.SAVSTK, (byte)stack);
        BasicPoke(MbasicMemory.SAVSTK + 1, (byte)(stack >> 8));
        BasicPoke(MbasicMemory.TEMPPT, MbasicMemory.TEMPST & 0xFF);
        BasicPoke(MbasicMemory.TEMPPT + 1, MbasicMemory.TEMPST >> 8);
        BasicPoke(MbasicMemory.CURLIN, 0xFF);
        BasicPoke(MbasicMemory.CURLIN + 1, 0xFF);
        Z80Registers registers = _machine.Processor.Registers;
        registers.SP = stack;
        registers.PC = rom.Prompt;
        _machine.Processor.Registers = registers;
        _calls.Reset();

        // MBASIC runs with the ROM banked out; the BIOS may have left it in, partway through a console call.
        _machine.Bus.BankRomOut();
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The monitor ROM, and while MBASIC runs, MBASIC itself and CP/M from the BDOS up: what a BASIC step into
    ///   machine code steps over.
    ///  </para>
    /// </remarks>
    public bool InRom(ushort address)
    {
        if (_machine.Bus.Area(address) == KayproMemoryArea.Rom) { return true; }
        if (!MbasicActive) { return false; }
        int bdos = Word(6);
        return address is >= KayproSdkModules.MbasicOrigin and < KayproSdkModules.MbasicOrigin + KayproSdkModules.MbasicSize
            || (bdos > KayproSdkModules.MbasicOrigin + KayproSdkModules.MbasicSize && address >= bdos);
    }

    // Whether MBASIC is in memory: GONE's bytes are its own.
    private bool MbasicActive
    {
        get
        {
            if (_mbasicRom is not { } rom || _gone.Length == 0) { return false; }
            for (int index = 0; index < _gone.Length; index++)
            {
                if (_machine.Bus.PeekRam((ushort)(rom.Gone + index)) != _gone[index]) { return false; }
            }

            return true;
        }
    }

    // Adds MBASIC's source, active wherever memory holds its bytes, and its BASIC hooks.
    private void AddMbasic(DebugInfo debug, string directory)
    {
        string source = Path.Join(directory, KayproSdkModules.MbasicSource);
        if (!File.Exists(source)) { return; }
        AssemblyResult result = KayproSdkModules.AssembleMbasic(source);
        debug.Add(new SourceMapModule(result, area: null));
        // STOP, END and Control-C between statements all pass CONSTP (CNTCCN reaches ST_STOP for every key, which
        // returns for all but Control-C), and Control-C in INPUT and the loop scans enters at STPEND; the statement
        // tells which. ENDCON ends a program that runs off its last line.
        _mbasicRom = BasicRom.From(
            result.Symbols,
            "READY",
            run: "ST_RUN",
            resume: "ST_CONT",
            [("CONSTP", "STOP"), ("STPEND", "STOP"), ("ENDCON", "ENDCON")]);

        if (_mbasicRom is { } rom)
        {
            int offset = rom.Gone - KayproSdkModules.MbasicOrigin;
            _gone = result.Sections[0].Bytes.Slice(offset, GoneLength).ToArray();
        }
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   RAM, as MBASIC's variables and program are there even while the BIOS has the ROM banked in.
    ///  </para>
    /// </remarks>
    public byte BasicPeek(ushort address) => _machine.Bus.PeekRam(address);

    /// <inheritdoc/>
    public void BasicPoke(ushort address, byte value) => _machine.Bus.PokeRam(address, value);

    private int Word(int address) => BasicPeek((ushort)address) | (BasicPeek((ushort)(address + 1)) << 8);
}
