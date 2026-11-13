// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using Retrocore.Cpu.M6809;
using Retrocore.Machines.Coco;

namespace Retrocore.Debug;

// The Color Computer's BASIC, for the BASIC thread and the program document: Color BASIC, with Extended and Disk
// Extended Color BASIC's words when their ROMs are fitted.
// Every statement starts at Color BASIC's GONE2: its own loop calls it, and so do the loops Extended
// BASIC's XVEC20 and Disk BASIC 1.1's DVEC20 put in its place. There the statement's first
// character is fetched, and TINPTR holds the colon before it, or the previous line's end. The 6809 keeps
// words high byte first.
internal sealed partial class CocoDebugTarget
{
    // Color BASIC's direct page and page 1, from ColorBasicEquates.asm.
    private const ushort ArrayFlag = 0x08;
    private const ushort TempPointer = 0x0B;
    private const ushort StringFloor = 0x21;
    private const ushort ContinuePointer = 0x2D;
    private const ushort StatementPointer = 0x2F;
    private const ushort Device = 0x6F;
    private const ushort CurrentLine = 0x68;
    private const ushort TextPointer = 0xA6;
    private const ushort StringStack = 0x01A9;

    // The errors' two letters, by code / 2: Color BASIC's, then Extended BASIC's from 50 and Disk BASIC's from 54.
    private static readonly string[] s_errors =
    [
        "NF", "SN", "RG", "OD", "FC", "OV", "OM", "UL", "BS", "DD", "/0", "ID", "TM", "OS", "LS", "ST", "CN", "FD",
        "AO", "DN", "IO", "FM", "NO", "IE", "DS", "UF", "NE", "BR", "DF", "OB", "WP", "FN", "FS", "AE", "FO", "SE",
        "VF", "ER"
    ];

    private BasicRom? _basicRom;

    /// <inheritdoc/>
    public BasicDialect? Basic => _machine.Model == CocoModel.Coco3
        ? null
        : BasicDialect.ColorBasicWith(_machine.Bus.HasExtendedBasic, DiskBasicVersion);

    /// <inheritdoc/>
    public BasicRom? BasicRom => _basicRom;

    /// <inheritdoc/>
    public int BasicCurrentLine => Word(CurrentLine);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   TINPTR: the colon before the statement, or the zero that ends the line before it, past which come
    ///   the line's link and number.
    ///  </para>
    /// </remarks>
    public int BasicTextPointer
    {
        get
        {
            int pointer = Word(StatementPointer);
            return Peek((ushort)pointer) == 0 ? pointer + 4 : pointer;
        }
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Color BASIC saves no stack pointer for each statement; at GONE2 its stack is under the call's return.
    ///  </para>
    /// </remarks>
    public int BasicStack => BasicLiveStack;

    /// <inheritdoc/>
    public int BasicLiveStack => _machine.Processor.Registers.S + 2;

    /// <inheritdoc/>
    public int BasicForSize => 18;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   GOSUB pushes its token, line and place over the return to the statement loop, and RETURN returns through
    ///   that address once it pulls them, so each GOSUB takes seven bytes.
    ///  </para>
    /// </remarks>
    public int BasicGosubSize => 7;

    /// <inheritdoc/>
    public (int Code, string Message, bool Handled) BasicError()
    {
        int code = _machine.Processor.Registers.B;
        string message = code / 2 < s_errors.Length ? $"?{s_errors[code / 2]} ERROR" : $"error {code}";
        return (code, message, false);
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   At GONE2 the statement's first character is already fetched, so it is fetched again from the new
    ///   place: <c>CHARAD</c> moves past the spaces to it, A holds it, and the zero flag says whether the statement is
    ///   empty.
    ///  </para>
    /// </remarks>
    public void SetBasicStatement(int line, int textPointer)
    {
        PokeWord(CurrentLine, line);
        PokeWord(StatementPointer, textPointer);
        int at = textPointer + 1;
        while (Peek((ushort)at) == ' ') { at++; }
        PokeWord(TextPointer, at);
        M6809Registers registers = _machine.Processor.Registers;
        byte first = Peek((ushort)at);
        registers.A = first;
        byte zero = (byte)M6809ConditionCode.Zero;
        registers.CC = first == 0 ? (byte)(registers.CC | zero) : (byte)(registers.CC & ~zero);
        _machine.Processor.Registers = registers;
    }

    /// <inheritdoc/>
    public bool InRom(ushort address) => _machine.Bus.Area(address) is CocoMemoryArea.ColorBasic
        or CocoMemoryArea.ExtendedBasic
        or CocoMemoryArea.Cartridge;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   As <c>RSTSTK</c> does, the stack starts at the bottom of string space with a zero under it, which
    ///   <c>FNDFOR</c> stops at, and the string stack and CONT are cleared; then the prompt shows OK.
    ///  </para>
    /// </remarks>
    public void EnterBasicPrompt(BasicRom rom)
    {
        ushort stack = (ushort)(Word(StringFloor) - 1);
        Poke(stack, 0);
        PokeWord(TempPointer, StringStack);
        PokeWord(ContinuePointer, 0);
        Poke(ArrayFlag, 0);
        Poke(Device, 0);
        PokeWord(CurrentLine, 0xFFFF);
        M6809Registers registers = _machine.Processor.Registers;
        registers.S = stack;
        registers.PC = rom.Prompt;
        _machine.Processor.Registers = registers;
        _calls.Reset();
    }

    // Disk BASIC's version when its ROM is in the slot, else 0.
    private int DiskBasicVersion => _machine.Bus.Cartridge is null && _machine.Bus.DiskController is { } controller
        ? CocoSdkModules.DiskVersionOf(controller.Rom.Bytes) ?? 11
        : 0;

    // Where Color BASIC runs statements, stops and reports errors, from its source's symbols.
    private static BasicRom? ColorBasicRom(IReadOnlyDictionary<string, long> symbols)
    {
        string[] labels = ["GONE2", "OKPRMT", "ERROR", "RUN", "CONT", "STOP", "END", "ENDPRG"];
        if (!labels.All(symbols.ContainsKey)) { return null; }
        ushort At(string label) => (ushort)symbols[label];
        return new BasicRom(
            StatementStart: At("GONE2"),
            Gone: At("GONE2"),
            Prompt: At("OKPRMT"),
            Error: At("ERROR"),
            Run: At("RUN"),
            Continue: At("CONT"),
            Stops: new Dictionary<ushort, string>
            {
                [At("STOP")] = BasicRom.StopOrBreak,
                [At("END")] = "END",
                [At("ENDPRG")] = "PRGEND"
            });
    }

    private int Word(ushort address) => (Peek(address) << 8) | Peek((ushort)(address + 1));

    private void PokeWord(ushort address, int value)
    {
        Poke(address, (byte)(value >> 8));
        Poke((ushort)(address + 1), (byte)value);
    }
}
