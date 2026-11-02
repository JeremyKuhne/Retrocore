// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text.RegularExpressions;

namespace Retrocore.Debug;

/// <summary>
///  Maps ca65/ld65 debug spans and VICE labels to IIe addresses.
/// </summary>
internal sealed partial class SymbolTable
{
    private readonly Dictionary<ushort, (string Path, int Line)> _locations = [];
    private readonly Dictionary<(string Path, int Line), List<ushort>> _addresses = new(LineComparer.Instance);
    private readonly Dictionary<string, long> _labels = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>
    ///  Loads debug metadata from a cc65 .dbg or VICE label file.
    /// </summary>
    /// <param name="path">The metadata path.</param>
    internal void Load(string path)
    {
        string[] lines = File.ReadAllLines(path);
        if (path.EndsWith(".dbg", StringComparison.OrdinalIgnoreCase))
        {
            string directory = Path.GetDirectoryName(Path.GetFullPath(path))
                ?? throw new InvalidDataException("Missing debug-file directory.");

            LoadDebugInfo(lines, directory);
            return;
        }

        Clear();
        foreach (string line in lines.Where(line => !string.IsNullOrWhiteSpace(line)))
        {
            string[] fields = line.Split(separator: (char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            if (fields.Length != 3 || fields[0] != "al")
            {
                throw new InvalidDataException("Expected a VICE 'al C:XXXX label' entry.");
            }

            _labels[fields[2].TrimStart('.')] = Number(fields[1].Split(':').Last(), hex: true);
        }
    }

    /// <summary>
    ///  Loads cc65 debug information, such as the retrocore assembler writes for any dialect.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   Bytes from a macro have a line record at the invocation and one for each macro body line. Stepping and stack
    ///   frames use the invocation line, while a breakpoint on a macro body line covers every expansion of it.
    ///  </para>
    /// </remarks>
    /// <param name="lines">The .dbg records.</param>
    /// <param name="directory">The directory relative file names resolve against.</param>
    internal void LoadDebugInfo(IEnumerable<string> lines, string directory)
    {
        Clear();
        Dictionary<int, string> files = [];
        Dictionary<int, int> segments = [];
        Dictionary<int, (int Segment, int Start, int Size)> spans = [];
        Dictionary<int, (string Name, int Parent)> scopes = [];
        List<(int File, int Line, bool Macro, string Spans)> sourceLines = [];
        List<(string Name, int Scope, long Value)> symbols = [];
        foreach (string line in lines)
        {
            int separator = line.IndexOf('\t');
            if (separator < 0) { separator = line.IndexOf(' '); }
            if (separator < 0) { continue; }
            string kind = line[..separator];
            Dictionary<string, string> fields = Fields(line[(separator + 1)..]);
            switch (kind)
            {
                case "file":
                    files[Integer(fields, "id")] = fields["name"];
                    break;
                case "seg":
                    segments[Integer(fields, "id")] = Integer(fields, "start");
                    break;
                case "span":
                    spans[Integer(fields, "id")] = (Integer(fields, "seg"), Integer(fields, "start"), Integer(fields, "size"));
                    break;
                case "scope":
                    int parent = fields.TryGetValue("parent", out string? owner) ? checked((int)Number(owner)) : -1;
                    scopes[Integer(fields, "id")] = (fields["name"], parent);
                    break;
                case "line" when fields.ContainsKey("span"):
                    bool macro = fields.TryGetValue("type", out string? type) && type != "0";
                    sourceLines.Add((Integer(fields, "file"), Integer(fields, "line"), macro, fields["span"]));
                    break;
                case "sym" when fields.TryGetValue("val", out string? value):
                    int scope = fields.TryGetValue("scope", out string? container) ? checked((int)Number(container)) : -1;
                    symbols.Add((fields["name"].TrimStart('.'), scope, Number(value)));
                    break;
            }
        }

        // ca65 records an include as written, relative to its own working directory, which the file does not record.
        // Next to the source files named with full paths is a better guess than next to the .dbg file.
        string[] roots =
        [
            directory,
            .. files.Values.Where(Path.IsPathFullyQualified).Select(Path.GetDirectoryName).OfType<string>().Distinct()
        ];

        foreach (int id in files.Keys.ToArray())
        {
            string name = files[id];
            files[id] = Path.IsPathFullyQualified(name)
                ? Path.GetFullPath(name)
                : roots.Select(root => Path.GetFullPath(name, root)).FirstOrDefault(File.Exists) ?? Path.GetFullPath(name, directory);
        }

        foreach ((int file, int line, bool macro, string ids) in sourceLines)
        {
            (string Path, int Line) location = (files[file], line);
            if (!_addresses.TryGetValue(location, out List<ushort>? addresses))
            {
                addresses = [];
                _addresses.Add(location, addresses);
            }

            foreach (string id in ids.Split('+'))
            {
                (int segment, int offset, int size) = spans[int.Parse(id, CultureInfo.InvariantCulture)];
                for (int i = 0; i < size; i++)
                {
                    ushort address = checked((ushort)(segments[segment] + offset + i));
                    addresses.Add(address);

                    // A macro body line never replaces the invocation line an address already has.
                    if (!macro || !_locations.ContainsKey(address)) { _locations[address] = location; }
                }
            }
        }

        // A plain name resolves to its first definition; a scoped one is also reachable as scope::name.
        foreach ((string name, int scope, long value) in symbols)
        {
            _labels.TryAdd(name, value);
            string qualified = name;
            for (int id = scope; scopes.TryGetValue(id, out (string Name, int Parent) owner) && owner.Name.Length != 0; id = owner.Parent)
            {
                qualified = $"{owner.Name}::{qualified}";
            }

            if (!ReferenceEquals(qualified, name)) { _labels[qualified] = value; }
        }
    }

    /// <summary>
    ///  Gets the source files the table maps addresses to.
    /// </summary>
    internal IEnumerable<string> Paths =>
        _locations.Values.Select(location => location.Path).Distinct(StringComparer.OrdinalIgnoreCase);

    /// <summary>
    ///  Gets every label and constant by name.
    /// </summary>
    internal IReadOnlyDictionary<string, long> Labels => _labels;

    /// <summary>
    ///  Gets the source location associated with an address.
    /// </summary>
    /// <param name="address">The CPU address.</param>
    /// <returns>The location, or null when no debug span covers it.</returns>
    internal (string Path, int Line)? Location(ushort address) => _locations.TryGetValue(address, out var location) ? location : null;

    /// <summary>
    ///  Gets addresses corresponding to a source breakpoint.
    /// </summary>
    /// <param name="path">The source path.</param>
    /// <param name="line">The one-based source line.</param>
    /// <returns>Every address belonging to the source line, including each expansion of a macro body line.</returns>
    internal ushort[] Addresses(string path, int line) =>
        _addresses.TryGetValue((Path.GetFullPath(path), line), out List<ushort>? addresses)
            ? [.. addresses.Distinct().Order()]
            : [];

    /// <summary>
    ///  Resolves a label.
    /// </summary>
    /// <param name="name">The label name.</param>
    /// <returns>The label address or constant.</returns>
    internal long Resolve(string name) => TryResolve(name, out long value)
        ? value : throw new FormatException($"Unknown label '{name}'.");

    /// <summary>
    ///  Resolves a label when it is defined.
    /// </summary>
    /// <param name="name">The label name.</param>
    /// <param name="value">The label address or constant.</param>
    /// <returns>Whether the label is defined.</returns>
    internal bool TryResolve(string name, out long value) => _labels.TryGetValue(name.TrimStart('.'), out value);

    /// <summary>
    ///  Gets the closest preceding source label for a displayed stack frame.
    /// </summary>
    /// <param name="address">The frame's instruction address.</param>
    /// <returns>The label, or null if no label precedes this address.</returns>
    internal string? Label(ushort address) => _labels.Where(pair => pair.Value <= address)
        .OrderByDescending(pair => pair.Value).Select(pair => pair.Key).FirstOrDefault();
    private void Clear()
    {
        _locations.Clear();
        _addresses.Clear();
        _labels.Clear();
    }

    private static int Integer(Dictionary<string, string> fields, string name) => checked((int)Number(fields[name]));
    private static long Number(string value, bool hex = false) => long.Parse(
        value.StartsWith("0x", StringComparison.OrdinalIgnoreCase) ? value[2..] : value,
        hex || value.StartsWith("0x", StringComparison.OrdinalIgnoreCase) ? NumberStyles.HexNumber : NumberStyles.Integer,
        CultureInfo.InvariantCulture);
    private static Dictionary<string, string> Fields(string text)
    {
        Dictionary<string, string> result = [];
        foreach (Match match in DebugFields().Matches(text))
        {
            string value = match.Groups[2].Value;
            result[match.Groups[1].Value] = value.StartsWith('"') ? value[1..^1].Replace("\\\"", "\"") : value;
        }

        return result;
    }

    [GeneratedRegex("""(?:^|,)(\w+)=("(?:\\.|[^"])*"|[^,]*)""")]
    private static partial Regex DebugFields();
}
