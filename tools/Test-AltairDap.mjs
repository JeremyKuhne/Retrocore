// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Altair 8800 DAP integration: launches an 8080 source that greets and echoes on the 88-2SIO's terminal, stops at a
// breakpoint in its Print routine with the 8080 call stack and registers, steps out to the caller, shows the terminal's
// frames and hardware, clears the screen while stopped, echoes typed keys, stops on a write to the serial data port and
// where the machine resets, and holds a breakpoint after HLT until a key's interrupt wakes the 8080. Then the 88-ACR's
// cassette records a tape through retro/media, a changed tape that eject holds back until it is saved, and plays it
// back from the launch's cassette option. The Altair has no ROM, so nothing is needed but the repository; with 8K
// BASIC's image in the external test data (RETROCORE_ALTAIR_BASIC, or the cache's altair-basic folder), it also runs
// BASIC on the terminal, and with
// MITS's 4K BASIC 3.2 tape (its tapes folder) it loads BASIC through the bootstrap and the 88-ACR.

import { resolve, join } from "node:path";
import { writeFileSync, existsSync, unlinkSync, readFileSync, mkdirSync, rmSync } from "node:fs";
import { tmpdir, homedir } from "node:os";
import assert from "node:assert/strict";
import { startDap } from "./DapClient.mjs";

const root = resolve(import.meta.dirname, "..");
const { request, event, events, fail, close, failure } = startDap(root);
let last = "";
const timeout = setTimeout(() => fail(new Error(`Altair DAP integration timed out; the screen was:
${last}`)), Number(process.env.RETROCORE_DAP_TIMEOUT ?? 240000));
const verbose = process.env.RETROCORE_DAP_VERBOSE === "1";
function phase(text) { if (verbose) console.log(`${new Date().toISOString()} ${text}`); }

const program = [
    ".cpu I8080",
    "Start:  lxi sp,$1000",
    "        mvi a,3             ; master reset the 88-2SIO's first ACIA",
    "        out $10",
    "        mvi a,$15           ; divide by 16, 8 bits, 1 stop bit",
    "        out $10",
    "        lxi h,Greeting",
    "        call Print",
    "Loop:   in $10              ; echo each key",
    "        rrc",
    "        jnc Loop",
    "        in $11",
    "        mov b,a",
    "Wait:   in $10",
    "        ani 2",
    "        jz Wait",
    "        mov a,b",
    "        out $11",
    "        jmp Loop",
    ";; Prints the zero-terminated string at HL.",
    "Print:  in $10",
    "        ani 2",
    "        jz Print",
    "        mov a,m",
    "        ora a",
    "        rz",
    "        out $11",
    "        inx h",
    "        jmp Print",
    "Greeting: .byte \"ALTAIR 8800\", 13, 10, 0",
    ""
];
const lineOf = label => program.findIndex(line => line.startsWith(`${label}:`)) + 1;

// Halts with the receive interrupt enabled; a key runs RST 7, whose handler reads it into B.
const halting = [
    ".cpu I8080",
    "        .org $38",
    "Handler: in $11",
    "        mov b,a",
    "        ret",
    "        .org $100",
    "Start:  lxi sp,$1000",
    "        mvi a,3",
    "        out $10",
    "        mvi a,$95           ; receive interrupt enabled",
    "        out $10",
    "        ei",
    "        hlt",
    "After:  nop",
    "        jmp After",
    ""
];

// Sends "TAPE" to the 88-ACR, waiting for its active-low transmitter ready in bit 7.
const recording = [
    ".cpu I8080",
    "Start:  lxi h,Bytes",
    "Write:  in 6",
    "        ani $80",
    "        jnz Write",
    "        mov a,m",
    "        ora a",
    "        jz Done",
    "        out 7",
    "        inx h",
    "        jmp Write",
    "Done:   hlt",
    "Bytes:  .byte \"TAPE\", 0",
    ""
];

// Reads four bytes from the 88-ACR into B, C, D and E, waiting for its active-low receiver ready in bit 0.
const playing = [
    ".cpu I8080",
    "Start:  call Read",
    "        mov b,a",
    "        call Read",
    "        mov c,a",
    "        call Read",
    "        mov d,a",
    "        call Read",
    "        mov e,a",
    "Done:   hlt",
    "Read:   in 6",
    "        rrc",
    "        jc Read",
    "        in 7",
    "        ret",
    ""
];

const cache = process.env.RETROCORE_CACHE || join(homedir(), "Retrocore");
const basic = join(process.env.RETROCORE_ALTAIR_BASIC || join(cache, "altair-basic"), "8kbas.bin");
const mitsTape = join(process.env.RETROCORE_ALTAIR_BASIC || join(cache, "altair-basic"), "tapes", "4KBAS32.TAP");
const cpm = join(process.env.RETROCORE_ALTAIR_DISK || join(cache, "altair-disk"), "cpm22b-56k.dsk");

// MITS's bootstrap for the 88-ACR, as the guide gives it, for 4K BASIC 3.2's tape.
const bootstrap = [
    ".cpu I8080",
    "        .org 0",
    "Boot:   lxi h,$0FAE",
    "Loop:   lxi sp,Stack",
    "        in $06",
    "        rrc",
    "        rc",
    "        in $07",
    "        cmp l",
    "        rz",
    "        dcr l",
    "        mov m,a",
    "        rnz",
    "        pchl",
    "Stack:  .word Loop",
    ""
];

// Forgets queued events of a kind, so a wait sees only what happens next.
function drop(name) {
    for (let index = events.length - 1; index >= 0; index--) {
        if (events[index].event === name) events.splice(index, 1);
    }
}

const text = frame => frame.rows.map(row => row.trimEnd()).join("\n");

// Waits for a running frame whose screen satisfies a test, while the machine runs.
async function screen(test, what) {
    phase(`waiting for ${what}`);
    drop("retro/frame");
    for (;;) {
        const frame = await event("retro/frame");
        last = `${text(frame)}\n(${frame.cycles} cycles)`;
        if (test(text(frame))) return frame;
        if (!frame.running) throw new Error(`Stopped before ${what}.`);
    }
}

// Waits for a stopped frame; running frames sent before the stop can still be queued ahead of it.
async function stoppedFrame() {
    for (;;) {
        const frame = await event("retro/frame");
        if (!frame.running) return frame;
    }
}

async function type(line) {
    for (const character of line) await request("retro/key", { code: character.charCodeAt(0) });
}

const source = join(tmpdir(), `retrocore-altair-${process.pid}.asm`);
const tape = join(tmpdir(), `retrocore-altair-${process.pid}.tap`);
try {
    writeFileSync(source, program.join("\n"));
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });

    // The source loads at $0100 and stops on entry.
    events.length = 0;
    await request("launch", { machine: "altair", source, stopOnEntry: true, speed: "max" });
    await request("setExceptionBreakpoints", { filters: [] });
    const print = lineOf("Print");
    const set = await request("setBreakpoints", { source: { path: source }, breakpoints: [{ line: print }] });
    assert.equal(set.breakpoints[0].verified, true);
    await request("configurationDone");
    assert.equal((await event("stopped")).reason, "entry");
    assert.equal((await request("evaluate", { expression: "PC" })).result, "$100 (256)");
    assert.equal((await request("threads")).threads[0].name, "Altair 8080");
    await request("retro/memory/mark", { memoryReference: "0x0000", address: 8, name: "RESTART1" });
    // Assembling in place: RST 1 lists as RST RESTART1 where $0008 is named, and that assembles back.
    const assembled = async line => request("retro/memory/assemble", { memoryReference: "0x0000", address: 0x2000, line });
    assert.deepEqual(await assembled("RST 1"), { bytes: [0xCF], text: "RST RESTART1", nop: [0x00] });
    assert.deepEqual([(await assembled("RST RESTART1")).bytes, (await assembled("RST $08")).bytes], [[0xCF], [0xCF]]);
    // After a tab, at $FFFF, and never with an operand too many.
    assert.deepEqual((await assembled("RST	RESTART1")).bytes, [0xCF]);
    assert.deepEqual((await request("retro/memory/assemble", { memoryReference: "0x0000", address: 0xFFFF, line: "RST RESTART1" })).bytes, [0xCF]);
    await assert.rejects(assembled("RST $08,$10"));
    await request("retro/memory/mark", { memoryReference: "0x0000", address: 8, name: "" });
    const hardware = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
    assert.deepEqual(Object.keys(hardware), ["model", "memory", "serial", "cassette", "disk", "proms", "terminal", "panel"]);
    assert.equal(hardware.disk.value, "none", "no disks, so no 88-DCDD");
    assert.equal(hardware.cassette.value, "Cassette interface at ports $06 and $07, 300 baud");
    assert.equal(hardware.memory.value, "64 KB at $0000");
    assert.equal(hardware.serial.value, "Two MC6850 ACIAs at ports $10 and $12, 9600 baud");

    // The breakpoint in Print, called from Start.
    await request("continue", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "breakpoint");
    let stack = await request("stackTrace", { threadId: 1 });
    assert.equal(stack.stackFrames[0].line, print);
    assert.equal(stack.stackFrames[0].name, "Print");
    assert.ok(stack.totalFrames >= 2, "the caller is on the call stack");
    assert.match(stack.stackFrames[1].name, /^Start/);
    assert.equal(stack.stackFrames[1].line, lineOf("Start") + 6, "the caller's frame is at its CALL");
    const greeting = (await request("evaluate", { expression: "Greeting" })).result;
    assert.equal((await request("evaluate", { expression: "HL" })).result, greeting, "HL points at the greeting");
    assert.equal((await request("evaluate", { expression: "SP" })).result, "$FFE (4094)");

    // Step out returns to the caller, after the CALL.
    await request("setBreakpoints", { source: { path: source }, breakpoints: [] });
    drop("retro/frame");
    await request("stepOut", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "step");
    stack = await request("stackTrace", { threadId: 1 });
    assert.equal(stack.stackFrames[0].line, lineOf("Loop"));
    assert.equal(stack.totalFrames, 1);

    // The greeting is on the terminal; a stop shows the 80x24 picture in the ADM-3A's white.
    const paused = await stoppedFrame();
    assert.equal(paused.machine, "altair");
    assert.equal(paused.columns, 80);
    assert.equal(paused.rows[0].trimEnd(), "ALTAIR 8800");
    assert.equal(Buffer.from(paused.video.pixels, "base64").length, 640 * 240 * 4);
    assert.equal(paused.screen, "white");
    assert.deepEqual(paused.screens, ["green", "white", "amber"]);

    // CLEAR SCREEN while stopped sends a frame showing the blank screen.
    await request("altair/clearScreen");
    assert.ok((await stoppedFrame()).rows.every(row => row.trim() === ""), "the stopped frame shows the cleared screen");

    // Typed keys echo.
    await request("continue", { threadId: 1 });
    await type("Hello, 8080!");
    await screen(screen => screen.includes("Hello, 8080!"), "the echoed keys after the clear");

    // A watch on writes to the serial data port stops after the OUT that sends the next key.
    const watch = await request("setDataBreakpoints", { breakpoints: [{ dataId: "port:11:1", accessType: "write" }] });
    assert.equal(watch.breakpoints[0].verified, true);
    await type("Z");
    assert.equal((await event("stopped")).reason, "data breakpoint");
    assert.equal((await request("evaluate", { expression: "A" })).result, "$5A (90)");
    await request("setDataBreakpoints", { breakpoints: [] });
    await request("continue", { threadId: 1 });

    // RESET stops at $0000, where the Altair's RAM is: the program at $0100 is not run again.
    await request("setExceptionBreakpoints", { filters: ["machineReset"] });
    await request("retro/reset");
    const reset = await event("stopped");
    assert.equal(reset.reason, "breakpoint");
    assert.equal(reset.description, "The machine reset.");
    assert.equal((await request("evaluate", { expression: "PC" })).result, "$0 (0)");

    // HLT waits for an interrupt: a breakpoint after it holds until a key's receive interrupt runs RST 7, whose
    // handler shows on the call stack above the halted instruction it interrupted. The relaunch waits for its own
    // configurationDone, so the machineReset filter set above comes off after it, as a client configures each launch,
    // and the new machine does not stop as it powers on.
    writeFileSync(source, halting.join("\n"));
    events.length = 0;
    await request("launch", { machine: "altair", source, loadAddress: 0x38, entryAddress: 0x100, stopOnEntry: false, speed: "max" });
    await request("setExceptionBreakpoints", { filters: [] });
    const after = halting.findIndex(line => line.startsWith("After:")) + 1;
    const handler = halting.findIndex(line => line.startsWith("Handler:")) + 1;
    await request("setBreakpoints", { source: { path: source }, breakpoints: [{ line: after }, { line: handler }] });
    await request("configurationDone");
    await new Promise(resolve => setTimeout(resolve, 1000));
    assert.ok(!events.some(message => message.event === "stopped"), "no stop while the 8080 is halted");
    await type("K");
    assert.equal((await event("stopped")).reason, "breakpoint");
    stack = await request("stackTrace", { threadId: 1 });
    assert.equal(stack.stackFrames[0].line, handler);
    assert.equal(stack.stackFrames[1].line, after, "the interrupt came before the instruction after HLT");
    await request("continue", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "breakpoint");
    assert.equal((await request("stackTrace", { threadId: 1 })).stackFrames[0].line, after);
    assert.equal((await request("evaluate", { expression: "B" })).result, "$4B (75)", "the handler read the key");

    // The 88-ACR records onto a tape whose file is written blank as the recording starts. The recording is a changed
    // tape, which an eject holds back until it is saved.
    phase("recording a tape");
    writeFileSync(source, recording.join("\n"));
    events.length = 0;
    await request("launch", { machine: "altair", source, stopOnEntry: true, speed: "max" });
    await request("setExceptionBreakpoints", { filters: [] });
    const done = recording.findIndex(line => line.startsWith("Done:")) + 1;
    await request("setBreakpoints", { source: { path: source }, breakpoints: [{ line: done }] });
    await request("configurationDone");
    assert.equal((await event("stopped")).reason, "entry");
    drop("retro/devices");
    let media = await request("retro/media", { device: "cassette", action: "record", path: tape });
    assert.equal(media.cassette.recording, true);
    assert.equal(readFileSync(tape).length, 0, "the recording's file is written blank");
    // Retro Devices hears of the new tape while the machine is stopped.
    const devices = await event("retro/devices");
    assert.equal(devices.devices.find(device => device.id === "cassette").media?.label, resolve(tape));
    assert.equal(media.cassette.motor, true);
    // A tape that cannot be read, or a recording with nowhere to go, is refused before the recording comes out.
    const missing = join(tmpdir(), `retrocore-missing-${process.pid}`, "missing.tap");
    await assert.rejects(request("retro/media", { device: "cassette", action: "insert", path: missing }));
    await assert.rejects(request("retro/media", { device: "cassette", action: "record", path: missing }));
    await assert.rejects(request("retro/media", { device: "cassette", action: "record", path: tmpdir() }), "a folder is no file");
    const recorder = (await request("retro/devices")).devices.find(device => device.id === "cassette");
    assert.equal(recorder.media?.label, resolve(tape), "the recording is still in");
    assert.equal(recorder.activity, "writing");
    await request("continue", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "breakpoint");
    await request("setBreakpoints", { source: { path: source }, breakpoints: [] });
    // The last byte is still on its way out; a third of a second lets it reach the tape.
    await request("continue", { threadId: 1 });
    await new Promise(resolve => setTimeout(resolve, 1500));
    await request("pause", { threadId: 1 });
    await event("stopped");
    await assert.rejects(request("retro/media", { device: "cassette", action: "eject" }), /tape in Cassette has changes not saved/);
    const saved = await request("retro/device", { id: "cassette", action: "save", supportsRetrocoreMedia: 1 });
    assert.equal(saved.outcome, "saved", JSON.stringify(saved));
    assert.equal(readFileSync(tape, "latin1"), "TAPE", "the save wrote the recording");
    media = await request("retro/media", { device: "cassette", action: "eject" });
    assert.equal(media.cassette.path, null);

    // The launch's cassette option plays the tape from the start; the program reads it into BC and DE.
    phase("playing the tape");
    writeFileSync(source, playing.join("\n"));
    events.length = 0;
    // It stops on entry, as a relaunch runs as soon as it is answered: otherwise the program could read the four bytes
    // and halt before the breakpoint is set.
    await request("launch", { machine: "altair", source, cassette: tape, stopOnEntry: true, speed: "max" });
    await request("setExceptionBreakpoints", { filters: [] });
    const end = playing.findIndex(line => line.startsWith("Done:")) + 1;
    await request("setBreakpoints", { source: { path: source }, breakpoints: [{ line: end }] });
    await request("configurationDone");
    assert.equal((await event("stopped")).reason, "entry");
    await request("continue", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "breakpoint");
    assert.equal((await request("evaluate", { expression: "BC" })).result, "$5441 (21569)", "T and A");
    assert.equal((await request("evaluate", { expression: "DE" })).result, "$5045 (20549)", "P and E");
    // The breakpoint stays with the source's path, which the tape step below reuses.
    await request("setBreakpoints", { source: { path: source }, breakpoints: [] });

    // A recording still in the recorder is not written when the session relaunches: nothing but a save writes an image.
    phase("relaunching while recording");
    const second = join(tmpdir(), `retrocore-altair-${process.pid}-2.tap`);
    writeFileSync(source, recording.join("\n"));
    events.length = 0;
    await request("launch", { machine: "altair", source, stopOnEntry: true, speed: "max" });
    await request("configurationDone");
    assert.equal((await event("stopped")).reason, "entry");
    await request("retro/media", { device: "cassette", action: "record", path: second });
    await request("continue", { threadId: 1 });
    await new Promise(resolve => setTimeout(resolve, 1500));
    await request("pause", { threadId: 1 });
    await event("stopped");
    assert.equal(readFileSync(second).length, 0, "nothing but a save writes the recording");
    writeFileSync(source, playing.join("\n"));
    await request("launch", { machine: "altair", source, stopOnEntry: true, speed: "max" });
    assert.equal(readFileSync(second).length, 0, "the relaunch does not write the recording");
    unlinkSync(second);

    // 8K BASIC, when its image is in the cache, on the 88-2SIO with caps lock.
    if (existsSync(basic)) {
        phase("running 8K BASIC");
        events.length = 0;
        await request("launch", {
            machine: "altair", program: basic, loadAddress: 0, entryAddress: 0, upperCase: true, stopOnEntry: false,
            speed: "max"
        });
        await request("setExceptionBreakpoints", { filters: [] });
        await request("configurationDone");
        await screen(screen => screen.includes("MEMORY SIZE?"), "8K BASIC's first question");
        for (const answer of ["a", "", "", "y"]) {
            await type(`${answer}\r`);
            await new Promise(resolve => setTimeout(resolve, 300));
        }

        await screen(screen => screen.includes("[EIGHT-K VERSION]") && screen.trimEnd().endsWith("OK"), "8K BASIC's banner");
        await type("print 6*7\r");
        await screen(screen => screen.includes(" 42"), "8K BASIC's answer");
    } else {
        console.log(`8K BASIC (${basic}) is missing, so BASIC was not run.`);
    }

    // 4K BASIC 3.2 from MITS's tape, when it is in the cache: the bootstrap launched as a source, the tape in the
    // 88-ACR, the terminal on the 88-SIO and A15 up for the checksum loader. 32 KB, since 3.2's memory test runs past
    // the top of 64 KB.
    if (existsSync(mitsTape)) {
        phase("loading 4K BASIC 3.2 from tape");
        writeFileSync(source, bootstrap.join("\n"));
        events.length = 0;
        await request("launch", {
            machine: "altair", source, loadAddress: 0, entryAddress: 0, cassette: mitsTape, console: "sio",
            switches: 0x8000, ramKilobytes: 32, upperCase: true, stopOnEntry: false, speed: "max"
        });
        await request("setExceptionBreakpoints", { filters: [] });
        await request("configurationDone");
        await screen(screen => screen.includes("MEMORY SIZE?"), "4K BASIC 3.2's first question, after the tape");
        for (const answer of ["", "", "y"]) {
            await type(`${answer}\r`);
            await new Promise(resolve => setTimeout(resolve, 300));
        }

        await screen(screen => screen.includes("[4K VERSION]") && screen.trimEnd().endsWith("OK"), "4K BASIC 3.2's banner");
    } else {
        console.log(`MITS's 4K BASIC 3.2 tape (${mitsTape}) is missing, so no tape was loaded.`);
    }

    // A launch that fails leaves no machine, rather than the one it replaced, which it has disposed. The running
    // machine's worker, cancelled by the launch, must not touch the missing machine or report its absence as a
    // failure, however the two interleave, so it is tried many times with the machine running at full speed.
    phase("failing relaunches while running");
    writeFileSync(source, [".cpu I8080", "Spin:   jmp Spin", ""].join("\n"));
    for (let attempt = 0; attempt < 20; attempt++) {
        events.length = 0;
        await request("launch", { machine: "altair", source, stopOnEntry: false, speed: "max" });
        await request("configurationDone");
        await new Promise(resolve => setTimeout(resolve, 20 + attempt * 5));
        await assert.rejects(request("launch", { machine: "altair", ramKilobytes: 99 }), /RAM must be 1 to 64 KB/);
        await new Promise(resolve => setTimeout(resolve, 100));
        await assert.rejects(request("evaluate", { expression: "PC" }), /No machine has been launched/);
        const failures = events.filter(message => message.event === "stopped" && message.body.reason === "exception");
        assert.deepEqual(failures.map(message => message.body.description), [], "the cancelled worker reported nothing");
    }

    // CP/M 2.2b, when its image is in the cache: the launch's disks fit the 88-DCDD and DBL, which boots drive 0.
    // A file saved under CP/M changes the disk, and the host saves it back to its image.
    if (existsSync(cpm)) {
        phase("booting CP/M");
        const copy = join(tmpdir(), `retrocore-altair-${process.pid}-cpm.dsk`);
        writeFileSync(copy, readFileSync(cpm));
        try {
            events.length = 0;
            await request("launch", { machine: "altair", disks: [copy], upperCase: true, stopOnEntry: false, speed: "max" });
            await request("configurationDone");
            await screen(screen => screen.trimEnd().endsWith("A>"), "CP/M's prompt");
            const rows = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
            assert.deepEqual(rows.disk.devices, ["disk0", "disk1", "disk2", "disk3"]);
            assert.equal(rows.proms.value, "DBL at $FF00");
            await type("dir\r");
            await screen(screen => screen.includes("MBASIC   COM") && screen.trimEnd().endsWith("A>"), "CP/M's directory");
            await type("save 1 retro.com\r");
            await new Promise(resolve => setTimeout(resolve, 1500));
            await screen(screen => screen.trimEnd().endsWith("A>"), "CP/M's prompt after SAVE");
            const disk0 = (await request("retro/devices")).devices.find(device => device.id === "disk0");
            assert.equal(disk0.media.changed, true, "SAVE changed the disk");
            const saved = await request("retro/device", { id: "disk0", action: "save", supportsRetrocoreMedia: true });
            assert.equal(saved.outcome, "saved", JSON.stringify(saved));
            assert.ok(readFileSync(copy).includes(Buffer.from("RETRO   COM")), "the image has the file's directory entry");
            assert.equal(readFileSync(copy).length, readFileSync(cpm).length, "the image keeps its trailer");
        } finally {
            if (existsSync(copy)) unlinkSync(copy);
        }
    } else {
        console.log(`CP/M 2.2b (${cpm}) is missing, so no disk was booted.`);
    }

    await request("disconnect", {});

    // A recording whose save fails stays changed, so the save can be tried again: here while the recording's folder
    // is gone, and then once it is back; closing the adapter's input ends the session. This adapter has its own
    // timeout, which kills it, since the script's covers only the first.
    phase("a failed save, then closing the input while recording");
    const folder = join(tmpdir(), `retrocore-altair-${process.pid}-folder`);
    const third = join(folder, "third.tap");
    mkdirSync(folder, { recursive: true });
    const other = startDap(root);
    const guard = setTimeout(() => other.fail(new Error("The second adapter timed out.")), 60000);
    try {
        writeFileSync(source, recording.join("\n"));
        await other.request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });
        await other.request("launch", { machine: "altair", source, stopOnEntry: true, speed: "max" });
        await other.request("configurationDone");
        assert.equal((await other.event("stopped")).reason, "entry");
        await other.request("retro/media", { device: "cassette", action: "record", path: third });
        await other.request("continue", { threadId: 1 });
        await new Promise(resolve => setTimeout(resolve, 1500));
        await other.request("pause", { threadId: 1 });
        await other.event("stopped");
        // With the folder gone, the blank file is too, which the save says first; saving there again fails, and the
        // recording stays changed, until the folder is back.
        rmSync(folder, { recursive: true });
        const gone = await other.request("retro/device", { id: "cassette", action: "save", supportsRetrocoreMedia: 1 });
        assert.equal(gone.outcome, "conflict", JSON.stringify(gone));
        const again = { id: "cassette", action: "save", overwrite: { sha256: null }, supportsRetrocoreMedia: 1 };
        await assert.rejects(other.request("retro/device", again), "the save fails while the folder is gone");
        assert.equal((await other.request("retro/devices")).devices.find(device => device.id === "cassette").media.changed, true);
        mkdirSync(folder);
        assert.equal((await other.request("retro/device", again)).outcome, "saved");
        assert.equal(readFileSync(third, "latin1"), "TAPE", "the second try saved the recording");
        await other.endInput();
    } finally {
        clearTimeout(guard);
        other.close();
        rmSync(folder, { recursive: true, force: true });
    }

    console.log("Altair DAP integration passed.");
} finally {
    clearTimeout(timeout);
    close();
    if (existsSync(source)) unlinkSync(source);
    if (existsSync(tape)) unlinkSync(tape);
}

if (failure()) throw failure();
