// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

// The journals of sessions that did not end cleanly, which a host finds as it starts, and what a person decides for
// one: recover its disks, which stay for the machine's next launch, or discard them.
internal sealed partial class RecoveryJournal
{
    // How long opening a journal waits for a session that is closing it, as a relaunch's or the off machine's open
    // can come a moment before the last host lets go.
    private const int TakeMilliseconds = 2000;

    // How long finding unclean journals waits for one: long enough for another host that only looks at it, as the off
    // machine and another search do, and short beside a running session, which holds it until it stops.
    private const int GlanceMilliseconds = 500;

    /// <summary>
    ///  Finds the journals whose session did not end cleanly and whose process is gone, holding changed disks; or,
    ///  given an <c>id</c>, that journal as it is now, cleanly ended or not, while it holds disks.
    /// </summary>
    /// <param name="args">Nothing, or <c>{ id }</c>: one journal's recovery id.</param>
    /// <returns>
    ///  Each one's <c>{ id, name, started, kept, disks, tapes, revision }</c>: its recovery id, the machine's name, when
    ///  the session started, when its media were last kept, the labels of its disks and tapes, how many of them are
    ///  tapes, and the journal's revision, which a discard can name so that media kept since are asked about again.
    /// </returns>
    internal static JsonArray Unclean(JsonObject? args = null)
    {
        JsonArray found = [];
        if (!Directory.Exists(Root)) { return found; }
        string? only = args?.String("id");
        IEnumerable<string> folders = only is null ? Directory.EnumerateDirectories(Root) : [FolderOf(only)];
        foreach (string folder in folders)
        {
            string id = Path.GetFileName(folder);
            if (!IsId(id) || !Directory.Exists(folder)) { continue; }
            FileStream? held;
            try
            {
                held = Take(folder, GlanceMilliseconds);
            }
            catch (UnauthorizedAccessException)
            {
                // A journal whose lock cannot be opened is passed over, and the others are still found.
                continue;
            }

            if (held is null) { continue; }
            using (held)
            {
                try
                {
                    if (Offer(folder, id, any: only is not null) is { } offer) { found.Add((JsonNode)offer); }
                }
                catch (Exception exception) when (exception is JsonException or IOException or UnauthorizedAccessException)
                {
                    // A journal that cannot be read now is offered when it can; its next open sets it aside.
                }
            }
        }

        return found;
    }

    // What a journal offers, or null when it holds no disks or, unless any session will do, its session ended cleanly.
    private static JsonObject? Offer(string folder, string id, bool any)
    {
        JsonObject? session = Read(Path.Join(folder, SessionFile));
        JsonArray disks = Read(Path.Join(folder, JournalFile))?["disks"] as JsonArray ?? [];
        if (session is null || session["clean"] is not JsonValue clean || !clean.TryGetValue(out bool ended) || (ended && !any))
        {
            return null;
        }

        List<JsonObject> entries = [.. disks.OfType<JsonObject>()];
        if (entries.Count == 0) { return null; }
        return new JsonObject
        {
            ["id"] = id,
            ["name"] = Text(session, "name"),
            ["started"] = Text(session, "started"),
            ["kept"] = entries.Select(entry => Text(entry, "kept")).Where(kept => kept is not null).Max(StringComparer.Ordinal),
            ["disks"] = new JsonArray([.. entries.Select(entry => (JsonNode?)(Text(entry, "label") ?? "a disk"))]),
            ["tapes"] = entries.Count(entry => MediaActions.IsTape(Text(entry, "type"))),
            ["revision"] = Revision(folder),
        };
    }

    // The journal's revision: a hash of what it says, which every commit changes, or empty for no journal.
    private static string Revision(string folder)
    {
        string path = Path.Join(folder, JournalFile);
        return File.Exists(path) ? Convert.ToHexStringLower(SHA256.HashData(File.ReadAllBytes(path)))[..16] : "";
    }

    /// <summary>
    ///  Decides for a journal whose session did not end cleanly: <c>recover</c> keeps its disks for the machine's next
    ///  launch, and the off machine, and no longer offers them; <c>discard</c> lets them go.
    /// </summary>
    /// <param name="args">
    ///  <c>{ id, action, revision }</c>: the journal's recovery id, <c>recover</c> or <c>discard</c>, and for a
    ///  discard, the revision of the journal the person was asked about, if known.
    /// </param>
    /// <returns>
    ///  An empty answer, or <c>{ outcome: "changed" }</c> when the journal is no longer at the revision a discard named,
    ///  as when the machine ran and kept disks again since, and nothing was let go.
    /// </returns>
    /// <exception cref="ArgumentException">The id or action is not one.</exception>
    /// <exception cref="InvalidOperationException">A running session has the journal.</exception>
    /// <exception cref="IOException">The journal cannot be written.</exception>
    /// <exception cref="UnauthorizedAccessException">Likewise.</exception>
    internal static JsonObject Resolve(JsonObject args)
    {
        string id = args.String("id") ?? throw new ArgumentException("id is required.");
        string action = args.String("action") ?? throw new ArgumentException("action is required: recover or discard.");
        if (action is not ("recover" or "discard"))
        {
            throw new ArgumentException("action must be recover or discard.");
        }

        string folder = FolderOf(id);
        if (!Directory.Exists(folder)) { return []; }
        using FileStream held = Take(folder) ?? throw new InvalidOperationException("A running session has this machine's recovery journal.");
        JsonObject session = Read(Path.Join(folder, SessionFile)) ?? [];
        if (action == "discard" && args.String("revision") is { } revision && revision != Revision(folder))
        {
            return new JsonObject { ["outcome"] = "changed" };
        }

        if (action == "discard" && Read(Path.Join(folder, JournalFile)) is { } journal)
        {
            // The snapshots the journal names, and no other file, then the journal itself.
            foreach (JsonObject entry in (journal["disks"] as JsonArray ?? []).OfType<JsonObject>())
            {
                string file = FileOf(entry);
                if (file.Length != 0 && Path.GetFileName(file) == file)
                {
                    TryDelete(Path.Join(folder, MediaFolder, file));
                }
            }

            File.Delete(Path.Join(folder, JournalFile));
        }

        session["clean"] = true;
        session[action == "recover" ? "recovered" : "discarded"] = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
        string temporary = Path.Join(folder, SessionFile + ".tmp");
        WriteDurably(temporary, Utf8(session));
        File.Move(temporary, Path.Join(folder, SessionFile), overwrite: true);
        return [];
    }

    // A journal's folder, by its id.
    private static string FolderOf(string id) => IsId(id)
        ? Path.Join(Root, id)
        : throw new ArgumentException("recoveryId is letters, digits, - and _, at most 64.");

    private static bool IsId(string id) =>
        id.Length is > 0 and <= 64 && id.All(character => char.IsAsciiLetterOrDigit(character) || character is '-' or '_');

    // Takes a journal's lock, which another process or session may hold; null when it does, after waiting a moment
    // for one that is closing.
    private static FileStream? Take(string folder, int wait = TakeMilliseconds)
    {
        long until = Environment.TickCount64 + wait;
        for (;;)
        {
            try
            {
                return new(Path.Join(folder, LockFile), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            }
            catch (IOException) when (Environment.TickCount64 < until)
            {
                Thread.Sleep(100);
            }
            catch (IOException)
            {
                return null;
            }
        }
    }

    /// <summary>
    ///  Reads a journal field's text, never failing on a field that is something else.
    /// </summary>
    /// <param name="json">The journal's object, such as a disk's entry.</param>
    /// <param name="name">The field.</param>
    /// <returns>Its text, or null for none or one that is not text.</returns>
    internal static string? Text(JsonObject json, string name) =>
        json[name] is JsonValue value && value.TryGetValue(out string? text) ? text : null;
}
