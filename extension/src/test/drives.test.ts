// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import * as path from "node:path";
import { test } from "node:test";
import {
    changeWords, keptSummary, leaveQuestion, revertedMessage, stoppedMessage, unsavedDisks,
    conflictQuestion, contextWords, form, iconName, iconNames, iconSvg, lossless, lossyQuestion, mark, readOnlyQuestion,
    savedMessage, summary, tooltipLines, type Device, type MediaSource
} from "../drives";

// The image's path as this system writes one.
const image = path.resolve(path.sep, "disks", "work.woz");

const revision =(written: string, sha256 = "a"): { length: number; written: string; sha256: string } => ({ length: 143360, written, sha256 });

// A Disk II drive with work.woz in it, changed or not, and its image as the host found it.
function drive(changed: boolean, source: Partial<MediaSource> = {}, writeProtected = false): Device {
    return {
        id: "disk1", kind: "floppyDrive", name: "Drive 1", description: "5¼-inch floppy drive", controller: "Disk II",
        formats: ["woz", "dsk", "do", "po", "d13"], saveFormats: ["woz", "dsk", "do", "po"],
        operations: ["insert", "eject", "writeProtect", "save"], tracks: 35, sides: 1,
        media: {
            label: image, format: "WOZ", writeProtected, changed, generation: 3,
            source: { kind: "image", path: image, saves: true, readOnly: null, stale: false, ...source }
        },
        activity: "writing", head: { motor: true, selected: true, track: 17, side: 0, sector: 4 }
    };
}

test("each kind of drive has its own picture, and a disk its lock as a badge coloured by what the drive is doing", () => {
    assert.equal(form(drive(false)), "floppy525");
    assert.equal(iconName(drive(false)), "floppy525-unlocked-writing");
    assert.equal(iconName(drive(false, {}, true)), "floppy525-locked-writing");
    assert.equal(iconName({ ...drive(false), media: null }), "floppy525-empty");
    assert.equal(form({ ...drive(false), formats: ["po", "2mg", "hdv", "img", "dsk"] }), "floppy35");
    assert.equal(form({ ...drive(false), kind: "blockStorage" }), "hardDisk");
    assert.equal(iconName({ ...drive(false), kind: "tapeDrive", activity: "reading" }), "tape-reading", "a tape has no badge");

    for (const name of iconNames()) {
        for (const dark of [false, true]) {
            const svg = iconSvg(name, dark);
            assert.match(svg, /^<svg [^>]*viewBox="0 0 16 16">.*<\/svg>$/);
            assert.equal(svg.includes("<rect x=\"9\" y=\"10.5\""), !name.endsWith("-empty") && !name.startsWith("tape"), `${name}'s badge`);
        }
    }
    assert.notEqual(iconSvg("floppy525-locked-idle", false), iconSvg("floppy525-unlocked-idle", false), "the shackle opens");
    assert.match(iconSvg("floppy525-locked-reading", true), /#89D185/, "reading is green");
    assert.match(iconSvg("floppy525-locked-writing", false), /#E51400/, "writing is red");
});

test("the row's end marks a changed disk, an image changed on disk, and both; the summary says the image's state", () => {
    assert.equal(mark(drive(false)), undefined);
    assert.equal(mark(drive(true)), "changed");
    assert.equal(mark(drive(false, { stale: true })), "stale");
    assert.equal(mark(drive(true, { stale: true })), "conflict");
    assert.equal(mark({ ...drive(true), operations: ["insert", "eject"] }), undefined, "a drive that cannot save has no mark");

    assert.equal(summary(drive(true)), "work.woz · track 17 sector 4 · writing", "the lock is on the icon, the change at the end");
    assert.equal(summary(drive(true, { stale: true, current: revision("2026-11-14T10:52:00Z") })),
        "work.woz · track 17 sector 4 · image changed on disk · writing");
    assert.equal(summary(drive(true, { stale: true, current: null })), "work.woz · track 17 sector 4 · image deleted · writing");
    assert.equal(summary(drive(true, { readOnly: "file" })), "work.woz · track 17 sector 4 · read-only image · writing");
    assert.equal(summary({ ...drive(false), media: null, activity: "idle" }), "empty · track 17 sector 4 · motor on");
});

test("the tooltip names the image, whether the disk changed, when the image changed, the lock and where the head is", () => {
    const now = new Date(2026, 10, 14, 11, 0);
    const read = new Date(2026, 10, 14, 10, 2).toISOString();
    const changed = new Date(2026, 10, 14, 10, 52).toISOString();
    const lines = tooltipLines(drive(true, { stale: true, baseline: revision(read), current: revision(changed, "b") }), now);
    assert.equal(lines[0], `work.woz (WOZ), ${image}`);
    assert.equal(lines[1], "Changed: not saved to the image");
    assert.match(lines[2], /^Image changed on disk: .*10:52.* today; it was .*10:02.* today when read$/);
    assert.equal(lines[3], "Unlocked: the machine can write it");
    assert.equal(lines[4], "Track 17, sector 4, writing");
    assert.equal(tooltipLines(drive(false), now)[1], "The same as its image");
    assert.equal(tooltipLines(drive(false, { stale: true, current: revision(changed, "b") }), now)[1],
        "Not changed by the machine, but its image is not the file it was read from", "an image changed on disk is not the same");
    assert.equal(tooltipLines(drive(false, { stale: true, current: null }), now)[1], "Not changed by the machine; its image is gone");
    assert.ok(tooltipLines(drive(false, { readOnly: "file" }), now).includes("Read-only file: Save As saves the disk under another name"));
    assert.ok(tooltipLines(drive(false, {}, true), now).includes("Locked: the machine cannot write it"));
});

test("the menus offer Save for a changed disk, a Save that will ask for a changed image, and Save As for a read-only one", () => {
    assert.deepEqual(contextWords(drive(false), true), ["device", "loaded", "insert", "eject", "unlocked", "revert", "save"]);
    assert.ok(contextWords(drive(true), true).includes("changed"));
    assert.ok(contextWords(drive(true, { stale: true }), true).includes("changedStale"));
    assert.ok(contextWords(drive(false, { stale: true }), true).includes("changedStale"), "a disk whose image changed saves over it");
    assert.ok(contextWords(drive(false, { stale: true, current: null }), true).includes("changedStale"), "or writes it again");
    assert.ok(contextWords(drive(true, { readOnly: "file" }), true).includes("changedReadOnly"));
    assert.ok(contextWords(drive(true, { kind: "built", saves: false }), true).includes("changedReadOnly"), "a built disk saves as");
    assert.ok(contextWords(drive(true, {}, true), true).includes("locked"));
    assert.deepEqual(contextWords(drive(true), false), ["device", "loaded", "insert", "eject", "unlocked"], "off, nothing to save");
});

test("the questions a save asks say what is off and offer the way out the plan draws", () => {
    assert.equal(lossless(drive(false)), "woz");
    assert.equal(lossless({ ...drive(false), saveFormats: ["jv3", "dmk", "dsk", "jv1"] }), "dmk");
    assert.equal(lossless({ ...drive(false), saveFormats: ["po", "2mg"] }), "2mg");

    const lossy = lossyQuestion("games.dsk", "Drive 1", "DSK", ["Track 3 does not read as 16 sectors."], "woz");
    assert.equal(lossy.message, "games.dsk can't hold the disk in Drive 1 as it is");
    assert.deepEqual(lossy.buttons, ["Save as WOZ...", "Save Anyway"]);
    assert.match(lossy.detail, /• Track 3 does not read as 16 sectors\.\n\nA \.woz keeps all of it\. Saving anyway/);
    assert.deepEqual(lossyQuestion("a.dsk", "Drive 1", "DSK", [], undefined).buttons, ["Save Anyway"]);

    const now = new Date(2026, 10, 14, 11, 0);
    const conflict = conflictQuestion("work.woz", "Drive 1", revision("2026-11-14T10:02:00Z"), revision("2026-11-14T10:52:00Z", "b"), now);
    assert.equal(conflict.message, "work.woz changed on disk after Drive 1 read it");
    assert.deepEqual(conflict.buttons, ["Overwrite", "Save As..."]);
    assert.match(conflict.detail, /kept as a backup/);
    assert.deepEqual(conflictQuestion("work.woz", "Drive 1", revision("x"), null).buttons, ["Save There Again", "Save As..."]);
    assert.deepEqual(conflictQuestion("copy.woz", "Drive 1", null, revision("x")).buttons, ["Replace", "Save As..."]);

    const file = readOnlyQuestion("system.po", "3.5 drive 2", "PO", "file");
    assert.equal(file.message, "system.po is a read-only file");
    assert.deepEqual(file.buttons, ["Save As...", "Make Writable and Save"]);
    assert.deepEqual(readOnlyQuestion("old.imd", "Drive 0", "IMD", "format").buttons, ["Save As..."]);
    assert.equal(readOnlyQuestion(undefined, "Drive 1", undefined, "noImage").message, "The disk in Drive 1 has no image of its own");

    assert.equal(savedMessage("work.woz", "Drive 1", true), "$(check) Saved work.woz from Drive 1; the version it replaced is kept");
    assert.equal(savedMessage("new.woz", "Drive 1", false), "$(check) Saved new.woz from Drive 1");
});

test("what a disk changed reads as the image's units, in the tooltip, the eject question and the revert note", () => {
    const sectors = { unit: "sector" as const, count: 14, summary: "tracks 17-18" };
    const blocks = { unit: "block" as const, count: 3, summary: "blocks 7-8, 200" };
    assert.equal(changeWords(sectors), "14 sectors on tracks 17-18");
    assert.equal(changeWords(blocks), "3 blocks: 7-8, 200");
    assert.equal(changeWords({ unit: "block", count: 1, summary: "block 9" }), "1 block: 9");
    assert.equal(changeWords({ unit: "sector", count: 0, summary: "" }), undefined, "nothing changed says nothing");
    assert.equal(changeWords(null), undefined);
    assert.equal(tooltipLines(drive(true), new Date(), "14 sectors on tracks 17-18")[1], "Changed: 14 sectors on tracks 17-18, not saved to the image");

    const leave = leaveQuestion("work.woz", "Drive 1", "ejecting it from Drive 1", "14 sectors on tracks 17-18");
    assert.equal(leave.message, "Save the changes to work.woz before ejecting it from Drive 1?");
    assert.equal(leave.detail, "The machine changed 14 sectors on tracks 17-18.");
    assert.deepEqual(leave.buttons, ["Save", "Save As...", "Discard"]);
    assert.match(leaveQuestion("a.dsk", "Drive 1", "ejecting it", undefined).detail, /since it was read/);

    assert.equal(revertedMessage("Drive 1", "work.woz", sectors), "Reverted Drive 1 to work.woz; 14 changed sectors were dropped.");
    assert.equal(revertedMessage("Drive 1", "work.woz", { unit: "block", count: 1, summary: "block 9" }), "Reverted Drive 1 to work.woz; 1 changed block was dropped.");
    assert.equal(revertedMessage("Drive 1", "work.woz", undefined), "Reverted Drive 1 to work.woz; its changes were dropped.");
    assert.equal(stoppedMessage("Apple IIe", ["work.woz", "prodos.2mg"]),
        "Apple IIe stopped with 2 disks not saved: work.woz, prodos.2mg. Their changes were not kept.");

    // What a stopping machine takes with it: changed disks in drives that save, and changed disks the machine ejected.
    const ejected = (label: string, changed: boolean) => ({ id: `k-${label}`, label, format: "2MG", why: "ejected" as const, when: "", changed });
    assert.deepEqual(unsavedDisks([drive(false), drive(true)]), ["work.woz"]);
    assert.deepEqual(unsavedDisks([{ ...drive(false), ejected: [ejected(path.resolve(path.sep, "a.2mg"), true), ejected("b.2mg", false)] }]), ["a.2mg"]);
    assert.deepEqual(unsavedDisks([{ ...drive(true), operations: ["insert", "eject"] }]), [], "a drive that cannot save has nothing to lose to a stop");
});

test("a disk with an image can be reverted, and one the machine ejected says when it left", () => {
    assert.ok(contextWords(drive(false), true).includes("revert"));
    assert.ok(!contextWords(drive(false, { kind: "built", saves: false }), true).includes("revert"), "a built disk has no image");
    assert.ok(!contextWords(drive(false), false).includes("revert"), "nor while the machine is off");
    const now = new Date(2026, 10, 14, 11, 0);
    const kept = { id: "k-1", label: image, format: "2MG", why: "ejected" as const, when: new Date(2026, 10, 14, 10, 41).toISOString(), changed: true };
    assert.match(keptSummary(kept, now), /^work\.woz · .*10:41.* today · ejected by the machine$/);
});
