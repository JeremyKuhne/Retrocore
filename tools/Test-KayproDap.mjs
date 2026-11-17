// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Kaypro II DAP integration: boots the SDK's build of the 81-149C ROM, which asks for a disk, and checks the display,
// the thread, the hardware rows, stepping in Kaypro2.asm's source, a function breakpoint on a ROM routine, Retrocore
// Memory's bank under the ROM and the reset stop. With the disk in RETROCORE_KAYPRO (or %USERPROFILE%\Retrocore\kaypro),
// it also boots CP/M from cpm22-rom149.img and stops in the ROM's READ through CP/M's BIOS.

import { resolve, join } from "node:path";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import assert from "node:assert/strict";
import { startDap } from "./DapClient.mjs";

const root = resolve(import.meta.dirname, "..");
delete process.env.RETROCORE_KAYPRO_ROMS;
const disks = process.env.RETROCORE_KAYPRO ?? join(process.env.RETROCORE_CACHE ?? join(homedir(), "Retrocore"), "kaypro");
const cpm = join(disks, "cpm22-rom149.img");
const { request, event, events, fail, close, failure } = startDap(root);
const timeout = setTimeout(() => fail(new Error("Kaypro DAP integration timed out.")), Number(process.env.RETROCORE_DAP_TIMEOUT ?? 120000));
const verbose = process.env.RETROCORE_DAP_VERBOSE === "1";
const started = Date.now();
const log = text => { if (verbose) console.log(`${((Date.now() - started) / 1000).toFixed(1)}s ${text}`); };

// Display frames arrive thirty times a second while the machine runs, each with its picture; only the newest is kept,
// so a long run does not hold them all.
const trimmer = setInterval(() => {
    const frames = events.filter(message => message.event === "retro/frame");
    for (const frame of frames.slice(0, -1)) events.splice(events.indexOf(frame), 1);
}, 250);

function drop(name) {
    for (let index = events.length - 1; index >= 0; index--) {
        if (events[index].event === name) events.splice(index, 1);
    }
}

async function launch(args, filters) {
    events.length = 0;
    await request("setExceptionBreakpoints", { filters: filters ?? [] });
    await request("launch", { machine: "kaypro2", stopOnEntry: false, speed: "max", ...args });
    await request("configurationDone");
}

async function type(text) {
    for (const character of text) await request("retro/key", { code: character === "\r" ? 13 : character.charCodeAt(0) });
}

async function screen(text) {
    drop("retro/frame");
    for (;;) {
        const frame = await event("retro/frame");
        if (frame.rows.join("\n").includes(text)) return frame;
        if (!frame.running) throw new Error(`Stopped before ${text}.`);
    }
}

// Waits for CP/M's prompt with the cursor after it, so a command typed next is not taken by the last one, as DIR
// takes a key to stop its listing.
async function prompt() {
    drop("retro/frame");
    for (;;) {
        const frame = await event("retro/frame");
        if (frame.rows.some(row => /^[A-P]>_\s*$/.test(row))) return frame;
        if (!frame.running) throw new Error("Stopped before CP/M's prompt.");
    }
}

try {
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });

    log("no disk");
    await launch({});
    const frame = await screen("Please place your diskette into Drive A");
    assert.equal(frame.machine, "kaypro2");
    assert.equal(frame.model, "Kaypro II");
    assert.equal(frame.columns, 80);
    assert.equal(frame.rows.length, 24);
    assert.equal((await request("threads")).threads[0].name, "Kaypro II Z80");
    const hardware = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
    assert.equal(hardware.model.name, "Kaypro II");
    assert.deepEqual(hardware.disk.devices, ["disk0", "disk1"]);

    // The ROM waits in the disk controller with no disk, so a pause is in Kaypro2.asm.
    drop("stopped");
    await request("pause", { threadId: 1 });
    await event("stopped");
    const frames = (await request("stackTrace", { threadId: 1 })).stackFrames;
    assert.ok(frames.some(frame => /Kaypro2\.asm$/.test(frame.source?.path ?? "")), "a frame in the ROM's source");

    // The RAM under the ROM is its own bank in Retrocore Memory.
    const banks = (await request("retro/memoryBanks")).banks?.map(bank => bank.name) ?? [];
    assert.ok(banks.includes("ram"), `the RAM under the ROM is a bank (${banks.join(", ")})`);

    log("reset");
    await launch({}, ["machineReset"]);
    let stopped = await event("stopped");
    assert.equal(stopped.description, "The machine reset as it powered on.");
    assert.equal((await request("stackTrace", { threadId: 1 })).stackFrames[0].instructionPointerReference, "0x0000");
    await request("continue", { threadId: 1 });

    if (existsSync(cpm)) {
        log("CP/M");
        await launch({ disks: [cpm] });
        await screen("A>");
        log("A>");

        // CP/M's BIOS reads through the ROM's READ, so a breakpoint there stops in Kaypro2.asm.
        drop("stopped");
        await request("setFunctionBreakpoints", { breakpoints: [{ name: "READ" }] });
        await type("DIR\r");
        stopped = await event("stopped");
        log("stopped in READ");
        assert.equal(stopped.reason, "function breakpoint");
        const top = (await request("stackTrace", { threadId: 1 })).stackFrames[0];
        assert.match(top.source?.path ?? "", /Kaypro2\.asm$/);
        assert.equal(top.name, "READ");
        await request("setFunctionBreakpoints", { breakpoints: [] });
        await request("continue", { threadId: 1 });
        await screen("PIP");
        await prompt();
        log("DIR");
        console.log("Kaypro II DAP passed: the ROM's sign-on, thread, hardware, source, banks and reset stop, CP/M's boot and a breakpoint in READ.");
    } else {
        console.log(`Kaypro II DAP passed: the ROM's sign-on, thread, hardware, source, banks and reset stop (no CP/M disk in ${disks}).`);
    }

    await request("disconnect");
} finally {
    clearTimeout(timeout);
    clearInterval(trimmer);
    close();
}
if (failure()) throw failure();
