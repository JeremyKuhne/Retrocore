// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// BBC Micro DAP integration, with nothing external: boots a Model B on the ROMs built from the SDK's sources, steps
// from the 6502 sample into Mos.asm and out again, stops at a breakpoint in BASIC's source when a typed PRINT runs, and
// at the MOS's reset. Then, on the ROM dumps in RETROCORE_BBC_ROMS, or %USERPROFILE%\Retrocore\bbc-roms\extract, when
// they are there, and otherwise on the sources (launched with a blank romDirectory, as ${env:RETROCORE_BBC_ROMS} gives
// when it is not set), boots a Model A and a Model B and lists the Model B's hardware.

import { resolve, join } from "node:path";
import { readFileSync, writeFileSync, existsSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import assert from "node:assert/strict";
import { startDap } from "./DapClient.mjs";

const root = resolve(import.meta.dirname, "..");
const romDirectory = process.env.RETROCORE_BBC_ROMS
    ?? join(process.env.RETROCORE_CACHE ?? join(process.env.USERPROFILE ?? "", "Retrocore"), "bbc-roms", "extract");

const dumps = existsSync(join(romDirectory, "bbcb", "os12.rom")) || existsSync(join(romDirectory, "os12.rom"));
const roms = dumps ? romDirectory : "";                         // the last parts' romDirectory: blank for the sources
const fromSources = dumps ? "" : ", from the SDK's sources";
const sdkRoms = join(root, "src", "Retrocore.Machines.Acorn", "Roms");
const mos = join(sdkRoms, "Mos", "Vectors.asm");
const statements = join(sdkRoms, "Basic", "Statements.asm");
const hello = join(root, "sample", "bbc", "hello.asm");

// The host takes RETROCORE_BBC_ROMS when a launch names no dumps, so the source's part must not see it.
delete process.env.RETROCORE_BBC_ROMS;
const { request, event, events, fail, close, failure } = startDap(root);
let last = "";
const timeout = setTimeout(() => fail(new Error(`BBC Micro DAP integration timed out; the screen was:
${last}`)), Number(process.env.RETROCORE_DAP_TIMEOUT ?? 240000));
const verbose = process.env.RETROCORE_DAP_VERBOSE === "1";
function phase(text) { if (verbose) console.log(`${new Date().toISOString()} ${text}`); }

// Waits for a running frame whose screen satisfies a test, while the machine runs.
async function screen(test, what) {
    phase(`waiting for ${what}`);
    drop("retro/frame");
    for (;;) {
        const frame = await event("retro/frame");
        last = `${frame.rows.join("\n")}\n(${frame.cycles} cycles)`;
        if (test(frame.rows.join("\n"))) return frame;
        if (!frame.running) throw new Error(`Stopped before ${what}.`);
    }
}

// Waits for some frames to pass while the machine runs.
async function frames(count) {
    drop("retro/frame");
    for (let index = 0; index < count; index++) await event("retro/frame");
}

// Forgets queued events of a kind, so a wait sees only what happens next.
function drop(name) {
    for (let index = events.length - 1; index >= 0; index--) {
        if (events[index].event === name) events.splice(index, 1);
    }
}

async function type(text) {
    for (const character of text) await request("retro/key", { code: character === "\r" ? 13 : character.charCodeAt(0) });
}

async function launch(args, filters) {
    events.length = 0;
    phase("launching");
    await request("setExceptionBreakpoints", { filters: filters ?? [] });
    await request("launch", { machine: "bbc", romDirectory: roms, stopOnEntry: false, speed: "max", sound: "off", ...args });
    await request("configurationDone");
    phase("configured");
}

const stopped = async reason => assert.equal((await event("stopped")).reason, reason);
const top = async () => (await request("stackTrace", { threadId: 1 })).stackFrames;
const basicFrames = async () => (await request("stackTrace", { threadId: 2 })).stackFrames;

// A BBC BASIC program for the BASIC thread, with a FOR loop calling a PROC.
const programLines = ["10 A=1:B$=\"HI\"", "20 FOR I%=1 TO 3:PROCADD:NEXT", "30 STOP", "40 PRINT A;B$", "50 END",
    "100 DEF PROCADD", "110 A=A+I%", "120 ENDPROC"];
const program = join(tmpdir(), `retrocore-bbc-${process.pid}.bbcbasic.bas`);
writeFileSync(program, `${programLines.join("\n")}\n`);

// A one-line program for the Model A; after a semicolon PRINT gives a number no field.
const modelA = join(tmpdir(), `retrocore-bbc-${process.pid}-a.bbcbasic.bas`);
writeFileSync(modelA, "10 PRINT \"MODEL A\";6*7\n");

// An empty 80-track DFS disk: a catalogue with no files and 800 sectors, the count's top two bits in &106.
const disk = join(tmpdir(), `retrocore-bbc-${process.pid}.ssd`);
const blank = Buffer.alloc(80 * 10 * 256);
blank[0x106] = 0x03;
blank[0x107] = 0x20;
writeFileSync(disk, blank);

try {
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });

    // The MOS from the SDK's source: the sample's JSR OSASCI steps into OSASCI in Mos.asm's Vectors.asm, and stepping
    // out comes back after the JSR.
    const sampleLines = readFileSync(hello, "utf8").split(/\r?\n/);
    const jsr = sampleLines.findIndex(line => line.trim() === "jsr OSASCI") + 1;
    const call = sampleLines.findIndex(line => line.trim() === "jsr SHOW") + 1;
    events.length = 0;
    await request("launch", { machine: "bbc", sdkRoms, romDirectory: "", source: hello, stopOnEntry: true, speed: "max", sound: "off" });
    assert.equal((await request("setBreakpoints", { source: { path: hello }, breakpoints: [{ line: jsr }] })).breakpoints[0].verified, true);
    await request("setExceptionBreakpoints", { filters: [] });
    await request("configurationDone");
    await stopped("entry");
    assert.equal((await request("threads")).threads[0].name, "Model B 6502");
    const sdkHardware = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
    assert.equal(sdkHardware.rom.value, "MOS 1.20, BASIC II, DNFS 1.20, from the SDK's sources");
    await request("continue", { threadId: 1 });
    await stopped("breakpoint");
    let stack = await top();
    assert.equal(stack[0].line, jsr);
    assert.equal(stack[1].line, call, "SHOW was called from PRINT");
    await request("stepIn", { threadId: 1 });
    await stopped("step");
    stack = await top();
    assert.equal(stack[0].source.path.toLowerCase(), mos.toLowerCase());
    assert.equal(stack[0].name, "OSASCI");
    await request("stepOut", { threadId: 1 });
    await stopped("step");
    stack = await top();
    assert.equal(stack[0].source.path.toLowerCase(), hello.toLowerCase());
    assert.equal(stack[0].line, jsr + 1);
    await request("setBreakpoints", { source: { path: hello }, breakpoints: [] });
    await request("continue", { threadId: 1 });
    await screen(text => text.includes("HELLO FROM THE 6502"), "the sample's message");

    // A breakpoint in BASIC's source, on PRINT's routine, stops when a typed PRINT runs, with BASIC paged in.
    const printLine = readFileSync(statements, "utf8").split(/\r?\n/).findIndex(line => line.startsWith("PRINT_STATEMENT:")) + 2;
    await launch({ sdkRoms, romDirectory: "" });
    await screen(text => /^>/m.test(text), "BASIC's prompt");
    await frames(5);
    const set = await request("setBreakpoints", { source: { path: statements }, breakpoints: [{ line: printLine }] });
    assert.equal(set.breakpoints[0].verified, true, JSON.stringify(set.breakpoints[0]));
    await type("PRINT 6*7\r");
    await stopped("breakpoint");
    stack = await top();
    assert.equal(stack[0].source.path.toLowerCase(), statements.toLowerCase());
    assert.equal(stack[0].line, printLine);
    await request("setBreakpoints", { source: { path: statements }, breakpoints: [] });
    await request("continue", { threadId: 1 });
    await screen(text => /^ *42 *$/m.test(text), "PRINT's 42");

    // A BBC BASIC file launched on the BASIC thread: it stops on the first statement, steps through colons, stops in a
    // PROC with the PROC's caller below it, shows the variables and the FOR loop, and stops at STOP.
    events.length = 0;
    await request("launch", { machine: "bbc", sdkRoms, romDirectory: "", basic: program, stopOnEntry: true, speed: "max", sound: "off" });
    await request("setExceptionBreakpoints", { filters: [] });
    await request("configurationDone");
    await stopped("entry");
    assert.equal((await request("threads")).threads[1].name, "BASIC");
    let basicTop = (await basicFrames())[0];
    assert.equal(basicTop.name, "10: A=1");
    assert.equal(basicTop.source.path.toLowerCase(), program.toLowerCase());
    await request("next", { threadId: 2 });
    await stopped("step");
    assert.equal((await basicFrames())[0].name, "10: B$=\"HI\"");
    await request("next", { threadId: 2 });
    await stopped("step");
    assert.equal((await basicFrames())[0].name, "20: FOR I%=1 TO 3");
    const set110 = await request("setBreakpoints", { source: { path: program }, breakpoints: [{ line: 7 }] });
    assert.equal(set110.breakpoints[0].verified, true, JSON.stringify(set110.breakpoints[0]));
    await request("continue", { threadId: 2 });
    await stopped("breakpoint");
    const inside = await basicFrames();
    assert.deepEqual(inside.map(frame => frame.name), ["110: A=A+I%", "20: PROCADD (PROC)"]);
    const scopes = Object.fromEntries((await request("scopes", { frameId: inside[0].id })).scopes.map(scope => [scope.name, scope.variablesReference]));
    const values = Object.fromEntries((await request("variables", { variablesReference: scopes.Variables })).variables.map(item => [item.name, item.value]));
    assert.deepEqual([values.A, values.B$, values["I%"]], ["1", "\"HI\"", "1"], JSON.stringify(values));
    const loops = (await request("variables", { variablesReference: scopes.Loops })).variables;
    assert.equal(loops[0].name, "I%");
    assert.equal(loops[0].value, "1 TO 3 STEP 1 (FOR in line 20)");
    const evaluate = async expression => (await request("evaluate", { expression, frameId: inside[0].id, context: "watch" })).result;
    assert.equal(await evaluate("A*10+I%"), "11");
    assert.equal(await evaluate("LEFT$(B$,1)+\"!\""), "\"H!\"");
    await request("setVariable", { variablesReference: scopes.Variables, name: "B$", value: "\"BYE\"" });
    assert.equal(await evaluate("B$"), "\"BYE\"");
    await request("setBreakpoints", { source: { path: program }, breakpoints: [] });
    await request("stepOut", { threadId: 2 });
    await stopped("step");
    assert.equal((await basicFrames())[0].name, "20: NEXT");

    // STOP stops the program, and BASIC reports it.
    await request("setExceptionBreakpoints", { filters: ["basicStart", "basicStop"] });
    await request("continue", { threadId: 2 });
    assert.equal((await event("stopped")).description, "STOP in 30.");
    const listed = await request("retro/basic/program");
    assert.equal(listed.dialect, "bbcbasic");
    assert.equal(listed.text, `${programLines.join("\n")}\n`);
    await request("setExceptionBreakpoints", { filters: [] });
    await request("continue", { threadId: 2 });
    await screen(text => text.includes("STOP at line 30"), "the STOP's report");

    // BREAK stops at the MOS's reset with the reset filter on.
    await request("setExceptionBreakpoints", { filters: ["machineReset"] });
    await request("retro/reset");
    await stopped("breakpoint");
    stack = await top();
    assert.match(stack[0].source.path, /Reset\.asm$/i);
    await request("continue", { threadId: 1 });

    // A Model A boots to BASIC with no disk interface, and runs a BASIC file.
    await launch({ model: "bbca", basic: modelA });
    await screen(text => text.includes("BBC Computer 16K") && /^MODEL A42 *$/m.test(text), "the Model A's program");
    assert.equal((await request("threads")).threads[0].name, "Model A 6502");

    // A Model B boots to BASIC with the DFS, and lists its hardware.
    await launch({ model: "bbcb", disks: [disk] });
    await screen(text => text.includes("BBC Computer 32K") && text.includes("Acorn DFS") && /^>/m.test(text), "the Model B's prompt");
    const hardware = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
    assert.deepEqual(Object.keys(hardware), ["model", "cpu", "rom", "memory", "video", "sound", "cassette", "disk"]);
    assert.equal(hardware.rom.value, `MOS 1.20, BASIC II, DNFS 1.20${fromSources}`);
    assert.equal(hardware.memory.value, "32 KB");
    assert.deepEqual(hardware.disk.devices, ["disk0", "disk1"]);

    // SAVE writes a program to the disk, which is then changed: it saves back to its SSD, whose catalogue names it.
    await frames(5);
    await type("10 PRINT \"SAVED\"\rSAVE \"HELLO\"\r*CAT\r");
    await screen(text => /HELLO/.test(text) && /^>$/m.test(text.trimEnd().split("\n").pop() ?? ""), "the catalogue");
    let drive = (await request("retro/devices")).devices.find(device => device.id === "disk0");
    assert.equal(drive.media.format, "SSD");
    assert.equal(drive.media.changed, true);
    const saved = await request("retro/device", { id: "disk0", action: "save", supportsRetrocoreMedia: true });
    assert.equal(saved.outcome, "saved", JSON.stringify(saved));
    assert.equal(readFileSync(disk).subarray(8, 15).toString("latin1"), "HELLO  ", "the catalogue's first name");

    await request("disconnect");
    console.log("BBC Micro DAP passed: stepping from the 6502 sample into Mos.asm and out, a breakpoint in BASIC's source, "
        + "a BBC BASIC program on the BASIC thread, the reset stop, a BASIC file on the Model A, and the Model B saving "
        + `a program to an SSD that saves to its image, ${dumps ? `the last parts on the dumps in ${romDirectory}` : "all from the SDK's sources"}.`);
} finally {
    clearTimeout(timeout);
    close();
    for (const file of [program, modelA, disk]) if (existsSync(file)) unlinkSync(file);
}
if (failure()) throw failure();
