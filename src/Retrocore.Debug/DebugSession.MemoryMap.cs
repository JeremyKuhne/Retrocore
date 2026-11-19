// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug;

// retro/memory/map: the bar across Retrocore Memory's top, the whole space by region and by what is mapped now.
internal sealed partial class DebugSession
{
    /// <summary>
    ///  Answers retro/memory/map: a memory view's space as the machine's regions and as what memory reads now.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   For a <c>memoryReference</c>: the machine's <c>regions</c>, each with its <c>start</c>, <c>length</c>,
    ///   <c>name</c> and <c>kind</c>, as <c>retro/memory/inspect</c> gives them; and the <c>areas</c>, the runs of
    ///   addresses that read the same part of the machine now, to the byte, each with its <c>start</c>,
    ///   <c>length</c>, <c>name</c>, such as <c>main RAM</c>, its <c>kind</c> (<c>ram</c>, <c>rom</c>, <c>io</c>,
    ///   <c>video</c> or <c>none</c>) and whether it is <c>mapped</c>: in the CPU's view always; in a bank's, whether
    ///   the CPU reads the bank there now, and whether it is <c>written</c>, as the CPU can write a bank it does not
    ///   read, such as the IIe's auxiliary RAM with RAMWRT on. A bank's runs split at its parts, the pieces one switch
    ///   puts in the CPU's view, such as the IIe's alternate zero page and stack, which name them. A bank's gaps are
    ///   <c>none</c>. A coprocessor's view, whose addresses are its own, has neither.
    ///  </para>
    /// </remarks>
    private JsonObject MemoryMap(JsonObject args)
    {
        MemoryReference(Required(args, "memoryReference"), out DebugMemoryBank? bank);
        JsonArray regions = [];
        JsonArray areas = [];
        if (bank?.InstructionSet is not null) { return new JsonObject { ["regions"] = regions, ["areas"] = areas }; }

        foreach (DebugRegion region in Target.Regions)
        {
            regions.Add((JsonNode)new JsonObject
            {
                ["start"] = region.Start,
                ["length"] = region.Length,
                ["name"] = region.Name,
                ["kind"] = region.Kind
            });
        }

        (string Name, string Kind, bool Mapped, bool Written)? run = null;
        int start = 0;
        // Every byte, as some areas are a byte or two, such as the Model III's printer registers at $37E8.
        for (int address = 0; address <= 0x10000; address++)
        {
            (string Name, string Kind, bool Mapped, bool Written)? here = address == 0x10000 ? null : MapArea(bank, (ushort)address);
            if (here == run && address != 0x10000) { continue; }
            if (run is { } previous)
            {
                areas.Add((JsonNode)new JsonObject
                {
                    ["start"] = start,
                    ["length"] = address - start,
                    ["name"] = previous.Name,
                    ["kind"] = previous.Kind,
                    ["mapped"] = previous.Mapped,
                    ["written"] = previous.Written
                });
            }

            run = here;
            start = address;
        }

        return new JsonObject { ["regions"] = regions, ["areas"] = areas };
    }

    // What an address reads now: in the CPU's view, the area there; in a bank's, the bank's part there, and whether
    // the CPU reads and writes it there, or none where the bank has no byte.
    private (string Name, string Kind, bool Mapped, bool Written) MapArea(DebugMemoryBank? bank, ushort address)
    {
        Enum read = Target.ReadArea(address);
        if (bank is null) { return (AreaName(read), Target.KindAt(address) ?? AreaKind(read), true, true); }
        if (bank.AreaOf(address) is not { } area) { return ($"{bank.Label} has no byte here", "none", false, false); }
        bool reads = bank.ReadBy(Target, address), writes = bank.WrittenBy(Target, address);
        string part = bank.PartAt?.Invoke(address) ?? bank.Label;
        string access = (reads, writes) switch
        {
            (true, true) => "the CPU reads and writes it here now",
            (true, false) => $"the CPU reads it here now, and writes {AreaName(Target.WriteArea(address))}",
            (false, true) => $"the CPU writes it here now, and reads {AreaName(read)}",
            _ => $"the CPU reads {AreaName(read)} here now"
        };

        return ($"{part}: {access}", AreaKind(area), reads, writes);
    }

    // What an area holds, from the names the machines give their areas.
    private static string AreaKind(Enum area) => area.ToString() switch
    {
        "None" or "Unmapped" => "none",
        "Video" => "video",
        "Io" or "Pia" or "Vias" or "Keyboard" or "Printer" or "ExpansionInterface" or "CassetteInterface" => "io",
        "Monitor" or "ExtendedBasic" or "ColorBasic" or "Cartridge" => "rom",
        string name when name.EndsWith("Rom", StringComparison.Ordinal) => "rom",
        _ => "ram"
    };
}
