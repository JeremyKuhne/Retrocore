// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;
using Retrocore.Media;
using Retrocore.Pascal;

namespace Retrocore.Debug;

// Pascal sources: line breakpoints and frames at their lines, through the compiler's listing.
//
// A source's listing is found by the source's name: HELLO.TEXT or hello.pas has HELLO.LST.TEXT, on a disk in a drive
// (read again when the disk changes, as when the Compiler writes it) or beside the source. The listing gives each
// line's segment, procedure and offset; a breakpoint there is a pascal breakpoint on the segment named as the listing
// names it.
internal sealed partial class DebugSession
{
    // The Pascal sources breakpoints are set in, each with its text when they were set, and the generation of the
    // disks' code files and listings they were bound with.
    private readonly Dictionary<string, string[]> _pascalSources = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, int> _pascalBound = new(StringComparer.OrdinalIgnoreCase);
    private long _pascalRefreshed;

    private static bool IsPascalSource(string path)
    {
        string name = Path.GetFileName(path);
        return name.EndsWith(".pas", StringComparison.OrdinalIgnoreCase)
            || name.EndsWith(".pascal", StringComparison.OrdinalIgnoreCase)
            || (name.EndsWith(".text", StringComparison.OrdinalIgnoreCase) && !name.EndsWith(".lst.text", StringComparison.OrdinalIgnoreCase));
    }

    // A source's name without its extension, in capitals, as its listing's name starts.
    private static string SourceBase(string path)
    {
        string name = Path.GetFileName(path);
        int dot = name.LastIndexOf('.');
        return (dot > 0 ? name[..dot] : name).ToUpperInvariant();
    }

    /// <summary>
    ///  Answers setBreakpoints for a Pascal source: each line binds through the listing to its statement's p-code.
    /// </summary>
    /// <param name="args">The request.</param>
    /// <param name="path">The source's full path.</param>
    /// <returns>The response.</returns>
    private JsonObject PascalSourceBreakpoints(JsonObject args, string path)
    {
        _requested[path] = args;
        _pascalSources[path] = File.Exists(path) ? File.ReadAllLines(path) : [];
        string group = $"pascal\n{path.ToUpperInvariant()}";
        _pascalBreakpoints.RemoveAll(entry => entry.State.Line is { } line && string.Equals(line.Path, path, StringComparison.OrdinalIgnoreCase));
        (string Where, PascalListing Listing)? listing = _target is null ? null : ListingFor(path);
        _pascalBound[path] = Pascal?.Generation ?? 0;
        HashSet<string> kept = [];
        List<JsonObject> responses = [];
        foreach (JsonObject breakpoint in (args["breakpoints"] as JsonArray ?? []).OfType<JsonObject>())
        {
            int line = breakpoint.Int("line") ?? 0;
            BreakpointState state = State(group, line.ToString(CultureInfo.InvariantCulture), breakpoint, kept);
            state.Kind = "breakpoint";
            state.Line = new(path, line);
            state.Location = $"{Path.GetFileName(path)}:{line}";
            if (Bind(path, line, listing, state) is { } where) { _pascalBreakpoints.Add((where, state)); }

            state.Response = new JsonObject
            {
                ["id"] = state.Id,
                ["verified"] = state.Problem is null,
                ["line"] = line,
                ["source"] = new JsonObject { ["name"] = Path.GetFileName(path), ["path"] = path }
            };

            responses.Add(Describe(state, changed: false));
        }

        Forget(group, kept);
        return new JsonObject { ["breakpoints"] = responses.ToJsonArray() };
    }

    // Where a source line's breakpoint stops: its statement's first p-code, or null with the state saying why not.
    private PascalBreakpoint? Bind(string path, int line, (string Where, PascalListing Listing)? found, BreakpointState state)
    {
        if (_target is null)
        {
            state.Problem ??= "Binds when the machine launches.";
            return null;
        }

        if (Pascal is not { } pascal)
        {
            state.Problem ??= "Only the Apple II and the Apple III run Apple Pascal.";
            return null;
        }

        if (found is not { } listing)
        {
            state.Problem ??= $"No compiler listing for {Path.GetFileName(path)}: compile it with the listing "
                + $"{SourceBase(path)}.LST.TEXT, on a disk in a drive or beside the source.";

            return null;
        }

        if (listing.Listing.Statement(line) is not { } statement)
        {
            state.Problem ??= $"{listing.Where} has no code on line {line}.";
            return null;
        }

        string[] text = _pascalSources.GetValueOrDefault(path) ?? [];
        if (line <= text.Length && !SameText(text[line - 1], statement.Text))
        {
            state.Problem ??= $"Line {line} of {listing.Where} is not the source's line {line}: compile it again with a listing.";
            return null;
        }

        string? name = listing.Listing.SegmentName(statement.Segment) is { } named ? PascalListing.CodeName(named) : null;
        int offset = FirstPcode(pascal, name, statement);
        state.Location = $"{Path.GetFileName(path)}:{line} ({name ?? statement.Segment.ToString(CultureInfo.InvariantCulture)}.{statement.Procedure}+${offset:X4})";
        return new PascalBreakpoint(name, statement.Segment, statement.Procedure, offset);
    }

    // Where a statement's code starts: the first p-code from where the compiler was when it read the line, which can be
    // inside a p-code it had not finished; the listing's offset when the code file is not on a disk.
    private static int FirstPcode(PascalRuntime pascal, string? name, PascalListingLine statement)
    {
        if (name is null
            || pascal.CodeSegment(name, statement.Segment) is not { } segment
            || segment.Procedure(statement.Procedure) is not { IsNative: false } procedure)
        {
            return statement.Offset;
        }

        try
        {
            return PcodeDisassembler.Disassemble(segment, procedure)
                .FirstOrDefault(instruction => instruction.Offset - procedure.Entry >= statement.Offset) is { } first
                    ? first.Offset - procedure.Entry
                    : statement.Offset;
        }
        catch (InvalidDataException)
        {
            return statement.Offset;
        }
    }

    private static bool SameText(string source, string listed) =>
        string.Equals(source.TrimEnd(), listed.TrimEnd(), StringComparison.OrdinalIgnoreCase);

    // A source's listing: on a disk in a drive, or beside the source.
    private (string Where, PascalListing Listing)? ListingFor(string path)
    {
        string wanted = $"{SourceBase(path)}.LST.TEXT";
        if (Pascal?.Listings.FirstOrDefault(entry => FileName(entry.File).Equals(wanted, StringComparison.OrdinalIgnoreCase)) is
            {
            File: not null
        } onDisk)
        {
            return onDisk;
        }

        string? directory = Path.GetDirectoryName(path);
        if (directory is null || !Directory.Exists(directory)) { return null; }

        HashSet<string> names = new(StringComparer.OrdinalIgnoreCase)
        {
            wanted, $"{SourceBase(path)}.LST", $"{SourceBase(path)}.LST.TXT"
        };

        foreach (string file in Directory.EnumerateFiles(directory))
        {
            if (!names.Contains(Path.GetFileName(file))) { continue; }

            // A listing copied raw from a Pascal disk keeps the text file's format: its header page, DLE and NULs.
            byte[] data = File.ReadAllBytes(file);
            string text = Array.IndexOf(data, (byte)0) >= 0 ? PascalTextFile.Read(data) : Encoding.UTF8.GetString(data);
            PascalListing listing = PascalListing.Parse(text);
            if (listing.Lines.Count != 0) { return (Path.GetFileName(file), listing); }
        }

        return null;
    }

    // The name of a file on a Pascal disk, after its volume's.
    private static string FileName(string file) => file[(Math.Max(file.LastIndexOf(':'), file.LastIndexOf('/')) + 1)..];

    // Where a frame's p-code is in a source: the listing that compiles its segment, the line, and the source's path
    // when a breakpoint's source has that listing.
    private (PascalListing Listing, PascalListingLine Line, string? Path)? PascalPlace(PascalFrame frame)
    {
        if (Pascal is not { } pascal || pascal.Segment(frame)?.Segment.Name is not { } name) { return null; }

        foreach ((string path, string[] text) in _pascalSources)
        {
            if (ListingFor(path) is { } listing
                && listing.Listing.Compiles(frame.SegmentNumber, name)
                && listing.Listing.LineAt(frame.SegmentNumber, frame.Procedure, frame.Offset) is { } line)
            {
                // A source that no longer has the listing's line there is not where the frame is.
                bool same = line.Line <= text.Length && SameText(text[line.Line - 1], line.Text);
                return (listing.Listing, line, same ? path : null);
            }
        }

        foreach ((_, PascalListing listing) in pascal.Listings)
        {
            if (listing.Compiles(frame.SegmentNumber, name) && listing.LineAt(frame.SegmentNumber, frame.Procedure, frame.Offset) is { } line)
            {
                return (listing, line, null);
            }
        }

        return null;
    }

    // Binds the sources' breakpoints again once a disk changes, as when the Compiler writes a new listing.
    private void RefreshPascalSources()
    {
        if (_pascalSources.Count == 0 || Pascal is not { } pascal || Stopwatch.GetElapsedTime(_pascalRefreshed).TotalSeconds < 1)
        {
            return;
        }

        _pascalRefreshed = Stopwatch.GetTimestamp();
        pascal.Refresh();

        // Each source binds again once the disks have been read since it bound, by this look or another.
        foreach (string path in _pascalSources.Keys.ToArray())
        {
            if (_pascalBound.GetValueOrDefault(path) == pascal.Generation || !_requested.TryGetValue(path, out JsonObject? request))
            {
                continue;
            }

            foreach (JsonObject breakpoint in (PascalSourceBreakpoints(request, path)["breakpoints"] as JsonArray ?? []).OfType<JsonObject>())
            {
                Notify("breakpoint", new JsonObject
                {
                    ["reason"] = "changed", ["breakpoint"] = breakpoint.DeepClone()
                });
            }
        }
    }
}
