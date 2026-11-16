// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

/// <summary>
///  What a person marks in Retrocore Memory: code and data, names and comments, kept in the disassembler's hints
///  file so annotating memory while debugging leads straight to <c>--disassemble</c>.
/// </summary>
/// <remarks>
///  <para>
///   The file is <see cref="DisassemblyHints"/>'s: <c>entries</c> are code marks, <c>data</c> ranges data marks,
///   and <c>names</c> and <c>comments</c> what they say. An address in a bank keeps its bank's name as a prefix, as
///   memory references do, such as <c>"aux:$0400"</c>; the disassembler, which reads one image, ignores those.
///   Anything else in the file, such as <c>noReturn</c> and <c>inline</c>, is kept as it was.
///  </para>
/// </remarks>
internal sealed class MemoryHints
{
    // The file is written for people to read and diff.
    private static readonly JsonSerializerOptions s_indented = new() { WriteIndented = true };

    private readonly JsonObject _root;
    // Banks are named without regard to case, as memory references name them.
    private readonly Dictionary<string, MemoryHintSpace> _spaces = [with(StringComparer.OrdinalIgnoreCase)];

    private MemoryHints(JsonObject root) => _root = root;

    /// <summary>
    ///  Gets hints with nothing marked.
    /// </summary>
    internal static MemoryHints Empty => new([]);

    /// <summary>
    ///  Reads a hints file.
    /// </summary>
    /// <param name="path">The file.</param>
    /// <returns>The hints.</returns>
    /// <exception cref="InvalidDataException">The file is not hints.</exception>
    internal static MemoryHints Read(string path)
    {
        JsonObject root = JsonNode.Parse(File.ReadAllText(path)) as JsonObject
            ?? throw new InvalidDataException($"{path} is not a JSON object.");

        Validate(root);
        MemoryHints hints = new(root);
        foreach (JsonNode? entry in root["entries"] as JsonArray ?? [])
        {
            (string space, int address) = Key(entry);
            hints.In(space).Code.Add(address);
        }

        foreach (JsonObject range in (root["data"] as JsonArray ?? []).OfType<JsonObject>())
        {
            (string space, int start) = Key(range["start"]);
            int length = range["length"] is { } count ? count.GetValue<int>() : Key(range["end"]).Address - start + 1;
            if (length <= 0) { throw new InvalidDataException($"The data range at ${start:X4} is empty."); }
            hints.In(space).Data.Add((start, length));
        }

        foreach ((string key, JsonNode? value) in root["names"] as JsonObject ?? [])
        {
            (string space, int address) = Key(key);
            hints.In(space).Names[address] = value?.GetValue<string>() ?? "";
        }

        foreach ((string key, JsonNode? value) in root["comments"] as JsonObject ?? [])
        {
            (string space, int address) = Key(key);
            hints.In(space).Comments[address] = value?.GetValue<string>() ?? "";
        }

        return hints;
    }

    /// <summary>
    ///  Gets the addresses a space's code is marked to start at.
    /// </summary>
    /// <param name="space">The bank's name, or empty for memory as the CPU maps it.</param>
    /// <returns>The addresses.</returns>
    internal IReadOnlyCollection<int> Code(string space) => _spaces.TryGetValue(space, out MemoryHintSpace? found) ? found.Code : [];

    /// <summary>
    ///  Gets a space's data marks, each one's first address and length.
    /// </summary>
    /// <param name="space">The bank's name, or empty for memory as the CPU maps it.</param>
    /// <returns>The ranges, in order.</returns>
    internal IReadOnlyList<(int Start, int Length)> Data(string space) =>
        _spaces.TryGetValue(space, out MemoryHintSpace? found) ? [.. found.Data.OrderBy(range => range.Start)] : [];

    /// <summary>
    ///  Gets a space's names by address.
    /// </summary>
    /// <param name="space">The bank's name, or empty for memory as the CPU maps it.</param>
    /// <returns>The names.</returns>
    internal IReadOnlyDictionary<int, string> Names(string space) =>
        _spaces.TryGetValue(space, out MemoryHintSpace? found) ? found.Names : new Dictionary<int, string>();

    /// <summary>
    ///  Gets a space's comments by address.
    /// </summary>
    /// <param name="space">The bank's name, or empty for memory as the CPU maps it.</param>
    /// <returns>The comments.</returns>
    internal IReadOnlyDictionary<int, string> Comments(string space) =>
        _spaces.TryGetValue(space, out MemoryHintSpace? found) ? found.Comments : new Dictionary<int, string>();

    /// <summary>
    ///  Marks a range as code, data, or neither.
    /// </summary>
    /// <param name="space">The bank's name, or empty for memory as the CPU maps it.</param>
    /// <param name="start">The first address.</param>
    /// <param name="length">The bytes marked.</param>
    /// <param name="kind">
    ///  <c>code</c>, which starts code at <paramref name="start"/>; <c>data</c>; or <c>clear</c>.
    /// </param>
    /// <param name="size">
    ///  The bytes of the instruction at an address, so code marked takes its whole instruction out of the data, and
    ///  data marked takes out each instruction marked to start that would run into it.
    /// </param>
    internal void Mark(string space, int start, int length, string kind, Func<int, int> size)
    {
        if (kind is not ("code" or "data" or "clear"))
        {
            throw new ArgumentException("A mark is code, data or clear.", nameof(kind));
        }

        MemoryHintSpace marks = In(space);
        int end = kind == "code" ? Math.Min(0x10000, start + Math.Max(1, size(start))) : start + length;

        // A mark replaces what the range had: its data, and the code whose instruction is in it.
        marks.Code.RemoveWhere(address => address < end && address + Math.Max(1, size(address)) > start);
        List<(int Start, int Length)> kept = [];
        foreach ((int from, int count) in marks.Data)
        {
            if (from < start) { kept.Add((from, Math.Min(count, start - from))); }
            if (from + count > end) { kept.Add((Math.Max(from, end), from + count - Math.Max(from, end))); }
        }

        marks.Data.Clear();
        marks.Data.AddRange(kept);
        if (kind == "code") { marks.Code.Add(start); }
        else if (kind == "data") { marks.Data.Add((start, length)); }

        // Data next to data is one range.
        marks.Data.Sort();
        for (int index = marks.Data.Count - 1; index > 0; index--)
        {
            (int before, int beforeLength) = marks.Data[index - 1];
            (int after, int afterLength) = marks.Data[index];
            if (before + beforeLength >= after)
            {
                marks.Data[index - 1] = (before, Math.Max(beforeLength, after + afterLength - before));
                marks.Data.RemoveAt(index);
            }
        }
    }

    /// <summary>
    ///  Names an address, or takes its name away.
    /// </summary>
    /// <param name="space">The bank's name, or empty for memory as the CPU maps it.</param>
    /// <param name="address">The address.</param>
    /// <param name="name">The name, or empty to take it away.</param>
    /// <exception cref="ArgumentException">
    ///  The name is not one the disassembler takes, a plain native identifier, or another address in the space has it.
    /// </exception>
    internal void Name(string space, int address, string name)
    {
        if (name.Length == 0)
        {
            In(space).Names.Remove(address);
            return;
        }

        if (!Disassembler.IsSymbolName(name))
        {
            throw new ArgumentException($"{name} is not a name the disassembler takes; use a native identifier, such as MYTABLE.", nameof(name));
        }

        foreach ((int other, string taken) in In(space).Names)
        {
            if (other != address && string.Equals(taken, name, StringComparison.Ordinal))
            {
                throw new ArgumentException($"${other:X4} is already named {name}.", nameof(name));
            }
        }

        In(space).Names[address] = name;
    }

    /// <summary>
    ///  Comments on an address, or takes its comment away.
    /// </summary>
    /// <param name="space">The bank's name, or empty for memory as the CPU maps it.</param>
    /// <param name="address">The address.</param>
    /// <param name="comment">The comment, or empty to take it away.</param>
    internal void Comment(string space, int address, string comment)
    {
        if (comment.Length == 0) { In(space).Comments.Remove(address); }
        else { In(space).Comments[address] = comment; }
    }

    /// <summary>
    ///  Writes the hints, keeping what else the file held.
    /// </summary>
    /// <param name="path">The file.</param>
    internal void Write(string path)
    {
        IEnumerable<(string Space, MemoryHintSpace Marks)> spaces = _spaces
            .OrderBy(pair => pair.Key, StringComparer.Ordinal)
            .Select(pair => (pair.Key, pair.Value));

        JsonArray entries = [];
        JsonArray data = [];
        JsonObject names = [];
        JsonObject comments = [];
        foreach ((string space, MemoryHintSpace marks) in spaces)
        {
            foreach (int address in marks.Code.Order()) { entries.Add((JsonNode)Text(space, address)); }
            foreach ((int start, int length) in marks.Data.OrderBy(range => range.Start))
            {
                data.Add((JsonNode)new JsonObject { ["start"] = Text(space, start), ["length"] = length });
            }

            foreach ((int address, string name) in marks.Names.OrderBy(pair => pair.Key))
            {
                names[Text(space, address)] = name;
            }

            foreach ((int address, string text) in marks.Comments.OrderBy(pair => pair.Key))
            {
                comments[Text(space, address)] = text;
            }
        }

        Set("entries", entries, entries.Count);
        Set("data", data, data.Count);
        Set("names", names, names.Count);
        Set("comments", comments, comments.Count);
        // The new file is written beside the old and then takes its place, so a write that fails leaves the old.
        string full = Path.GetFullPath(path);
        string directory = Path.GetDirectoryName(full) ?? ".";
        Directory.CreateDirectory(directory);
        string temporary = Path.Join(directory, $".{Path.GetFileName(full)}.{Guid.NewGuid():N}.tmp");
        try
        {
            File.WriteAllText(temporary, _root.ToJsonString(s_indented) + Environment.NewLine);
            File.Move(temporary, full, overwrite: true);
        }
        finally
        {
            File.Delete(temporary);
        }
    }

    // Refuses a file whose parts the disassembler reads are not the shapes it takes, so marks never rewrite one.
    private static void Validate(JsonObject root)
    {
        Shape<JsonArray>(root, "entries");
        Shape<JsonArray>(root, "data");
        Shape<JsonArray>(root, "noReturn");
        Shape<JsonObject>(root, "names");
        Shape<JsonObject>(root, "comments");
        Shape<JsonObject>(root, "inline");
        foreach (JsonNode? range in root["data"] as JsonArray ?? [])
        {
            if (range is not JsonObject) { throw new InvalidDataException("Each data range is an object."); }
        }

        foreach (string part in (string[])["names", "comments"])
        {
            foreach ((string key, JsonNode? value) in root[part] as JsonObject ?? [])
            {
                if (value is not JsonValue text || !text.TryGetValue(out string? _))
                {
                    throw new InvalidDataException($"The {part} entry {key} is not text.");
                }
            }
        }
    }

    private static void Shape<T>(JsonObject root, string name) where T : JsonNode
    {
        if (root[name] is { } node && node is not T)
        {
            throw new InvalidDataException($"The hints file's {name} is not a JSON {(typeof(T) == typeof(JsonArray) ? "array" : "object")}.");
        }
    }

    // Puts a part of the file in place, or takes it away when it is empty.
    private void Set(string name, JsonNode node, int count)
    {
        if (count == 0) { _root.Remove(name); }
        else { _root[name] = node; }
    }

    private MemoryHintSpace In(string space)
    {
        if (!_spaces.TryGetValue(space, out MemoryHintSpace? found))
        {
            found = new MemoryHintSpace();
            _spaces.Add(space, found);
        }

        return found;
    }

    // An address as the file writes it, such as "$0400" or "aux:$0400".
    private static string Text(string space, int address) =>
        (space.Length == 0 ? "" : space + ":") + "$" + address.ToString("X4", CultureInfo.InvariantCulture);

    // An address as the file gives it: a number, "$0400", or "aux:$0400" for a bank's.
    private static (string Space, int Address) Key(JsonNode? node)
    {
        if (node is JsonValue value && value.TryGetValue(out int number)) { return ("", checked((ushort)number)); }
        return Key(node?.GetValue<string>() ?? throw new InvalidDataException("An address is missing."));
    }

    private static (string Space, int Address) Key(string text)
    {
        int colon = text.IndexOf(':', StringComparison.Ordinal);
        string space = colon < 0 ? "" : text[..colon];
        return (space, checked((ushort)CommandAddress.Parse(colon < 0 ? text : text[(colon + 1)..])));
    }
}
