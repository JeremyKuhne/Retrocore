// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The Apple II's block drives save through the debug adapter, and the machine boots again from what was saved. A boot
// block, booted from slot 7, writes itself to block 5 through the slot's ProDOS driver, retrying while the write
// fails; the saved image is pinned by digest, so it is the same image whichever drive wrote it:
// - a ProFile in slot 7 saves to its .po, keeping a backup, then as a 2MG, which boots again and saves again;
// - slot 7's own block device loads locked, so the guest's writes fail as write-protected ($2B) and nothing changes,
//   until the drive is unlocked, when the write goes through and the image saves; saved as a 2MG, the saved machine
//   keeps it, and the next launch with that saved machine boots the 2MG;
// - a 3.5 drive's 2MG saves unchanged as the file it read, and as bare blocks.
// The ROMs are assembled from the SDK's sources, so no dumps are needed.

import { resolve, join } from "node:path";
import { mkdirSync, writeFileSync, readFileSync, rmSync, existsSync } from "node:fs";
import { createHash } from "node:crypto";
import assert from "node:assert/strict";
import { startDap } from "./DapClient.mjs";

const root = resolve(import.meta.dirname, "..");
const folder = join(root, "artifacts", `block-media-${process.pid}`);
mkdirSync(folder, { recursive: true });

// The SHA-256 of the 280-block image once the boot block has copied itself to block 5.
const pinned = "09071f7bf5681c40b3701b655e28971368af92df2f7471e33046e4c320bb5efc";

// The boot block, at $0800: it calls the slot 7 driver ($C700 + $C7FF) to write the block it is in ($0800) to block
// 5, through a vector at $00, keeps the error in $06, tries again while the write fails, and then marks $07 with $A5.
const boot = Buffer.alloc(512);
Buffer.from([
    0x01,                   // the number of blocks to load
    0xA9, 0x02, 0x85, 0x42, // LDA #2 (WRITE), STA $42
    0xA9, 0x70, 0x85, 0x43, // LDA #$70 (slot 7, drive 1), STA $43
    0xA9, 0x00, 0x85, 0x44, // LDA #0, STA $44 (the buffer's low byte)
    0x85, 0x47,             // STA $47 (the block's high byte)
    0xA9, 0x08, 0x85, 0x45, // LDA #$08, STA $45: the buffer is $0800
    0xA9, 0x05, 0x85, 0x46, // LDA #5, STA $46: block 5
    0xAD, 0xFF, 0xC7,       // LDA $C7FF, the driver's offset in the slot's page
    0x85, 0x00,             // STA $00
    0xA9, 0xC7, 0x85, 0x01, // LDA #$C7, STA $01
    0x20, 0x2E, 0x08,       // JSR $082E
    0x85, 0x06,             // STA $06: the error
    0xB0, 0xDA,             // BCS $0801: try again
    0xA9, 0xA5, 0x85, 0x07, // LDA #$A5, STA $07: written
    0x4C, 0x2B, 0x08,       // JMP $082B: wait
    0x6C, 0x00, 0x00,       // $082E: JMP ($0000), into the driver
]).copy(boot);

const image = Buffer.alloc(512 * 280);
boot.copy(image);
const expected = Buffer.from(image);
boot.copy(expected, 5 * 512);
const sha256 = bytes => createHash("sha256").update(bytes).digest("hex");
assert.equal(sha256(expected), pinned, "the expected image is the one pinned");

let request;
const delay = milliseconds => new Promise(done => setTimeout(done, milliseconds));
const zeroPage = async address =>
    Buffer.from((await request("readMemory", { memoryReference: `0x${address.toString(16)}`, count: 1 })).data, "base64")[0];
const waitFor = async (address, value, what) => {
    for (let tries = 0; tries < 400; tries++) {
        if (await zeroPage(address) === value) return;
        await delay(25);
    }
    assert.fail(`${what}: $${address.toString(16)} never became $${value.toString(16)}`);
};
const device = async id => (await request("retro/devices")).devices.find(candidate => candidate.id === id);

// Runs a machine in a debug host of its own, as each launch is a session of its own.
const session = async (args, body) => {
    const dap = startDap(root);
    request = dap.request;
    try {
        await request("initialize", { adapterID: "retrocore" });
        await request("launch", { machine: "apple2", model: "iie-enhanced", stopOnEntry: false, speed: "max", sound: "off", ...args });
        await request("configurationDone");
        await body();
    } finally {
        dap.close();
    }
};
const save = async (id, extra = {}) => {
    const body = await request("retro/device", { id, action: "save", supportsRetrocoreMedia: true, ...extra });
    assert.equal(body.outcome, "saved", JSON.stringify(body));
    return body;
};
const blocksOf = file => {
    const bytes = readFileSync(file);
    if (bytes.subarray(0, 4).toString("ascii") !== "2IMG") return bytes;
    const offset = bytes.readUInt32LE(24);
    return bytes.subarray(offset, offset + bytes.readUInt32LE(28));
};

try {
    // A ProFile in slot 7 boots the block, which writes block 5; the drive is changed, saves to its .po as the pinned
    // image keeping a backup of the one it replaced, and then as a 2MG.
    const profile = join(folder, "profile.po");
    const twoImg = join(folder, "profile.2mg");
    writeFileSync(profile, image);
    await session({ proFiles: [{ slot: 7, image: profile }] }, async () => {
        await waitFor(7, 0xA5, "the ProFile's write");
        const drive = await device("slot7profile");
        assert.ok(drive.operations.includes("save") && drive.operations.includes("writeProtect"));
        assert.deepEqual(drive.saveFormats, ["po", "hdv", "2mg"]);
        assert.equal(drive.media.changed, true);
        const saved = await save("slot7profile");
        assert.equal(sha256(readFileSync(profile)), pinned);
        assert.ok(saved.backup && existsSync(saved.backup), "a save keeps what it replaced");
        assert.equal(sha256(readFileSync(saved.backup)), sha256(image));
        assert.equal((await device("slot7profile")).media.changed, false);

        await save("slot7profile", { path: twoImg });
        assert.equal(readFileSync(twoImg).subarray(0, 4).toString("ascii"), "2IMG");
        assert.equal(sha256(blocksOf(twoImg)), pinned);
    });

    // The 2MG boots again, writes again, and saves again as a 2MG.
    await session({ proFiles: [{ slot: 7, image: twoImg }] }, async () => {
        await waitFor(7, 0xA5, "the 2MG's write");
        const drive = await device("slot7profile");
        assert.equal(drive.media.format, "2MG");
        assert.equal(drive.media.label, twoImg);
        await save("slot7profile");
        assert.equal(sha256(blocksOf(twoImg)), pinned);
    });

    // Slot 7's block device loads locked: the guest's write fails as write-protected and changes nothing, until the
    // drive is unlocked; then it saves.
    const slot7 = join(folder, "slot7.po");
    const moved = join(folder, "slot7.2mg");
    let machineState;
    writeFileSync(slot7, image);
    await session({ diskImage: slot7 }, async () => {
        await waitFor(6, 0x2B, "the locked write");
        const drive = await device("slot7");
        assert.equal(drive.media.writeProtected, true);
        assert.equal(drive.media.changed, false);
        await request("retro/device", { id: "slot7", action: "writeProtect", writeProtected: false });
        await waitFor(7, 0xA5, "the unlocked write");
        assert.equal((await device("slot7")).media.changed, true);
        await save("slot7");
        assert.equal(sha256(readFileSync(slot7)), pinned);
        await save("slot7", { path: moved });
        machineState = (await request("retro/devices")).configuration;
        assert.equal(machineState.media.slot7.path, moved, "the saved machine keeps where slot 7 now is");
    });

    // The launch with that saved machine takes slot 7's image from it, as no insert can.
    await session({ diskImage: slot7, machineState }, async () => {
        const drive = await device("slot7");
        assert.equal(drive.media.label, moved);
        assert.equal(drive.media.format, "2MG");
    });

    // A 3.5 drive's 2MG saves unchanged as the file it read, and as bare blocks.
    const disk35 = join(folder, "disk35.2mg");
    const header = Buffer.from(readFileSync(twoImg).subarray(0, 64));
    const blocks = Buffer.alloc(1600 * 512);
    blocksOf(twoImg).copy(blocks);
    header.writeUInt32LE(1600, 20);
    header.writeUInt32LE(blocks.length, 28);
    writeFileSync(disk35, Buffer.concat([header, blocks]));
    const before = sha256(readFileSync(disk35));
    const bare = join(folder, "disk35.po");
    await session({ disk35: 5, disk35Images: [disk35] }, async () => {
        const drive = await device("disk35d1");
        assert.ok(drive.operations.includes("save"));
        assert.equal(drive.media.format, "2MG");
        await save("disk35d1");
        assert.equal(sha256(readFileSync(disk35)), before, "an unchanged disk writes nothing");
        await save("disk35d1", { path: bare });
        assert.equal(sha256(readFileSync(bare)), sha256(blocks));
    });

    console.log("Block media DAP passed: the ProFile, slot 7 and the 3.5 drive save, and the saved image boots again.");
} finally {
    rmSync(folder, { recursive: true, force: true });
}
