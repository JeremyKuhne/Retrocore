// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Kaypro II DAP integration: boots the SDK's build of the 81-149C ROM, which asks for a disk, and checks the display,
// the thread, the hardware rows, stepping in Kaypro2.asm's source, a function breakpoint on a ROM routine, Retrocore
// Memory's banks and the reset stop, and a program loaded under the ROM. With the disks in RETROCORE_KAYPRO (or
// %USERPROFILE%\Retrocore\kaypro), it also boots CP/M from cpm22-rom149.img, stops in the ROM's READ through CP/M's
// BIOS, and runs MBASIC from MBasic.img.

import { resolve, join } from "node:path";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import assert from "node:assert/strict";
import { startDap } from "./DapClient.mjs";

const root = resolve(import.meta.dirname, "..");
delete process.env.RETROCORE_KAYPRO_ROMS;
const disks = process.env.RETROCORE_KAYPRO ?? join(process.env.RETROCORE_CACHE ?? join(homedir(), "Retrocore"), "kaypro");
const cpm = join(disks, "cpm22-rom149.img");
const mbasic = join(disks, "MBasic.img");
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

    // Each bank has bytes only in its own range: RAM's ends with the ROM's 16K, and video RAM's at $3FFF.
    assert.equal((await request("readMemory", { memoryReference: "ram:0x8000", count: 1 })).unreadableBytes, 1);
    const shown = (await request("readMemory", { memoryReference: "video:0x3000", count: 1 })).data;
    await assert.rejects(request("writeMemory", { memoryReference: "video:0x4000", data: Buffer.from([0x42]).toString("base64") }));
    assert.equal((await request("readMemory", { memoryReference: "video:0x3000", count: 1 })).data, shown, "no write wraps into video RAM");

    // A program at $0100 runs from RAM as it starts, before the ROM has booted: the ROM is banked out.
    log("program");
    const folder = mkdtempSync(join(tmpdir(), "retrocore-kaypro-"));
    try {
        const program = join(folder, "program.com");
        writeFileSync(program, Buffer.from([0x3E, 0x2A, 0x76]));
        drop("stopped");
        await launch({ program, loadAddress: 0x0100, stopOnEntry: true });
        await event("stopped");
        assert.equal((await request("stackTrace", { threadId: 1 })).stackFrames[0].instructionPointerReference, "0x0100");
        const loaded = Buffer.from((await request("readMemory", { memoryReference: "0x0100", count: 3 })).data, "base64");
        assert.deepEqual([...loaded], [0x3E, 0x2A, 0x76], "the CPU reads the program at $0100");
        drop("stopped");
        await request("stepIn", { threadId: 1, granularity: "instruction" });
        await event("stopped");
        assert.equal((await request("stackTrace", { threadId: 1 })).stackFrames[0].instructionPointerReference, "0x0102");
    } finally {
        rmSync(folder, { recursive: true, force: true });
    }

    log("reset");
    await launch({}, ["machineReset"]);
    let stopped = await event("stopped");
    assert.equal(stopped.description, "The machine reset as it powered on.");
    assert.equal((await request("stackTrace", { threadId: 1 })).stackFrames[0].instructionPointerReference, "0x0000");
    await request("continue", { threadId: 1 });

    if (existsSync(cpm) && existsSync(mbasic)) {
        log("CP/M");
        await launch({ disks: [cpm, mbasic] });
        await screen("A>");
        log("A>");

        // CP/M's BIOS reads through the ROM's READ, so a breakpoint there stops in Kaypro2.asm.
        drop("stopped");
        await request("setFunctionBreakpoints", { breakpoints: [{ name: "READ" }] });
        await type("DIR B:\r");
        stopped = await event("stopped");
        log("stopped in READ");
        assert.equal(stopped.reason, "function breakpoint");
        const top = (await request("stackTrace", { threadId: 1 })).stackFrames[0];
        assert.match(top.source?.path ?? "", /Kaypro2\.asm$/);
        assert.equal(top.name, "READ");
        await request("setFunctionBreakpoints", { breakpoints: [] });
        await request("continue", { threadId: 1 });
        await screen("MBASIC");
        await prompt();
        log("DIR B:");

        await type("B:MBASIC\r");
        await screen("Ok");
        await type("PRINT 6*7\r");
        await screen(" 42");
        log("PRINT 6*7");

        // A BASIC file: CP/M boots, the launch starts MBASIC from drive B, and RUN stops on the BASIC thread at the
        // first statement, with MBASIC's source on the CPU thread.
        log("MBASIC program");
        const program = join(mkdtempSync(join(tmpdir(), "retrocore-kaypro-")), "squares.mbasic.bas");
        writeFileSync(program, "10 TOTAL=0\n20 FOR I%=1 TO 3\n30 GOSUB 100\n40 NEXT I%\n50 PRINT \"TOTAL\";TOTAL\n60 END\n100 TOTAL=TOTAL+I%*I%:RETURN\n");
        await launch({ disks: [cpm, mbasic], command: "B:MBASIC", basic: program }, ["basicStart"]);
        stopped = await event("stopped");
        assert.equal(stopped.threadId, 2, `RUN stops on the BASIC thread (${stopped.description ?? stopped.reason})`);
        assert.equal((await request("stackTrace", { threadId: 2 })).stackFrames[0].name, "10: TOTAL=0");
        for (let step = 0; step < 3; step++) {
            drop("stopped");
            await request("stepIn", { threadId: 2 });
            await event("stopped");
        }

        const basicFrames = (await request("stackTrace", { threadId: 2 })).stackFrames;
        assert.equal(basicFrames[0].name, "100: TOTAL=TOTAL+I%*I%", "a step into GOSUB goes to line 100");
        assert.equal(basicFrames.length, 2, "GOSUB's return is on the BASIC call stack");
        const scopes = (await request("scopes", { frameId: basicFrames[0].id })).scopes;
        const variables = (await request("variables", { variablesReference: scopes[0].variablesReference })).variables;
        const byName = Object.fromEntries(variables.map(variable => [variable.name, variable.value]));
        assert.equal(byName["I%"], "1", `I% is 1 (${JSON.stringify(byName)})`);
        const cpu = (await request("stackTrace", { threadId: 1 })).stackFrames;
        assert.ok(cpu.some(frame => /[\\/]Mbasic[\\/]\w+\.asm$/.test(frame.source?.path ?? "")), "the CPU is in MBASIC's source");
        await request("setExceptionBreakpoints", { filters: [] });
        await request("continue", { threadId: 2 });
        await screen("TOTAL 14");
        console.log("Kaypro II DAP passed: the ROM's sign-on, thread, hardware, source, banks, a program under the ROM and reset stop, CP/M's boot, a breakpoint in READ, and MBASIC.");
    } else {
        console.log(`Kaypro II DAP passed: the ROM's sign-on, thread, hardware, source, banks, a program under the ROM and reset stop (no disks in ${disks}).`);
    }

    await request("disconnect");
} finally {
    clearTimeout(timeout);
    clearInterval(trimmer);
    close();
}
if (failure()) throw failure();
