// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Atari 800 DAP integration, with nothing external: the OS, the floating point package, Atari BASIC and the 810's
// firmware all built from the SDK's sources. An Atari BASIC file launched on the BASIC thread stops on its first
// statement, steps through its statements, stops at a breakpoint in a GOSUB with the GOSUB's frame below it, and shows
// its variables and FOR loop from BASIC's own tables; the program in memory reads and writes as text, and an error
// stops at its statement. A breakpoint in BASIC's cartridge (AtariBasic/Execution.asm) and one in the OS (Os/Editor.asm)
// stop as BASIC runs a typed line. Then the machine starts from a binary load file (.xex) and from a disk, booted by the 810, and the
// 6502 sample runs.

import { startDap } from "./DapClient.mjs";
import { resolve, join } from "node:path";
import { readFileSync, writeFileSync, unlinkSync, mkdirSync } from "node:fs";
import assert from "node:assert/strict";

const root = resolve(import.meta.dirname, "..");
const sdkRoms = join(root, "src", "Retrocore.Machines.Atari", "Roms");
const hello = join(root, "sample", "atari", "hello.asm");

// The host takes RETROCORE_ATARI_ROMS when a launch names no dumps, so the sources' parts must not see it.
delete process.env.RETROCORE_ATARI_ROMS;
const { request, event, events, fail, close, failure } = startDap(root);
let last = "";
const timeout = setTimeout(() => fail(new Error(`Atari DAP integration timed out; the screen was:
${last}`)), Number(process.env.RETROCORE_DAP_TIMEOUT ?? 240000));
const frames = async thread => (await request("stackTrace", { threadId: thread })).stackFrames;
const stopped = async reason => {
    const stop = await event("stopped");
    assert.equal(stop.reason, reason, JSON.stringify(stop));
    return stop;
};

// Drops the events of a kind that came before now.
function drop(name) {
    for (let index = events.length - 1; index >= 0; index--) {
        if (events[index].event === name) events.splice(index, 1);
    }
}

// Waits for a running frame whose screen satisfies a test, while the machine runs.
async function screen(test, what) {
    drop("retro/frame");
    for (;;) {
        const frame = await event("retro/frame");
        last = `${frame.rows.join("\n")}\n(${frame.cycles} cycles)`;
        if (test(frame.rows.join("\n"))) return frame;
        if (!frame.running) throw new Error(`Stopped before ${what}.`);
    }
}

// The first line after a label in a source, 1-based: the label's first instruction.
function after(path, label) {
    const lines = readFileSync(path, "utf8").split("\n");
    const index = lines.findIndex(line => line.startsWith(`${label}:`));
    assert.ok(index >= 0, `${label} is not in ${path}`);
    return index + 2;
}

async function type(text) {
    for (const key of text) await request("retro/key", { code: key.charCodeAt(0) });
}

// A boot program: puts HI at the top left of the screen, through SAVMSC, and waits.
const code = [0xA0, 0x00, 0xA9, 0x28, 0x91, 0x58, 0xC8, 0xA9, 0x29, 0x91, 0x58];

const folder = join(root, "artifacts", "atari-dap");
mkdirSync(folder, { recursive: true });
const file = join(folder, `loop-${process.pid}.atari.bas`);
writeFileSync(file, [
    "REM retrocore atari",
    "20 A=1:B=2",
    "30 FOR I=1 TO 3:GOSUB 100:NEXT I",
    "40 PRINT A;\" \";B",
    "50 END",
    "100 A=A+I",
    "110 RETURN",
    ""
].join("\n"));

// A binary load file: the program at $2000, then RUNAD.
const program = [...code, 0x4C, 0x0B, 0x20];
const xex = join(folder, `hi-${process.pid}.xex`);
writeFileSync(xex, Buffer.from([
    0xFF, 0xFF, 0x00, 0x20, (0x2000 + program.length - 1) & 0xFF, (0x2000 + program.length - 1) >> 8, ...program,
    0xE0, 0x02, 0xE1, 0x02, 0x00, 0x20
]));

// A raw 8 KB ROM for the 800's right slot, which maps it at $8000.
const right = join(folder, `right-${process.pid}.rom`);
writeFileSync(right, Buffer.alloc(0x2000, 0xEA));

// A disk whose boot sector, loaded at $0700, runs the same program from $0706.
const atr = join(folder, `hi-${process.pid}.atr`);
const sectors = 720;
const image = Buffer.alloc(16 + sectors * 128);
const paragraphs = sectors * 128 / 16;
image.set([0x96, 0x02, paragraphs & 0xFF, (paragraphs >> 8) & 0xFF, 0x80, 0x00, (paragraphs >> 16) & 0xFF], 0);
image.set([0x00, 0x01, 0x00, 0x07, 0x11, 0x07, ...code, 0x4C, 0x11, 0x07], 16);
writeFileSync(atr, image);

try {
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });

    // An Atari BASIC file on the BASIC thread, stopped on its first statement, in the file's own line.
    await request("launch", { machine: "atari800", sdkRoms, basic: file, stopOnEntry: true });
    await request("configurationDone");
    await stopped("entry");
    assert.equal((await request("threads")).threads[1].name, "BASIC");
    let top = (await frames(2))[0];
    assert.equal(top.name, "20: A=1");
    assert.equal(top.source.path.toLowerCase(), file.toLowerCase());

    // A step goes to the statement after the colon, then to the next line.
    await request("next", { threadId: 2 });
    await stopped("step");
    assert.equal((await frames(2))[0].name, "20: B=2");
    await request("next", { threadId: 2 });
    await stopped("step");
    assert.equal((await frames(2))[0].name, "30: FOR I=1 TO 3");

    // A breakpoint in the subroutine stops with the GOSUB's frame below it.
    const set = await request("setBreakpoints", { source: { path: file }, breakpoints: [{ line: 6 }] });
    assert.equal(set.breakpoints[0].verified, true, JSON.stringify(set.breakpoints[0]));
    await request("continue", { threadId: 2 });
    await stopped("breakpoint");
    const inside = await frames(2);
    assert.deepEqual(inside.map(frame => frame.name), ["100: A=A+I", "30: GOSUB 100 (GOSUB)"]);

    // The variables and the FOR loop, from BASIC's value table and run-time stack, and expressions in its arithmetic.
    const scopes = Object.fromEntries((await request("scopes", { frameId: inside[0].id })).scopes.map(scope => [scope.name, scope.variablesReference]));
    const values = Object.fromEntries((await request("variables", { variablesReference: scopes.Variables })).variables.map(item => [item.name, item.value]));
    assert.deepEqual([values.A, values.B, values.I], ["1", "2", "1"]);
    const loops = (await request("variables", { variablesReference: scopes.Loops })).variables;
    assert.equal(loops[0].name, "I");
    const evaluate = async expression => (await request("evaluate", { expression, frameId: inside[0].id, context: "watch" })).result;
    assert.equal(await evaluate("A*10+B/4"), "10.5");
    await request("setVariable", { variablesReference: scopes.Variables, name: "B", value: "7" });
    assert.equal(await evaluate("B"), "7");
    await request("setBreakpoints", { source: { path: file }, breakpoints: [] });

    // Step out returns to the statement after the GOSUB.
    await request("stepOut", { threadId: 2 });
    await stopped("step");
    assert.equal((await frames(2))[0].name, "30: NEXT I");

    // The program in memory reads as text, and writing text puts a new program in.
    const listed = await request("retro/basic/program");
    assert.equal(listed.dialect, "atari");
    assert.equal(listed.text.split("\n")[0], "20 A=1:B=2");
    const written = await request("retro/basic/write", { text: "10 PRINT \"NEW\"\n20 GOTO 10\n" });
    assert.equal(written.success, true, JSON.stringify(written.diagnostics));
    assert.equal((await request("retro/basic/program")).text, "10 PRINT \"NEW\"\n20 GOTO 10\n");
    const refused = await request("retro/basic/write", { text: "10 PRINT (\n" });
    assert.equal(refused.success, false);

    // An error stops at its statement with Atari BASIC's message.
    await request("setExceptionBreakpoints", { filters: ["basicErrors"] });
    assert.equal((await request("retro/basic/write", { text: "10 A=1:GOTO 999\n" })).success, true);
    await request("continue", { threadId: 1 });
    await type("RUN\r");
    const error = await stopped("exception");
    assert.match(error.description, /ERROR- 12: line not found/);
    assert.equal((await frames(2))[0].name, "10: GOTO 999");

    // A breakpoint in BASIC's cartridge, at the statement dispatch, and one in the OS's screen editor, stop as BASIC
    // runs a typed line.
    await request("setExceptionBreakpoints", { filters: [] });
    const basicSource = join(sdkRoms, "AtariBasic", "Execution.asm");
    const inBasic = await request("setBreakpoints", { source: { path: basicSource }, breakpoints: [{ line: after(basicSource, "EXECUTE_STATEMENT") }] });
    assert.equal(inBasic.breakpoints[0].verified, true, JSON.stringify(inBasic.breakpoints[0]));
    await request("continue", { threadId: 1 });
    await type("PRINT 1\r");
    await stopped("breakpoint");
    assert.equal((await frames(1))[0].source.path.toLowerCase(), basicSource.toLowerCase());
    await request("setBreakpoints", { source: { path: basicSource }, breakpoints: [] });

    const osSource = join(sdkRoms, "Os", "Editor.asm");
    const inOs = await request("setBreakpoints", { source: { path: osSource }, breakpoints: [{ line: after(osSource, "EDITOR_PUT") }] });
    assert.equal(inOs.breakpoints[0].verified, true, JSON.stringify(inOs.breakpoints[0]));
    await request("continue", { threadId: 1 });
    await stopped("breakpoint");
    assert.equal((await frames(1))[0].source.path.toLowerCase(), osSource.toLowerCase());
    await request("setBreakpoints", { source: { path: osSource }, breakpoints: [] });

    // An .xex boots from drive 1 and runs, with a raw ROM in the right slot and a tape that can be locked.
    await request("launch", {
        machine: "atari800", sdkRoms, executable: xex, basicCartridge: "none", rightCartridge: right, cassette: xex,
        stopOnEntry: false, speed: "max"
    });
    await request("configurationDone");
    await screen(text => text.startsWith("HI"), "the .xex's HI");
    const regions = (await request("retro/memory/map", { memoryReference: "0x0000" })).regions;
    assert.equal(regions.find(region => region.start === 0x8000)?.name, "Right cartridge", JSON.stringify(regions));
    await request("retro/device", { id: "cassette", action: "writeProtect", writeProtected: true });
    const cassette = (await request("retro/devices")).devices.find(candidate => candidate.id === "cassette");
    assert.equal(cassette.media.writeProtected, true, JSON.stringify(cassette));

    // A disk boots through the 810 and runs its boot sector.
    await request("launch", { machine: "atari800", sdkRoms, disks: [atr], basicCartridge: "none", stopOnEntry: false, speed: "max" });
    await request("configurationDone");
    await screen(text => text.startsWith("HI"), "the boot sector's HI");

    // The 6502 sample prints through CIO, with BASIC at READY.
    await request("launch", { machine: "atari800", sdkRoms, source: hello, stopOnEntry: false, speed: "max" });
    await request("configurationDone");
    await screen(text => text.includes("HELLO FROM THE 6502"), "the sample's line");

    console.log("Atari DAP passed: an Atari BASIC file stops on entry, steps, stops in a GOSUB with its caller below, shows its variables and FOR loop, reads and writes its program and stops on an error; breakpoints in AtariBasic.asm and Os.asm stop; and the machine runs an .xex with a raw ROM in the right slot and a locked tape, boots a disk through the 810 and runs the 6502 sample, all from the SDK's sources.");
} catch (error) {
    fail(error);
} finally {
    clearTimeout(timeout);
    close();
    for (const path of [file, xex, right, atr]) unlinkSync(path);
}

if (failure()) {
    console.error(failure());
    process.exit(1);
}
