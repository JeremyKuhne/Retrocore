// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug;

// retro/memory/map: the bar across Retrocore Memory's top, the whole space by region and by what is mapped now.
internal sealed partial class DebugSession
{
    // The map's grain: the TRS-80's smallest areas, such as the expansion interface's at $37E0, are 32 bytes.
    private const int MapStep = 16;

    /// <summary>
    ///  Answers retro/memory/map: a memory view's space as the machine's regions and as what memory reads now.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   For a <c>memoryReference</c>: the machine's <c>regions</c>, each with its <c>start</c>, <c>length</c>,
    ///   <c>name</c> and <c>kind</c>, as <c>retro/memory/inspect</c> gives them; and the <c>areas</c>, the runs of
    ///   addresses that read the same part of the machine now, in 16-byte steps, each with its <c>start</c>,
    ///   <c>length</c>, <c>name</c>, such as <c>main RAM</c>, its <c>kind</c> (<c>ram</c>, <c>rom</c>, <c>io</c>,
    ///   <c>video</c> or <c>none</c>) and whether it is <c>mapped</c>: in the CPU's view always; in a bank's, whether
    ///   the CPU reads the bank there now. A bank's gaps are <c>none</c>. A coprocessor's view, whose addresses are its
    ///   own, has neither.
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

        (string Name, string Kind, bool Mapped)? run = null;
        int start = 0;
        for (int address = 0; address <= 0x10000; address += MapStep)
        {
            (string Name, string Kind, bool Mapped)? here = address == 0x10000 ? null : MapArea(bank, (ushort)address);
            if (here == run && address != 0x10000) { continue; }
            if (run is { } previous)
            {
                areas.Add((JsonNode)new JsonObject
                {
                    ["start"] = start,
                    ["length"] = address - start,
                    ["name"] = previous.Name,
                    ["kind"] = previous.Kind,
                    ["mapped"] = previous.Mapped
                });
            }

            run = here;
            start = address;
        }

        return new JsonObject { ["regions"] = regions, ["areas"] = areas };
    }

    // What an address reads now: in the CPU's view, the area there; in a bank's, the bank, and whether the CPU reads
    // it there, or none where the bank has no byte.
    private (string Name, string Kind, bool Mapped) MapArea(DebugMemoryBank? bank, ushort address)
    {
        Enum read = Target.ReadArea(address);
        if (bank is null) { return (AreaName(read), AreaKind(read), true); }
        if (bank.AreaOf(address) is not { } area) { return ($"{bank.Label} has no byte here", "none", false); }
        bool mapped = bank.Areas.Contains(read);
        return (mapped ? $"{bank.Label}, which the CPU reads here now" : $"{bank.Label}; the CPU reads {AreaName(read)} here", AreaKind(area), mapped);
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
