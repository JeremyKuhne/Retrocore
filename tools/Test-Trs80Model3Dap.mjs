// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Model III, 4, 4P and II DAP integration: launches each from stand-in ROM dumps under MAME's names, which show READY
// on the screen, and checks the display, the thread, the hardware rows, the reset stop and the error a launch with a
// dump missing gives. The stand-ins are a few hand-assembled instructions, so the script needs no real ROMs. Without a
// ROM directory, the Model III and Model II boot the SDK's builds of their real ROMs, with source and, on the Model
// III, the BASIC thread, for Level II's BASIC and Level I's.

import { resolve, join } from "node:path";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import assert from "node:assert/strict";
import { startDap } from "./DapClient.mjs";

const root = resolve(import.meta.dirname, "..");

// The launches without romDirectory must not find the user's dumps.
delete process.env.RETROCORE_TRS80_ROMS;
const { request, event, events, fail, close, failure } = startDap(root);
const timeout = setTimeout(() => fail(new Error("Model III and II DAP integration timed out.")), Number(process.env.RETROCORE_DAP_TIMEOUT ?? 120000));

// Copies READY to video RAM and waits: the Model III's at $3C00, and the Model II's at $F800 once port $FF maps it.
const ready = [...Buffer.from("READY")];
const model3 = [0xF3, 0x31, 0x00, 0x80, 0x21, 0x11, 0x00, 0x11, 0x00, 0x3C, 0x01, 0x05, 0x00, 0xED, 0xB0, 0x18, 0xFE, ...ready];
const model2 = [
    0xF3, 0x31, 0x00, 0x80, 0x3E, 0x80, 0xD3, 0xFF, 0x21, 0x15, 0x00, 0x11, 0x00, 0xF8, 0x01, 0x05, 0x00, 0xED, 0xB0,
    0x18, 0xFE, ...ready
];

function image(size, code) {
    const bytes = Buffer.alloc(size);
    Buffer.from(code).copy(bytes);
    return bytes;
}

const roms = mkdtempSync(join(tmpdir(), "retrocore-trs80-"));
writeFileSync(join(roms, "8041364.u104"), image(0x2000, model3));
writeFileSync(join(roms, "8040332.u105"), image(0x1000, []));
writeFileSync(join(roms, "8040316c.u106"), image(0x800, []));
writeFileSync(join(roms, "8044316a.u36"), image(0x800, []));
writeFileSync(join(roms, "8075332.u69"), image(0x1000, model3));
writeFileSync(join(roms, "8049007.u103"), image(0x800, []));
writeFileSync(join(roms, "u54.u11"), image(0x800, model2));
writeFileSync(join(roms, "8043316.u9"), image(0x800, []));

// Sets drive select's wait bit with no disk command, which holds the Z80 until the controller asks for data or
// finishes: here, for good.
const held = join(roms, "held");
mkdirSync(held);
writeFileSync(join(held, "8041364.u104"), image(0x2000, [0xF3, 0x3E, 0xC1, 0xD3, 0xF4, 0x18, 0xFE]));
writeFileSync(join(held, "8040332.u105"), image(0x1000, []));
writeFileSync(join(held, "8040316c.u106"), image(0x800, []));

// Starts an FD1793 step, then asserts WAIT. The controller finishes the step without needing media.
const finiteWait = join(roms, "finite-wait");
mkdirSync(finiteWait);
writeFileSync(join(finiteWait, "8041364.u104"), image(0x2000, [
    0xF3,                         // DI
    0x3E, 0x81, 0xD3, 0xF4,      // Select drive 0 without WAIT.
    0x3E, 0x50, 0xD3, 0xF0,      // Submit Step In with track update.
    0x3E, 0xC1, 0xD3, 0xF4,      // Assert WAIT while the controller is busy.
    0x3E, 0x2A,                   // Held by WAIT; next instruction is at $000F.
    0x18, 0xFE                    // JR to itself.
]));
writeFileSync(join(finiteWait, "8040332.u105"), image(0x1000, []));
writeFileSync(join(finiteWait, "8040316c.u106"), image(0x800, []));

function drop(name) {
    for (let index = events.length - 1; index >= 0; index--) {
        if (events[index].event === name) events.splice(index, 1);
    }
}

async function launch(args, filters, directory = roms) {
    events.length = 0;
    await request("setExceptionBreakpoints", { filters: filters ?? [] });
    await request("launch", { ...(directory ? { romDirectory: directory } : {}), stopOnEntry: false, speed: "max", ...args });
    await request("configurationDone");
}

async function type(text) {
    for (const character of text) await request("retro/key", { code: character === "\r" ? 13 : character.charCodeAt(0) });
}

// The exception filters the launch's capabilities event lists.
function filters() {
    const capabilities = events.filter(message => message.event === "capabilities").at(-1);
    return capabilities.body.capabilities.exceptionBreakpointFilters.map(filter => filter.filter);
}

async function screen(text) {
    drop("retro/frame");
    for (;;) {
        const frame = await event("retro/frame");
        if (frame.rows.join("\n").includes(text)) return frame;
        if (!frame.running) throw new Error(`Stopped before ${text}.`);
    }
}

try {
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });

    await assert.rejects(
        request("launch", { machine: "trs80-model3", romDirectory: join(roms, "none") }),
        /8040316c\.u106 \(or 8040316b\.u106\) is missing/);

    const cases = [
        { args: { machine: "trs80-model3" }, thread: "Model III Z80", model: "Model III", columns: 64 },
        { args: { machine: "trs80-model4" }, thread: "Model 4 Z80", model: "Model 4", columns: 64 },
        { args: { machine: "trs80-model3", model: "4p" }, thread: "Model 4P Z80", model: "Model 4P", columns: 64 },
        { args: { machine: "trs80-model2" }, thread: "Model II Z80", model: "Model II", columns: 80 },
        { args: { machine: "trs80-model2", model: "16" }, thread: "Model 16 Z80", model: "Model 16", columns: 80 }
    ];

    for (const test of cases) {
        if (process.env.RETROCORE_DAP_VERBOSE === "1") console.log(`launching ${JSON.stringify(test.args)}`);
        await launch(test.args);
        const frame = await screen("READY");
        assert.equal(frame.model, test.model);
        assert.equal(frame.columns, test.columns);
        assert.equal((await request("threads")).threads[0].name, test.thread);
        const hardware = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
        assert.equal(hardware.model.name, `TRS-80 ${test.model}`);
        assert.ok(!filters().includes("basicStart"), `the ${test.model}'s stand-in ROM has no BASIC to stop in`);
    }

    // Without dumps, the SDK's builds boot: the Model III to its first prompt, stepping in Model3.asm's source, and
    // the Model II to its boot ROM's request for a disk.
    // A Z80 held by the disk controller's wait for longer than an instruction can take runs on, and pauses where it
    // is held, inside its instruction.
    if (process.env.RETROCORE_DAP_VERBOSE === "1") console.log("held by the wait");
    await launch({ machine: "trs80-model3", diskController: true }, [], held);
    for (let frame = 0; frame < 5; frame++) {
        drop("retro/frame");
        assert.ok((await event("retro/frame")).running, "the held machine runs on");
    }
    drop("stopped");
    await request("pause", { threadId: 1 });
    const paused = await event("stopped");
    assert.equal(paused.reason, "pause", `the held machine pauses (${paused.description ?? paused.reason})`);
    assert.equal((await request("stackTrace", { threadId: 1 })).stackFrames[0].instructionPointerReference, "0x0005",
        "it pauses at the instruction it is held in, after OUT");

    await launch({ machine: "trs80-model3", diskController: true, stopOnEntry: true, textOnly: true }, [], finiteWait);
    assert.equal((await event("stopped")).reason, "entry");
    const maxCycles = 100;
    const run = await request("retro/runUntil", { stopOn: { kind: "instruction", address: 0xFFFF }, maxCycles });
    const exhausted = await event("retro/run/result", body => body.launchId === run.launchId && body.runId === run.runId);
    assert.equal(exhausted.outcome, "cycleBudgetExceeded");
    assert.ok(exhausted.cycles > run.startCycle + maxCycles, "the disk wait outlasts the deadline");
    assert.equal((await event("stopped")).reason, "pause");
    assert.equal((await request("stackTrace", { threadId: 1 })).stackFrames[0].instructionPointerReference, "0x000F",
        "budget expiry parks at the first instruction boundary after the disk wait");

    if (process.env.RETROCORE_DAP_VERBOSE === "1") console.log("SDK ROMs");
    await launch({ machine: "trs80-model3" }, [], null);
    assert.deepEqual(filters(), ["machineReset", "contracts", "basicStart", "basicErrors", "basicHandledErrors", "basicStop"],
        "the Model III's BASIC offers its stops");
    await screen("Cass?");
    drop("stopped");
    await request("pause", { threadId: 1 });
    await event("stopped");
    const frames = (await request("stackTrace", { threadId: 1 })).stackFrames;
    assert.ok(frames.some(frame => /Model3\.asm|Level2\.asm/.test(frame.source?.path ?? "")), "a frame in the ROM's source");

    // Model III BASIC is Level II's, so RUN stops on the BASIC thread at its first statement.
    await request("setExceptionBreakpoints", { filters: ["basicStart"] });
    await request("continue", { threadId: 1 });
    for (const keys of ["\r", "\r"]) {
        await type(keys);
        await new Promise(resolve => setTimeout(resolve, 500));
    }

    await screen("READY");
    await type("10 A=1\r");
    await screen(">10 A=1");
    drop("stopped");
    await type("RUN\r");
    const basic = await event("stopped");
    assert.equal(basic.threadId, 2, "RUN stops on the BASIC thread");
    assert.equal((await request("stackTrace", { threadId: 2 })).stackFrames[0].name, "10: A=1");
    await request("continue", { threadId: 2 });
    await launch({ machine: "trs80-model2" }, [], null);
    await screen("INSERT DISKETTE");

    // The Model III with Level I BASIC, from Level1.asm's Model III build, has a BASIC thread too: RUN stops on it at
    // its first statement, and a pause at INPUT shows the INPUT's line.
    await launch({ machine: "trs80-model3", rom: "level1" }, ["basicStart"], null);
    await screen("READY");
    assert.ok(filters().includes("basicStart"), "Level I has a BASIC thread");
    const written = await request("retro/basic/write", { text: "10 INPUT A\n20 P. A*2\n30 GOTO 10\n" });
    assert.equal(written.success, true, JSON.stringify(written.diagnostics));
    drop("stopped");
    await type("RUN\r");
    const levelOne = await event("stopped");
    assert.deepEqual([levelOne.threadId, levelOne.description], [2, "RUN starts at 10."]);
    await request("continue", { threadId: 2 });
    await new Promise(resolve => setTimeout(resolve, 500));
    await request("pause", { threadId: 2 });
    await event("stopped");
    assert.equal((await request("stackTrace", { threadId: 2 })).stackFrames[0].name, "10: INPUT A");

    // A basic launch of a Level I file loads it into the Model III's Level I and stops at its first statement.
    const file = join(roms, "program.level1.bas");
    writeFileSync(file, "10 A=5\n20 P. A*2\n");
    await launch({ machine: "trs80-model3", rom: "level1", basic: file, stopOnEntry: true }, [], null);
    const entry = await event("stopped");
    assert.deepEqual([entry.threadId, entry.reason], [2, "entry"]);
    const first = (await request("stackTrace", { threadId: 2 })).stackFrames[0];
    assert.deepEqual([first.name, first.source?.path, first.line], ["10: A=5", file, 1]);

    // An error in a DATA item that READ is taking stops in the READ's line, as on the Model I.
    const data = join(roms, "data.level1.bas");
    writeFileSync(data, "10 READ A\n20 DATA 1+\n");
    await launch({ machine: "trs80-model3", rom: "level1", basic: data }, ["basicErrors"], null);
    const dataError = await event("stopped");
    assert.deepEqual([dataError.threadId, dataError.reason, dataError.description], [2, "exception", "WHAT? in 10 (code 2)."]);
    assert.equal((await request("stackTrace", { threadId: 2 })).stackFrames[0].name, "10: READ A");
    await assert.rejects(request("launch", { machine: "trs80-model4", rom: "level1" }), /Only the Model III has Level I/);

    // A disks value that is not a list, or an entry that is neither a path nor null, is refused, rather than
    // launching with the drives empty.
    for (const machine of ["trs80-model3", "trs80-model2"]) {
        await assert.rejects(request("launch", { machine, disks: "trsdos.dsk" }), /disks must be a list/);
        await assert.rejects(request("launch", { machine, disks: [null, 7] }), /disks\[1\] must be an image's path/);
    }

    if (process.env.RETROCORE_DAP_VERBOSE === "1") console.log("reset");
    // Machine reset stops at power-on, at $0000, and the Model II's reset switch restarts the boot ROM there too.
    await launch({ machine: "trs80-model2" }, ["machineReset"]);
    let stopped = await event("stopped");
    assert.equal(stopped.description, "The machine reset as it powered on.");
    await request("continue", { threadId: 1 });
    await screen("READY");
    drop("stopped");
    await request("retro/reset");
    stopped = await event("stopped");
    assert.equal(stopped.reason, "breakpoint");
    assert.equal(stopped.description, "The machine reset.");
    const top = (await request("stackTrace", { threadId: 1 })).stackFrames[0];
    assert.equal(top.instructionPointerReference, "0x0000");

    await request("disconnect");
    console.log("Model III, 4, 4P, II and 16 DAP passed: missing dumps, each machine's boot from stand-in dumps and the SDK's ROMs, BASIC's thread, threads, hardware and the Model II's reset stop.");
} finally {
    clearTimeout(timeout);
    close();
    rmSync(roms, { recursive: true, force: true });
}
if (failure()) throw failure();
