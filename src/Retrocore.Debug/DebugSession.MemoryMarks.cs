// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug;

// retro/memory/mark: Retrocore Memory's marks, names and comments, kept in the launch's hints file.
internal sealed partial class DebugSession
{
    // The hints file marks are kept in, or null where the launch names none and has no program or source to put one
    // beside; and what it holds.
    private string? _hintsPath;
    private MemoryHints _hints = MemoryHints.Empty;

    // The space a memory view's marks are kept under: its bank's name, or empty for memory as the CPU maps it.
    private static string HintSpace(DebugMemoryBank? bank) => bank?.Name ?? "";

    // Finds and reads a launch's hints file: its hints setting, or <name>.hints.json beside its program or source.
    private void LoadHints(JsonObject args, string? sourceFile, string? program)
    {
        string? beside = sourceFile ?? program ?? args.String("debugFile");
        string? path = args.String("hints") ?? (beside is null ? null : Path.ChangeExtension(beside, ".hints.json"));
        _hintsPath = path is null ? null : Path.GetFullPath(path);
        _hints = MemoryHints.Empty;
        if (_hintsPath is null || !File.Exists(_hintsPath)) { return; }
        try
        {
            _hints = MemoryHints.Read(_hintsPath);
        }
        catch (InvalidDataException exception) { Unreadable(exception); }
        catch (System.Text.Json.JsonException exception) { Unreadable(exception); }
        catch (IOException exception) { Unreadable(exception); }
        catch (InvalidOperationException exception) { Unreadable(exception); }
        catch (FormatException exception) { Unreadable(exception); }
        catch (OverflowException exception) { Unreadable(exception); }
    }

    // Says why the hints file could not be read; marks then start a new one there.
    private void Unreadable(Exception exception) => Notify("output", new JsonObject
    {
        ["category"] = "console",
        ["output"] = $"The hints file {_hintsPath} could not be read, so it starts empty: {exception.Message}\n"
    });

    /// <summary>
    ///  Answers retro/memory/mark: marks a range as code, data or neither, or names or comments on an address, and
    ///  writes the hints file.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   One of <c>kind</c> (<c>code</c>, <c>data</c> or <c>clear</c>, for <c>count</c> bytes from <c>address</c>),
    ///   <c>name</c> or <c>comment</c>; an empty name or comment takes it away. The answer gives the file's
    ///   <c>path</c>.
    ///  </para>
    /// </remarks>
    private JsonObject MemoryMark(JsonObject args)
    {
        MemoryReference(Required(args, "memoryReference"), out DebugMemoryBank? bank);
        int address = args.Int("address") ?? throw new ArgumentException("address is required.");
        int count = args.Int("count") ?? 1;
        if (address is < 0 or > 0xFFFF || count < 1 || address + count > 0x10000)
        {
            throw new ArgumentOutOfRangeException(nameof(args), "A mark covers 1 or more bytes in $0000-$FFFF.");
        }

        string path = _hintsPath ?? throw new InvalidOperationException(
            "This launch has no program or source to keep marks beside; name a file with the launch's hints setting.");

        string space = HintSpace(bank);
        if (args.String("kind") is { } kind) { _hints.Mark(space, address, count, kind); }
        else if (args["name"] is not null) { _hints.Name(space, address, (args.String("name") ?? "").Trim()); }
        else if (args["comment"] is not null) { _hints.Comment(space, address, (args.String("comment") ?? "").Trim()); }
        else { throw new ArgumentException("A mark gives kind, name or comment."); }

        _hints.Write(path);
        return new JsonObject { ["path"] = path };
    }
}
