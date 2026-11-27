// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu.I8080;
using Retrocore.Isa;
using Retrocore.Machines.Devices;
using Retrocore.Basic;
using Retrocore.Machines.Trs80Model100;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

/// <summary>
///  A TRS-80 Model 100 or Tandy 102 under the debugger: the 80C85, its ROM and RAM, the LCD and the keyboard.
/// </summary>
/// <remarks>
///  <para>
///   The ROM is the user's (see <see cref="Launch"/>). The call stack follows <c>CALL</c>, <c>RST</c> and the 8085's
///   TRAP and RST 5.5, 6.5 and 7.5, which push the program counter with no opcode fetch. The LCD's text is the ROM's
///   copy of the screen at <c>$FE00</c>, so a program that draws on the LCD itself shows only as pixels.
///  </para>
///  <para>
///   Keys are ASCII, with 8, 9 and 13 as DEL, TAB and ENTER and the other control codes from 1 to 26 as CTRL and a
///   letter, and these codes for the Model 100's own keys: 28 to 31 the arrows, right, left, up and down (the codes
///   its ROM gives them); 128 to 135 F1 to F8; 136 LABEL; 137 PRINT; 138 PASTE; 139 PAUSE, the PAUSE/BREAK key; 140
///   BREAK, the same key with SHIFT.
///  </para>
/// </remarks>
internal sealed partial class Trs80Model100DebugTarget : IDebugTarget, IRecordingTarget
{
    /// <summary>
    ///  The LCD's own colors, the only screen it has.
    /// </summary>
    internal const string LcdScreen = "lcd";

    private static readonly DebugRegisters s_registers = new(I8080Isa.Description);
    private static readonly string[] s_screens = [LcdScreen];

    private readonly Trs80Model100Machine _machine;
    private readonly I8080CallStack _calls;
    private readonly byte[] _pixels = new byte[Trs80Model100Lcd.Width * Trs80Model100Lcd.Height * 4];
    private DebugFrame _beforeInstruction;
    private bool _instruction;
    private bool _fetched;
    private bool _acknowledged;
    private bool _resetPending;
    private string? _ramImagePath;

    // The emulated seconds the ROM takes to reach its menu after the power comes on.
    private const double BootSeconds = 3;

    /// <summary>
    ///  Wraps a machine.
    /// </summary>
    /// <param name="machine">The machine.</param>
    internal Trs80Model100DebugTarget(Trs80Model100Machine machine)
    {
        _machine = machine;
        _calls = new(this, is8085: true);
        Requests = new Dictionary<string, Func<JsonObject, JsonObject>>
        {
            ["retro/video"] = _ => VideoFrame()
        };
    }

    /// <summary>
    ///  Gets the machine.
    /// </summary>
    internal Trs80Model100Machine Machine => _machine;

    private string ModelName => _machine.Variant == Trs80Model100Variant.Tandy102 ? "Tandy 102" : "TRS-80 Model 100";

    /// <inheritdoc/>
    public string ThreadName => $"{ModelName} 80C85";

    /// <inheritdoc/>
    public string Cpu => I8080Isa.Name8085;

    /// <inheritdoc/>
    public InstructionSet InstructionSet => I8080Isa.InstructionSet8085;

    /// <inheritdoc/>
    public bool HasPorts => true;

    /// <inheritdoc/>
    public DebugRegisters Registers => s_registers;

    /// <inheritdoc/>
    public ProcessorCycle LastCycle => _machine.LastCycle;

    /// <inheritdoc/>
    public DebugFrame Frame => AltairDebugTarget.FrameOf(_machine.Processor.Registers);

    /// <inheritdoc/>
    public ushort ProgramCounter
    {
        get => _machine.Processor.Registers.PC;
        set
        {
            I8080Registers registers = _machine.Processor.Registers;
            registers.PC = value;
            _machine.Processor.Registers = registers;
        }
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   A halted 8085, as the ROM halts waiting for a key, is between instructions in each idle state, with PC past
    ///   its HLT; it is not at a boundary for the debugger until an interrupt or reset sends it on, nor while the
    ///   power is off, as the Altair's 8080 is not.
    ///  </para>
    /// </remarks>
    public bool IsInstructionBoundary => _machine.Processor.IsInstructionBoundary && !IsIdle;

    /// <inheritdoc/>
    public bool InInstruction => _instruction;

    /// <inheritdoc/>
    /// <remarks>Halted, the CPU waits for an interrupt; turned off, for the power switch.</remarks>
    public bool IsIdle => _machine.IsPoweredOff || _machine.Processor.IsHalted;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The 8085's TRAP and RST 5.5 to 7.5 as well as INTR's acknowledge: RST 7.5 comes every 3.9 ms, so an
    ///   instruction it lands on is met once, when it runs after the handler returns.
    ///  </para>
    /// </remarks>
    public bool IsTakingInterrupt => _machine.Processor.IsTakingInterrupt;

    /// <inheritdoc/>
    public ulong CycleCount => _machine.Processor.CycleCount;

    /// <inheritdoc/>
    public int ClockHertz => Trs80Model100Timing.ClockHertz;

    /// <inheritdoc/>
    public bool Accelerated => false;

    /// <inheritdoc/>
    public IDebugCallStack CallStack => _calls;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   $E000 is RAM at every size, and below the ROM's variables at $F5F0; a program there owns the machine, as
    ///   BASIC's files and text may lie there in a small one.
    ///  </para>
    /// </remarks>
    public int DefaultLoadAddress => 0xE000;

    /// <inheritdoc/>
    public Enum ProgramArea => Trs80Model100MemoryArea.Ram;

    /// <inheritdoc/>
    public string ContractModel => "Model100";

    /// <inheritdoc/>
    public IReadOnlyList<string> UsedRegisters { get; } = ["A", "B", "C", "D", "E", "H", "L"];

    /// <inheritdoc/>
    /// <remarks>The ROM's variables and hooks, from <c>$F5F0</c>.</remarks>
    public (string Name, ushort Start, int Length) MemoryScope => ("System RAM", 0xF5F0, 256);

    /// <inheritdoc/>
    public int MaximumKey => 140;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The program is the one BASIC has open, a <c>.BA</c> file or BASIC's unsaved program; writing it moves the
    ///   files after it in RAM. Stepping by BASIC's lines waits for the ROM as an SDK source.
    ///  </para>
    /// </remarks>
    public BasicDialect? Basic => BasicDialect.Model100;

    /// <inheritdoc/>
    public string? BasicAwayMessage =>
        "BASIC is not at its prompt: choose BASIC on the menu, and stop any program it is running, then try again.";

    /// <inheritdoc/>
    public IReadOnlyDictionary<string, Func<JsonObject, JsonObject>> Requests { get; }

    /// <inheritdoc/>
    public IReadOnlyList<IDevice> Devices => _machine.Devices;

    /// <inheritdoc/>
    public IReadOnlyList<string> Screens => s_screens;

    /// <inheritdoc/>
    public string Screen
    {
        get => LcdScreen;
        set => DebugScreens.Require(value, s_screens);
    }

    /// <inheritdoc/>
    public byte Peek(ushort address) => _machine.Bus.Peek(address);

    /// <inheritdoc/>
    public Enum ReadArea(ushort address) => _machine.Bus.Area(address);

    /// <inheritdoc/>
    public int? PointsTo(IsaRegister register, long value) =>
        register.Bits >= 16 && register.Name != "PSW" ? (int)(value & 0xFFFF) : null;

    /// <inheritdoc/>
    public bool StepCycle()
    {
        if (_machine.Processor.IsInstructionBoundary && !_instruction)
        {
            _beforeInstruction = Frame;
            _instruction = true;
            _fetched = false;
            _acknowledged = false;
        }

        _machine.StepCycle();
        _fetched |= _machine.Processor.FetchedOpcode;
        _acknowledged |= _machine.LastCycle.Operation == BusOperation.InterruptAcknowledge;
        if (_machine.Processor.IsInstructionBoundary && _instruction)
        {
            _instruction = false;

            // An INTR's acknowledge fetches the device's opcode; TRAP and RST 5.5-7.5 fetch nothing, but push the
            // program counter, which the call stack checks. A halted CPU's idle states do neither.
            DebugFrame after = Frame;
            if (_fetched)
            {
                _calls.Complete(_beforeInstruction, after, _acknowledged);
            }
            else if (after.StackPointer != _beforeInstruction.StackPointer)
            {
                _calls.Complete(_beforeInstruction, after, interrupt: true);
            }
        }

        return _machine.Processor.FetchedOpcode;
    }

    /// <inheritdoc/>
    public void RunCycles(int cycles)
    {
        for (int count = 0; count < cycles; count++) { _machine.StepCycle(); }
        _calls.Reset();
        _instruction = false;
    }

    /// <inheritdoc/>
    public (ushort Target, int Length)? CallAt(ushort address)
    {
        byte opcode = Peek(address);
        return I8080CallStack.CallLength(opcode, is8085: true) switch
        {
            3 => ((ushort)(Peek((ushort)(address + 1)) | (Peek((ushort)(address + 2)) << 8)), 3),
            1 => ((ushort)(opcode == 0xCB ? 0x0040 : opcode & 0x38), 1),
            _ => null
        };
    }

    /// <inheritdoc/>
    public string? Trap(ushort address) => null;

    /// <inheritdoc/>
    public void Poke(ushort address, byte value)
    {
        if (!CanPoke(address))
        {
            throw new ArgumentException($"${address:X4} is not RAM.");
        }

        _machine.Bus.Write(address, value);
    }

    /// <inheritdoc/>
    public bool CanPoke(ushort address) => _machine.Bus.Area(address) == Trs80Model100MemoryArea.Ram;

    /// <inheritdoc/>
    public void Load(int address, ReadOnlySpan<byte> bytes)
    {
        for (int index = 0; index < bytes.Length; index++)
        {
            if (address + index > 0xFFFF || _machine.Bus.Area((ushort)(address + index)) != Trs80Model100MemoryArea.Ram)
            {
                throw new ArgumentException($"Program must fit in RAM; ${address + index:X4} is not RAM.");
            }
        }

        for (int index = 0; index < bytes.Length; index++)
        {
            _machine.Bus.Write((ushort)(address + index), bytes[index]);
        }
    }

    /// <inheritdoc/>
    /// <remarks>The ROM is not an SDK source yet, so there is nothing to add.</remarks>
    public void AddSdkModules(DebugInfo debug, string? directory)
    {
    }

    /// <inheritdoc/>
    public bool InRom(ushort address) => _machine.Bus.Area(address) is Trs80Model100MemoryArea.Rom or Trs80Model100MemoryArea.OptionRom;

    /// <inheritdoc/>
    public bool Key(int code) => code is >= 0 and <= 140 && _machine.Keyboard.Type((byte)code);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The RESET button, which is the power switch's restart: the CPU starts at $0000 with the devices reset, and the
    ///   ROM finds RAM still valid. It turns a machine that software turned off back on.
    ///  </para>
    /// </remarks>
    public void Reset()
    {
        _machine.PowerOn();
        _calls.Reset();
        _instruction = false;
        _resetPending = true;
    }

    /// <inheritdoc/>
    public bool TakeResetStop()
    {
        if (!_resetPending || !IsInstructionBoundary || _machine.Processor.Registers.PC != 0)
        {
            return false;
        }

        _resetPending = false;
        return true;
    }

    /// <inheritdoc/>
    public IEnumerable<(string Event, JsonObject Body)> StatusEvents() => [];

    /// <summary>
    ///  Gets the file the RAM is kept in between sessions, or null when the launch named none.
    /// </summary>
    internal string? RamImagePath => _ramImagePath;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Writes the RAM to the launch's <c>ramImage</c>, as the battery keeps it when the machine is switched off: to a
    ///   file beside it first, then over it, so a save that fails leaves the image as it was, and the save can be
    ///   tried again. The CPU's state is not kept, as it is not when the power goes, so the next session starts with
    ///   the power coming on.
    ///  </para>
    /// </remarks>
    public void SaveRecordings()
    {
        if (_ramImagePath is not { } path) { return; }
        string temporary = $"{path}.{Environment.ProcessId}.tmp";
        try
        {
            File.WriteAllBytes(temporary, _machine.SaveRam());
            File.Move(temporary, path, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporary)) { File.Delete(temporary); }
        }
    }

    /// <inheritdoc/>
    public void DeviceAction(IDevice device, string action, JsonObject args) =>
        throw new ArgumentException($"{device.Info.Name} does not support {action}.");

    /// <inheritdoc/>
    public JsonObject DisplayState(bool running) => new()
    {
        ["machine"] = DebugMachines.Trs80Model100,
        ["model"] = ModelName,
        ["columns"] = 40,
        ["rows"] = _machine.ScreenText().Select(line => line.PadRight(40)).ToJsonArray(),
        ["cycles"] = CycleCount,
        ["poweredOff"] = _machine.IsPoweredOff,
        ["video"] = VideoState(),
        ["screen"] = LcdScreen,
        ["screens"] = Screens.ToJsonArray(),
        ["running"] = running
    };

    /// <inheritdoc/>
    public ReadOnlySpan<byte> RenderVideo()
    {
        _machine.Lcd.Render(_pixels, scanned: true);
        return _pixels;
    }

    /// <inheritdoc/>
    public IReadOnlyList<HardwareRow> Hardware()
    {
        Trs80Model100Bus bus = _machine.Bus;
        return
        [
            new(
                "model",
                ModelName,
                "OKI 80C85 at 2.4576 MHz",
                "The launch's model option: 100 or 102; with none, a known ROM tells its model by its digest, and any other is a Model 100."),
            new(
                "rom",
                "ROM",
                Trs80Model100Roms.Identify(_machine.Roms.Main) is { } known
                    ? $"32 KB, {(known == Trs80Model100Variant.Tandy102 ? "the US Tandy 102's" : "the US Model 100's")}"
                    : "32 KB, not a dump known here",
                "BASIC, TEXT, TELCOM, ADDRSS and SCHEDL; the user's, from rom or romDirectory."),
            new(
                "optionRom",
                "Option ROM",
                _machine.Roms.Option is { } option ? $"{option.Length / 1024.0:0.#} KB{(bus.OptionRomSelected ? ", selected" : "")}" : "none",
                "The launch's optionRom option; port $E0 bit 0 puts it over $0000-$7FFF."),
            new(
                "memory",
                "Memory",
                $"{_machine.Configuration.RamKilobytes} KB at ${bus.RamStart:X4}-$FFFF",
                "The launch's ramKilobytes option: 8, 16, 24 or 32."),
            new("lcd", "LCD", "240x64, ten HD44102 drivers", "40 characters by 8 lines."),
            new(
                "clock",
                "Clock",
                $"uPD1990AC, TP at {bus.Clock.TimingPulseHertz} Hz on RST 7.5",
                "The launch's time option sets it; the host's time by default."),
            new(
                "power",
                "Power",
                _machine.IsPoweredOff ? "off" : "on",
                "Software turns it off with port $BA bit 4; Reset turns it back on."),
            new(
                "ramImage",
                "RAM image",
                _ramImagePath ?? "none",
                "The launch's ramImage option: the file that keeps the RAM between sessions, saved as the session ends."),
            new(
                "files",
                "Files",
                Files(),
                "The files in RAM's directory, without the ROM's own programs and its hidden entries; the launch's files option puts host files in it."),
            new("io", "Serial, modem, cassette, printer, wand", "not connected", "Coming in later phases.")
        ];
    }

    // The files in RAM's directory; before the ROM has set it up, whatever its bytes say.
    private string Files()
    {
        IReadOnlyList<Model100File> files = new Model100Files(new TargetBasicMemory(this)).List();
        return files.Count == 0 ? "none" : string.Join(", ", files.Select(file => file.Name));
    }

    private JsonObject VideoState() => new()
    {
        ["width"] = Trs80Model100Lcd.Width,
        ["height"] = Trs80Model100Lcd.Height,
        ["pixelFormat"] = "rgba",
        ["cycles"] = CycleCount
    };

    private JsonObject VideoFrame()
    {
        _machine.Lcd.Render(_pixels, scanned: true);
        JsonObject frame = VideoState();
        frame["pixels"] = Convert.ToBase64String(_pixels);
        return frame;
    }
}
