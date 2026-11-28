// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Commodore VIC-20 DAP integration: boots BASIC 2 to READY. from the SDK's sources on NTSC, stops in the shared
// BASIC and the VIC-20's kernal sources with the 6502 call stack, shows the VIC's picture in colour, stops where the
// machine resets, warm starts with RUN/STOP and RESTORE, records a program onto a blank tape and saves it as a TAP
// image, loads it back, and launches a .prg BASIC program and an assembly source that prints through the kernal.
// Then the expansions and PAL change the memory and the thread, and a 1541 on device 8 formats a blank disk, saves a
// program on it, writes it back as a D64 image and lists its directory: with MAME's c1541 ROM set (in
// RETROCORE_VIC20_ROMS or %USERPROFILE%\Retrocore\vic20-roms\extract) when it is there, else from the SDK's build of
// the drive's DOS.

import { resolve, join } from "node:path";
import { readFileSync, writeFileSync, existsSync, unlinkSync } from "node:fs";
import { tmpdir, homedir } from "node:os";
import assert from "node:assert/strict";
import { startDap } from "./DapClient.mjs";

const root = resolve(import.meta.dirname, "..");
const sdkRoms = join(root, "src", "Retrocore.Machines.Commodore", "Roms");
const startup = join(sdkRoms, "Vic20", "Kernal.Startup.asm");
const channels = join(sdkRoms, "Vic20", "Kernal.Channels.asm");
const nativeInit = join(sdkRoms, "Basic", "Commodore.KernalStartup.asm");
const nativeOutput = join(root, "src", "Retrocore.Basic", "Roms", "Microsoft6502Basic", "MsBasic.OutputCore.asm");
const transfers = join(root, "src", "Retrocore.Basic", "Roms", "Microsoft6502Basic", "MsBasic.ProgramTransfers.asm");
const vic20Roms = process.env.RETROCORE_VIC20_ROMS || join(homedir(), "Retrocore", "vic20-roms", "extract");
const driveRoms = join(vic20Roms, "c1541");

const { request, event, events, fail, close, failure } = startDap(root);
let last = "";
const timeout = setTimeout(() => fail(new Error(`VIC-20 DAP integration timed out; the screen was:
${last}`)), Number(process.env.RETROCORE_DAP_TIMEOUT ?? 240000));

// The line after a label or a routine's .proc: its first instruction.
function lineOf(file, label) {
    const lines = readFileSync(file, "utf8").split(/\r?\n/);
    const index = lines.findIndex(line => line === `${label}:` || line.trim() === `.proc ${label}`);
    assert.ok(index >= 0, `${label} is in ${file}`);
    return index + 2;
}

// Forgets queued events of a kind, so a wait sees only what happens next.
function drop(name) {
    for (let index = events.length - 1; index >= 0; index--) {
        if (events[index].event === name) events.splice(index, 1);
    }
}

// The screen's rows joined: BASIC's lines wrap across the VIC's 22-column rows, up to four of them, so a test reads
// across rows too.
const text = frame => frame.rows.map(row => row.trimEnd()).join("\n");
const joined = screen => screen.replace(/\n/g, "");

// Waits for a running frame whose screen satisfies a test.
async function screen(test, what) {
    drop("retro/frame");
    for (;;) {
        const frame = await event("retro/frame");
        last = `${text(frame)}\n(${frame.cycles} cycles)`;
        if (test(text(frame))) return frame;
        if (!frame.running) throw new Error(`Stopped before ${what}.`);
    }
}

async function stoppedFrame() {
    for (;;) {
        const frame = await event("retro/frame");
        if (!frame.running) return frame;
    }
}

async function type(line) {
    for (const character of line) await request("retro/key", { code: character === "\r" ? 13 : character.charCodeAt(0) });
}

// Types a command and waits for READY. after it.
async function command(line, what) {
    await type(`${line}\r`);
    await screen(screen => joined(screen).includes(line) && ready(screen.slice(screen.lastIndexOf(line.slice(-10)))), what);
}

// Waits for an emulated second to pass: a reset leaves the last READY. on the screen until the kernal clears it, and
// keys typed before then are lost.
async function settle() {
    drop("retro/frame");
    const start = (await event("retro/frame")).cycles;
    while ((await event("retro/frame")).cycles < start + 1_000_000) { /* running */ }
}

async function launch(args, filters) {
    events.length = 0;
    await request("setExceptionBreakpoints", { filters: filters ?? [] });
    await request("launch", { machine: "vic20", sdkRoms, stopOnEntry: false, speed: "max", ...args });
    await request("configurationDone");
}

// The last line with anything on it is a fresh READY.
const ready = screen => /READY\.\s*$/.test(screen);

const rows = async () => Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));

const tape = join(tmpdir(), `retrocore-vic20-${process.pid}.tap`);
const prg = join(tmpdir(), `retrocore-vic20-${process.pid}.prg`);
const hello = join(tmpdir(), `retrocore-vic20-${process.pid}.asm`);
const disk = join(tmpdir(), `retrocore-vic20-${process.pid}.d64`);
try {
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });
    await assert.rejects(request("launch", { machine: "vic20", sdkRoms, video: "secam" }), /video must be ntsc or pal/);
    await assert.rejects(request("launch", { machine: "vic20", sdkRoms, ramExpansion: "64k" }), /ramExpansion must be none, 3k/);
    await assert.rejects(request("launch", { machine: "vic20", sdkRoms, sound: "loud" }), /sound must be speaker or off/);

    // Boot: BASIC 2's banner, the unexpanded machine's free bytes, and READY.
    await launch({});
    await screen(screen => screen.includes("**** CBM BASIC V2 ****") && screen.includes("3583 BYTES FREE") && ready(screen), "READY.");
    assert.equal((await request("threads")).threads[0].name, "VIC-20 6502");
    const hardware = await rows();
    assert.deepEqual(Object.keys(hardware), [
        "video", "cpu", "rom", "memory", "sound", "cassette", "cartridge", "serial8", "serial9", "serial10", "serial11"
    ]);
    assert.equal(hardware.video.value, "NTSC, the 6560");
    // The SDK's builds, or with RETROCORE_VIC20_ROMS set, the dumps.
    assert.ok(hardware.rom.value.startsWith("BASIC 2 and kernal 901486-06"), hardware.rom.value);
    assert.equal(hardware.memory.value, "5 KB, unexpanded");
    assert.equal(hardware.cartridge.value, "empty");
    assert.equal(hardware.serial8.value, "empty");
    assert.deepEqual((await request("retro/devices")).devices.map(device => device.id), ["cassette"]);

    // BASIC's cold start, in the shared Commodore source for BASICs over a kernal, after the kernal's reset.
    const initLine = lineOf(nativeInit, "ColdStart");
    const setInit = await request("setBreakpoints", { source: { path: nativeInit }, breakpoints: [{ line: initLine }] });
    assert.equal(setInit.breakpoints[0].verified, true, JSON.stringify(setInit.breakpoints[0]));
    await request("retro/reset");
    assert.equal((await event("stopped")).reason, "breakpoint");
    const initFrame = (await request("stackTrace", { threadId: 1 })).stackFrames[0];
    assert.equal(initFrame.source.path.toLowerCase(), nativeInit.toLowerCase());
    const initPc = parseInt((await request("evaluate", { expression: "PC" })).result.slice(1), 16);
    assert.ok(initPc >= 0xE000 && initPc < 0xE47C, "BASIC's cold start is in its part of the kernal's chip");
    await request("setBreakpoints", { source: { path: nativeInit }, breakpoints: [] });
    await request("continue", { threadId: 1 });
    await screen(ready, "READY. after BASIC's cold start");

    // A numeric PRINT stops in the shared Microsoft source.
    const outputLine = lineOf(nativeOutput, "FormatFac");
    const setOutput = await request("setBreakpoints", { source: { path: nativeOutput }, breakpoints: [{ line: outputLine }] });
    assert.equal(setOutput.breakpoints[0].verified, true, JSON.stringify(setOutput.breakpoints[0]));
    await type("PRINT 42\r");
    assert.equal((await event("stopped")).reason, "breakpoint");
    assert.equal((await request("stackTrace", { threadId: 1 })).stackFrames[0].source.path.toLowerCase(), nativeOutput.toLowerCase());
    await request("setBreakpoints", { source: { path: nativeOutput }, breakpoints: [] });
    await request("continue", { threadId: 1 });
    await screen(ready, "READY. after PRINT");

    // A stop shows the VIC's picture in colour, the frame's size its own.
    await request("pause", { threadId: 1 });
    await event("stopped");
    const paused = await stoppedFrame();
    assert.equal(paused.machine, "vic20");
    assert.equal(paused.standard, "ntsc");
    assert.equal(paused.columns, 22);
    assert.equal(Buffer.from(paused.video.pixels, "base64").length, paused.video.width * paused.video.height * 4);
    assert.equal(paused.screen, "color");
    assert.deepEqual(paused.screens, ["color", "white", "green", "amber"]);
    await request("continue", { threadId: 1 });

    // A breakpoint in the kernal: the jiffy clock, which the IRQ ticks 60 times a second, with the interrupt below it.
    const tick = lineOf(channels, "Tick");
    const set = await request("setBreakpoints", { source: { path: channels }, breakpoints: [{ line: tick }] });
    assert.equal(set.breakpoints[0].verified, true, JSON.stringify(set.breakpoints[0]));
    assert.equal((await event("stopped")).reason, "breakpoint");
    const stack = await request("stackTrace", { threadId: 1 });
    assert.match(stack.stackFrames[0].name, /Tick$/);
    assert.equal(stack.stackFrames[0].line, tick);
    assert.equal(stack.stackFrames[0].source.path.toLowerCase(), channels.toLowerCase());
    assert.ok(stack.totalFrames >= 2, "the interrupt handler is on the call stack");
    await request("setBreakpoints", { source: { path: channels }, breakpoints: [] });
    await request("continue", { threadId: 1 });

    // RESET stops at the kernal's first instruction, in its start-up source.
    await request("setExceptionBreakpoints", { filters: ["machineReset"] });
    await request("retro/reset");
    const reset = await event("stopped");
    assert.equal(reset.reason, "breakpoint");
    const top = (await request("stackTrace", { threadId: 1 })).stackFrames[0];
    assert.equal(top.name, "Startup::Reset");
    assert.equal(top.source.path.toLowerCase(), startup.toLowerCase());
    await request("setExceptionBreakpoints", { filters: [] });
    await request("continue", { threadId: 1 });
    await settle();
    await screen(ready, "READY. after the reset");

    // RUN/STOP and RESTORE stop a running program and warm start to READY., keeping it.
    await type("10 GOTO 10\rRUN\r");
    await screen(screen => joined(screen).includes("RUN") && !ready(screen), "the loop running");
    await settle(); // Let the typed RETURN go before pressing the key chord.
    // RESTORE reads STOP through the column left selected by the keyboard scan. Press it from BASIC, not mid-scan.
    const goTo = await request("setBreakpoints", { source: { path: transfers }, breakpoints: [{ line: lineOf(transfers, "GoTo") }] });
    assert.equal(goTo.breakpoints[0].verified, true, JSON.stringify(goTo.breakpoints[0]));
    assert.equal((await event("stopped")).reason, "breakpoint");
    await request("setBreakpoints", { source: { path: transfers }, breakpoints: [] });
    assert.equal((await request("retro/key", { code: 257 })).delivered, 1);
    await request("continue", { threadId: 1 });
    await screen(screen => ready(screen) && !joined(screen).includes("RUN"), "RUN/STOP and RESTORE's warm start");
    await type("NEW\r");

    // A program saved on a blank tape, then saved as a TAP image through the save the host does.
    await type("10 PRINT \"VIC\";6*7\r");
    await request("retro/device", { id: "cassette", action: "record" });
    await type("SAVE \"PROG\"\r");
    await screen(screen => joined(screen).includes("SAVING PROG") && ready(screen), "the save");
    await request("retro/device", { id: "cassette", action: "stop" });
    const tapeDevice = (await request("retro/devices")).devices.find(device => device.id === "cassette");
    assert.equal(tapeDevice.media.changed, true, "a recording is a changed tape");
    const saved = await request("retro/device", { id: "cassette", action: "save", path: tape, supportsRetrocoreMedia: true });
    assert.equal(saved.outcome, "saved", JSON.stringify(saved));
    const image = readFileSync(tape);
    assert.equal(image.subarray(0, 12).toString(), "C64-TAPE-RAW");
    assert.equal(image[13], 1, "the header names the VIC-20, machine 1");
    assert.equal(image[14], 1, "on NTSC");

    // Loaded back from the image, it runs.
    await type("NEW\r");
    await request("retro/device", { id: "cassette", action: "insert", path: tape, supportsRetrocoreMedia: true });
    await type("LOAD\r");
    await screen(screen => joined(screen).includes("FOUND PROG"), "the tape's header");
    await type(" ");
    await screen(screen => joined(screen).includes("LOADING") && ready(screen), "the load");
    await type("RUN\r");
    await screen(screen => screen.includes("VIC 42"), "the loaded program's output");

    // A .prg program at BASIC's start loads with BASIC's pointers set and runs.
    const memory = await request("readMemory", { memoryReference: "0x1001", count: 32 });
    const bytes = Buffer.from(memory.data, "base64");
    const found = bytes.indexOf(Buffer.from([0, 0, 0]));
    assert.ok(found >= 0, "the program's end link is in its first 32 bytes");
    const end = found + 3;
    writeFileSync(prg, Buffer.concat([Buffer.from([0x01, 0x10]), bytes.subarray(0, end)]));
    await launch({ program: prg });
    await screen(screen => screen.includes("VIC 42"), "the .prg program's output");

    // The same .prg, written for the unexpanded machine, moves to BASIC's start with 8K and runs there.
    await launch({ program: prg, ramExpansion: "8k" });
    await screen(screen => screen.includes("VIC 42"), "the .prg program's output with 8K");

    // A launched source prints through the kernal's character output, then waits, as it was started with no return
    // address of its own to go back to.
    writeFileSync(hello, [
        ".cpu Mos6502",
        "CHROUT = $FFD2",
        "        ldx #0",
        "Next:   lda Message,x",
        "        beq Done",
        "        jsr CHROUT",
        "        inx",
        "        bne Next",
        "Done:   jmp Done",
        "Message: .byte \"HELLO\", 0",
        ""
    ].join("\n"));
    events.length = 0;
    await request("launch", { machine: "vic20", sdkRoms, source: hello, stopOnEntry: true, speed: "max" });
    await request("setExceptionBreakpoints", { filters: [] });
    await request("configurationDone");
    assert.equal((await event("stopped")).reason, "entry");
    assert.equal((await request("evaluate", { expression: "PC" })).result, "$1400 (5120)");
    await request("continue", { threadId: 1 });
    await screen(screen => screen.includes("HELLO"), "the program's output");

    // The expansions change the memory BASIC finds.
    for (const [ramExpansion, free, memory] of [
        ["3k", "6655 BYTES FREE", "8 KB: 5 KB and 3K at $0400"],
        ["8k", "11775 BYTES FREE", "13 KB: 5 KB and block 1"],
        ["32k", "28159 BYTES FREE", "32 KB: 5 KB and 3K at $0400, block 1, block 2, block 3"]
    ]) {
        await launch({ ramExpansion });
        await screen(screen => screen.includes(free) && ready(screen), `READY. with ${ramExpansion}`);
        assert.equal((await rows()).memory.value, memory);
    }

    // PAL: the 6561, its own kernal and thread, and the same BASIC.
    await launch({ video: "pal" });
    await screen(screen => screen.includes("**** CBM BASIC V2 ****") && ready(screen), "PAL's READY.");
    assert.equal((await request("threads")).threads[0].name, "VIC-20 (PAL) 6502");
    const pal = await rows();
    assert.equal(pal.video.value, "PAL, the 6561");
    assert.ok(pal.rom.value.startsWith("BASIC 2 and kernal 901486-07"), pal.rom.value);
    await request("setExceptionBreakpoints", { filters: ["machineReset"] });
    await request("retro/reset");
    assert.equal((await event("stopped")).reason, "breakpoint");
    assert.equal((await request("stackTrace", { threadId: 1 })).stackFrames[0].source.path.toLowerCase(), startup.toLowerCase());
    await request("setExceptionBreakpoints", { filters: [] });
    await request("continue", { threadId: 1 });

    // A 1541 on device 8: a blank disk formatted, a program saved on it, the disk saved as a D64 image and listed. The
    // drive runs MAME's c1541 set when it is there, else the SDK's build of its DOS.
    {
        const dumps = ["325302-01.uab4", "901229-06 aa.uab5"].every(chip => existsSync(join(driveRoms, chip)));
        console.log(dumps ? "The 1541 runs MAME's c1541 set." : "The 1541 runs the SDK's build of its DOS.");
        const drives = dumps ? { driveRomDirectory: driveRoms } : {};
        writeFileSync(disk, Buffer.alloc(174848));
        await launch({ ...drives, disks: [disk] });
        await screen(ready, "READY. with a 1541");
        const units = await rows();
        assert.equal(units.serial8.value, "1541 disk drive");
        assert.deepEqual(units.serial8.devices, ["disk8"]);
        assert.deepEqual(units.serial9.actions, ["addCard"]);
        await command("OPEN15,8,15,\"N:RETROCORE,RC\":CLOSE15", "the format's command");
        await type("10 PRINT \"DISK\";6*7\r");
        await command("SAVE \"PROG\",8", "the save to disk");
        const driveState = (await request("retro/devices")).devices.find(device => device.id === "disk8");
        assert.equal(driveState.media.changed, true, "the formatted disk is changed");
        const written = await request("retro/device", { id: "disk8", action: "save", supportsRetrocoreMedia: true });
        assert.equal(written.outcome, "saved", JSON.stringify(written));
        const d64 = readFileSync(disk);
        assert.equal(d64.length, 174848);
        assert.equal(d64.subarray(0x165A2, 0x165A4).toString(), "RC", "the disk ID is in the BAM");
        await command("NEW", "NEW");
        await command("LOAD \"$\",8", "the directory's load");
        await type("LIST\r");
        await screen(screen => joined(screen).includes("\"PROG\"") && joined(screen).includes("BLOCKS FREE"), "the directory");

        // A second drive connects as device 9 and leaves again.
        await request("retro/hardware", { id: "serial9", action: "add1541" });
        assert.ok((await request("retro/devices")).devices.some(device => device.id === "disk9"));
        await request("retro/hardware", { id: "serial9", action: "removeCard" });
        assert.ok(!(await request("retro/devices")).devices.some(device => device.id === "disk9"));

        await assert.rejects(
            request("launch", { machine: "vic20", sdkRoms, ...drives, diskUnits: [12] }),
            /diskUnits holds different device numbers, 8 to 11/);
        await assert.rejects(
            request("launch", { machine: "vic20", sdkRoms, ...drives, diskModel: "1571" }),
            /diskModel is 1541 or 1540/);
    }

    await request("disconnect", {});
    console.log("VIC-20 DAP integration passed.");
} finally {
    clearTimeout(timeout);
    close();
    for (const file of [tape, prg, hello, disk]) if (existsSync(file)) unlinkSync(file);
}

if (failure()) throw failure();
