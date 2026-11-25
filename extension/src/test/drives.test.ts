// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import * as path from "node:path";
import { test } from "node:test";
import {
    changeWords, crashedMessage, discardKept, discardKeptQuestion, letGoQuestion, saveAllKept, keptSummary, leaveQuestion, revertedMessage, stoppedMessage, unsavedDisks,
    conflictQuestion, contextWords, form, hasTapeKeys, iconName, iconNames, iconSvg, lossless, lossyQuestion, mark, readOnlyQuestion,
    savedMessage, summary, tooltipLines, type Device, type MediaRecovery, type MediaSource
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

test("a changed disk says when the recovery journal kept it, and warns when the journal is behind", () => {
    const now = new Date(2026, 10, 14, 11, 0);
    const kept = new Date(2026, 10, 14, 10, 52).toISOString();
    const withRecovery = (recovery: MediaRecovery, changed = true): Device => ({ ...drive(changed), media: { ...drive(changed).media!, recovery } });

    // Kept, and kept mid-write: said in the tooltip, with no warning.
    const upToDate = withRecovery({ lastCheckpoint: kept, behind: false });
    assert.equal(mark(upToDate), "changed");
    assert.match(tooltipLines(upToDate, now).find(line => line.startsWith("Kept")) ?? "", /^Kept for recovery at .*10:52.* today$/);
    assert.match(tooltipLines(withRecovery({ lastCheckpoint: kept, behind: false, midWrite: true }), now).join("\n"),
        /Kept for recovery at .*10:52.* today, caught while the drive was writing/);

    // Behind: the row warns, the summary says so, and the tooltip says why and what is kept.
    const failing = withRecovery({ lastCheckpoint: kept, behind: true, problem: "There is not enough space on the disk." });
    assert.equal(mark(failing), "behind");
    assert.equal(summary(failing), "work.woz · track 17 sector 4 · recovery behind · writing");
    assert.match(tooltipLines(failing, now).join("\n"),
        /Recovery behind: the journal could not be written: There is not enough space on the disk\. Changes up to .*10:52.* today are kept; later ones would be lost if Retrocore stopped unexpectedly/);
    assert.match(tooltipLines(withRecovery({ lastCheckpoint: null, behind: true }), now).join("\n"),
        /Recovery behind: checkpoints are late\. The changes would be lost if Retrocore stopped unexpectedly/);

    // A conflict still marks as one, and an unchanged disk says nothing of recovery.
    assert.equal(mark({ ...failing, media: { ...failing.media!, source: { ...failing.media!.source!, stale: true } } }), "conflict");
    const same = withRecovery({ lastCheckpoint: null, behind: true }, false);
    assert.equal(mark(same), undefined);
    assert.ok(!tooltipLines(same, now).some(line => line.startsWith("Recovery") || line.startsWith("Kept")));
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
    assert.deepEqual(contextWords(drive(false), false), ["device", "loaded", "insert", "eject", "unlocked"], "off, nothing to save");
    assert.deepEqual(contextWords(drive(true), false), ["device", "loaded", "insert", "eject", "unlocked", "revert", "save", "changed"],
        "off, a disk the last run kept saves and reverts");
});

test("a Datasette's keys show while the machine runs; a tape drive that cannot save records to a file instead", () => {
    const deck: Device = {
        ...drive(false), id: "cassette1", kind: "tapeDrive", name: "Cassette #1", formats: ["tap", "wav"],
        saveFormats: ["tap", "wav"], operations: ["insert", "eject", "record", "save"]
    };
    assert.ok(hasTapeKeys(deck));
    const words = contextWords(deck, true);
    for (const word of ["recordKey", "play", "stop", "rewind", "save"]) assert.ok(words.includes(word), word);
    assert.ok(!words.includes("record"), "RECORD goes down on the tape in the deck, with no file to name");
    assert.ok(!contextWords({ ...deck, media: null }, true).includes("play"), "no keys to press with no tape");
    assert.deepEqual(contextWords(deck, false).filter(word => ["recordKey", "play"].includes(word)), [], "nor while the machine is off");

    const recorder: Device = { ...deck, operations: ["insert", "eject", "record"] };
    assert.ok(!hasTapeKeys(recorder));
    assert.ok(contextWords(recorder, true).includes("record"));
    assert.ok(!contextWords(recorder, true).includes("play"));
});

test("Discard asks about the disks kept now, again when the journal changed meanwhile, and lets nothing go unasked", async () => {
    // The machine ran again while the first question was open: that answer lets nothing go, and the newer disks are asked about.
    const journals = [{ disks: ["work.woz"], revision: "a" }, { disks: ["work.woz", "game.woz"], revision: "b" }];
    const asked: string[][] = [];
    const resolved: string[] = [];
    const outcome = await discardKept(async () => journals.shift(), async disks => { asked.push(disks); return true; },
        async revision => { resolved.push(revision); return revision === "a" ? { outcome: "changed" } : {}; });
    assert.equal(outcome, "discarded");
    assert.deepEqual(asked, [["work.woz"], ["work.woz", "game.woz"]]);
    assert.deepEqual(resolved, ["a", "b"]);

    // No to the question: nothing is resolved.
    let sent = false;
    assert.equal(await discardKept(async () => ({ disks: ["work.woz"], revision: "a" }), async () => false, async () => { sent = true; return {}; }), "kept");
    assert.equal(sent, false);
    assert.equal(await discardKept(async () => undefined, async () => true, async () => ({})), "none");
});

test("Save All saves each kept disk while the machine is the one asked about, and stops at the first not saved", async () => {
    const kept = (id: string, ejected: string[] = []): Device => ({
        ...drive(true), id, media: { ...drive(true).media!, kept: true },
        ejected: ejected.map(item => ({ id: item, label: image, format: "WOZ", why: "ejected" as const, when: "", changed: true }))
    });
    const devices = [kept("disk0", ["k-1"]), { ...drive(false), id: "disk1" }, kept("disk2")];
    const saved: string[] = [];
    assert.equal(await saveAllKept(devices, () => true, async (id, ejected) => { saved.push(ejected ?? id); return true; }), true);
    assert.deepEqual(saved, ["disk0", "k-1", "disk2"], "the unchanged disk is left alone");

    // A question cancelled: the disks after it stay kept.
    saved.length = 0;
    assert.equal(await saveAllKept(devices, () => true, async (id, ejected) => { saved.push(ejected ?? id); return false; }), false);
    assert.deepEqual(saved, ["disk0"]);

    // Another machine chosen meanwhile: nothing more is saved to this one's images.
    saved.length = 0;
    let shown = true;
    assert.equal(await saveAllKept(devices, () => shown, async (id, ejected) => { saved.push(ejected ?? id); shown = false; return true; }), false);
    assert.deepEqual(saved, ["disk0"]);
});

test("a machine that is off asks before it lets a changed disk go, as Undo cannot put it back", () => {
    const revert = letGoQuestion("Drive 1", "revert", image);
    assert.equal(revert.message, "Revert the disk in Drive 1 to work.woz?");
    assert.deepEqual(revert.buttons, ["Revert"]);
    assert.match(letGoQuestion("Drive 1", "discard", image).detail, /^work\.woz\. .*Undo/);
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
    assert.equal(stoppedMessage("Apple IIe", [], ["work.woz", "prodos.2mg"]),
        "Apple IIe stopped with 2 disks not saved: work.woz, prodos.2mg. Their changes were not kept.");
    assert.equal(stoppedMessage("Apple IIe", ["work.woz"], []),
        "Apple IIe stopped with 1 disk not saved: work.woz. It is kept, still changed, for its next launch.");
    assert.equal(crashedMessage("Apple IIe", [path.join(path.sep, "disks", "work.woz"), "prodos.2mg"], undefined),
        "Apple IIe did not stop cleanly. 2 disks had changes not saved: work.woz, prodos.2mg.");
    assert.match(crashedMessage("Apple IIe", ["work.woz"], new Date(2026, 10, 14, 10, 52).toISOString(), new Date(2026, 10, 14, 11, 0)),
        /^Apple IIe did not stop cleanly\. 1 disk had changes not saved: work\.woz, the last kept at .+ today\.$/);
    const discard = discardKeptQuestion("Apple IIe", ["work.woz"]);
    assert.equal(discard.message, "Discard the changes to the disk Apple IIe kept?");
    assert.deepEqual(discard.buttons, ["Discard"]);
    assert.equal(summary({ ...drive(true), media: { ...drive(true).media!, kept: true }, activity: "idle", head: undefined }),
        "work.woz · kept from the last run");
    assert.equal(stoppedMessage("Apple IIe", ["work.woz"], ["hello.dsk"]),
        "Apple IIe stopped with 2 disks not saved: work.woz, hello.dsk. work.woz is kept, still changed, for its next "
            + "launch; the changes to hello.dsk were not kept.");

    // What a stopping machine takes with it: changed disks in drives that save, and changed disks the machine ejected.
    const ejected = (label: string, changed: boolean) => ({ id: `k-${label}`, label, format: "2MG", why: "ejected" as const, when: "", changed });
    assert.deepEqual(unsavedDisks([drive(false), drive(true)]), { kept: [], lost: ["work.woz"] });
    assert.deepEqual(unsavedDisks([drive(true)], true), { kept: ["work.woz"], lost: [] }, "the journal keeps a disk from an image");
    assert.deepEqual(unsavedDisks([drive(true, { kind: "built", saves: false })], true), { kept: [], lost: ["work.woz"] },
        "a disk the launch built is built again, not kept");
    assert.deepEqual(unsavedDisks([{ ...drive(true), operations: ["writeProtect", "save"] }], true), { kept: [], lost: ["work.woz"] },
        "a disk only the launch puts in, as slot 7's, cannot go back");
    assert.deepEqual(unsavedDisks([{ ...drive(false), ejected: [ejected(path.resolve(path.sep, "a.2mg"), true), ejected("b.2mg", false)] }]),
        { kept: [], lost: ["a.2mg"] });
    assert.deepEqual(unsavedDisks([{ ...drive(true), operations: ["insert", "eject"] }]), { kept: [], lost: [] },
        "a drive that cannot save has nothing to lose to a stop");
});

test("a disk with an image can be reverted, and one the machine ejected says when it left", () => {
    assert.ok(contextWords(drive(false), true).includes("revert"));
    assert.ok(!contextWords(drive(false, { kind: "built", saves: false }), true).includes("revert"), "a built disk has no image");
    assert.ok(!contextWords(drive(false), false).includes("revert"), "nor while the machine is off");
    const now = new Date(2026, 10, 14, 11, 0);
    const kept = { id: "k-1", label: image, format: "2MG", why: "ejected" as const, when: new Date(2026, 10, 14, 10, 41).toISOString(), changed: true };
    assert.match(keptSummary(kept, now), /^work\.woz · .*10:41.* today · ejected by the machine$/);
});
