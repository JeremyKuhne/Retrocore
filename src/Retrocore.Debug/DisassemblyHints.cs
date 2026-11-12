// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Assembler;

namespace Retrocore.Debug;

/// <summary>
///  What a person or agent knows about a program that following its code does not show, for
///  <see cref="DisassembleCommand"/>.
/// </summary>
/// <remarks>
///  <para>
///   A JSON file, each address a string such as <c>"$0812"</c> or a number:
///  </para>
///  <code>
///  {
///    "entries": ["$0A10"],
///    "data": [{ "start": "$0F00", "end": "$0F3F" }, { "start": "$0E00", "length": 16 }],
///    "names": { "$0812": "ReadImage", "$F0": "Pointer" },
///    "comments": { "$0812": "Reads the master image." },
///    "noReturn": ["$0900"],
///    "inline": { "$0950": 2, "$0960": "zero" }
///  }
///  </code>
///  <para>
///   <c>entries</c> are more places code starts. <c>data</c> ranges, their ends included, are never code.
///   <c>names</c> inside the program are labels and outside it equates, and win over the sources' names.
///   <c>comments</c> go above their address. <c>noReturn</c> subroutines never return to their caller, and
///   <c>inline</c> ones are followed by that many bytes, or by a zero-terminated string, before execution goes on.
///  </para>
/// </remarks>
internal sealed class DisassemblyHints
{
    /// <summary>
    ///  Gets the places code starts, besides the program's first byte.
    /// </summary>
    internal List<ushort> Entries { get; } = [];

    /// <summary>
    ///  Gets the ranges that are data: each one's first address and length.
    /// </summary>
    internal List<(ushort Start, int Length)> Data { get; } = [];

    /// <summary>
    ///  Gets the names: labels inside the program, equates outside it.
    /// </summary>
    internal Dictionary<ushort, string> Names { get; } = [];

    /// <summary>
    ///  Gets the comments, each above its address.
    /// </summary>
    internal Dictionary<ushort, string> Comments { get; } = [];

    /// <summary>
    ///  Gets the subroutines that do not return, or take bytes after their JSR.
    /// </summary>
    internal Dictionary<ushort, AnalysisCall> Calls { get; } = [];

    /// <summary>
    ///  Reads a hints file.
    /// </summary>
    /// <param name="path">The file.</param>
    /// <returns>The hints.</returns>
    /// <exception cref="InvalidDataException">The file is not hints.</exception>
    internal static DisassemblyHints Read(string path)
    {
        JsonObject root = JsonNode.Parse(File.ReadAllText(path)) as JsonObject
            ?? throw new InvalidDataException($"{path} is not a JSON object.");

        DisassemblyHints hints = new();
        foreach (JsonNode? entry in root["entries"] as JsonArray ?? [])
        {
            hints.Entries.Add(Address(entry));
        }

        foreach (JsonObject range in (root["data"] as JsonArray ?? []).OfType<JsonObject>())
        {
            ushort start = Address(range["start"]);
            int length = range["length"] is { } count ? count.GetValue<int>() : Address(range["end"]) - start + 1;
            if (length <= 0) { throw new InvalidDataException($"The data range at ${start:X4} is empty."); }
            hints.Data.Add((start, length));
        }

        foreach ((string key, JsonNode? value) in root["names"] as JsonObject ?? [])
        {
            hints.Names[Address(key)] = Text(value);
        }

        foreach ((string key, JsonNode? value) in root["comments"] as JsonObject ?? [])
        {
            hints.Comments[Address(key)] = Text(value);
        }

        foreach (JsonNode? entry in root["noReturn"] as JsonArray ?? [])
        {
            hints.Calls[Address(entry)] = AnalysisCall.NoReturn;
        }

        foreach ((string key, JsonNode? value) in root["inline"] as JsonObject ?? [])
        {
            bool zero = value is JsonValue text && text.TryGetValue(out string? word) && word == "zero";
            hints.Calls[Address(key)] = zero ? AnalysisCall.InlineZeroTerminated : AnalysisCall.InlineBytes(value?.GetValue<int>() ?? 0);
        }

        return hints;
    }

    private static string Text(JsonNode? node) =>
        node?.GetValue<string>() ?? throw new InvalidDataException("A name or comment is empty.");

    private static ushort Address(JsonNode? node)
    {
        if (node is JsonValue value && value.TryGetValue(out int number)) { return checked((ushort)number); }
        return Address(node?.GetValue<string>() ?? throw new InvalidDataException("An address is missing."));
    }

    private static ushort Address(string text) => checked((ushort)CommandAddress.Parse(text));
}
