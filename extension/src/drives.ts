// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// What the Drives view shows of a drive, without VS Code: its picture and lock badge, the mark at the row's end
// (changed, stale or both), its summary and tooltip, the words its menus pick actions by, and the words of the
// questions a save asks. The media persistence plan's "UI workflow" draws each of them.

import * as path from "node:path";

/** A revision of an image file, as the debug host gives it. */
export interface Revision { length: number; written: string; sha256: string }

/** Where a drive's disk came from: an image file, or built by the launch. */
export interface MediaSource {
    kind: "image" | "built";
    path?: string;
    /** Whether the image's own format can be written back. */
    saves: boolean;
    /** Why the image cannot be saved over: format, an image that can only be read; file, a read-only file. */
    readOnly?: "format" | "file" | null;
    /** Whether the file changed or went since the disk matched it. */
    stale?: boolean;
    /** While stale, the revision the disk matches. */
    baseline?: Revision | null;
    /** While stale, the revision there now, or null when the file is gone. */
    current?: Revision | null;
}

/** A drive's media as retro/devices gives it. */
export interface Media {
    label: string;
    format: string;
    writeProtected: boolean;
    changed: boolean;
    generation?: number;
    medium?: string;
    version?: number;
    source?: MediaSource;
}

/** A device as the debug host's retro/devices describes it. */
export interface Device {
    id: string;
    kind: "floppyDrive" | "tapeDrive" | "blockStorage";
    name: string;
    description: string;
    controller: string;
    formats: string[];
    saveFormats?: string[];
    operations: ("insert" | "eject" | "record" | "writeProtect" | "save")[];
    tracks: number;
    sides: number;
    media: Media | null;
    activity: "idle" | "seeking" | "reading" | "writing";
    head?: { motor: boolean; selected: boolean; track: number; side: number; sector: number | null };
    transport?: { motor: boolean; mode: "stopped" | "playing" | "recording"; position: number; length: number };
    blocks?: { count: number; last: number | null };
}

/** The picture a drive is drawn with. */
export type Form = "floppy525" | "floppy35" | "hardDisk" | "tape";

/** The picture for a kind of drive: a 3.5-inch drive is a floppy drive that takes 3.5-inch images. */
export function form(device: Device): Form {
    if (device.kind === "tapeDrive") return "tape";
    if (device.kind === "blockStorage") return "hardDisk";
    return device.formats.includes("2mg") || device.formats.includes("hdv") ? "floppy35" : "floppy525";
}

/**
 * The icon's name: its picture, then for a disk its lock, then what it is doing, which colours the badge (a tape, with
 * no badge, takes the colour itself); "empty" for a drive with nothing in it.
 */
export function iconName(device: Device): string {
    const picture = form(device);
    if (device.media === null) return `${picture}-empty`;
    if (picture === "tape") return `tape-${device.activity}`;
    return `${picture}-${device.media.writeProtected ? "locked" : "unlocked"}-${device.activity}`;
}

/** Whether a drive's disk can be saved to an image: it saves, and holds a disk. */
export const saves = (device: Device): boolean => device.media !== null && device.operations.includes("save");

/** Whether the disk's own image changed or went since the disk matched it. */
export const isStale = (device: Device): boolean => device.media?.source?.stale === true;

/** Whether Save cannot write the disk's own image, so it saves as another: built, read-only or only readable. */
export function isReadOnlyImage(device: Device): boolean {
    const source = device.media?.source;
    return source !== undefined && (source.kind !== "image" || !source.saves || (source.readOnly ?? null) !== null);
}

/**
 * The mark at the row's end, as Git marks a file: changed, a disk with changes not saved; stale, its image changed on
 * disk; conflict, both.
 */
export function mark(device: Device): "changed" | "stale" | "conflict" | undefined {
    if (!saves(device)) return undefined;
    const changed = device.media?.changed === true;
    const stale = isStale(device);
    return changed && stale ? "conflict" : changed ? "changed" : stale ? "stale" : undefined;
}

/** What the image's state says in a summary, if anything: read-only, changed on disk or deleted. */
function imageState(device: Device): string | undefined {
    const source = device.media?.source;
    if (source === undefined || !saves(device)) return undefined;
    if (source.stale) return source.current === null ? "image deleted" : "image changed on disk";
    if (source.kind === "image" && isReadOnlyImage(device)) return "read-only image";
    return undefined;
}

/** The one-line summary after a device's name: its media, where it is, the image's state and what it is doing. */
export function summary(device: Device): string {
    const parts: string[] = [device.media ? path.basename(device.media.label) || device.media.format : "empty"];
    if (device.head) {
        const track = Number.isInteger(device.head.track) ? String(device.head.track) : device.head.track.toFixed(2);
        parts.push(`track ${track}` + (device.sides > 1 ? ` side ${device.head.side}` : "")
            + (device.head.sector !== null ? ` sector ${device.head.sector}` : ""));
    }
    if (device.transport && device.media) parts.push(`${device.transport.position.toLocaleString()} of ${device.transport.length.toLocaleString()} bytes`);
    if (device.blocks?.last !== null && device.blocks?.last !== undefined) parts.push(`block ${device.blocks.last}`);
    const state = imageState(device);
    if (state !== undefined) parts.push(state);
    if (device.activity !== "idle") parts.push(device.activity);
    else if (device.head?.motor || device.transport?.motor) parts.push("motor on");
    return parts.join(" · ");
}

/** A time a file was written, as a person reads it: 10:52 today, or the date and time. */
export function when(written: string, now: Date = new Date()): string {
    const time = new Date(written);
    if (Number.isNaN(time.getTime())) return written;
    const clock = time.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
    return time.toDateString() === now.toDateString() ? `${clock} today` : `${time.toLocaleDateString()} ${clock}`;
}

/** The lock, as the tooltip and the details say it. */
export const lockState = (media: Media): string => media.writeProtected
    ? "Locked: the machine cannot write it"
    : "Unlocked: the machine can write it";

/** What the drive is doing, as the tooltip's last line says it, such as Track 17, sector 4, writing. */
function position(device: Device): string | undefined {
    const parts: string[] = [];
    if (device.head && device.media) {
        parts.push(`Track ${device.head.track}` + (device.sides > 1 ? `, side ${device.head.side}` : "")
            + (device.head.sector !== null ? `, sector ${device.head.sector}` : ""));
    }
    if (device.blocks?.last !== null && device.blocks?.last !== undefined) parts.push(`Block ${device.blocks.last}`);
    if (device.transport && device.media) {
        parts.push(`${device.transport.position.toLocaleString()} of ${device.transport.length.toLocaleString()} bytes, ${device.transport.mode}`);
    }
    if (device.activity !== "idle") parts.push(device.activity);
    else if (device.head?.motor || device.transport?.motor) parts.push("motor on");
    return parts.length === 0 ? undefined : parts.join(", ");
}

/** The tooltip's lines after the drive's name: the disk and its image, changed, stale, read-only, lock and where. */
export function tooltipLines(device: Device, now: Date = new Date()): string[] {
    const media = device.media;
    if (media === null) return ["Empty"];
    const source = media.source;
    const lines = [source?.path !== undefined ? `${path.basename(media.label)} (${media.format}), ${source.path}` : `${media.label} (${media.format})`];
    if (saves(device)) {
        lines.push(source?.kind === "built" ? (media.changed ? "Changed: built by the launch, and not saved anywhere" : "Built by the launch")
            : media.changed ? "Changed: not saved to the image"
            // A disk the machine did not change is the image as it was read, which is not the file there now.
            : source?.stale ? (source.current === null ? "Not changed by the machine; its image is gone" : "Not changed by the machine, but its image is not the file it was read from")
            : "The same as its image");
        if (source?.stale) {
            const read = source.baseline ? `; it was ${when(source.baseline.written, now)} when read` : "";
            lines.push(source.current === null ? "Image deleted since it was read"
                : `Image changed on disk: ${source.current ? when(source.current.written, now) : "since it was read"}${read}`);
        }
        if (source?.readOnly === "file") lines.push("Read-only file: Save As saves the disk under another name");
        else if (source?.readOnly === "format" || (source?.kind === "image" && !source.saves)) lines.push(`${media.format} can only be read: Save As saves the disk as another image`);
    }
    if (device.operations.includes("writeProtect") || form(device) !== "tape") lines.push(lockState(media));
    const where = position(device);
    if (where !== undefined) lines.push(where[0].toUpperCase() + where.slice(1));
    return lines;
}

/**
 * The words the drive's menus pick their actions by. While the machine is off, a tape cannot record and nothing has
 * changed a disk to save.
 */
export function contextWords(device: Device, running: boolean): string[] {
    const words = ["device", device.media ? "loaded" : "empty"];
    if (device.operations.includes("insert")) words.push("insert");
    if (running && device.operations.includes("record")) words.push("record");
    if (device.media && device.operations.includes("eject")) words.push("eject");
    if (device.media && device.operations.includes("writeProtect")) words.push(device.media.writeProtected ? "locked" : "unlocked");
    if (running && saves(device)) {
        words.push("save");
        // Save writes the disk's own image at once; for a read-only image it saves as another, and for an image changed
        // on disk, as a disk the same as its image may have, it says first that it will ask.
        if (device.media?.changed || isStale(device)) {
            words.push(isReadOnlyImage(device) ? "changedReadOnly" : isStale(device) ? "changedStale" : "changed");
        }
    }
    return words;
}

/** The format that holds all of a drive's disk, which a lossy save offers instead: WOZ, DMK or 2MG. */
export function lossless(device: Device | undefined): string | undefined {
    const formats = device?.saveFormats ?? [];
    return ["woz", "dmk", "2mg"].find(format => formats.includes(format));
}

/** A question a save asks: its message, the detail under it, and its buttons, the first the one most asked for. */
export interface Question { message: string; detail: string; buttons: string[] }

/** Asks about a format that cannot hold all of the disk. */
export function lossyQuestion(file: string, drive: string, format: string, losses: string[], keeps: string | undefined): Question {
    const keep = keeps === undefined ? "" : `A .${keeps} keeps all of it. `;
    return {
        message: `${file} can't hold the disk in ${drive} as it is`,
        detail: `${format} would lose:\n${losses.map(loss => `• ${loss}`).join("\n")}\n\n${keep}`
            + `Saving anyway writes what ${format} holds, and the disk stays marked changed.`,
        buttons: [...keeps === undefined ? [] : [`Save as ${keeps.toUpperCase()}...`], "Save Anyway"]
    };
}

/** Asks about an image that changed or went since the disk matched it, or since the person chose it. */
export function conflictQuestion(file: string, drive: string, baseline: Revision | null | undefined, current: Revision | null | undefined,
    now: Date = new Date()): Question {
    if (!current) {
        return {
            message: `${file} was deleted after ${drive} read it`,
            detail: "Saving writes the disk there again.",
            buttons: ["Save There Again", "Save As..."]
        };
    }
    if (!baseline) {
        return {
            message: `${file} changed since you chose it`,
            detail: `The file changed at ${when(current.written, now)}. Replacing it keeps what it held as a backup.`,
            buttons: ["Replace", "Save As..."]
        };
    }
    return {
        message: `${file} changed on disk after ${drive} read it`,
        detail: `The file changed at ${when(current.written, now)}; it was ${when(baseline.written, now)} when read. `
            + "Overwriting replaces the file's changes; they are kept as a backup.",
        buttons: ["Overwrite", "Save As..."]
    };
}

/** Says why a disk cannot be saved where it was asked, and what can be done instead. */
export function readOnlyQuestion(file: string | undefined, drive: string, format: string | undefined,
    reason: "noImage" | "format" | "file" | "access" | undefined): Question {
    switch (reason) {
        case "file":
            return {
                message: `${file ?? "The image"} is a read-only file`,
                detail: `Save the disk in ${drive} under another name, or make the file writable and save over it.`,
                buttons: ["Save As...", "Make Writable and Save"]
            };
        case "format":
            return {
                message: `${file ?? "The image"} is ${format ?? "an image"} Retrocore can only read`,
                detail: `Save the disk in ${drive} as another image.`,
                buttons: ["Save As..."]
            };
        case "noImage":
            return {
                message: `The disk in ${drive} has no image of its own`,
                detail: "Save it as an image to keep it.",
                buttons: ["Save As..."]
            };
        default:
            return {
                message: `${file ?? "The image"} can't be written`,
                detail: `Save the disk in ${drive} somewhere else.`,
                buttons: ["Save As..."]
            };
    }
}

/** What the status bar says for a moment after a save that asked nothing. */
export function savedMessage(file: string, drive: string, backup: boolean): string {
    return `$(check) Saved ${file} from ${drive}${backup ? "; the version it replaced is kept" : ""}`;
}

/** A drive's icon as an SVG, light or dark: its picture, and a disk's padlock badge in its activity's colour. */
export function iconSvg(name: string, dark: boolean): string {
    const [picture, ...rest] = name.split("-");
    const empty = rest[0] === "empty";
    const activity = picture === "tape" ? rest[0] : rest[1];
    const foreground = empty ? (dark ? "#6F6F6F" : "#A0A0A0") : dark ? "#C5C5C5" : "#424242";
    const colours: Record<string, [string, string]> = {
        reading: ["#388A34", "#89D185"], writing: ["#E51400", "#F48771"], seeking: ["#BF8803", "#CCA700"]
    };
    const lit = colours[activity ?? ""]?.[dark ? 1 : 0];
    const stroke = picture === "tape" && lit !== undefined ? lit : foreground;
    const shapes: Record<string, string> = {
        // A 5.25-inch disk: its jacket, hub hole and head window.
        floppy525: `<rect x="1.5" y="1.5" width="11" height="11" rx="0.5"/><circle cx="7" cy="7" r="2"/><path d="M6 10v2.5M8 10v2.5"/>`,
        // A 3.5-inch disk: its case with a cut corner, shutter and label.
        floppy35: `<path d="M1.5 1.5h9l2 2v9h-11z"/><path d="M4 1.5v3.5h5v-3.5M3.5 12.5v-4h7v4"/>`,
        // A hard disk: a stack of platters.
        hardDisk: `<ellipse cx="7" cy="3.5" rx="5.5" ry="2"/><path d="M1.5 3.5v7c0 1.1 2.5 2 5.5 2s5.5-.9 5.5-2v-7M1.5 7c0 1.1 2.5 2 5.5 2s5.5-.9 5.5-2"/>`,
        // A cassette: its shell, two reels and the tape window.
        tape: `<rect x="1.5" y="3.5" width="13" height="9" rx="1"/><circle cx="5.5" cy="7.5" r="1.5"/><circle cx="10.5" cy="7.5" r="1.5"/><path d="M4 12.5l1-2h6l1 2"/>`
    };
    const body = `<g fill="none" stroke="${stroke}" stroke-width="1">${shapes[picture] ?? shapes.floppy525}</g>`;
    let badge = "";
    if (!empty && picture !== "tape") {
        const colour = lit ?? foreground;
        const background = dark ? "#252526" : "#FFFFFF";
        // The padlock in the bottom-right corner: its body, and its shackle closed or swung open.
        const shackle = rest[0] === "locked" ? "M10 10.5v-1.5a1.75 1.75 0 0 1 3.5 0v1.5" : "M10 10.5v-1.5a1.75 1.75 0 0 1 3.5 0";
        badge = `<rect x="8" y="9" width="8" height="7" fill="${background}"/>`
            + `<path d="${shackle}" fill="none" stroke="${colour}" stroke-width="1.2"/>`
            + `<rect x="9" y="10.5" width="5.5" height="4.5" rx="0.5" fill="${colour}"/>`;
    }
    return `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">${body}${badge}</svg>`;
}

/** Every icon name, so they can be written out ahead of use. */
export function iconNames(): string[] {
    const activities = ["idle", "seeking", "reading", "writing"];
    const names: string[] = [];
    for (const picture of ["floppy525", "floppy35", "hardDisk"]) {
        names.push(`${picture}-empty`);
        for (const lock of ["locked", "unlocked"]) for (const activity of activities) names.push(`${picture}-${lock}-${activity}`);
    }
    names.push("tape-empty", ...activities.map(activity => `tape-${activity}`));
    return names;
}
