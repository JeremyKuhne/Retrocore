// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug;

// Retrocore Memory's frozen bytes: bytes held at a value while the machine runs.
internal sealed partial class DebugSession
{
    // The frozen bytes and the values they are held at, by bank name (null for memory as the CPU maps it), as the
    // Apple II builds its bank records again when a card changes. A byte of memory as the CPU maps it keeps the area
    // its write reached when frozen, such as the language card's bank 2, and is held only while writes reach it there,
    // so switching to bank 1 does not write the value into bank 1.
    private readonly Dictionary<(string? Bank, ushort Address), (byte Value, Enum? Area)> _frozen = [];

    // The CPU addresses any frozen byte has, in any bank, which a write the CPU makes there is checked against; and
    // whether the instruction running now has written one, which it then puts back as it ends.
    private readonly bool[] _frozenAt = new bool[0x10000];
    private bool _freezeWritten;

    /// <summary>
    ///  Answers retro/memory/freeze: freezes bytes at values and thaws others, then lists the frozen bytes of the
    ///  reference's space.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   <c>freeze</c> lists <c>{ offset, value }</c> and <c>thaw</c> offsets, from the reference. A frozen byte is
    ///   written at once, and again as soon as an instruction that writes it ends, so the program never reads a value
    ///   of its own there; the bytes are also written at the start of each slice the machine runs, for writes that are
    ///   not the CPU's. Only bytes a write can reach now can be frozen.
    ///  </para>
    ///  <para>
    ///   A request is all or nothing: every byte is checked before any changes, and should a write still fail, the
    ///   bytes written and the freezes made are put back.
    ///  </para>
    /// </remarks>
    private JsonObject FreezeMemory(JsonObject args)
    {
        long start = MemoryReference(Required(args, "memoryReference"), out DebugMemoryBank? bank);
        List<ushort> thaws = [];
        foreach (JsonNode? offset in args["thaw"] as JsonArray ?? [])
        {
            thaws.Add(ByteAddress(start + (offset?.GetValue<long>() ?? throw new ArgumentException("A thawed byte needs an offset."))));
        }

        List<(ushort Address, byte Value)> freezes = [];
        foreach (JsonNode? item in args["freeze"] as JsonArray ?? [])
        {
            ushort address = ByteAddress(start + (item.Long("offset") ?? throw new ArgumentException("A frozen byte needs an offset.")));
            int value = item.Int("value") ?? throw new ArgumentException("A frozen byte needs a value.");
            if (value is < 0 or > 0xFF)
            {
                throw new ArgumentException($"A byte holds 0 to 255, not {value}, so {Reference(bank, address)} cannot be frozen at it.");
            }

            if (!Writable(bank, address))
            {
                throw new ArgumentException($"{Reference(bank, address)} is not RAM now, so it cannot be frozen.");
            }

            freezes.Add((address, (byte)value));
        }

        foreach (ushort address in thaws)
        {
            _frozen.Remove((bank?.Name, address));
        }

        if (freezes.Count != 0)
        {
            Freeze(bank, freezes);
            ApplyFreezes();
            Invalidate();
            NotifyMemory();
        }

        // Watch expressions show which bytes are frozen.
        Notify("invalidated", new JsonObject { ["areas"] = new JsonArray("variables") });
        return new JsonObject
        {
            ["frozen"] = _frozen
                .Where(pair => string.Equals(pair.Key.Bank, bank?.Name, StringComparison.OrdinalIgnoreCase))
                .OrderBy(pair => pair.Key.Address)
                .Select(pair => (JsonNode?)new JsonObject
                {
                    ["address"] = pair.Key.Address,
                    ["value"] = pair.Value.Value
                })
                .ToJsonArray()
        };
    }

    // Freezes bytes, writing each at once; should a write fail, the bytes written and the freezes made go back as
    // they were.
    private void Freeze(DebugMemoryBank? bank, List<(ushort Address, byte Value)> freezes)
    {
        List<(ushort Address, byte Old, (byte, Enum?)? Frozen)> done = [];
        foreach ((ushort address, byte value) in freezes)
        {
            byte old = MemoryByte(bank, address) ?? 0;
            (byte, Enum?)? before = _frozen.TryGetValue((bank?.Name, address), out (byte, Enum?) held) ? held : null;
            if (!Write(bank, address, value))
            {
                foreach ((ushort written, byte restore, (byte, Enum?)? frozen) in Enumerable.Reverse(done))
                {
                    Write(bank, written, restore);
                    if (frozen is { } kept) { _frozen[(bank?.Name, written)] = kept; }
                    else { _frozen.Remove((bank?.Name, written)); }
                }

                throw new ArgumentException($"{Reference(bank, address)} is not RAM now, so it cannot be frozen.");
            }

            _frozen[(bank?.Name, address)] = (value, bank is null ? Target.WriteArea(address) : null);
            _frozenAt[address] = true;
            done.Add((address, old, before));
        }
    }

    // An address within the CPU's 64K.
    private static ushort ByteAddress(long address) => address is >= 0 and <= 0xFFFF
        ? (ushort)address
        : throw new ArgumentException("The bytes must be within the CPU's 64K.");

    // Whether a write can reach a byte now.
    private bool Writable(DebugMemoryBank? bank, ushort address) => bank is null
        ? Target.CanPoke(address)
        : bank.Writable(address);

    // Writes a byte, reporting whether the write reached it.
    private bool Write(DebugMemoryBank? bank, ushort address, byte value)
    {
        if (bank is not null) { return bank.Poke?.Invoke(address, value) ?? false; }
        Target.Poke(address, value);
        return true;
    }

    // The bank a frozen byte's bank name names now; null for memory as the CPU maps it, or for a bank that is gone,
    // such as a slot's ROM after its card comes out.
    private DebugMemoryBank? FrozenBank(string? name, out bool gone)
    {
        gone = false;
        if (name is null) { return null; }
        DebugMemoryBank? bank = Target.Banks.FirstOrDefault(item => string.Equals(item.Name, name, StringComparison.OrdinalIgnoreCase));
        gone = bank is null;
        return bank;
    }

    // Whether a freeze holds now: a byte of the CPU's memory waits while another area is mapped where it was frozen.
    private bool Holds(Enum? area, ushort address) => area is null || Equals(Target.WriteArea(address), area);

    // Writes the frozen bytes back where the program changed them; one whose memory is mapped away waits, and one
    // whose bank is gone is thawed.
    private void ApplyFreezes()
    {
        List<(string? Bank, ushort Address)>? gone = null;
        foreach (((string? name, ushort address), (byte value, Enum? area)) in _frozen)
        {
            DebugMemoryBank? bank = FrozenBank(name, out bool missing);
            if (missing)
            {
                (gone ??= []).Add((name, address));
                continue;
            }

            if (!Holds(area, address)) { continue; }
            if (MemoryByte(bank, address) == value || !Writable(bank, address)) { continue; }
            Write(bank, address, value);
        }

        foreach ((string? Bank, ushort Address) key in gone ?? [])
        {
            _frozen.Remove(key);
        }

        // The addresses checked are the frozen bytes' now, as bytes thawed since go.
        Array.Clear(_frozenAt);
        foreach ((string? _, ushort address) in _frozen.Keys)
        {
            _frozenAt[address] = true;
        }
    }

    // Notes a write the CPU's last bus cycle made to a frozen byte's address, in any bank, and puts the frozen bytes back
    // once its instruction ends: a write to another bank's byte at the address changes nothing they hold, so it writes
    // nothing.
    private void FreezeCycle(IDebugTarget cpu)
    {
        ProcessorCycle cycle = cpu.LastCycle;
        if (cycle.Operation == BusOperation.Write && !cycle.IsStalled && _frozenAt[cycle.Address])
        {
            _freezeWritten = true;
        }

        if (!_freezeWritten || !cpu.IsInstructionBoundary) { return; }
        _freezeWritten = false;
        ApplyFreezes();
    }

    // Whether an expression reads a frozen byte, as [$4100], [aux:$0400] or [$4100].w do, so a watch expression can
    // say so. The address inside the brackets is read as the expression evaluator reads it, in the frame's CPU, so
    // [16] is $0010, and a word's second byte wraps from $FFFF to $0000 as the evaluator's does.
    private bool FrozenIn(string expression, int frameId)
    {
        if (_frozen.Count == 0 || MemoryExpression().Match(expression.Trim()) is not { Success: true } read)
        {
            return false;
        }

        try
        {
            ExpressionEvaluator evaluator = new(FrameTarget(frameId), _debug, read.Groups[1].Value, FrameRegisters(frameId));
            long address = evaluator.EvaluateReference(out DebugMemoryBank? bank, out bool cpu);
            if (!cpu) { bank ??= ThreadBank(FrameIndex(frameId).Thread); }
            if (address is < 0 or > 0xFFFF) { return false; }
            int length = read.Groups[2].Success ? 2 : 1;
            for (int index = 0; index < length; index++)
            {
                ushort at = (ushort)(address + index);
                if (_frozen.TryGetValue((bank?.Name, at), out (byte Value, Enum? Area) frozen) && Holds(frozen.Area, at))
                {
                    return true;
                }
            }
        }
        catch (Exception exception) when (IsEvaluationError(exception))
        {
            // The expression evaluated already; an address it cannot resolve again is not frozen.
        }

        return false;
    }
}
