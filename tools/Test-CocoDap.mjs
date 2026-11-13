// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Color Computer DAP integration, with nothing external: runs Color and Extended BASIC built from the SDK's
// sources, stepping from the 6809 sample into ColorBasic.asm, through the console out hook into ExtendedBasic.asm, and
// out again; with a disk, into DiskBasic.asm's hook instead; boots a CoCo 3 on its ROM built from the sources,
// stepping into its ColorBasic.asm, out, and on into a patch in Coco3.asm, and switches it to 80 columns; runs a Color
// BASIC file on the BASIC thread; then boots a
// CoCo 2 with the disk controller to Disk Extended Color BASIC, saves and lists a program on a disk, stops in the
// sample with its call stack, and boots a CoCo 3 to its 80-column screen. Those last parts run on the ROM dumps in
// RETROCORE_COCO_ROMS, or %USERPROFILE%\Retrocore\coco-roms\extract, when they are there, and otherwise on the
// sources, launched with a blank romDirectory as ${env:RETROCORE_COCO_ROMS} gives when it is not set.

import { resolve, join } from "node:path";
import { readFileSync, writeFileSync, existsSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import assert from "node:assert/strict";
import { startDap } from "./DapClient.mjs";

const root = resolve(import.meta.dirname, "..");
const romDirectory = process.env.RETROCORE_COCO_ROMS
    ?? join(process.env.RETROCORE_CACHE ?? join(process.env.USERPROFILE ?? "", "Retrocore"), "coco-roms", "extract");

const dumps = existsSync(romDirectory);
const roms = dumps ? romDirectory : "";                         // the last parts' romDirectory: blank for the sources
const fromSources = dumps ? "" : ", from the SDK's sources";
const sdkRoms = join(root, "src", "Retrocore.Machines.Coco", "Roms");
const colorBasic = join(sdkRoms, "ColorBasic.asm");
const extendedBasic = join(sdkRoms, "ExtendedBasic.asm");
const diskBasic = join(sdkRoms, "DiskBasic.asm");
const coco3 = join(sdkRoms, "Coco3.asm");
const hello = join(root, "sample", "coco", "hello.asm");

// The host takes RETROCORE_COCO_ROMS when a launch names no dumps, so the source's part must not see it.
delete process.env.RETROCORE_COCO_ROMS;
const { request, event, events, fail, close, failure } = startDap(root);
let last = "";
const timeout = setTimeout(() => fail(new Error(`Color Computer DAP integration timed out; the screen was:
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
    await request("launch", { machine: "coco", romDirectory: roms, stopOnEntry: false, speed: "max", sound: "off", ...args });
    await request("configurationDone");
    phase("configured");
}

const basicFrames = async () => (await request("stackTrace", { threadId: 2 })).stackFrames;
const stopped = async reason => assert.equal((await event("stopped")).reason, reason);

// A disk as Disk BASIC's DSKINI leaves it: 35 tracks of 18 256-byte sectors, every byte $FF.
const disk = join(tmpdir(), `retrocore-coco-${process.pid}.dsk`);
writeFileSync(disk, Buffer.alloc(35 * 18 * 256, 0xFF));

// A Color BASIC program for the BASIC thread.
const programLines = ["10 A=1:B$=\"HI\"", "20 FOR I=1 TO 3:GOSUB 100:NEXT I", "30 STOP", "40 PRINT A;B$", "100 A=A+I", "110 RETURN"];
const program = join(tmpdir(), `retrocore-coco-${process.pid}.colorbasic.bas`);
writeFileSync(program, `${programLines.join("\n")}\n`);
try {
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });

    // Color and Extended BASIC, from the SDK's sources: the sample's JSR [CHROUT] steps into PUTCHR in ColorBasic.asm,
    // then through the RAM hook into Extended BASIC's XVEC3, and stepping out twice comes back.
    const sampleLines = readFileSync(hello, "utf8").split(/\r?\n/);
    const chrout = sampleLines.findIndex(line => line.trim() === "jsr [CHROUT]") + 1;
    events.length = 0;
    await request("launch", {
        machine: "coco", model: "coco2", sdkRoms, source: hello, stopOnEntry: true, speed: "max", sound: "off"
    });
    assert.equal((await request("setBreakpoints", { source: { path: hello }, breakpoints: [{ line: chrout }] })).breakpoints[0].verified, true);
    await request("setExceptionBreakpoints", { filters: [] });
    await request("configurationDone");
    assert.equal((await event("stopped")).reason, "entry");
    const sdkHardware = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
    assert.equal(sdkHardware.rom.value, "Color BASIC 1.2, Extended Color BASIC 1.1, from the SDK's sources");
    await request("continue", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "breakpoint");
    await request("stepIn", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "step");
    let sdkStack = await request("stackTrace", { threadId: 1 });
    assert.equal(sdkStack.stackFrames[0].source.path.toLowerCase(), colorBasic.toLowerCase());
    assert.equal(sdkStack.stackFrames[0].name, "PUTCHR");
    assert.equal(sdkStack.stackFrames[1].line, chrout);
    await request("stepIn", { threadId: 1 });                   // into the hook's JMP, in RAM
    assert.equal((await event("stopped")).reason, "step");
    await request("stepIn", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "step");
    sdkStack = await request("stackTrace", { threadId: 1 });
    assert.equal(sdkStack.stackFrames[0].source.path.toLowerCase(), extendedBasic.toLowerCase());
    assert.equal(sdkStack.stackFrames[0].name, "XVEC3");
    await request("stepOut", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "step");
    sdkStack = await request("stackTrace", { threadId: 1 });
    assert.equal(sdkStack.stackFrames[0].source.path.toLowerCase(), colorBasic.toLowerCase());
    await request("stepOut", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "step");
    sdkStack = await request("stackTrace", { threadId: 1 });
    assert.equal(sdkStack.stackFrames[0].source.path.toLowerCase(), hello.toLowerCase());
    assert.equal(sdkStack.stackFrames[0].line, chrout + 1);
    await request("setBreakpoints", { source: { path: hello }, breakpoints: [] });
    await request("continue", { threadId: 1 });
    await screen(text => text.includes("EXTENDED COLOR BASIC 1.1") && text.includes("HELLO FROM THE 6809"), "the sample on the SDK's BASIC");

    // With a disk, Disk BASIC from the SDK's source takes the console out hook: stepping from PUTCHR through the hook
    // goes into DVEC3 in DiskBasic.asm.
    events.length = 0;
    await request("launch", {
        machine: "coco", model: "coco2", sdkRoms, source: hello, disks: [disk], stopOnEntry: true, speed: "max", sound: "off"
    });
    assert.equal((await request("setBreakpoints", { source: { path: hello }, breakpoints: [{ line: chrout }] })).breakpoints[0].verified, true);
    await request("setExceptionBreakpoints", { filters: [] });
    await request("configurationDone");
    assert.equal((await event("stopped")).reason, "entry");
    const diskHardware = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
    assert.equal(diskHardware.rom.value, "Color BASIC 1.2, Extended Color BASIC 1.1, from the SDK's sources");
    assert.equal(diskHardware.disk.value, "WD1793, Disk Extended Color BASIC 1.1");
    await request("continue", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "breakpoint");
    for (let step = 0; step < 3; step++) {                      // into PUTCHR, the hook's JMP, and the hook
        await request("stepIn", { threadId: 1 });
        assert.equal((await event("stopped")).reason, "step");
    }
    sdkStack = await request("stackTrace", { threadId: 1 });
    assert.equal(sdkStack.stackFrames[0].source.path.toLowerCase(), diskBasic.toLowerCase());
    assert.equal(sdkStack.stackFrames[0].name, "DVEC3");
    await request("setBreakpoints", { source: { path: hello }, breakpoints: [] });
    await request("continue", { threadId: 1 });
    await screen(text => text.includes("DISK EXTENDED COLOR BASIC 1.1") && text.includes("HELLO FROM THE 6809"), "the sample on the SDK's Disk BASIC");

    // A CoCo 3 boots its ROM built from the SDK's sources, which it copies into RAM and patches: the sample's
    // JSR [CHROUT] steps into PUTCHR in the CoCo 3's build of ColorBasic.asm, and stepping out comes back.
    events.length = 0;
    await request("launch", {
        machine: "coco", model: "coco3", sdkRoms, source: hello, stopOnEntry: true, speed: "max", sound: "off"
    });
    assert.equal((await request("setBreakpoints", { source: { path: hello }, breakpoints: [{ line: chrout }] })).breakpoints[0].verified, true);
    await request("setExceptionBreakpoints", { filters: [] });
    await request("configurationDone");
    assert.equal((await event("stopped")).reason, "entry");
    const coco3Hardware = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
    assert.equal(coco3Hardware.rom.value, "Color, Extended and Super Extended Color BASIC 2.0, from the SDK's sources");
    await request("continue", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "breakpoint");
    await request("stepIn", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "step");
    sdkStack = await request("stackTrace", { threadId: 1 });
    assert.equal(sdkStack.stackFrames[0].source.path.toLowerCase(), colorBasic.toLowerCase());
    assert.equal(sdkStack.stackFrames[0].name, "PUTCHR");
    await request("stepOut", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "step");
    sdkStack = await request("stackTrace", { threadId: 1 });
    assert.equal(sdkStack.stackFrames[0].source.path.toLowerCase(), hello.toLowerCase());
    assert.equal(sdkStack.stackFrames[0].line, chrout + 1);

    // The next character steps on from PUTCHR into SCRCHR, whose first instruction start-up patched: that is the
    // patch's line in Coco3.asm.
    await request("continue", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "breakpoint");
    let patch;
    for (let step = 0; step < 60 && !patch; step++) {
        await request("stepIn", { threadId: 1 });
        assert.equal((await event("stopped")).reason, "step");
        const frame = (await request("stackTrace", { threadId: 1 })).stackFrames[0];
        if (frame.source?.path.toLowerCase() === coco3.toLowerCase()) patch = frame;
    }
    assert.ok(patch, "stepping from PUTCHR reaches the SCRCHR patch in Coco3.asm");
    assert.equal(patch.name, "SCRCHR_PATCH");
    assert.match(readFileSync(coco3, "utf8").split(/\r?\n/)[patch.line - 1], /JMP PUTCHR3/);
    await request("setBreakpoints", { source: { path: hello }, breakpoints: [] });
    await request("continue", { threadId: 1 });
    await screen(text => text.includes("EXTENDED COLOR BASIC 2.0") && text.includes("HELLO FROM THE 6809"), "the sample on the CoCo 3's SDK ROM");

    // The CoCo 3 on the SDK's ROM switches to 80 columns.
    events.length = 0;
    await request("setExceptionBreakpoints", { filters: [] });
    await request("launch", { machine: "coco", model: "coco3", sdkRoms, stopOnEntry: false, speed: "max", sound: "off" });
    await request("configurationDone");
    await screen(text => text.includes("EXTENDED COLOR BASIC 2.0") && /\nOK/.test(text), "the CoCo 3's OK from the SDK's ROM");
    await frames(10);                                           // BASIC waiting for a key, not still starting
    await type("WIDTH 80\r");
    const sdkWide = await screen(text => /^OK/m.test(text) && !text.includes("EXTENDED"), "the 80-column screen from the SDK's ROM");
    assert.equal(sdkWide.columns, 80);

    // A Color BASIC file launched on the BASIC thread: it stops on the first statement, steps through colons, stops in
    // a GOSUB with the GOSUB's frame below it, shows the variables and the FOR loop, and stops at STOP.
    events.length = 0;
    await request("launch", { machine: "coco", model: "coco2", sdkRoms, basic: program, stopOnEntry: true, speed: "max", sound: "off" });
    await request("setExceptionBreakpoints", { filters: [] });
    await request("configurationDone");
    await stopped("entry");
    assert.equal((await request("threads")).threads[1].name, "BASIC");
    let top = (await basicFrames())[0];
    assert.equal(top.name, "10: A=1");
    assert.equal(top.source.path.toLowerCase(), program.toLowerCase());
    await request("next", { threadId: 2 });
    await stopped("step");
    assert.equal((await basicFrames())[0].name, "10: B$=\"HI\"");
    await request("next", { threadId: 2 });
    await stopped("step");
    assert.equal((await basicFrames())[0].name, "20: FOR I=1 TO 3");

    const set = await request("setBreakpoints", { source: { path: program }, breakpoints: [{ line: 5 }] });
    assert.equal(set.breakpoints[0].verified, true, JSON.stringify(set.breakpoints[0]));
    await request("continue", { threadId: 2 });
    await stopped("breakpoint");
    const inside = await basicFrames();
    assert.deepEqual(inside.map(frame => frame.name), ["100: A=A+I", "20: GOSUB 100 (GOSUB)"]);
    const scopes = Object.fromEntries((await request("scopes", { frameId: inside[0].id })).scopes.map(scope => [scope.name, scope.variablesReference]));
    const values = Object.fromEntries((await request("variables", { variablesReference: scopes.Variables })).variables.map(item => [item.name, item.value]));
    assert.deepEqual([values.A, values.B$, values.I], ["1", "\"HI\"", "1"], JSON.stringify(values));
    const loops = (await request("variables", { variablesReference: scopes.Loops })).variables;
    assert.equal(loops[0].name, "I");
    assert.equal(loops[0].value, "1 TO 3 STEP 1 (FOR in line 20)");
    const evaluate = async expression => (await request("evaluate", { expression, frameId: inside[0].id, context: "watch" })).result;
    assert.equal(await evaluate("A*10+I"), "11");
    assert.equal(await evaluate("LEFT$(B$,1)+\"!\""), "\"H!\"");
    await request("setVariable", { variablesReference: scopes.Variables, name: "B$", value: "\"BYE\"" });
    assert.equal(await evaluate("B$"), "\"BYE\"");
    await request("setBreakpoints", { source: { path: program }, breakpoints: [] });
    await request("stepOut", { threadId: 2 });
    await stopped("step");
    assert.equal((await basicFrames())[0].name, "20: NEXT I");

    // STOP stops the program, and CONT resumes at the statement after it.
    await request("setExceptionBreakpoints", { filters: ["basicStart", "basicStop"] });
    await request("continue", { threadId: 2 });
    assert.equal((await event("stopped")).description, "STOP in 30.");
    const listed = await request("retro/basic/program");
    assert.equal(listed.dialect, "colorbasic");
    assert.equal(listed.text, `${programLines.join("\n")}\n`);
    await request("continue", { threadId: 2 });
    await screen(text => text.includes("BREAK IN 30"), "the STOP's BREAK");
    await type("CONT\r");
    const resumed = await event("stopped");
    assert.equal(resumed.description, "CONT resumes at 40.");
    assert.equal((await basicFrames())[0].name, "40: PRINT A;B$");
    await request("setExceptionBreakpoints", { filters: [] });
    await request("continue", { threadId: 2 });
    await screen(text => text.includes(" 7 BYE"), "the program's PRINT");

    // Writing text puts a new program in memory.
    const written = await request("retro/basic/write", { text: "10 PRINT HEX$(255)\n20 GOTO 10\n" });
    assert.equal(written.success, true, JSON.stringify(written.diagnostics));
    assert.equal((await request("retro/basic/program")).text, "10 PRINT HEX$(255)\n20 GOTO 10\n");

    // A CoCo 2 with a disk boots Disk Extended Color BASIC.
    await launch({ model: "coco2", disks: [disk] });
    await screen(text => text.includes("DISK EXTENDED COLOR BASIC") && /\nOK/.test(text), "Disk BASIC's OK");
    assert.equal((await request("threads")).threads[0].name, "CoCo 2 6809");
    const hardware = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
    assert.deepEqual(Object.keys(hardware), ["model", "cpu", "rom", "memory", "video", "cassette", "cartridge", "disk"]);
    assert.equal(hardware.rom.value, `Color BASIC 1.2, Extended Color BASIC 1.1${fromSources}`);
    assert.equal(hardware.model.value, "Color Computer 2");
    assert.equal(hardware.memory.value, "64 KB");
    assert.equal(hardware.disk.value, "WD1793, Disk Extended Color BASIC 1.1");
    assert.deepEqual(hardware.disk.devices, ["disk0", "disk1", "disk2", "disk3"]);

    // SAVE writes the program to the disk and DIR lists it.
    await type("10 PRINT \"SAVED\";6*7\rSAVE \"HELLO\"\r");
    await screen(text => /SAVE "HELLO"\s*\nOK/.test(text), "SAVE's OK");
    await type("DIR\r");
    await screen(text => /HELLO\s+BAS/.test(text), "the directory");

    // A stop sends the whole picture.
    await request("pause", { threadId: 1 });
    await event("stopped");
    const paused = await event("retro/frame");
    assert.equal(paused.running, false);
    assert.equal(Buffer.from(paused.video.pixels, "base64").length, paused.video.width * paused.video.height * 4);
    assert.equal((await request("evaluate", { expression: "DP" })).result.startsWith("$"), true);
    await request("continue", { threadId: 1 });

    // The 6809 sample: a breakpoint in SHOW shows PRINT as its caller, and stepping out returns there.
    const lines = readFileSync(hello, "utf8").split(/\r?\n/);
    const jsr = lines.findIndex(line => line.trim() === "jsr [CHROUT]") + 1;
    const bsr = lines.findIndex(line => line.trim() === "bsr SHOW") + 1;
    events.length = 0;
    await request("launch", { machine: "coco", romDirectory: roms, model: "coco2", source: hello, stopOnEntry: true, speed: "max", sound: "off" });
    assert.equal((await request("setBreakpoints", { source: { path: hello }, breakpoints: [{ line: jsr }] })).breakpoints[0].verified, true);
    await request("setExceptionBreakpoints", { filters: [] });
    await request("configurationDone");
    assert.equal((await event("stopped")).reason, "entry");
    await request("continue", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "breakpoint");
    assert.equal((await request("evaluate", { expression: "A" })).result, "$48 (72)");
    let stack = await request("stackTrace", { threadId: 1 });
    assert.equal(stack.stackFrames[0].line, jsr);
    assert.ok(stack.totalFrames >= 2, "PRINT is on the call stack");
    assert.equal(stack.stackFrames[1].line, bsr);
    await request("stepOut", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "step");
    stack = await request("stackTrace", { threadId: 1 });
    assert.equal(stack.stackFrames[0].line, bsr + 1, "step out returns after the BSR");
    await request("setBreakpoints", { source: { path: hello }, breakpoints: [] });
    await request("continue", { threadId: 1 });
    await screen(text => text.includes("HELLO FROM THE 6809"), "the sample's message");

    // A CoCo 3 boots Extended Color BASIC 2.0 and switches to 80 columns.
    await launch({ model: "coco3" });
    await screen(text => text.includes("EXTENDED COLOR BASIC 2.0") && /\nOK/.test(text), "the CoCo 3's OK");
    assert.equal((await request("threads")).threads[0].name, "CoCo 3 6809");
    await frames(10);                                           // BASIC waiting for a key, not still starting
    await type("WIDTH 80\r");
    const wide = await screen(text => /^OK/m.test(text) && !text.includes("EXTENDED"), "the 80-column screen");
    assert.equal(wide.columns, 80);

    await request("disconnect");
    console.log("Color Computer DAP passed: stepping from the 6809 sample into ColorBasic.asm, ExtendedBasic.asm, DiskBasic.asm and "
        + "Coco3.asm and out, a Color BASIC program on the BASIC thread, Disk Extended Color BASIC saving and listing a program on a disk, a breakpoint in the sample "
        + `with its call stack and step out, and a CoCo 3 at 80 columns, ${dumps ? `the last parts on the dumps in ${romDirectory}` : "all from the SDK's sources"}.`);
} finally {
    clearTimeout(timeout);
    close();
    if (existsSync(disk)) unlinkSync(disk);
    if (existsSync(program)) unlinkSync(program);
}
if (failure()) throw failure();
