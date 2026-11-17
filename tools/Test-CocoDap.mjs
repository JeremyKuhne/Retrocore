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
import { readFileSync, writeFileSync, existsSync, unlinkSync, rmSync } from "node:fs";
import { randomUUID } from "node:crypto";
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

// The machine's recovery journal, in local data as the host finds it, removed afterward.
const recoveryId = `test-coco-${randomUUID()}`;
const journal = join(process.env.RETROCORE_LOCAL_DATA
    ?? join(process.env.LOCALAPPDATA ?? join(process.env.HOME ?? "", ".local", "share"), "Retrocore"), "Recovery", recoveryId);

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
const dmk = join(tmpdir(), `retrocore-coco-${process.pid}.dmk`);

// A Color BASIC program for the BASIC thread.
const programLines = ["10 A=1:B$=\"HI\"", "20 FOR I=1 TO 3:GOSUB 100:NEXT I", "30 STOP", "40 PRINT A;B$", "100 A=A+I", "110 RETURN"];
const program = join(tmpdir(), `retrocore-coco-${process.pid}.colorbasic.bas`);
writeFileSync(program, `${programLines.join("\n")}\n`);

// One for IF's ELSE, a function's two-byte token before a statement, and a line whose number's low byte is zero.
const branches = join(tmpdir(), `retrocore-coco-${process.pid}-branches.colorbasic.bas`);
writeFileSync(branches, "10 IF 0 THEN A=1 ELSE A=2\n20 A=ABS(1):STOP\n30 END\n256 B=1:STOP\n");
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
    // Retrocore Memory reads the CoCo 2's text as its MC6847 draws it: uppercase in either style.
    const cocoCharacters = (await request("retro/memory/characters")).text;
    assert.equal(cocoCharacters[0x01], "A", "$01 draws an uppercase A, dark on green");
    assert.equal(cocoCharacters[0x41], "A", "and $41 the same A, light on dark");
    // Retrocore Memory's map and inspector name the CoCo's regions by what the map reads there now.
    const cocoInspect = async address => request("retro/memory/inspect", { memoryReference: "0x0000", address });
    assert.deepEqual([(await cocoInspect(0x0421)).region, (await cocoInspect(0x0421)).detail], ["Text screen, where BASIC shows it", "row 1, column 1"]);
    assert.equal((await cocoInspect(0x8000)).region, "Extended Color BASIC ROM");
    assert.equal((await cocoInspect(0xA000)).region, "Color BASIC ROM");
    assert.equal((await cocoInspect(0xC000)).region, "No ROM mapped here");
    assert.equal((await cocoInspect(0xFFFE)).region, "Vectors, from the ROM");
    const cocoMap = await request("retro/memory/map", { memoryReference: "0x0000" });
    const cocoArea = address => cocoMap.areas.find(area => address >= area.start && address < area.start + area.length);
    assert.deepEqual([cocoArea(0x0000).kind, cocoArea(0x8000).kind, cocoArea(0xC000).kind, cocoArea(0xFF00).kind], ["ram", "rom", "none", "io"]);
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
    // Retrocore Memory's inspector names a register's bits: from the masks its documentation links to, as INIT0's
    // <MMUEN> is bit 6, and from what it says of a bit by number, as INIT1's "the timer's clock, in bit 5" does.
    const bitsAt = async address => (await request("retro/memory/inspect", { memoryReference: "0x0000", address })).bits;
    const init0 = await bitsAt(0xFF90);
    assert.deepEqual(init0.map(bit => bit.name), ["COCO", "MMUEN", "IEN", "FEN", "MC3", "MC2", "MC1", "MC0"]);
    assert.deepEqual(init0[1], { bit: 6, name: "MMUEN", meaning: "INIT0's bit that turns the MMU on, which maps each 8K of the 64K address space to a block of RAM or ROM." });
    assert.deepEqual(await bitsAt(0xFF91), [
        { bit: 5, name: null, meaning: "the timer's clock" },
        { bit: 0, name: null, meaning: "which of the MMU's two tasks maps the address space" }
    ]);
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

    // A false IF steps to its ELSE, which IF runs without the statement loop; ABS ($FF $82) is no REM, so STOP is a
    // statement of its own; and Set Next Statement to line 256, whose number's low byte is zero, runs B=1 first.
    events.length = 0;
    await request("launch", { machine: "coco", model: "coco2", sdkRoms, basic: branches, stopOnEntry: true, speed: "max", sound: "off" });
    await request("setExceptionBreakpoints", { filters: [] });
    await request("configurationDone");
    await stopped("entry");
    assert.match((await basicFrames())[0].name, /^10: IF 0 THEN A=1/);
    const steps = [];
    for (let step = 0; step < 3; step++) {
        await request("next", { threadId: 2 });
        await stopped("step");
        steps.push((await basicFrames())[0].name);
    }
    assert.match(steps[0], /^10: ELSE A=2/, JSON.stringify(steps));
    assert.deepEqual(steps.slice(1), ["20: A=ABS(1)", "20: STOP"]);
    const jump = (await request("gotoTargets", { source: { path: branches }, line: 4 })).targets;
    assert.equal(jump[0].label, "256: B=1");
    await request("goto", { threadId: 2, targetId: jump[0].id });
    await stopped("goto");
    assert.equal((await basicFrames())[0].name, "256: B=1");
    await request("next", { threadId: 2 });
    await stopped("step");
    assert.equal((await basicFrames())[0].name, "256: STOP");
    const variables = await request("variables", {
        variablesReference: Object.fromEntries((await request("scopes", { frameId: (await basicFrames())[0].id })).scopes
            .map(scope => [scope.name, scope.variablesReference])).Variables
    });
    assert.deepEqual(Object.fromEntries(variables.variables.map(item => [item.name, item.value])), { A: "1", B: "1" });

    // A CoCo 2 with a disk boots Disk Extended Color BASIC.
    await launch({ model: "coco2", disks: [disk], recoveryId });
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

    // The disk is changed: an older client's eject is refused, and a save writes it back to its JVC image, whose
    // directory then lists the program, and then saves it as DMK, which it comes from after.
    let drive = (await request("retro/devices")).devices.find(device => device.id === "disk0");
    assert.deepEqual(drive.saveFormats, ["dsk", "jvc", "dmk"]);
    assert.equal(drive.media.format, "JVC");
    assert.equal(drive.media.changed, true);
    await assert.rejects(request("retro/media", { device: "disk", action: "eject", drive: 0 }), /changes not saved/);

    // What changed, by the JVC's sectors: the program's and the directory's, on track 17. Reverted, the disk is its image again and the
    // changed one is kept for Undo, which puts it back.
    const differences = await request("retro/device", { id: "disk0", action: "differences", supportsRetrocoreMedia: true });
    assert.equal(differences.differences.unit, "sector", JSON.stringify(differences.differences));
    assert.ok(differences.differences.count > 0);
    assert.match(differences.differences.summary, /\b17\b/);
    const reverted = await request("retro/device", { id: "disk0", action: "revert", supportsRetrocoreMedia: true });
    assert.equal(reverted.outcome, "reverted");
    assert.equal(reverted.devices.find(device => device.id === "disk0").media.changed, false);
    assert.equal(reverted.devices.find(device => device.id === "disk0").undo.id, reverted.undo);
    const undone = await request("retro/device", { id: "disk0", action: "undo", medium: reverted.undo, supportsRetrocoreMedia: true });
    assert.equal(undone.outcome, "undone");
    assert.equal(undone.devices.find(device => device.id === "disk0").media.changed, true);

    // Kept: the machine launched again under the same recovery id has the changed disk back in its drive, still
    // changed against its image, which DIR reads.
    await launch({ model: "coco2", disks: [disk], recoveryId });
    await screen(text => text.includes("DISK EXTENDED COLOR BASIC") && /\nOK/.test(text), "Disk BASIC's OK again");
    drive = (await request("retro/devices")).devices.find(device => device.id === "disk0");
    assert.equal(drive.media.changed, true, "the kept disk is back, changed");
    assert.equal(drive.media.label.toLowerCase(), disk.toLowerCase());
    const kept = await request("retro/device", { id: "disk0", action: "differences", supportsRetrocoreMedia: true });
    assert.match(kept.differences.summary, /\b17\b/);
    await type("DIR\r");
    await screen(text => /HELLO\s+BAS/.test(text), "the kept disk's directory");
    let saved = await request("retro/device", { id: "disk0", action: "save", supportsRetrocoreMedia: true });
    assert.equal(saved.outcome, "saved", JSON.stringify(saved));
    drive = saved.devices.find(device => device.id === "disk0");
    assert.equal(drive.media.changed, false);
    const directory = readFileSync(disk).subarray(((17 * 18) + 2) * 256, ((17 * 18) + 3) * 256);
    assert.equal(directory.subarray(0, 8).toString("latin1"), "HELLO   ");
    saved = await request("retro/device", { id: "disk0", action: "save", path: dmk, supportsRetrocoreMedia: true });
    assert.equal(saved.outcome, "saved", JSON.stringify(saved));
    drive = saved.devices.find(device => device.id === "disk0");
    assert.equal(drive.media.format, "DMK");
    assert.equal(drive.media.label.toLowerCase(), dmk.toLowerCase());

    // A stop sends the whole picture.
    await request("pause", { threadId: 1 });
    await event("stopped");

    // Frames sent while it ran, as the saves above went on, come first.
    let paused = await event("retro/frame");
    while (paused.running) paused = await event("retro/frame");
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
    // A word is the 6809's, high byte first, as the reset vector at $FFFE is.
    const word = (await request("evaluate", { expression: "[$FFFE].w", context: "watch" })).result;
    assert.equal(word, (await request("evaluate", { expression: "[$FFFE]*256+[$FFFF]", context: "watch" })).result);
    assert.equal((await request("retro/memoryBanks")).banks[0].bigEndian, true, "the CPU's memory is big-endian");
    // The listing decodes the 6809's five-byte instructions, as CMPD [$1234] is.
    // The bytes it borrows are put back after.
    const borrowed = (await request("readMemory", { memoryReference: "0x3000", count: 5 })).data;
    await request("writeMemory", { memoryReference: "0x3000", data: Buffer.from([0x10, 0xA3, 0x9F, 0x12, 0x34]).toString("base64") });
    const cmpd = (await request("retro/memory/listing", { memoryReference: "0x0000", address: 0x3000, count: 5, starts: [0x3000] })).lines[0];
    await request("writeMemory", { memoryReference: "0x3000", data: borrowed });
    assert.deepEqual([cmpd.size, cmpd.text.startsWith("CMPD")], [5, true], JSON.stringify(cmpd));
    // A direct-page operand is an offset in DP's page, as LDA <$34 is.
    await request("writeMemory", { memoryReference: "0x3000", data: Buffer.from([0x96, 0x34]).toString("base64") });
    const direct = (await request("retro/memory/listing", { memoryReference: "0x0000", address: 0x3000, count: 2, starts: [0x3000] })).lines[0];
    await request("writeMemory", { memoryReference: "0x3000", data: borrowed });
    const dp = parseInt((await request("evaluate", { expression: "DP" })).result.substring(1), 16);
    assert.equal(direct.target, dp * 256 + 0x34, JSON.stringify(direct));
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
        + "Coco3.asm and out, a Color BASIC program on the BASIC thread, Disk Extended Color BASIC saving and listing a program on a disk that says what changed, reverts and undoes, is kept for the next launch, and saves to its image and as DMK, a breakpoint in the sample "
        + `with its call stack and step out, and a CoCo 3 at 80 columns, ${dumps ? `the last parts on the dumps in ${romDirectory}` : "all from the SDK's sources"}.`);
} finally {
    clearTimeout(timeout);
    close();
    rmSync(journal, { recursive: true, force: true });
    if (existsSync(disk)) unlinkSync(disk);
    if (existsSync(dmk)) unlinkSync(dmk);
    if (existsSync(program)) unlinkSync(program);
    if (existsSync(branches)) unlinkSync(branches);
}
if (failure()) throw failure();
