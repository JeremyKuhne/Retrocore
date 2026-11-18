// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
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
    ///  Finds the journals whose session did not end cleanly and whose process is gone, holding changed disks.
    /// </summary>
    /// <returns>
    ///  Each one's <c>{ id, name, started, kept, disks }</c>: its recovery id, the machine's name, when the session
    ///  started, when its disks were last kept, and the disks' labels.
    /// </returns>
    internal static JsonArray Unclean()
    {
        JsonArray found = [];
        if (!Directory.Exists(Root)) { return found; }
        foreach (string folder in Directory.EnumerateDirectories(Root))
        {
            string id = Path.GetFileName(folder);
            if (!IsId(id) || Take(folder, GlanceMilliseconds) is not { } held) { continue; }
            using (held)
            {
                try
                {
                    JsonObject? session = Read(Path.Join(folder, SessionFile));
                    JsonArray disks = Read(Path.Join(folder, JournalFile))?["disks"] as JsonArray ?? [];
                    if (session is null || session["clean"] is not JsonValue clean || !clean.TryGetValue(out bool ended) || ended)
                    {
                        continue;
                    }

                    List<JsonObject> entries = [.. disks.OfType<JsonObject>()];
                    if (entries.Count == 0) { continue; }
                    found.Add((JsonNode)new JsonObject
                    {
                        ["id"] = id,
                        ["name"] = Text(session, "name"),
                        ["started"] = Text(session, "started"),
                        ["kept"] = entries.Select(entry => Text(entry, "kept")).Where(kept => kept is not null).Max(StringComparer.Ordinal),
                        ["disks"] = new JsonArray([.. entries.Select(entry => (JsonNode?)(Text(entry, "label") ?? "a disk"))]),
                    });
                }
                catch (Exception exception) when (exception is JsonException or IOException or UnauthorizedAccessException)
                {
                    // A journal that cannot be read now is offered when it can; its next open sets it aside.
                }
            }
        }

        return found;
    }

    /// <summary>
    ///  Decides for a journal whose session did not end cleanly: <c>recover</c> keeps its disks for the machine's next
    ///  launch, and the off machine, and no longer offers them; <c>discard</c> lets them go.
    /// </summary>
    /// <param name="args">
    ///  <c>{ id, action }</c>: the journal's recovery id, and <c>recover</c> or <c>discard</c>.
    /// </param>
    /// <returns>An empty answer.</returns>
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

    // A field's text, or null for none or one that is not text.
    private static string? Text(JsonObject json, string name) =>
        json[name] is JsonValue value && value.TryGetValue(out string? text) ? text : null;
}
