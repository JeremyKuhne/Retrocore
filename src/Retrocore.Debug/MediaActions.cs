// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;
using Retrocore.Machines.Devices;
using Retrocore.Media;
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
        s_sources.AddOrUpdate(medium, new DiskSource(Guid.NewGuid(), path, codec, FileRevision.Of(path, bytes)));

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
    /// <param name="args">Its arguments: <c>discard</c> lets a changed disk go.</param>
    /// <returns>The answer when the host acted or the machine must not, or null for the machine to act.</returns>
    /// <exception cref="InvalidOperationException">
    ///  A changed disk would leave its drive and the client does not speak the answers.
    /// </exception>
    internal static JsonObject? Device(IDevice device, string action, JsonObject args)
    {
        if (action == "save" && device is Apple2FloppyDrive drive) { return Save(drive, args); }
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
    /// <param name="args">Its arguments: <c>discard</c> lets the changed disks go.</param>
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
    ///  <c>changed</c> until it is saved or <c>discard</c> is given.
    /// </summary>
    /// <param name="devices">The devices whose media would leave.</param>
    /// <param name="args">The request's arguments: <c>discard</c>, and <c>supportsRetrocoreMedia</c>.</param>
    /// <param name="what">What would take the media out, for a refusal's message, such as <c>eject it</c>.</param>
    /// <returns>The answer for the first changed disk, or null when every disk can go.</returns>
    /// <exception cref="InvalidOperationException">
    ///  A changed disk would leave its drive and the client does not speak the answers.
    /// </exception>
    internal static JsonObject? Detach(IEnumerable<IDevice> devices, JsonObject args, string what)
    {
        if (args.Bool("discard") == true || devices.FirstOrDefault(HasUnsaved) is not { } device) { return null; }
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
    ///  Saves a Disk II disk: to its own image, in the format and order it was read in, or to <c>path</c> as its
    ///  extension says, taking the save step by step.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The disk is snapshotted, the snapshot encoded, and the encoding written only over the revision of the image
    ///   the disk matches, or the one <c>overwrite</c> names; the save completes only if the drive still holds the
    ///   disk it snapshotted. An unchanged disk saved to its own unchanged image writes nothing, so the file stays
    ///   byte for byte the one it read.
    ///  </para>
    /// </remarks>
    /// <param name="drive">The drive.</param>
    /// <param name="args">
    ///  <c>path</c>, <c>acceptLosses</c> to save though the format cannot hold all of the disk, and <c>overwrite</c>'s
    ///  <c>sha256</c>, the revision of a changed image the user agreed to replace.
    /// </param>
    /// <returns>The answer: <c>saved</c>, <c>losses</c>, <c>conflict</c> or <c>readOnly</c>.</returns>
    /// <exception cref="InvalidOperationException">The drive is empty.</exception>
    /// <exception cref="ArgumentException">The path's format cannot hold a Disk II disk.</exception>
    internal static JsonObject Save(Apple2FloppyDrive drive, JsonObject args)
    {
        WozDisk disk = drive.Disk ?? throw new InvalidOperationException($"{drive.Info.Name} is empty.");
        DiskSource? source = Source(disk);
        if ((args.String("path") ?? source?.Path) is not { } asked) { return ReadOnly(drive, "noImage"); }

        string path = Path.GetFullPath(asked);
        DiskSource? mine = source is not null && SameFile(path, source.Path) ? source : null;
        IImageCodec? codec = mine is not null ? mine.Codec : DiskIIImage.CodecFor(Path.GetExtension(path));
        if (codec is null)
        {
            return mine is not null
                ? ReadOnly(drive, "format")
                : throw new ArgumentException($"{Path.GetFileName(path)} is not a .woz, .dsk, .do or .po image; save it as .woz.");
        }

        // An unchanged disk saved to its own image as it was read writes nothing.
        if (mine is not null && drive.Media?.Changed != true && mine.Baseline.SameAs(FileRevision.Read(path)))
        {
            return Answer(drive, "saved", mine);
        }

        // 1. The snapshot, under the machine's lock, which the caller holds; 2. its encoding.
        int generation = drive.MountGeneration;
        EncodedImage encoded = codec.Encode(disk.Snapshot());
        if (!encoded.IsLossless && args.Bool("acceptLosses") != true)
        {
            JsonObject losses = Answer(drive, "losses", source);
            losses["format"] = codec.Format;
            losses["losses"] = encoded.Losses.ToJsonArray();
            return losses;
        }

        // 3. The commit, over the revision the disk matches or the one the user agreed to replace.
        string? authorized = args["overwrite"] is JsonObject overwrite ? overwrite.String("sha256") : null;
        ImageWrite written = ImageWriter.Write(path, encoded.Bytes, mine?.Baseline, authorized);
        switch (written.Outcome)
        {
            case "conflict":
                JsonObject conflict = Answer(drive, "conflict", source);
                conflict["generation"] = generation;
                conflict["baseline"] = source?.Baseline.ToJson();
                conflict["current"] = written.Revision?.ToJson();
                return conflict;
            case "readOnly":
                return ReadOnly(drive, written.Reason ?? "file");
        }

        // 4. Complete, only for the disk the snapshot was taken of: it now comes from the image just written, which a
        // lossy save leaves it changed against.
        DiskSource saved = new(source?.Id ?? Guid.NewGuid(), path, codec, written.Revision ?? FileRevision.Of(path, encoded.Bytes));
        if (ReferenceEquals(drive.Disk, disk) && drive.MountGeneration == generation)
        {
            s_sources.AddOrUpdate(disk, saved);
            drive.Saved(path, codec.Format, encoded.IsLossless);
        }

        JsonObject answer = Answer(drive, "saved", saved);
        if (encoded.Notes.Count != 0) { answer["notes"] = encoded.Notes.ToJsonArray(); }
        if (!encoded.IsLossless) { answer["losses"] = encoded.Losses.ToJsonArray(); }
        if (written.Backup is not null) { answer["backup"] = written.Backup; }
        return answer;
    }

    // An answer about a drive's disk.
    private static JsonObject Answer(Apple2FloppyDrive drive, string outcome, DiskSource? source) => new()
    {
        ["outcome"] = outcome,
        ["device"] = drive.Id,
        ["medium"] = source?.MediumId,
    };

    // The disk cannot be saved where it is asked to be: noImage (a disk no image gave), format (an image that can only
    // be read), file (a read-only file) or access (where it cannot be written). Save as can.
    private static JsonObject ReadOnly(Apple2FloppyDrive drive, string reason)
    {
        JsonObject answer = Answer(drive, "readOnly", drive.Disk is { } disk ? Source(disk) : null);
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
