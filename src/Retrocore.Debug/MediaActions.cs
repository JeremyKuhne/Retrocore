// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Media;
using Retrocore.Media.Trs80;
using System.Runtime.CompilerServices;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

/// <summary>
///  The host's part in media: where each disk came from, saving one safely, and the one way a changed disk leaves its
///  drive. Every host, the debug adapter and Retrocore Desktop, sends a device's actions and a card's removal through
///  here before the machine acts.
/// </summary>
/// <remarks>
///  <para>
///   The outcomes a person decides on come back as answers rather than errors: <c>saved</c>, <c>changed</c>,
///   <c>conflict</c>, <c>losses</c> and <c>readOnly</c>, each naming its device, and the medium id and mount generation
///   it is about where it has them. A client that speaks them says so with <c>supportsRetrocoreMedia</c> in its
///   request; for one that does not, a changed disk that would leave its drive is refused with a message instead,
///   as the safe default.
///  </para>
///  <para>
///   An answer holds only for the disk it was about: a request that answers one gives that mount's
///   <c>generation</c>, or lists it in <c>discards</c>, so a question left open while another disk went in never
///   saves or lets go of the new one.
///  </para>
/// </remarks>
internal static class MediaActions
{
    // Where each disk read from an image came from, by the disk itself, so it goes when the disk does.
    private static readonly ConditionalWeakTable<IMedium, DiskSource> s_sources = [];

    /// <summary>
    ///  Records where a disk read from an image came from, as it goes in a drive.
    /// </summary>
    /// <param name="medium">The disk.</param>
    /// <param name="path">The image's full path.</param>
    /// <param name="codec">The codec that writes the image back, or null for one that can only be read.</param>
    /// <param name="bytes">The image's bytes, as read.</param>
    internal static void Register(IMedium medium, string path, IImageCodec? codec, ReadOnlySpan<byte> bytes) =>
        Keep(medium, new DiskSource(Guid.NewGuid(), path, codec, FileRevision.Of(path, bytes)));

    /// <summary>
    ///  Occurs when an image a disk came from changes on disk, or is marked read-only or writable, as the device list
    ///  then shows; raised off the machine's thread.
    /// </summary>
    internal static event Action? SourcesChanged;

    /// <summary>
    ///  Checks an image as it is now, for each disk read from it, and says so when any of them sees it differently.
    /// </summary>
    /// <param name="path">The image's full path.</param>
    internal static void Recheck(string path)
    {
        List<DiskSource> sources = [.. s_sources.Select(pair => pair.Value).Where(source => SameFile(path, source.Path))];
        if (sources.Count == 0 || ImageCheck.Of(path) is not { } check) { return; }
        bool changed = false;
        foreach (DiskSource source in sources)
        {
            if (source.Check == check) { continue; }
            source.Check = check;
            changed = true;
        }

        if (changed) { SourcesChanged?.Invoke(); }
    }

    // Keeps where a disk came from, and watches its image.
    private static void Keep(IMedium medium, DiskSource source)
    {
        s_sources.AddOrUpdate(medium, source);
        ImageWatcher.Watch(source.Path, path => s_sources.Any(pair => SameFile(path, pair.Value.Path)), Recheck);
    }

    /// <summary>
    ///  Gets where a disk came from, or null for one no image gave, as a disk a launch built.
    /// </summary>
    /// <param name="medium">The disk.</param>
    /// <returns>Its source, or null.</returns>
    internal static DiskSource? Source(IMedium medium) => s_sources.TryGetValue(medium, out DiskSource? source) ? source : null;

    /// <summary>
    ///  Gets whether a device holds a medium with changes not saved to its image, which leaving the drive would lose.
    /// </summary>
    /// <param name="device">The device.</param>
    /// <returns>True when it does.</returns>
    internal static bool HasUnsaved(IDevice device) =>
        device.Media is { Changed: true } && device.Info.Operations.HasFlag(MediaOperations.Save);

    /// <summary>
    ///  Acts on a device's media where the host has a part: saves a disk, and answers <c>changed</c> before a changed
    ///  disk is ejected or another inserted over it.
    /// </summary>
    /// <param name="device">The device.</param>
    /// <param name="action">The action, such as <c>save</c> or <c>eject</c>.</param>
    /// <param name="args">
    ///  Its arguments: <c>generation</c>, the mount an answer was about, and <c>discards</c> or <c>discard</c>, which
    ///  let changed disks go.
    /// </param>
    /// <returns>The answer when the host acted or the machine must not, or null for the machine to act.</returns>
    /// <exception cref="InvalidOperationException">
    ///  A changed disk would leave its drive and the client does not speak the answers, or the drive holds another
    ///  disk than the <c>generation</c> answered about.
    /// </exception>
    internal static JsonObject? Device(IDevice device, string action, JsonObject args)
    {
        if (args.Int("generation") is { } generation && device is IMediumSlot slot && slot.MountGeneration != generation)
        {
            throw new InvalidOperationException(
                $"Another disk went in {device.Info.Name} since you were asked about it, so nothing was done.");
        }

        if (action == "save" && device.Info.Operations.HasFlag(MediaOperations.Save) && device is IMediumSlot)
        {
            return Unspoken(device, Save(device, args), args);
        }

        return action == "eject" || (action == "insert" && device.Media is not null)
            ? Detach([device], args, action == "eject" ? "eject it" : "insert another disk")
            : null;
    }

    /// <summary>
    ///  Answers <c>changed</c> before a card with a changed disk in one of its drives comes out.
    /// </summary>
    /// <param name="ids">The ids of the devices on the card's row, or null for a row with none.</param>
    /// <param name="devices">The machine's devices.</param>
    /// <param name="action">The action, such as <c>removeCard</c>.</param>
    /// <param name="args">Its arguments: <c>discards</c> or <c>discard</c> lets the changed disks go.</param>
    /// <returns>The answer when the card must not come out yet, or null for the machine to act.</returns>
    /// <exception cref="InvalidOperationException">
    ///  A changed disk would leave its drive and the client does not speak the answers.
    /// </exception>
    internal static JsonObject? Hardware(IReadOnlyCollection<string>? ids, IEnumerable<IDevice> devices, string action, JsonObject args) =>
        action != "removeCard" || ids is null
            ? null
            : Detach(devices.Where(device => ids.Contains(device.Id)), args, "remove its card");

    /// <summary>
    ///  Prepares devices' media to leave their drives: an unchanged disk goes, and a changed one answers
    ///  <c>changed</c> until it is saved or let go.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A changed disk is let go when <c>discards</c> lists its drive and mount, <c>{ device, generation }</c>, as a
    ///   client does for each disk the person chose to discard, so each is asked about in turn and a disk that went in
    ///   since is asked about again. <c>discard: true</c> lets every changed disk go, as a client that does not speak
    ///   the answers is told to send.
    ///  </para>
    /// </remarks>
    /// <param name="devices">The devices whose media would leave.</param>
    /// <param name="args">
    ///  The request's arguments: <c>discards</c> or <c>discard</c>, and <c>supportsRetrocoreMedia</c>.
    /// </param>
    /// <param name="what">What would take the media out, for a refusal's message, such as <c>eject it</c>.</param>
    /// <returns>The answer for the first changed disk not let go, or null when every disk can go.</returns>
    /// <exception cref="InvalidOperationException">
    ///  A changed disk would leave its drive and the client does not speak the answers.
    /// </exception>
    internal static JsonObject? Detach(IEnumerable<IDevice> devices, JsonObject args, string what)
    {
        if (args.Bool("discard") == true) { return null; }
        JsonArray discards = args.Array("discards") ?? [];
        bool Discarded(IDevice candidate) => candidate is IMediumSlot slot
            && discards.Any(entry => entry.String("device") == candidate.Id && entry.Int("generation") == slot.MountGeneration);

        IDevice? device = devices.FirstOrDefault(candidate => HasUnsaved(candidate) && !Discarded(candidate));
        if (device is null) { return null; }
        if (args["supportsRetrocoreMedia"] is null)
        {
            throw new InvalidOperationException(
                $"The disk in {device.Info.Name} has changes not saved to its image. Save it first, or {what} with discard: true.");
        }

        JsonObject answer = new() { ["outcome"] = "changed", ["device"] = device.Id, ["label"] = device.Media?.Label };
        if (device is IMediumSlot { Medium: { } medium } slot)
        {
            answer["medium"] = Source(medium)?.MediumId;
            answer["generation"] = slot.MountGeneration;
        }

        return answer;
    }

    /// <summary>
    ///  Saves a drive's medium, such as a Disk II disk or a ProFile's image: to its own image, in the format (and for a
    ///  sector image, the order) it was read in, or to <c>path</c> as its extension says, taking the save step by step.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The disk is snapshotted, the snapshot encoded, and the encoding written only over the revision of the image
    ///   the disk matches, or the one <c>overwrite</c> names; the save completes only if the drive still holds the
    ///   disk it snapshotted. An unchanged disk saved to its own unchanged image writes nothing, so the file stays
    ///   byte for byte the one it read.
    ///  </para>
    /// </remarks>
    /// <param name="device">The drive, an <see cref="IMediumSlot"/>.</param>
    /// <param name="args">
    ///  <c>path</c>, <c>acceptLosses</c> to save though the format cannot hold all of the disk, and <c>overwrite</c>'s
    ///  <c>sha256</c>, the revision of the file there the user agreed to replace (null for none). Save As to a file
    ///  that is there needs it, as the file the person chose; without it, Save As writes only where there is no file.
    /// </param>
    /// <returns>The answer: <c>saved</c>, <c>losses</c>, <c>conflict</c> or <c>readOnly</c>.</returns>
    /// <exception cref="InvalidOperationException">The drive is empty.</exception>
    /// <exception cref="ArgumentException">The path's format cannot hold the drive's medium.</exception>
    internal static JsonObject Save(IDevice device, JsonObject args)
    {
        IMediumSlot drive = device as IMediumSlot ?? throw new ArgumentException($"{device.Info.Name} holds no medium to save.");
        IMedium disk = drive.Medium ?? throw new InvalidOperationException($"{device.Info.Name} is empty.");
        DiskSource? source = Source(disk);
        if ((args.String("path") ?? source?.Path) is not { } asked) { return ReadOnly(device, "noImage"); }

        string path = Path.GetFullPath(asked);
        DiskSource? mine = source is not null && SameFile(path, source.Path) ? source : null;
        IImageCodec? codec = mine is not null ? mine.Codec : CodecFor(device, disk, Path.GetExtension(path));
        if (codec is null)
        {
            string formats = string.Join(", ", device.Info.SaveFormats.Select(format => "." + format));
            return mine is not null
                ? ReadOnly(device, "format")
                : throw new ArgumentException($"{Path.GetFileName(path)} is not an image {device.Info.Name} saves; save it as {formats}.");
        }

        // An unchanged disk saved to its own image as it was read writes nothing.
        if (mine is not null && device.Media?.Changed != true && mine.Baseline.SameAs(FileRevision.Read(path)))
        {
            return Answer(device, "saved", mine);
        }

        // 1. The snapshot, under the machine's lock, which the caller holds; 2. its encoding.
        int generation = drive.MountGeneration;
        EncodedImage encoded = codec.Encode(disk.Snapshot());
        if (!encoded.IsLossless && args.Bool("acceptLosses") != true)
        {
            JsonObject losses = Answer(device, "losses", source);
            losses["format"] = codec.Format;
            losses["losses"] = encoded.Losses.ToJsonArray();
            return losses;
        }

        // 3. The commit, over the revision the disk matches (for a new image, no file at all) or the one the user agreed
        // to replace.
        Overwrite? authorized = args.Object("overwrite") is { } overwrite ? new(overwrite.String("sha256")) : null;
        ImageWrite written = ImageWriter.Write(path, encoded.Bytes, mine?.Baseline, authorized);
        switch (written.Outcome)
        {
            case "conflict":
                JsonObject conflict = Answer(device, "conflict", source);
                conflict["path"] = path;
                conflict["baseline"] = mine?.Baseline.ToJson();
                conflict["current"] = written.Revision?.ToJson();
                return conflict;
            case "readOnly":
                return ReadOnly(device, written.Reason ?? "file");
        }

        // 4. Complete, only for the disk the snapshot was taken of: it now comes from the image just written, which a
        // lossy save leaves it changed against.
        DiskSource saved = new(source?.Id ?? Guid.NewGuid(), path, codec, written.Revision ?? FileRevision.Of(path, encoded.Bytes));
        if (ReferenceEquals(drive.Medium, disk) && drive.MountGeneration == generation)
        {
            Keep(disk, saved);
            drive.Saved(path, codec.Format, encoded.IsLossless);
        }

        JsonObject answer = Answer(device, "saved", saved);
        if (encoded.Notes.Count != 0) { answer["notes"] = encoded.Notes.ToJsonArray(); }
        if (!encoded.IsLossless) { answer["losses"] = encoded.Losses.ToJsonArray(); }
        if (written.Backup is not null) { answer["backup"] = written.Backup; }
        return answer;
    }

    // A save that did not save is an error for a client that does not speak the answers, which would otherwise take
    // the answer for a save; one that does hears the answer.
    private static JsonObject Unspoken(IDevice device, JsonObject answer, JsonObject args)
    {
        string? outcome = answer.String("outcome");
        if (args["supportsRetrocoreMedia"] is not null || outcome == "saved") { return answer; }
        string name = device.Info.Name;
        throw new InvalidOperationException(outcome switch
        {
            "losses" => $"{answer.String("format")} cannot hold all of the disk in {name}, so it was not saved: "
                + $"{string.Join(" ", (answer.Array("losses") ?? []).Select(loss => loss?.GetValue<string>()))} "
                + "Save it with acceptLosses: true, or in a format that holds it all.",
            "conflict" => $"The image of the disk in {name} is not the one it was read from, so it was not saved. "
                + "Save it with overwrite's sha256 set to the image's now, or with another path.",
            _ => $"The disk in {name} cannot be saved to its image ({answer.String("reason")}). Save it with another path.",
        });
    }

    // The codec that writes a drive's medium as an extension says, among the formats the drive saves: a Disk II disk
    // as WOZ or sectors, a TRS-80 or Color Computer floppy as JV1, JV3, JVC or DMK, a block device as bare blocks or
    // 2MG.
    private static IImageCodec? CodecFor(IDevice device, IMedium medium, string extension)
    {
        bool saves = device.Info.SaveFormats.Contains(extension.TrimStart('.'), StringComparer.OrdinalIgnoreCase);
        if (!saves) { return null; }
        return medium switch
        {
            WozDisk => DiskIIImage.CodecFor(extension),
            FloppyDisk => FloppyImageCodec.For(extension, device.Info.SaveFormats),
            _ => BlockImageCodec.For(extension),
        };
    }

    // An answer about a drive's disk, and the mount it is about.
    private static JsonObject Answer(IDevice device, string outcome, DiskSource? source) => new()
    {
        ["outcome"] = outcome,
        ["device"] = device.Id,
        ["medium"] = source?.MediumId,
        ["generation"] = (device as IMediumSlot)?.MountGeneration,
    };

    // The disk cannot be saved where it is asked to be: noImage (a disk no image gave), format (an image that can only
    // be read), file (a read-only file) or access (where it cannot be written). Save as can.
    private static JsonObject ReadOnly(IDevice device, string reason)
    {
        JsonObject answer = Answer(device, "readOnly", (device as IMediumSlot)?.Medium is { } disk ? Source(disk) : null);
        answer["reason"] = reason;
        return answer;
    }

    // Whether a path names a disk's own image: compared without case where the file system ignores it, as Windows'
    // and macOS's do by default, and with it elsewhere.
    private static bool SameFile(string path, string own) =>
        string.Equals(path, Path.GetFullPath(own), OperatingSystem.IsWindows() || OperatingSystem.IsMacOS()
            ? StringComparison.OrdinalIgnoreCase
            : StringComparison.Ordinal);
}
