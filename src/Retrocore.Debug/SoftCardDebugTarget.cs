// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Cpu.Z80;
using Retrocore.Isa;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Devices;

namespace Retrocore.Debug;

/// <summary>
///  The Z80 SoftCard's Z80 as the debugger sees it: its own thread, registers and calls, and the Apple's memory
///  through the card's address translation. Everything that is the machine's, not the CPU's, is the Apple's.
/// </summary>
/// <remarks>
///  <para>
///   The session runs this view while the Z80 has the bus. Its calls are followed from the card's instruction
///   boundaries, so an instruction the Z80 finishes after handing the bus back still counts.
///  </para>
/// </remarks>
internal sealed class SoftCardDebugTarget : IDebugTarget
{
    private static readonly DebugRegisters s_registers = new(Z80Isa.Description);

    private readonly Apple2DebugTarget _host;
    private readonly Z80CallStack _calls;
    private DebugFrame? _before;
    private int _resets;

    /// <summary>
    ///  Creates the view of a card.
    /// </summary>
    /// <param name="host">The Apple's target.</param>
    /// <param name="card">The card.</param>
    internal SoftCardDebugTarget(Apple2DebugTarget host, SoftCard card)
    {
        _host = host;
        Card = card;
        _calls = new(this);
        card.InstructionBoundary = Boundary;
        Bank = new(
            "z80",
            "The SoftCard Z80's memory",
            [SoftCardMemoryArea.Z80],
            [(0x0000, 0x10000)],
            address => card.Peek(address),
            (address, value) => PokeHost(host, card.Translate(address), value),
            Z80Isa.InstructionSet);
    }

    // Writes a byte the Z80 reaches, or reports that ROM or I/O is there, so a write can roll back or stop part way.
    private static bool PokeHost(Apple2DebugTarget host, ushort address, byte value)
    {
        try
        {
            host.Poke(address, value);
            return true;
        }
        catch (ArgumentException)
        {
            return false;
        }
    }

    /// <summary>
    ///  Gets the card.
    /// </summary>
    internal SoftCard Card { get; }

    /// <summary>
    ///  Gets the Z80's address space as a memory bank, which names it in references such as <c>z80:0x0100</c>.
    /// </summary>
    internal DebugMemoryBank Bank { get; }

    // Each Z80 instruction boundary, whichever CPU's view is running: the instruction that ended, for the calls. After
    // a reset there is no instruction that ended, only a new start.
    private void Boundary(Z80Card card)
    {
        Forget();
        DebugFrame after = Frame;
        if (_before is { } before) { _calls.Complete(before, after); }
        _before = after;
    }

    // Forgets the Z80's calls once the card has reset it, or a reset has stopped it.
    private void Forget()
    {
        if (Card.Resets == _resets) { return; }
        _resets = Card.Resets;
        _calls.Reset();
        _before = null;
    }

    /// <summary>
    ///  Starts tracking the Z80's calls afresh from where it is, as a launched program's entry, so a call its first
    ///  instruction makes is on the stack.
    /// </summary>
    internal void Begin()
    {
        Forget();
        _calls.Reset();
        _before = Frame;
    }

    /// <inheritdoc/>
    public string ThreadName => "SoftCard Z80";

    /// <inheritdoc/>
    public string Cpu => "Z80";

    /// <inheritdoc/>
    public InstructionSet InstructionSet => Z80Isa.InstructionSet;

    /// <inheritdoc/>
    public DebugRegisters Registers => s_registers;

    /// <inheritdoc/>
    public ProcessorCycle LastCycle
    {
        get
        {
            // The Z80's memory accesses reach the Apple's memory through the card, so data breakpoints watch them there.
            ProcessorCycle cycle = Card.Processor.LastCycle;
            return cycle.Operation is BusOperation.Read or BusOperation.Write
                ? cycle with { Address = Card.Translate(cycle.Address) }
                : cycle;
        }
    }

    /// <inheritdoc/>
    public DebugFrame Frame => Trs80DebugTarget.FrameOf(Card.Processor.Registers);

    /// <inheritdoc/>
    public ushort ProgramCounter
    {
        get => Card.Processor.Registers.PC;
        set
        {
            Z80Registers registers = Card.Processor.Registers;
            registers.PC = value;
            Card.Processor.Registers = registers;
        }
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   WAIT holding the Z80 at its next opcode fetch, while the 6502 has the bus, is a boundary too: nothing of
    ///   that instruction has run.
    ///  </para>
    /// </remarks>
    public bool IsInstructionBoundary => Card.Processor.IsInstructionBoundary || Card.WaitingAtInstruction;

    /// <inheritdoc/>
    public bool InInstruction => !IsInstructionBoundary;

    /// <inheritdoc/>
    public ulong CycleCount => _host.CycleCount;

    /// <inheritdoc/>
    public int ClockHertz => _host.ClockHertz;

    /// <inheritdoc/>
    public bool Accelerated => _host.Accelerated;

    /// <inheritdoc/>
    public IDebugCallStack CallStack
    {
        get
        {
            Forget();
            return _calls;
        }
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   CP/M's transient program area.
    ///  </para>
    /// </remarks>
    public int DefaultLoadAddress => 0x0100;

    /// <inheritdoc/>
    public Enum ProgramArea => SoftCardMemoryArea.Z80;

    /// <inheritdoc/>
    public string ContractModel => "SoftCard";

    /// <inheritdoc/>
    public IReadOnlyList<string> UsedRegisters { get; } = ["A", "B", "C", "D", "E", "H", "L", "IX", "IY"];

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The Apple's zero page, where CP/M passes registers to the 6502.
    ///  </para>
    /// </remarks>
    public (string Name, ushort Start, int Length) MemoryScope => ("Apple zero page", 0xF000, 256);

    /// <inheritdoc/>
    public IReadOnlyList<DebugMemoryBank> Banks => _host.Banks;

    /// <inheritdoc/>
    public IReadOnlyList<string> Screens => _host.Screens;

    /// <inheritdoc/>
    public string Screen
    {
        get => _host.Screen;
        set => _host.Screen = value;
    }

    /// <inheritdoc/>
    public byte Peek(ushort address) => Card.Peek(address);

    /// <inheritdoc/>
    public Enum ReadArea(ushort address) => SoftCardMemoryArea.Z80;

    /// <inheritdoc/>
    public int? PointsTo(IsaRegister register, long value) =>
        register.Bits >= 16 && register.Name is not ("AF" or "AF'") ? (int)(value & 0xFFFF) : null;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   One T-state, half of the Apple's cycle, so the run can stop at an instruction that starts mid-cycle.
    ///  </para>
    /// </remarks>
    public bool StepCycle()
    {
        _host.StepTState();
        return Card.Processor.FetchedOpcode;
    }

    /// <summary>
    ///  Gets whether the next <see cref="StepCycle"/> starts an Apple cycle, in which the 6502 runs if the Z80 has given
    ///  the bus back.
    /// </summary>
    internal bool StartsHostCycle => _host.StartsCycle;

    /// <summary>
    ///  Gets the 6502's cycle in the last step, when it ran one beside the Z80; null when it was held.
    /// </summary>
    internal ProcessorCycle? HostCycle => _host.Stepped ? _host.LastCycle : null;

    /// <inheritdoc/>
    public (ushort Target, int Length)? CallAt(ushort address)
    {
        byte opcode = Peek(address);
        return Z80CallStack.CallLength(opcode) switch
        {
            3 => ((ushort)(Peek((ushort)(address + 1)) | (Peek((ushort)(address + 2)) << 8)), 3),
            1 => ((ushort)(opcode & 0x38), 1),
            _ => null
        };
    }

    /// <inheritdoc/>
    public string? Trap(ushort address) => null;

    /// <inheritdoc/>
    public void Poke(ushort address, byte value) => _host.Poke(Card.Translate(address), value);

    /// <inheritdoc/>
    public void Load(int address, ReadOnlySpan<byte> bytes)
    {
        if (address < 0 || bytes.Length > 0x10000 - address)
        {
            throw new ArgumentException("Program must fit in the Z80's 64K.");
        }

        for (int index = 0; index < bytes.Length; index++)
        {
            _host.Poke(Card.Translate((ushort)(address + index)), bytes[index]);
        }
    }

    /// <inheritdoc/>
    public void AddSdkModules(DebugInfo debug, string? directory)
    {
    }

    /// <inheritdoc/>
    public bool HasBeam => _host.HasBeam;

    /// <inheritdoc/>
    public void SetBeamBreaks(IReadOnlyCollection<int> positions) => _host.SetBeamBreaks(positions);

    /// <inheritdoc/>
    public int? CycleBreak() => _host.CycleBreak();

    /// <inheritdoc/>
    public IReadOnlyList<HardwareRow> Hardware() => _host.Hardware();

    /// <inheritdoc/>
    public JsonObject DisplayState(bool running) => _host.DisplayState(running);

    /// <inheritdoc/>
    public ReadOnlySpan<byte> RenderVideo() => _host.RenderVideo();

    /// <inheritdoc/>
    public JsonObject? TakeAudio() => _host.TakeAudio();

    /// <inheritdoc/>
    public bool Key(int code) => _host.Key(code);

    /// <inheritdoc/>
    public void Reset() => _host.Reset();

    /// <inheritdoc/>
    public bool TakeResetStop() => _host.TakeResetStop();

    /// <inheritdoc/>
    public IReadOnlyDictionary<string, Func<JsonObject, JsonObject>> Requests => _host.Requests;

    /// <inheritdoc/>
    public IEnumerable<(string Event, JsonObject Body)> StatusEvents() => _host.StatusEvents();

    /// <inheritdoc/>
    public IReadOnlyList<IDevice> Devices => _host.Devices;

    /// <inheritdoc/>
    public void DeviceAction(IDevice device, string action, JsonObject args) => _host.DeviceAction(device, action, args);

    /// <inheritdoc/>
    public void HardwareAction(string id, string action, JsonObject args) => _host.HardwareAction(id, action, args);

    /// <inheritdoc/>
    public JsonObject? Cards() => _host.Cards();

    /// <inheritdoc/>
    public IEnumerable<string> RestoreCards(JsonObject cards) => _host.RestoreCards(cards);
}
