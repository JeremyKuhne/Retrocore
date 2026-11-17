// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Media;
using System.Runtime.CompilerServices;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

// The disks the host keeps out of their drives: the last one a person discarded or reverted in each drive, for Undo,
// and the changed ones the machine ejected, each until it is saved, put back or let go. They live as long as the
// session's devices do; the recovery journal keeps them past it (the media persistence plan's fourth phase).
internal static partial class MediaActions
{
    // The disk each drive's Undo puts back.
    private static readonly ConditionalWeakTable<IDevice, KeptDisk> s_undo = [];

    // The changed disks the machine ejected from each drive, oldest first.
    private static readonly ConditionalWeakTable<IDevice, List<KeptDisk>> s_ejected = [];

    /// <summary>
    ///  Gets the disk a drive's Undo puts back, if any.
    /// </summary>
    /// <param name="device">The drive.</param>
    /// <returns>The disk, or null.</returns>
    internal static KeptDisk? Undoable(IDevice device) => s_undo.TryGetValue(device, out KeptDisk? kept) ? kept : null;

    /// <summary>
    ///  Gets the changed disks the machine ejected from a drive, taking in those it ejected since last asked.
    /// </summary>
    /// <param name="device">The drive.</param>
    /// <returns>The disks, oldest first.</returns>
    /// <remarks>
    ///  <para>
    ///   A drive's ejected disks go with it, so a card with one changed is not taken out until each is saved or let go
    ///   (<see cref="Detach"/>).
    ///  </para>
    /// </remarks>
    internal static IReadOnlyList<KeptDisk> Ejected(IDevice device)
    {
        List<KeptDisk> kept = s_ejected.GetValue(device, _ => []);
        if (device is IEjectingSlot slot)
        {
            foreach (EjectedMedium ejected in slot.TakeEjected())
            {
                // An unchanged disk is its image, so nothing is lost when it goes.
                if (ejected.Medium.IsDirty) { kept.Add(new(ejected.Medium, ejected.Label, ejected.Format, "ejected")); }
            }
        }

        return kept;
    }

    // Reads the drive's image again in place of its disk, through the machine's own insert, and keeps the disk it
    // replaces for Undo when it had changes. A bad image leaves the disk where it was, as an insert does.
    private static JsonObject Revert(IDevice device, Action<string, JsonObject> machine)
    {
        IMediumSlot drive = device as IMediumSlot ?? throw new ArgumentException($"{device.Info.Name} holds no medium to revert.");
        IMedium disk = drive.Medium ?? throw new InvalidOperationException($"{device.Info.Name} is empty.");
        if (Source(disk) is not { } source || device.Media is not { } media)
        {
            throw new InvalidOperationException($"The disk in {device.Info.Name} has no image to revert to.");
        }

        KeptDisk kept = new(disk, media.Label, media.Format, "reverted");
        machine("insert", new JsonObject { ["path"] = source.Path });
        if (disk.IsDirty) { s_undo.AddOrUpdate(device, kept); }
        JsonObject answer = Answer(device, "reverted", Source(drive.Medium ?? disk));
        answer["undo"] = disk.IsDirty ? kept.Id : null;
        return answer;
    }

    // Answers changed for the first changed disk the machine ejected from a card's drives that is not let go, as it
    // would go with the card; discards lets one go by its drive and ejected id.
    private static JsonObject? HoldEjected(IEnumerable<IDevice> card, JsonObject args)
    {
        if (args.Bool("discard") == true) { return null; }
        JsonArray discards = args.Array("discards") ?? [];
        foreach (IDevice device in card)
        {
            foreach (KeptDisk kept in Ejected(device).Where(kept => kept.Medium.IsDirty))
            {
                if (discards.Any(entry => entry.String("device") == device.Id && entry.String("ejected") == kept.Id))
                {
                    continue;
                }

                if (args["supportsRetrocoreMedia"] is null)
                {
                    throw new InvalidOperationException(
                        $"The machine ejected a disk from {device.Info.Name} with changes not saved. Save it first, or remove its card with discard: true.");
                }

                // No mount generation: an answer about an ejected disk lets go of that disk alone, never the drive's.
                JsonObject answer = Answer(device, "changed", Source(kept.Medium));
                answer["generation"] = null;
                answer["label"] = kept.Label;
                answer["ejected"] = kept.Id;
                return answer;
            }
        }

        return null;
    }

    // The changed disk in a drive that a person let go of, to keep for Undo once it has left; null for none.
    private static KeptDisk? Outgoing(IDevice device) =>
        device is IMediumSlot { Medium: { } disk } && device.Media is { } media && HasUnsaved(device)
            ? new(disk, media.Label, media.Format, "discarded")
            : null;

    // An eject or insert that lets a changed disk go: the machine acts, and only once it has does the disk become the
    // one Undo puts back, so a failed insert leaves both the disk and the Undo there was. With no machine to act (a
    // caller that acts itself), nothing is kept, as nothing says the action went through.
    private static JsonObject? Discard(IDevice device, string action, JsonObject args, Action<string, JsonObject>? machine)
    {
        if (machine is null || Outgoing(device) is not { } outgoing) { return null; }

        machine(action, args);
        s_undo.AddOrUpdate(device, outgoing);
        JsonObject answer = Answer(device, "discarded", Source(outgoing.Medium));
        answer["undo"] = outgoing.Id;
        return answer;
    }

    // Puts a kept disk in its drive in place of the one there, which, if it was changed and let go, becomes the one
    // Undo puts back; the answer names that Undo, or none.
    private static JsonObject Replace(IDevice device, KeptDisk kept, string outcome)
    {
        KeptDisk? outgoing = Outgoing(device);
        IMediumSlot drive = (IMediumSlot)device;
        drive.Unmount();
        drive.Mount(kept.Medium, kept.Label, kept.Format);
        // The Undo goes only when it is the disk put back: Insert Again leaves another disk's Undo where it was.
        if (outgoing is null)
        {
            if (Undoable(device)?.Id == kept.Id) { s_undo.Remove(device); }
        }
        else
        {
            s_undo.AddOrUpdate(device, outgoing);
        }

        JsonObject answer = Answer(device, outcome, Source(kept.Medium));
        answer["undo"] = outgoing?.Id;
        return answer;
    }

    // Puts back the disk the last revert or discard dropped: in the drive, the disk there going as an eject would, or
    // among the drive's ejected disks for one that was ejected.
    private static JsonObject Undo(IDevice device, JsonObject args)
    {
        if (Undoable(device) is not { } kept || kept.Id != args.String("medium"))
        {
            throw new InvalidOperationException($"There is nothing to undo in {device.Info.Name}.");
        }

        if (kept.Why == "discardedEjected")
        {
            s_undo.Remove(device);
            s_ejected.GetValue(device, _ => []).Add(kept with { Why = "ejected" });
            return Answer(device, "undone", Source(kept.Medium));
        }

        return Detach([device], args, "put the disk back") ?? Replace(device, kept, "undone");
    }

    // Acts on a disk the machine ejected: saves it, puts it back in its drive (the disk there going as an eject
    // would), or lets it go, which Undo can put back.
    private static JsonObject Kept(IDevice device, string id, string action, JsonObject args)
    {
        List<KeptDisk> ejected = s_ejected.GetValue(device, _ => []);
        KeptDisk kept = ejected.FirstOrDefault(candidate => candidate.Id == id)
            ?? throw new InvalidOperationException($"{device.Info.Name} has no ejected disk {id}; it was put back or let go.");

        JsonObject answer;
        switch (action)
        {
            case "save":
                answer = Save(device, kept.Medium, args, () => ejected.Contains(kept), (label, format, whole) =>
                {
                    kept.Label = label;
                    kept.Format = format;
                    if (whole) { ejected.Remove(kept); }
                });

                break;
            case "insertAgain":
                if (Detach([device], args, "put the ejected disk back") is { } held) { return held; }
                answer = Replace(device, kept, "inserted");
                ejected.Remove(kept);
                break;
            case "discard":
                ejected.Remove(kept);
                s_undo.AddOrUpdate(device, kept with { Why = "discardedEjected" });
                answer = Answer(device, "discarded", Source(kept.Medium));
                answer["undo"] = Undoable(device)?.Id;
                break;
            default:
                throw new ArgumentException($"An ejected disk can be saved, put back or let go, not {action}.");
        }

        answer["ejected"] = id;
        return answer;
    }
}
