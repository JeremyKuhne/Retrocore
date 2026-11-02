// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Touki.Io;

namespace Retrocore.Assembler;

public static partial class AssemblyDebugFile
{
    /// <summary>
    ///  Collects records with dense ids in first-use order, then writes them in ld65's record order.
    /// </summary>
    /// <param name="result">The assembly output.</param>
    private sealed class Builder(AssemblyResult result)
    {
        // Compiler-generated names: private scope labels, Merlin macro locals and loop counters, and variable versions.
        private static readonly string[] s_internalMarkers = ["__retro_", "__merlin_", "__Merlin", "#"];

        private readonly Dictionary<string, int> _files = new(StringComparer.Ordinal);
        private readonly Dictionary<(int File, int Line, int Type, int Count), int> _lineIds = [];
        private readonly List<(int File, int Line, int Type, int Count, List<int> Spans)> _lines = [];
        private readonly Dictionary<(int Section, int Base), int> _segmentIds = [];
        private readonly List<(int Section, int Start, int FirstOffset, int End)> _segments = [];
        private readonly List<(int Segment, int Start, int Size)> _spans = [];
        private readonly Dictionary<string, int> _scopeIds = new(StringComparer.Ordinal) { [""] = 0 };
        private readonly List<(string Name, int Parent)> _scopes = [("", -1)];
        private readonly List<string> _symbols = [];

        /// <summary>
        ///  Writes the records.
        /// </summary>
        /// <param name="writer">The destination.</param>
        internal void Write(TextWriter writer)
        {
            CollectSpans();
            CollectSymbols();

            writer.Write("version\tmajor=2,minor=0\n");
            writer.WriteFormatted($"info\tcsym=0,file={_files.Count},lib=0,line={_lines.Count},mod=1,scope={_scopes.Count},");
            writer.WriteFormatted($"seg={_segments.Count},span={_spans.Count},sym={_symbols.Count},type=0\n");

            foreach (KeyValuePair<string, int> file in _files.OrderBy(pair => pair.Value))
            {
                (long size, long time) = FileStamp(file.Key);
                writer.WriteFormatted($"file\tid={file.Value},name=\"{Escape(file.Key)}\",size={size},mtime=0x{time:X8},mod=0\n");
            }

            for (int id = 0; id < _lines.Count; id++)
            {
                (int file, int line, int type, int count, List<int> spans) = _lines[id];
                writer.WriteFormatted($"line\tid={id},file={file},line={line}");
                if (type != 0) { writer.WriteFormatted($",type={type}"); }
                if (count != 0) { writer.WriteFormatted($",count={count}"); }
                if (spans.Count != 0) { writer.WriteFormatted($",span={string.Join("+", spans)}"); }
                writer.Write('\n');
            }

            string module = _files.Count == 0 ? "" : Path.GetFileName(_files.First(pair => pair.Value == 0).Key);
            writer.WriteFormatted($"mod\tid=0,name=\"{Escape(module)}\"{(_files.Count == 0 ? "" : ",file=0")}\n");
            for (int id = 0; id < _segments.Count; id++)
            {
                (int section, int start, _, int end) = _segments[id];
                int size = end;
                string addressSize = start + size <= 0x100 ? "zeropage" : start + size <= 0x10000 ? "absolute" : "far";
                writer.WriteFormatted($"seg\tid={id},name=\"{Escape(result.Sections[section].Name)}\",start=0x{start:X6},");
                writer.WriteFormatted($"size=0x{size:X4},addrsize={addressSize},type=rw\n");
            }

            for (int id = 0; id < _spans.Count; id++)
            {
                (int segment, int start, int size) = _spans[id];
                writer.WriteFormatted($"span\tid={id},seg={segment},start={start},size={size}\n");
            }

            for (int id = 0; id < _scopes.Count; id++)
            {
                (string name, int parent) = _scopes[id];
                if (parent < 0)
                {
                    writer.WriteFormatted($"scope\tid={id},name=\"\",mod=0\n");
                }
                else
                {
                    writer.WriteFormatted($"scope\tid={id},name=\"{Escape(name)}\",mod=0,type=scope,parent={parent}\n");
                }
            }

            foreach (string symbol in _symbols) { writer.Write(symbol); }
        }

        /// <summary>
        ///  Groups emitted bytes into segments by constant address offset and records each statement as a span.
        /// </summary>
        private void CollectSpans()
        {
            foreach (AssemblySourceMapEntry entry in result.SourceMap)
            {
                // Reserved space such as BSS emits nothing but is still memory a debugger can map to its line.
                if (entry.OccupiedSize == 0 || entry.Location is not { } location) { continue; }
                int segment = Segment(entry);
                (_, int start, int firstOffset, int end) = _segments[segment];
                int spanStart = entry.Offset - firstOffset;
                _segments[segment] = (entry.Section, start, firstOffset, Math.Max(end, spanStart + entry.OccupiedSize));
                int span = _spans.Count;
                _spans.Add((segment, spanStart, entry.OccupiedSize));

                // The first location outside any macro is the line a debugger steps by. Each macro body line is also a
                // line, counted as ld65 does from the outermost expansion (1) inward.
                int depth = 0;
                AssemblyLocation call = location;
                while (call.IsMacroExpansion && call.ExpandedFrom is { } from)
                {
                    depth++;
                    call = from;
                }

                _lines[Line(call, type: 0, count: 0)].Spans.Add(span);
                for (AssemblyLocation level = location; level.IsMacroExpansion && level.ExpandedFrom is { } from; level = from)
                {
                    _lines[Line(level, MacroLineType, depth--)].Spans.Add(span);
                }
            }
        }

        /// <summary>
        ///  Finds or adds the segment for an entry's section and address base.
        /// </summary>
        /// <param name="entry">The source map entry.</param>
        /// <returns>The segment id.</returns>
        private int Segment(AssemblySourceMapEntry entry)
        {
            (int Section, int Base) key = (entry.Section, entry.Address - entry.Offset);
            if (_segmentIds.TryGetValue(key, out int id))
            {
                // A run may begin later in the section than an entry seen afterwards; keep the lowest offset first.
                (int section, int start, int firstOffset, int end) = _segments[id];
                if (entry.Offset < firstOffset)
                {
                    int shift = firstOffset - entry.Offset;
                    _segments[id] = (section, entry.Address, entry.Offset, end + shift);
                    for (int index = 0; index < _spans.Count; index++)
                    {
                        (int segment, int spanStart, int size) = _spans[index];
                        if (segment == id) { _spans[index] = (id, spanStart + shift, size); }
                    }
                }

                return id;
            }

            id = _segments.Count;
            _segmentIds.Add(key, id);
            _segments.Add((entry.Section, entry.Address, entry.Offset, 0));
            return id;
        }

        /// <summary>
        ///  Finds or adds a line record.
        /// </summary>
        /// <param name="location">The source location.</param>
        /// <param name="type">The ld65 line type.</param>
        /// <param name="count">The macro expansion depth.</param>
        /// <returns>The line id.</returns>
        private int Line(AssemblyLocation location, int type, int count)
        {
            // ld65 line numbers start at one.
            (int, int, int, int) key = (File(location.Path), location.Line + 1, type, count);
            if (!_lineIds.TryGetValue(key, out int id))
            {
                id = _lines.Count;
                _lineIds.Add(key, id);
                _lines.Add((key.Item1, key.Item2, type, count, []));
            }

            return id;
        }

        private int File(string path)
        {
            if (!_files.TryGetValue(path, out int id))
            {
                id = _files.Count;
                _files.Add(path, id);
            }

            return id;
        }

        /// <summary>
        ///  Records source-visible symbols, splitting qualified names into scopes.
        /// </summary>
        private void CollectSymbols()
        {
            Dictionary<string, string> sourceNames = new(StringComparer.Ordinal);
            foreach (KeyValuePair<string, string> alias in result.SymbolAliases)
            {
                sourceNames[alias.Value] = alias.Key;
            }

            foreach (AssemblySymbol symbol in result.SymbolDefinitions.OrderBy(symbol => symbol.Name, StringComparer.Ordinal))
            {
                string name = sourceNames.TryGetValue(symbol.Name, out string? source) ? source : symbol.Name;
                if (IsInternal(name)) { continue; }
                int separator = name.LastIndexOf("::", StringComparison.Ordinal);
                int scope = separator < 0 ? 0 : Scope(name[..separator]);
                string leaf = separator < 0 ? name : name[(separator + 2)..];
                string addressSize = symbol.Value is >= 0 and <= 0xFF ? "zeropage" : symbol.Value is >= 0 and <= 0xFFFF ? "absolute" : "far";
                string definition = symbol.Location is { } location ? $",def={Line(Outermost(location), type: 0, count: 0)}" : "";
                string kind = symbol.IsConstant ? "equ" : "lab";
                string fields = $"name=\"{Escape(leaf)}\",addrsize={addressSize},scope={scope}{definition}";
                _symbols.Add($"sym\tid={_symbols.Count},{fields},val=0x{symbol.Value:X},type={kind}\n");
            }
        }

        private int Scope(string qualified)
        {
            if (_scopeIds.TryGetValue(qualified, out int id)) { return id; }
            int separator = qualified.LastIndexOf("::", StringComparison.Ordinal);
            int parent = separator < 0 ? 0 : Scope(qualified[..separator]);
            id = _scopes.Count;
            _scopeIds.Add(qualified, id);
            _scopes.Add((separator < 0 ? qualified : qualified[(separator + 2)..], parent));
            return id;
        }

        private static AssemblyLocation Outermost(AssemblyLocation location)
        {
            while (location.IsMacroExpansion && location.ExpandedFrom is { } from) { location = from; }
            return location;
        }

        /// <summary>
        ///  Tests for compiler-generated names: private scope labels, Merlin macro locals and versioned variables.
        /// </summary>
        /// <param name="name">The source name.</param>
        /// <returns>Whether the name is not one a source wrote.</returns>
        private static bool IsInternal(string name)
        {
            foreach (string marker in s_internalMarkers)
            {
                if (name.Contains(marker, StringComparison.Ordinal)) { return true; }
            }

            return false;
        }

        // As in ld65, only quotes are escaped, so Windows paths keep single backslashes.
        private static string Escape(string text) => text.Replace("\"", "\\\"");

        private static (long Size, long Time) FileStamp(string path)
        {
            try
            {
                FileInfo file = new(path);
                return file.Exists ? (file.Length, new DateTimeOffset(file.LastWriteTimeUtc).ToUnixTimeSeconds()) : (0, 0);
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
            {
                return (0, 0);
            }
        }
    }
}
