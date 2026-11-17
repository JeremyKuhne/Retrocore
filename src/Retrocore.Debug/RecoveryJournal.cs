// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

/// <summary>
///  A machine's recovery journal in local data: the changed disks it has not saved, kept past its session so that a
///  stop or a relaunch loses none of them, and put back in their drives the next time the machine starts.
/// </summary>
/// <remarks>
///  <para>
///   It is <c>Recovery\&lt;id&gt;\</c> under <see cref="LocalData.Root"/>: <c>session.json</c> says which process
///   has it and whether that session ended cleanly; <c>Media\</c> holds each disk's snapshots, lossless images (WOZ2,
///   2MG or DMK) numbered and never rewritten; and <c>journal.json</c> names the latest snapshot of each disk with
///   its drive, its image and the image's baseline. A commit writes the snapshots first and <c>journal.json</c>
///   after them, replacing it in one step, so a crash at any point leaves the previous commit whole.
///  </para>
///  <para>
///   A disk it held that cannot go back in its drive, as when the drive is gone, stays in the journal untouched:
///   nothing in it is dropped but by saving or letting go of the disk. A journal that cannot be read is moved aside
///   with its snapshots, into an <c>Unreadable-&lt;time&gt;\</c> folder beside them.
///  </para>
///  <para>
///   One process has a journal at a time: it holds <c>journal.lock</c> open, unshared, from opening the journal to
///   closing it, and the system lets go of it if the process ends without closing.
///  </para>
/// </remarks>
internal sealed partial class RecoveryJournal
{
    private const string SessionFile = "session.json";
    private const string LockFile = "journal.lock";
    private const string JournalFile = "journal.json";
    private const string MediaFolder = "Media";

    private readonly string _folder;

    // Held from opening the journal to closing it, so no other process opens it meanwhile.
    private readonly FileStream _lock;

    // Commits run one at a time, off the machine's thread, and none after the journal is closed.
    private readonly Lock _writing = new();
    private bool _closed;
    private int _next;

    // The snapshot each disk's journaled version is in, so a disk unchanged since it was last kept is not copied again.
    private readonly ConcurrentDictionary<Guid, Written> _written = [];

    // What the journal held when opened that could not go back in a drive, carried into every commit as it was.
    private readonly List<JsonObject> _unplaced = [];

    private readonly DateTime _started = DateTime.UtcNow;

    private RecoveryJournal(string id, string folder, FileStream held, IReadOnlyList<JsonObject> kept, int next)
    {
        Id = id;
        _folder = folder;
        _lock = held;
        Kept = kept;
        _next = next;
    }

    /// <summary>
    ///  Gets the journal's id: the machine's, as its launch gave it.
    /// </summary>
    internal string Id { get; }

    /// <summary>
    ///  Gets the disks the journal held when it was opened, which the launch puts back.
    /// </summary>
    internal IReadOnlyList<JsonObject> Kept { get; }

    /// <summary>
    ///  Gets the folder of the recovery journals, under local data.
    /// </summary>
    internal static string Root => Path.Join(LocalData.Root, "Recovery");

    /// <summary>
    ///  Opens a machine's journal, taking it for this process.
    /// </summary>
    /// <param name="id">The machine's recovery id: letters, digits, <c>-</c> and <c>_</c>, at most 64.</param>
    /// <param name="problems">What it found wrong, such as a journal it could not read, which it set aside.</param>
    /// <returns>The journal; or null when another running session has it.</returns>
    /// <exception cref="ArgumentException">The id is not one.</exception>
    /// <exception cref="IOException">Local data cannot be written.</exception>
    /// <exception cref="UnauthorizedAccessException">Local data cannot be written.</exception>
    internal static RecoveryJournal? Open(string id, List<string> problems)
    {
        if (id.Length is 0 or > 64 || !id.All(character => char.IsAsciiLetterOrDigit(character) || character is '-' or '_'))
        {
            throw new ArgumentException("recoveryId is letters, digits, - and _, at most 64.");
        }

        string folder = Path.Join(Root, id);
        Directory.CreateDirectory(Path.Join(folder, MediaFolder));
        FileStream held;
        try
        {
            held = new(Path.Join(folder, LockFile), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        }
        catch (IOException)
        {
            // Another process, or another session in this one, has it.
            return null;
        }

        try
        {
            RecoveryJournal opened = Read(folder, held, id, problems);
            opened.WriteSession(clean: false);
            return opened;
        }
        catch
        {
            held.Dispose();
            throw;
        }
    }

    // Reads the journal's disks, under its lock.
    private static RecoveryJournal Read(string folder, FileStream held, string id, List<string> problems)
    {
        List<JsonObject> kept = [];
        string journal = Path.Join(folder, JournalFile);
        if (File.Exists(journal))
        {
            try
            {
                kept.AddRange((Read(journal)?["disks"] as JsonArray ?? []).OfType<JsonObject>().Select(disk => (JsonObject)disk.DeepClone()));
            }
            catch (JsonException exception)
            {
                // Set aside with its snapshots, never deleted, so the commits that follow keep their hands off them.
                string aside = Path.Join(folder, $"Unreadable-{DateTime.UtcNow:yyyyMMddHHmmssfff}");
                Directory.CreateDirectory(aside);
                File.Move(journal, Path.Join(aside, JournalFile));
                Directory.Move(Path.Join(folder, MediaFolder), Path.Join(aside, MediaFolder));
                Directory.CreateDirectory(Path.Join(folder, MediaFolder));
                problems.Add($"The recovery journal could not be read ({exception.Message}); it is kept, with its disks, in {aside}.");
            }
        }

        int next = Directory.EnumerateFiles(Path.Join(folder, MediaFolder))
            .Select(file => Number(Path.GetFileName(file)))
            .DefaultIfEmpty(0)
            .Max() + 1;

        return new(id, folder, held, kept, next);
    }

    /// <summary>
    ///  Gets whether the journal holds a disk's version already, so a checkpoint need not copy the disk again.
    /// </summary>
    /// <param name="medium">The disk's medium id.</param>
    /// <param name="version">Its version now.</param>
    /// <returns>True when that version is kept.</returns>
    internal bool Holds(Guid medium, long version) => _written.TryGetValue(medium, out Written? written) && written.Version == version;

    /// <summary>
    ///  Reads the image a disk the journal held was kept as.
    /// </summary>
    /// <param name="disk">The disk, one of <see cref="Kept"/>.</param>
    /// <returns>The snapshot's image.</returns>
    /// <exception cref="InvalidDataException">The entry names no snapshot.</exception>
    /// <exception cref="IOException">The snapshot cannot be read.</exception>
    internal byte[] Image(JsonObject disk) =>
        File.ReadAllBytes(Path.Join(_folder, MediaFolder, disk.String("file") ?? throw new InvalidDataException("A kept disk names no snapshot.")));

    /// <summary>
    ///  Records that a disk the journal held is back in the machine, as the medium it now is, so the next checkpoint
    ///  keeps the same snapshot until the machine changes it.
    /// </summary>
    /// <param name="disk">The disk, one of <see cref="Kept"/>.</param>
    /// <param name="medium">Its medium id.</param>
    /// <param name="version">The version of the medium it was put back as.</param>
    internal void Placed(JsonObject disk, Guid medium, long version) =>
        _written[medium] = new(version, disk.String("file") ?? "", disk.String("kind") ?? "", disk.Bool("writeProtected") == true);

    /// <summary>
    ///  Records that a disk the journal held could not go back in the machine, so it stays in the journal as it was.
    /// </summary>
    /// <param name="disk">The disk, one of <see cref="Kept"/>.</param>
    internal void Unplaced(JsonObject disk)
    {
        lock (_writing) { _unplaced.Add(disk); }
    }

    /// <summary>
    ///  Commits a checkpoint: each changed disk's snapshot, then the journal naming them, then removes the snapshots no
    ///  longer named.
    /// </summary>
    /// <param name="disks">The changed disks, as <see cref="MediaActions.Journal"/> takes them.</param>
    /// <param name="close">
    ///  Whether this is the last commit, as the session ends cleanly: the journal is closed with it, so no checkpoint
    ///  still being written can follow it with older disks.
    /// </param>
    /// <exception cref="IOException">A file could not be written; the previous commit stands.</exception>
    /// <exception cref="UnauthorizedAccessException">Likewise.</exception>
    internal void Commit(IReadOnlyList<JournalDisk> disks, bool close = false)
    {
        lock (_writing)
        {
            if (_closed) { return; }
            if (close) { _closed = true; }
            JsonArray entries = [];
            foreach (JournalDisk disk in disks)
            {
                Written? written;
                if (disk.Snapshot is { } snapshot)
                {
                    string file = $"{disk.Medium:N}-{_next++}.{Extension(snapshot.Kind)}";
                    WriteDurably(Path.Join(_folder, MediaFolder, file), snapshot.Image.Span);
                    written = new(disk.Version, file, snapshot.Kind, snapshot.WriteProtected);
                    _written[disk.Medium] = written;
                }
                else if (!_written.TryGetValue(disk.Medium, out written))
                {
                    continue;
                }

                JsonObject entry = (JsonObject)disk.Entry.DeepClone();
                entry["medium"] = $"{disk.Medium:N}";
                entry["type"] = disk.Type;
                entry["kind"] = written.Kind;
                entry["writeProtected"] = written.WriteProtected;
                entry["file"] = written.File;
                entry["kept"] = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
                entries.Add((JsonNode)entry);
            }

            foreach (JsonObject unplaced in _unplaced) { entries.Add((JsonNode)unplaced.DeepClone()); }

            string temporary = Path.Join(_folder, JournalFile + ".tmp");
            WriteDurably(temporary, Utf8(new JsonObject { ["disks"] = entries }));
            File.Move(temporary, Path.Join(_folder, JournalFile), overwrite: true);

            // Only now is an older snapshot no longer needed; a disk saved or let go leaves the journal with them.
            HashSet<string> named = [.. entries.OfType<JsonObject>().Select(entry => entry.String("file") ?? "")];
            foreach (string file in Directory.EnumerateFiles(Path.Join(_folder, MediaFolder)))
            {
                if (!named.Contains(Path.GetFileName(file))) { TryDelete(file); }
            }

            foreach (Guid gone in _written.Keys.Where(medium => !disks.Any(disk => disk.Medium == medium)).ToList())
            {
                _written.TryRemove(gone, out _);
            }

            // What the last commit holds is the machine's unsaved state, and the journal is free for the next session.
            if (close)
            {
                WriteSession(clean: true);
                _lock.Dispose();
            }
        }
    }

    private void WriteSession(bool clean)
    {
        using Process process = Process.GetCurrentProcess();
        JsonObject session = new()
        {
            ["processId"] = Environment.ProcessId,
            ["processStart"] = process.StartTime.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture),
            ["started"] = _started.ToString("O", CultureInfo.InvariantCulture),
            ["clean"] = clean,
        };

        if (clean) { session["ended"] = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture); }
        string temporary = Path.Join(_folder, SessionFile + ".tmp");
        WriteDurably(temporary, Utf8(session));
        File.Move(temporary, Path.Join(_folder, SessionFile), overwrite: true);
    }

    // A JSON file as people read it, indented.
    private static byte[] Utf8(JsonObject json)
    {
        using MemoryStream stream = new();
        using (Utf8JsonWriter writer = new(stream, new JsonWriterOptions { Indented = true }))
        {
            json.WriteTo(writer);
        }

        return stream.ToArray();
    }

    private static JsonObject? Read(string path) => File.Exists(path) ? JsonNode.Parse(File.ReadAllBytes(path)) as JsonObject : null;

    // A snapshot's number, from its name: <medium>-<number>.<extension>.
    private static int Number(string file)
    {
        string name = Path.GetFileNameWithoutExtension(file);
        int dash = name.LastIndexOf('-');
        return dash >= 0 && int.TryParse(name.AsSpan(dash + 1), NumberStyles.None, CultureInfo.InvariantCulture, out int number) ? number : 0;
    }

    private static string Extension(string kind) => kind switch
    {
        WozDisk.SnapshotKind => "woz",
        TwoImgContainer.SnapshotKind => "2mg",
        _ => kind,
    };

    // Writes a file and flushes it to the disk, so a commit that names it never names a file still in the cache.
    private static void WriteDurably(string path, ReadOnlySpan<byte> bytes)
    {
        using FileStream stream = new(path, FileMode.Create, FileAccess.Write, FileShare.None);
        stream.Write(bytes);
        stream.Flush(flushToDisk: true);
    }

    private static void TryDelete(string file)
    {
        try
        {
            File.Delete(file);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            // The next commit removes it.
        }
    }
}
