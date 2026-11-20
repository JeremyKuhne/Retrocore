// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The recovery journal across processes, as a crash leaves it: a Color Computer's Disk BASIC writes a disk, the
// debug host keeps it in the journal at a checkpoint and is killed without stopping, and the language server, a
// process of its own, offers the session that did not stop cleanly, shows the kept disk on the machine while it is
// off, saves it to its image there, and stops offering it once recovered. A second crash's disk is let go with
// discard. Then two hosts launch one machine at once, and only the first keeps its journal. Local data is a folder
// of the test's own. Needs nothing external: without ROM dumps the machine runs on the SDK's sources.

import { startDap } from "./DapClient.mjs";
import { spawn } from "node:child_process";
import { join, resolve } from "node:path";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import assert from "node:assert/strict";

const root = resolve(import.meta.dirname, "..");
const host = join(root, "artifacts", "AnyCPU", "Release", "Retrocore.Debug", "net11.0", "Retrocore.Debug.dll");
const romDirectory = process.env.RETROCORE_COCO_ROMS
    ?? join(process.env.RETROCORE_CACHE ?? join(process.env.USERPROFILE ?? "", "Retrocore"), "coco-roms", "extract");
const roms = existsSync(romDirectory) ? romDirectory : "";

// Every host here keeps its journals in the test's own local data, checkpointing every second.
const localData = mkdtempSync(join(tmpdir(), "retrocore-recovery-"));
process.env.RETROCORE_LOCAL_DATA = localData;
process.env.RETROCORE_CHECKPOINT_SECONDS = "1";
delete process.env.RETROCORE_COCO_ROMS;

const recoveryId = `test-recovery-${process.pid}`;
const journal = join(localData, "Recovery", recoveryId, "journal.json");
const disk = join(localData, "coco.dsk");
writeFileSync(disk, Buffer.alloc(35 * 18 * 256, 0xFF));
const configuration = { machine: "coco", model: "coco2", romDirectory: roms, disks: [disk], recoveryId, name: "CoCo for Recovery" };

/** Starts the language server and returns request(method, params). */
function startLanguageServer() {
    const child = spawn("dotnet", [host, "--language-server"]);
    let buffer = Buffer.alloc(0);
    let id = 1;
    const pending = new Map();
    child.stderr.on("data", data => process.stderr.write(data));
    child.stdout.on("data", data => {
        buffer = Buffer.concat([buffer, data]);
        for (;;) {
            const end = buffer.indexOf("\r\n\r\n");
            if (end < 0) return;
            const length = Number(/Content-Length:\s*(\d+)/i.exec(buffer.subarray(0, end).toString("ascii"))[1]);
            if (buffer.length < end + 4 + length) return;
            const message = JSON.parse(buffer.subarray(end + 4, end + 4 + length).toString("utf8"));
            buffer = buffer.subarray(end + 4 + length);
            const waiter = message.id === undefined ? undefined : pending.get(message.id);
            if (waiter === undefined) continue;
            pending.delete(message.id);
            if (message.error) waiter.reject(new Error(message.error.message));
            else waiter.resolve(message.result);
        }
    });
    const request = (method, params) => new Promise((resolve, reject) => {
        const message = JSON.stringify({ jsonrpc: "2.0", id, method, params });
        pending.set(id++, { resolve, reject });
        child.stdin.write(`Content-Length: ${Buffer.byteLength(message)}\r\n\r\n${message}`);
    });
    return { request, close: () => child.kill() };
}

// Waits for a running frame whose screen satisfies a test.
async function screen(dap, test, what) {
    for (let index = dap.events.length - 1; index >= 0; index--) if (dap.events[index].event === "retro/frame") dap.events.splice(index, 1);
    for (;;) {
        const frame = await dap.event("retro/frame");
        if (test(frame.rows.join("\n"))) return frame;
        if (!frame.running) throw new Error(`Stopped before ${what}.`);
    }
}

async function type(dap, text) {
    for (const character of text) await dap.request("retro/key", { code: character === "\r" ? 13 : character.charCodeAt(0) });
}

// Waits for the journal to list a disk kept after a time, as a checkpoint commits it.
async function kept(after) {
    for (let tries = 0; tries < 100; tries++) {
        if (existsSync(journal)) {
            const disks = JSON.parse(readFileSync(journal, "utf8")).disks;
            if (disks.some(entry => entry.kept > after)) return disks;
        }
        await new Promise(resolve => setTimeout(resolve, 200));
    }
    throw new Error("No checkpoint kept the disk.");
}

// A host that boots the CoCo with the disk, has Disk BASIC save a program on it, waits for a checkpoint, and is
// killed, as a crash ends it.
async function crash(program) {
    const dap = startDap(root);
    await dap.request("initialize", { adapterID: "retrocore" });
    await dap.request("launch", { ...configuration, stopOnEntry: false, speed: "max", sound: "off" });
    await dap.request("configurationDone");
    await screen(dap, text => text.includes("DISK EXTENDED COLOR BASIC") && /\nOK/.test(text), "Disk BASIC's OK");
    const before = new Date().toISOString();
    await type(dap, `10 PRINT "${program}"\rSAVE "${program}"\r`);
    await screen(dap, text => new RegExp(`SAVE "${program}"\\s*\\nOK`).test(text), "SAVE's OK");
    await kept(before);
    dap.close();
    await new Promise(resolve => setTimeout(resolve, 500));
}

const language = startLanguageServer();
const timeout = setTimeout(() => { console.error("The recovery DAP test timed out."); process.exit(1); }, Number(process.env.RETROCORE_DAP_TIMEOUT ?? 240000));
try {
    // A crash: the session that did not stop cleanly is offered, with its name and disk.
    await crash("FIRST");
    let offered = (await language.request("retrocore/recovery/list", {})).journals.find(entry => entry.id === recoveryId);
    assert.ok(offered, "the crashed session is offered");
    assert.equal(offered.name, "CoCo for Recovery");
    assert.deepEqual(offered.disks.map(label => label.toLowerCase()), [disk.toLowerCase()]);

    // The machine while off has the kept disk, changed; saved there, it leaves the journal, and its image has the program.
    let off = await language.request("retrocore/machine/describe", { configuration });
    let drive = off.devices.find(device => device.id === "disk0");
    assert.equal(drive.media.changed, true, JSON.stringify(drive.media));
    assert.equal(drive.media.kept, true);
    // The machine is built for each request, but its mount is named alike each time, and an answer about another is refused.
    const generation = drive.media.generation;
    assert.equal((await language.request("retrocore/machine/describe", { configuration })).devices.find(device => device.id === "disk0").media.generation, generation);
    await assert.rejects(language.request("retrocore/machine/change",
        { configuration, request: "device", arguments: { id: "disk0", action: "save", generation: generation + 1, supportsRetrocoreMedia: 1 } }));
    const held = await language.request("retrocore/machine/change",
        { configuration, request: "device", arguments: { id: "disk0", action: "eject", supportsRetrocoreMedia: 1 } });
    assert.equal(held.outcome, "changed", JSON.stringify(held));
    assert.equal(held.generation, generation);
    const saved = await language.request("retrocore/machine/change",
        { configuration, request: "device", arguments: { id: "disk0", action: "save", generation, supportsRetrocoreMedia: 1 } });
    assert.equal(saved.outcome, "saved", JSON.stringify(saved));
    assert.equal(JSON.parse(readFileSync(journal, "utf8")).disks.length, 0, "a saved disk leaves the journal");
    assert.ok(readFileSync(disk).includes(Buffer.from("FIRST   BAS")), "the image has the program");
    off = await language.request("retrocore/machine/describe", { configuration });
    assert.equal(off.devices.find(device => device.id === "disk0").media.changed, false);
    assert.equal(off.devices.find(device => device.id === "disk0").media.generation,
        saved.devices.find(device => device.id === "disk0").media.generation, "a save's answer names the disk as the next request does");
    await language.request("retrocore/recovery/resolve", { id: recoveryId, action: "recover" });
    offered = (await language.request("retrocore/recovery/list", {})).journals.find(entry => entry.id === recoveryId);
    assert.equal(offered, undefined, "a recovered session is not offered again");

    // A second crash's disk, let go: the journal no longer has it, and the image stays as saved.
    await crash("SECOND");
    assert.ok((await language.request("retrocore/recovery/list", {})).journals.some(entry => entry.id === recoveryId));
    await language.request("retrocore/recovery/resolve", { id: recoveryId, action: "discard" });
    assert.equal((await language.request("retrocore/recovery/list", {})).journals.some(entry => entry.id === recoveryId), false);
    assert.equal(existsSync(journal), false);
    assert.equal(readFileSync(disk).includes(Buffer.from("SECOND  BAS")), false, "the image was never written");
    off = await language.request("retrocore/machine/describe", { configuration });
    assert.equal(off.devices.find(device => device.id === "disk0").media.changed, false);

    // Two hosts launch one machine at once: the first keeps the journal, and the second says it keeps none.
    const first = startDap(root);
    const second = startDap(root);
    try {
        await first.request("initialize", { adapterID: "retrocore" });
        await first.request("launch", { ...configuration, stopOnEntry: true, speed: "max", sound: "off" });
        assert.equal((await first.request("retro/devices")).recovery, true);
        await second.request("initialize", { adapterID: "retrocore" });
        await second.request("launch", { ...configuration, stopOnEntry: true, speed: "max", sound: "off" });
        assert.equal((await second.request("retro/devices")).recovery, false, "a second process keeps no journal of the same machine");
        await first.request("disconnect");
        await second.request("disconnect");
    } finally {
        first.close();
        second.close();
    }

    console.log("Recovery DAP passed: a crashed session's disk is offered by the language server, shown changed on the machine while off, "
        + "saved there to its image and leaves the journal; a second crash's disk is discarded; and of two hosts launching one machine, only the first keeps its journal.");
} finally {
    clearTimeout(timeout);
    language.close();
    await new Promise(resolve => setTimeout(resolve, 500));
    rmSync(localData, { recursive: true, force: true });
}
