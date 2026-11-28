// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using Touki.Io;

namespace Retrocore.Debug.Project;

/// <summary>
///  The memory a target's program may use: where it loads, its free RAM, the zero-page bytes it may use, and the
///  areas the machine and its environment keep, each with the reason.
/// </summary>
/// <remarks>
///  <para>
///   The SDK ships a map for each machine and environment, with RAM size variants:
///   <c>Sdk/1/environments/&lt;environment&gt;/&lt;name&gt;.map.json</c>, where the name is the first of
///   <c>&lt;catalog id&gt;-&lt;RAM&gt;k</c>, <c>&lt;catalog id&gt;</c>, <c>&lt;family&gt;-&lt;RAM&gt;k</c> and
///   <c>&lt;family&gt;</c> that exists, the RAM being the target's <c>RC_RAM_KB</c>. A machine with no map at all
///   builds as before, at its launch's load address with no checks; one whose family has maps but none for its RAM is
///   an error.
///  </para>
///  <para>
///   Every address from <c>$0100</c> up is in a free area or a reserved one, never both; the zero page is given as
///   the bytes a program may use, and the rest of it is the machine's. A map for a CPU with no zero page, such as the
///   Z80's or the 6809's, leaves <c>zeroPage</c> out and gives every address from <c>$0000</c> as free or reserved. A target's <c>memoryMap</c> changes its map
///   (<see cref="With"/>): its <c>free</c> areas leave the reserved areas they overlap, its <c>reserved</c> areas
///   leave free RAM, and its <c>load</c> and <c>zeroPage</c> replace the map's.
///  </para>
/// </remarks>
internal sealed class MemoryMap
{
    /// <summary>
    ///  The fields a map file gives.
    /// </summary>
    internal static readonly string[] Fields = ["description", "load", "free", "zeroPage", "reserved"];

    /// <summary>
    ///  The fields a target's <c>memoryMap</c> can give.
    /// </summary>
    internal static readonly string[] OverrideFields = ["load", "free", "zeroPage", "reserved"];

    /// <summary>
    ///  The fields a memory area gives.
    /// </summary>
    internal static readonly string[] AreaFields = ["start", "end", "why"];

    private const string Extension = ".map.json";

    private MemoryMap(string file, string description, int load, List<MemoryArea> free, List<MemoryArea> zeroPage, List<MemoryArea> reserved)
    {
        File = file;
        Description = description;
        Load = load;
        Free = free;
        ZeroPage = zeroPage;
        Reserved = reserved;
    }

    /// <summary>
    ///  Gets the map file's full path.
    /// </summary>
    internal string File { get; }

    /// <summary>
    ///  Gets what the map describes.
    /// </summary>
    internal string Description { get; }

    /// <summary>
    ///  Gets where a program loads, in free RAM.
    /// </summary>
    internal int Load { get; }

    /// <summary>
    ///  Gets the free RAM, in address order.
    /// </summary>
    internal IReadOnlyList<MemoryArea> Free { get; }

    /// <summary>
    ///  Gets the zero-page bytes a program may use, in address order.
    /// </summary>
    internal IReadOnlyList<MemoryArea> ZeroPage { get; }

    /// <summary>
    ///  Gets the areas the machine keeps, in address order, each with its reason.
    /// </summary>
    internal IReadOnlyList<MemoryArea> Reserved { get; }

    /// <summary>
    ///  Gets the free area a program loads into: the one holding <see cref="Load"/>.
    /// </summary>
    internal MemoryArea LoadArea => Free.First(area => area.Contains(Load));

    /// <summary>
    ///  Finds the SDK's map for a target's machine, environment and RAM.
    /// </summary>
    /// <param name="target">The target.</param>
    /// <param name="sdk">The SDK's root, <c>Sdk/</c>.</param>
    /// <returns>The map, or null when the SDK has none for the machine's family in the environment.</returns>
    /// <exception cref="ProjectException">
    ///  The family has maps but none for the target's RAM, or the map is malformed.
    /// </exception>
    internal static MemoryMap? Find(ProjectTarget target, string sdk)
    {
        string folder = Path.Join(sdk, target.Project.Sdk, "environments", target.Environment);
        int kilobytes = TargetDefines.RamKilobytes(target);
        string[] names =
        [
            $"{target.Machine.Id}-{kilobytes}k", target.Machine.Id, $"{target.Machine.Family}-{kilobytes}k", target.Machine.Family
        ];

        foreach (string name in names)
        {
            string file = Path.Join(folder, name + Extension);
            if (System.IO.File.Exists(file)) { return Read(file); }
        }

        if (Directory.Exists(folder)
            && Directory.EnumerateFiles(folder, $"{target.Machine.Family}-*{Extension}").Any())
        {
            throw new ProjectException(
                $"{target.Project.File}: target {target.Name}: the SDK has no memory map for {target.Machine.Id} with {kilobytes}K in the '{target.Environment}' environment.");
        }

        return null;
    }

    /// <summary>
    ///  Reads a map file.
    /// </summary>
    /// <param name="file">The file's full path.</param>
    /// <returns>The map.</returns>
    /// <exception cref="ProjectException">The file cannot be read, or is malformed.</exception>
    internal static MemoryMap Read(string file)
    {
        JsonObject json;
        try
        {
            json = JsonNode.Parse(System.IO.File.ReadAllText(file)) as JsonObject
                ?? throw new ProjectException($"{file}: a memory map is a JSON object.");
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException)
        {
            throw new ProjectException($"{file}: the memory map cannot be read: {exception.Message}");
        }

        Check(file, "the memory map", json, Fields);
        string description = Text(json["description"]) ?? "";
        int load = json["load"] is { } loadNode
            ? Address(file, "'load'", loadNode)
            : throw new ProjectException($"{file}: the memory map must give 'load'.");

        List<MemoryArea> free = Areas(file, "'free'", json["free"], why: false);
        List<MemoryArea> zeroPage = ZeroPageAreas(file, "'zeroPage'", json["zeroPage"]);
        List<MemoryArea> reserved = Areas(file, "'reserved'", json["reserved"], why: true);
        MemoryMap map = new(file, description, load, Sorted(Merged(free)), Sorted(zeroPage), Sorted(reserved));
        map.Validate(file);
        return map;
    }

    /// <summary>
    ///  Checks a target's <c>memoryMap</c> as the project file gives it, before any map is found for it.
    /// </summary>
    /// <param name="file">The project file.</param>
    /// <param name="where">The target, as messages name it.</param>
    /// <param name="node">The <c>memoryMap</c>.</param>
    /// <returns>The override, a copy.</returns>
    /// <exception cref="ProjectException">It is malformed.</exception>
    internal static JsonObject ReadOverride(string file, string where, JsonNode node)
    {
        if (node is not JsonObject json)
        {
            throw new ProjectException($"{file}: {where}'s 'memoryMap' must be an object of load, free, zeroPage and reserved.");
        }

        string what = $"{where}'s 'memoryMap'";
        Check(file, what, json, OverrideFields);
        if (json["load"] is { } load) { _ = Address(file, $"{what} 'load'", load); }
        _ = Areas(file, $"{what} 'free'", json["free"], why: false);
        _ = ZeroPageAreas(file, $"{what} 'zeroPage'", json["zeroPage"]);
        _ = Areas(file, $"{what} 'reserved'", json["reserved"], why: true);
        return (JsonObject)json.DeepClone();
    }

    /// <summary>
    ///  Applies a target's <c>memoryMap</c> to the map.
    /// </summary>
    /// <param name="target">The target, whose <see cref="ProjectTarget.MemoryMapOverride"/> it applies.</param>
    /// <returns>The map as the target has it.</returns>
    /// <exception cref="ProjectException">The result is not a map: its load address is not in free RAM.</exception>
    internal MemoryMap With(ProjectTarget target)
    {
        if (target.MemoryMapOverride is not { } json) { return this; }
        string file = target.Project.File;
        string what = $"target {target.Name}'s 'memoryMap'";
        List<MemoryArea> free = [.. Free];
        List<MemoryArea> reserved = [.. Reserved];
        foreach (MemoryArea area in Areas(file, $"{what} 'free'", json["free"], why: false))
        {
            reserved = Without(reserved, area);
            free = Without(free, area);
            free.Add(area);
        }

        foreach (MemoryArea area in Areas(file, $"{what} 'reserved'", json["reserved"], why: true))
        {
            free = Without(free, area);
            reserved = Without(reserved, area);
            reserved.Add(area);
        }

        List<MemoryArea> zeroPage = json["zeroPage"] is { } zero ? ZeroPageAreas(file, $"{what} 'zeroPage'", zero) : [.. ZeroPage];
        int load = json["load"] is { } loadNode ? Address(file, $"{what} 'load'", loadNode) : Load;
        MemoryMap map = new(File, Description, load, Sorted(Merged(free)), Sorted(zeroPage), Sorted(reserved));
        if (!map.Free.Any(area => area.Contains(load)))
        {
            throw new ProjectException(
                $"{file}: target {target.Name}: its program loads at ${load:X4}, which its memory map does not give as free RAM.");
        }

        map.Validate($"{file}: {what}");
        return map;
    }

    /// <summary>
    ///  Gets the linker configuration the build uses when a target gives none: <c>STARTUP</c>, <c>CODE</c>,
    ///  <c>RODATA</c>, <c>DATA</c> and <c>BSS</c>, in that order, from the load address, and <c>ZEROPAGE</c> in the
    ///  largest run of free zero-page bytes (the first, of runs of the same size).
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The RAM region runs to <c>$FFFF</c>, not to the end of the free area, so a program too big for it is
    ///   reported by the memory check (<see cref="Check(ProjectTarget, AssemblyResult)"/>), which says by how much,
    ///   rather than by the linker. A source with no <c>.section</c> assembles at the load address as before, in
    ///   <c>CODE</c>. <c>STARTUP</c> is for the code an environment that starts a program at its first byte, such as
    ///   <c>prodos</c> and <c>sos</c>, starts it at: a <c>JMP</c> on to its entry, which a platform folder can put
    ///   there whatever its family's folder puts first in <c>CODE</c>.
    ///  </para>
    /// </remarks>
    /// <param name="target">The target, which the configuration's comment names.</param>
    /// <returns>The configuration's text.</returns>
    internal string LinkerConfiguration(ProjectTarget target)
    {
        MemoryArea? zeroPage = ZeroPage.OrderByDescending(area => area.Length).FirstOrDefault();
        using StringWriter text = new(CultureInfo.InvariantCulture);
        text.WriteFormatted($"# Made by retrocore build for target {target.Name} from {Path.GetFileName(File)}.\n");
        text.Write("MEMORY {\n");
        if (zeroPage is not null)
        {
            text.WriteFormatted($"    ZP: start = ${zeroPage.Start:X2}, size = ${zeroPage.Length:X2}, file = \"\";\n");
        }

        text.WriteFormatted($"    RAM: start = ${Load:X4}, size = ${0x10000 - Load:X4}, file = %O;\n");
        text.Write("}\nSEGMENTS {\n");
        if (zeroPage is not null) { text.Write("    ZEROPAGE: load = ZP, type = zp, optional = yes;\n"); }
        text.Write("    STARTUP: load = RAM, type = ro, optional = yes;\n");
        text.Write("    CODE: load = RAM, type = ro, optional = yes;\n");
        text.Write("    RODATA: load = RAM, type = ro, optional = yes;\n");
        text.Write("    DATA: load = RAM, type = rw, optional = yes;\n");
        text.Write("    BSS: load = RAM, type = bss, define = yes, optional = yes;\n");
        text.Write("}\n");
        return text.ToString();
    }

    /// <summary>
    ///  Checks where a build put each section against the target's map.
    /// </summary>
    /// <param name="target">The target.</param>
    /// <param name="result">The assembly.</param>
    /// <exception cref="ProjectException">
    ///  A section uses zero page the map leaves to the machine, or overlaps a reserved area; the message names each,
    ///  and, when the program runs past its free RAM, how far.
    /// </exception>
    internal void Check(ProjectTarget target, AssemblyResult result)
    {
        List<string> errors = [];
        List<(string Name, int Start, int End)> sections =
        [
            .. result.Sections.Where(section => section.Size > 0)
                .Select(section => (section.Name, section.Origin, Math.Min(0xFFFF, section.Origin + section.Size - 1)))
        ];

        foreach ((string name, int start, int end) in sections)
        {
            string span = new MemoryArea(start, end).ToString();

            // A map with no zero page checks the first page as it checks the rest.
            int first = ZeroPage.Count == 0 ? 0 : 0x100;
            if (start < first)
            {
                foreach (MemoryArea run in Runs(start, Math.Min(end, 0xFF), address => !ZeroPage.Any(area => area.Contains(address))))
                {
                    errors.Add(
                        $"section {name} ({span}) uses zero page {Byte(run)}, which the memory map leaves to the machine; a program may use {string.Join(", ", ZeroPage.Select(Byte))} on target {target.Name}.");
                }
            }

            if (end < first) { continue; }
            foreach (MemoryArea area in Reserved.Where(area => area.Overlaps(Math.Max(start, first), end)))
            {
                errors.Add($"section {name} ({span}) overlaps {area.Why} ({area}) on target {target.Name}.");
            }
        }

        if (errors.Count == 0) { return; }

        // How far over its free RAM the program runs: the sections that run on from its load address, each starting
        // where one before it ends, or within it.
        MemoryArea home = LoadArea;
        List<(string Name, int Start, int End)> loaded = [];
        int reached = Load - 1;
        foreach ((string Name, int Start, int End) section in sections.Where(section => section.Start >= Load).OrderBy(section => section.Start))
        {
            if (section.Start > reached + 1) { break; }
            loaded.Add(section);
            reached = Math.Max(reached, section.End);
        }

        if (loaded.Count != 0 && loaded.Max(section => section.End) > home.End)
        {
            int used = loaded.Max(section => section.End) - Load + 1;
            int room = home.End - Load + 1;
            errors.Add(
                $"The program does not fit: from ${Load:X4} its sections take {used} bytes ({string.Join(", ", loaded.Select(section => $"{section.Name} {section.End - section.Start + 1}"))}), and the free RAM there ends at ${home.End:X4}, {room} bytes, so it is {used - room} bytes over.");
        }

        throw new ProjectException(
            $"{target.Project.File}: target {target.Name}: {Path.GetFileName(File)}:{System.Environment.NewLine}{string.Join(System.Environment.NewLine, errors)}");
    }

    // Every address from $0100 is free or reserved, not both; the zero page is given only by its bytes; free RAM, from
    // $0100 up, holds the load address. A map with no zero page, for a CPU that has none, such as the Z80, accounts for
    // every address from $0000 instead.
    private void Validate(string file)
    {
        int first = ZeroPage.Count == 0 ? 0 : 0x100;
        List<MemoryArea> all = [.. Free.Concat(Reserved).Where(area => area.End >= first).OrderBy(area => area.Start)];
        int next = first;
        foreach (MemoryArea area in all)
        {
            int start = Math.Max(area.Start, first);
            if (start > next)
            {
                throw new ProjectException($"{file}: ${next:X4}-${start - 1:X4} is neither free nor reserved.");
            }

            if (start < next)
            {
                throw new ProjectException($"{file}: {area} is both free and reserved, or listed twice.");
            }

            next = area.End + 1;
        }

        if (next != 0x10000)
        {
            throw new ProjectException($"{file}: ${next:X4}-$FFFF is neither free nor reserved.");
        }

        if (ZeroPage.Count != 0 && Reserved.Concat(Free).Any(area => area.Start < 0x100))
        {
            throw new ProjectException($"{file}: the zero page is given by 'zeroPage', not as free or reserved areas.");
        }

        if (!Free.Any(area => area.Contains(Load)))
        {
            throw new ProjectException($"{file}: the load address ${Load:X4} is not in free RAM.");
        }
    }

    private static List<MemoryArea> Areas(string file, string what, JsonNode? node, bool why)
    {
        if (node is null) { return []; }
        if (node is not JsonArray list) { throw new ProjectException($"{file}: {what} must be a list of areas."); }
        List<MemoryArea> areas = [];
        foreach (JsonNode? item in list)
        {
            if (item is not JsonObject area)
            {
                throw new ProjectException($"{file}: each of {what} is an object of start and end{(why ? " and why" : "")}.");
            }

            Check(file, $"an area of {what}", area, AreaFields);
            int start = area["start"] is { } startNode
                ? Address(file, $"an area of {what}'s start", startNode)
                : throw new ProjectException($"{file}: an area of {what} must give 'start'.");

            int end = area["end"] is { } endNode
                ? Address(file, $"an area of {what}'s end", endNode)
                : throw new ProjectException($"{file}: an area of {what} must give 'end'.");

            if (end < start)
            {
                throw new ProjectException($"{file}: an area of {what} ends at ${end:X4}, before its start, ${start:X4}.");
            }

            string? reason = Text(area["why"]);
            if (why && string.IsNullOrWhiteSpace(reason))
            {
                throw new ProjectException($"{file}: the reserved area ${start:X4}-${end:X4} of {what} must say why.");
            }

            areas.Add(new(start, end, reason));
        }

        return areas;
    }

    // The zero-page bytes a list gives, its runs merged where they touch or overlap.
    private static List<MemoryArea> ZeroPageAreas(string file, string what, JsonNode? node)
    {
        if (node is null) { return []; }
        if (node is not JsonArray list)
        {
            throw new ProjectException($"{file}: {what} must be a list of bytes or runs, such as \"$06-$09\".");
        }

        // A map for a CPU with no zero page leaves 'zeroPage' out; one that gives it gives a byte.
        if (list.Count == 0)
        {
            throw new ProjectException($"{file}: {what} must give at least one byte a program may use.");
        }

        List<MemoryArea> areas = [];
        foreach (JsonNode? item in list)
        {
            string text = item?.GetValueKind() == JsonValueKind.String ? item.GetValue<string>() : "";
            string[] parts = text.Split('-');
            if (parts.Length is not (1 or 2)
                || !TryAddress(parts[0], out int start)
                || !TryAddress(parts[^1], out int end)
                || end < start
                || end > 0xFF)
            {
                throw new ProjectException($"{file}: in {what}, '{text}' must be a byte or a run of them, such as \"$06-$09\".");
            }

            areas.Add(new(start, end));
        }

        return Merged(areas);
    }

    private static int Address(string file, string what, JsonNode node)
    {
        string text = node.GetValueKind() == JsonValueKind.String ? node.GetValue<string>() : "";
        return TryAddress(text, out int address)
            ? address
            : throw new ProjectException($"{file}: {what} must be an address such as \"$0800\".");
    }

    /// <summary>
    ///  Reads an address written as a map writes one, such as <c>$0800</c>.
    /// </summary>
    /// <param name="text">The text.</param>
    /// <param name="address">The address.</param>
    /// <returns>Whether the text is an address from <c>$0000</c> to <c>$FFFF</c>.</returns>
    internal static bool TryAddress(string text, out int address)
    {
        address = 0;
        text = text.Trim();
        return text.Length is > 1 and <= 5
            && text[0] == '$'
            && int.TryParse(text.AsSpan(1), NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out address)
            && address is >= 0 and <= 0xFFFF;
    }

    private static string? Text(JsonNode? node) =>
        node is JsonValue value && value.GetValueKind() == JsonValueKind.String ? value.GetValue<string>() : null;

    private static void Check(string file, string what, JsonObject json, string[] fields)
    {
        foreach ((string key, JsonNode? value) in json)
        {
            if (!fields.Contains(key))
            {
                throw new ProjectException($"{file}: {what} has no field '{key}'; its fields are {string.Join(", ", fields)}.");
            }

            if (value is null)
            {
                throw new ProjectException($"{file}: {what}'s '{key}' is null; leave it out instead.");
            }
        }
    }

    // The areas with a run's addresses taken out, splitting any the run falls inside.
    private static List<MemoryArea> Without(List<MemoryArea> areas, MemoryArea run)
    {
        List<MemoryArea> left = [];
        foreach (MemoryArea area in areas)
        {
            if (!area.Overlaps(run.Start, run.End))
            {
                left.Add(area);
                continue;
            }

            if (area.Start < run.Start) { left.Add(area with { End = run.Start - 1 }); }
            if (area.End > run.End) { left.Add(area with { Start = run.End + 1 }); }
        }

        return left;
    }

    // Free areas that touch become one.
    private static List<MemoryArea> Merged(List<MemoryArea> areas)
    {
        List<MemoryArea> merged = [];
        foreach (MemoryArea area in areas.OrderBy(area => area.Start))
        {
            if (merged.Count != 0 && merged[^1].End + 1 >= area.Start)
            {
                merged[^1] = merged[^1] with { End = Math.Max(merged[^1].End, area.End) };
            }
            else
            {
                merged.Add(area);
            }
        }

        return merged;
    }

    private static List<MemoryArea> Sorted(List<MemoryArea> areas) => [.. areas.OrderBy(area => area.Start)];

    // The runs of addresses from start to end that a test holds for.
    private static IEnumerable<MemoryArea> Runs(int start, int end, Func<int, bool> test)
    {
        int? first = null;
        for (int address = start; address <= end + 1; address++)
        {
            bool holds = address <= end && test(address);
            if (holds && first is null) { first = address; }
            if (!holds && first is { } from)
            {
                yield return new(from, address - 1);
                first = null;
            }
        }
    }

    private static string Byte(MemoryArea area) => area.Start == area.End ? $"${area.Start:X2}" : $"${area.Start:X2}-${area.End:X2}";
}
