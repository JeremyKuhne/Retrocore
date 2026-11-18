// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Commodore PET DAP integration: boots BASIC 2 to READY. from the SDK's sources, shows the 320x200 screen in the
// monitor's phosphor, stops at a breakpoint in the SDK's kernal source with the 6502 call stack, stops where the
// machine resets, records a program onto a blank tape in cassette 1 and saves it as a TAP image, loads it back, and
// launches a .prg BASIC program and an assembly source that prints through the kernal. With MAME's c4040 ROM set (in
// RETROCORE_PET_ROMS or %USERPROFILE%\Retrocore\pet-roms\extract), a 4040 on device 8 formats a blank disk, saves a
// program on it, writes it back as a D64 image and lists its directory. Then a 4032 boots BASIC 4 from the SDK's
// sources, stops in its kernal's source and at reset, and with the 4040 that comes with it formats a disk with
// HEADER and lists it with DIRECTORY.

import { resolve, join } from "node:path";
import { readFileSync, writeFileSync, existsSync, unlinkSync } from "node:fs";
import { tmpdir, homedir } from "node:os";
import assert from "node:assert/strict";
import { startDap } from "./DapClient.mjs";

const root = resolve(import.meta.dirname, "..");
const sdkRoms = join(root, "src", "Retrocore.Machines.Commodore", "Roms");
const kernal = join(sdkRoms, "Basic2", "Kernal2.asm");
const petRoms = process.env.RETROCORE_PET_ROMS || join(homedir(), "Retrocore", "pet-roms", "extract");
const driveRoms = join(petRoms, "c4040");

const { request, event, events, fail, close, failure } = startDap(root);
let last = "";
const timeout = setTimeout(() => fail(new Error(`PET DAP integration timed out; the screen was:
${last}`)), Number(process.env.RETROCORE_DAP_TIMEOUT ?? 240000));

// The line after a label: its first instruction.
function lineOf(file, label) {
    const lines = readFileSync(file, "utf8").split(/\r?\n/);
    const index = lines.findIndex(line => line === `${label}:`);
    assert.ok(index >= 0, `${label} is in ${file}`);
    return index + 2;
}

// Forgets queued events of a kind, so a wait sees only what happens next.
function drop(name) {
    for (let index = events.length - 1; index >= 0; index--) {
        if (events[index].event === name) events.splice(index, 1);
    }
}

const text = frame => frame.rows.map(row => row.trimEnd()).join("\n");

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

// Types a command and waits for READY. after it: the PET reads no keys while it waits on the IEEE-488 bus.
async function command(line, what) {
    await type(`${line}\r`);
    await screen(screen => screen.includes(line) && ready(screen.slice(screen.lastIndexOf(line))), what);
}

async function launch(args, filters) {
    events.length = 0;
    await request("setExceptionBreakpoints", { filters: filters ?? [] });
    await request("launch", { machine: "pet", sdkRoms, stopOnEntry: false, speed: "max", ...args });
    await request("configurationDone");
}

// The last line with anything on it is a fresh READY.
const ready = screen => /READY\.\s*$/.test(screen);

const tape = join(tmpdir(), `retrocore-pet-${process.pid}.tap`);
const prg = join(tmpdir(), `retrocore-pet-${process.pid}.prg`);
const hello = join(tmpdir(), `retrocore-pet-${process.pid}.asm`);
const disk = join(tmpdir(), `retrocore-pet-${process.pid}.d64`);
try {
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });

    // Boot: BASIC 2's banner and READY.
    await launch({});
    await screen(screen => screen.includes("### COMMODORE BASIC ###") && ready(screen), "READY.");
    assert.equal((await request("threads")).threads[0].name, "PET 2001 (BASIC 2) 6502");
    const devices = await request("retro/devices");
    const hardware = Object.fromEntries(devices.hardware.map(row => [row.id, row]));
    assert.deepEqual(Object.keys(hardware), [
        "model", "cpu", "rom", "memory", "video", "sound", "cassette1", "cassette2",
        "ieee8", "ieee9", "ieee10", "ieee11", "ieee12", "ieee13", "ieee14", "ieee15"
    ]);
    assert.equal(hardware.ieee8.value, "empty");
    assert.equal(hardware.rom.value, "BASIC 2, from the SDK's sources");
    assert.deepEqual(devices.devices.map(device => device.id), ["cassette1", "cassette2"]);

    // A stop shows the 320x200 picture in the 2001-N's green.
    await request("pause", { threadId: 1 });
    await event("stopped");
    const paused = await stoppedFrame();
    assert.equal(paused.machine, "pet");
    assert.equal(paused.model, "pet2001-basic2");
    assert.equal(Buffer.from(paused.video.pixels, "base64").length, 320 * 200 * 4);
    assert.equal(paused.screen, "green");
    assert.deepEqual(paused.screens, ["green", "white", "amber"]);
    await request("continue", { threadId: 1 });

    // A breakpoint in the kernal: the jiffy clock, which the editor's interrupt calls 60 times a second.
    const udtim = lineOf(kernal, "UDTIM");
    const set = await request("setBreakpoints", { source: { path: kernal }, breakpoints: [{ line: udtim }] });
    assert.equal(set.breakpoints[0].verified, true, JSON.stringify(set.breakpoints[0]));
    assert.equal((await event("stopped")).reason, "breakpoint");
    const stack = await request("stackTrace", { threadId: 1 });
    assert.equal(stack.stackFrames[0].name, "UDTIM");
    assert.equal(stack.stackFrames[0].line, udtim);
    assert.ok(stack.totalFrames >= 2, "the interrupt handler is on the call stack");
    await request("setBreakpoints", { source: { path: kernal }, breakpoints: [] });
    await request("continue", { threadId: 1 });

    // RESET stops at the kernal's first instruction, which starts BASIC again.
    await request("setExceptionBreakpoints", { filters: ["machineReset"] });
    await request("retro/reset");
    const reset = await event("stopped");
    assert.equal(reset.reason, "breakpoint");
    const top = (await request("stackTrace", { threadId: 1 })).stackFrames[0];
    assert.equal(top.name, "START");
    assert.equal(top.source.path.toLowerCase(), kernal.toLowerCase());
    await request("setExceptionBreakpoints", { filters: [] });
    await request("continue", { threadId: 1 });
    await screen(ready, "READY. after the reset");

    // A program saved on a blank tape in cassette 1, then saved as a TAP image through the save the host does.
    await type("10 PRINT \"PET\";6*7\r");
    await request("retro/device", { id: "cassette1", action: "record" });
    await type("SAVE \"PROG\"\r");
    await screen(screen => screen.includes("WRITING PROG") && ready(screen), "the save");
    await request("retro/device", { id: "cassette1", action: "stop" });

    // RECORD again records on, onto the same tape, so the unsaved recording is not asked about.
    const resumed = await request("retro/device", { id: "cassette1", action: "record", supportsRetrocoreMedia: true });
    assert.notEqual(resumed?.outcome, "changed", JSON.stringify(resumed));
    await request("retro/device", { id: "cassette1", action: "stop" });
    const tapeDevice =(await request("retro/devices")).devices.find(device => device.id === "cassette1");
    assert.equal(tapeDevice.media.changed, true, "a recording is a changed tape");
    const saved = await request("retro/device", { id: "cassette1", action: "save", path: tape, supportsRetrocoreMedia: true });
    assert.equal(saved.outcome, "saved", JSON.stringify(saved));
    assert.equal(readFileSync(tape).subarray(0, 12).toString(), "C64-TAPE-RAW");

    // Loaded back from the image, it runs.
    await type("NEW\r");
    await request("retro/device", { id: "cassette1", action: "insert", path: tape, supportsRetrocoreMedia: true });
    await type("LOAD\r");
    await screen(screen => screen.includes("FOUND PROG") && ready(screen), "the load");
    await type("RUN\r");
    await screen(screen => screen.includes("PET 42"), "the loaded program's output");

    // A .prg program at BASIC's start loads with BASIC's pointers set and runs.
    const memory = await request("readMemory", { memoryReference: "0x0401", count: 32 });
    const bytes = Buffer.from(memory.data, "base64");
    const end = bytes.indexOf(Buffer.from([0, 0, 0])) + 3;
    writeFileSync(prg, Buffer.concat([Buffer.from([0x01, 0x04]), bytes.subarray(0, end)]));
    await launch({ program: prg });
    await screen(screen => screen.includes("PET 42"), "the .prg program's output");

    // A launched source prints through the kernal's character output.
    writeFileSync(hello, [
        ".cpu Mos6502",
        "OUTCH = $FFD2",
        "        ldx #0",
        "Next:   lda Message,x",
        "        beq Done",
        "        jsr OUTCH",
        "        inx",
        "        bne Next",
        "Done:   rts",
        "Message: .byte \"HELLO\", 0",
        ""
    ].join("\n"));
    events.length = 0;
    await request("launch", { machine: "pet", sdkRoms, source: hello, stopOnEntry: true, speed: "max" });
    await request("setExceptionBreakpoints", { filters: [] });
    await request("configurationDone");
    assert.equal((await event("stopped")).reason, "entry");
    assert.equal((await request("evaluate", { expression: "PC" })).result, "$800 (2048)");
    await request("continue", { threadId: 1 });
    await screen(screen => screen.includes("HELLO"), "the program's output");

    // A 4040 on device 8: a blank disk formatted, a program saved on it, the disk saved as a D64 image and listed.
    if (existsSync(join(driveRoms, "901468-14.uj1"))) {
        writeFileSync(disk, Buffer.alloc(174848));
        await launch({ driveRomDirectory: driveRoms, diskUnits: [8], disks: [disk], ramKilobytes: 32 });
        await screen(ready, "READY. with a 4040");
        const units = await request("retro/devices");
        const rows = Object.fromEntries(units.hardware.map(row => [row.id, row]));
        assert.equal(rows.ieee8.value, "4040 dual disk drive");
        assert.deepEqual(rows.ieee8.devices, ["disk8-0", "disk8-1"]);
        assert.deepEqual(rows.ieee9.actions, ["addCard"]);
        await command("OPEN15,8,15,\"N0:RETROCORE,RC\":CLOSE15", "the format's command");
        await type("10 PRINT \"DISK\";6*7\r");
        await screen(screen => screen.includes("10 PRINT \"DISK\";6*7"), "the program line");
        await command("SAVE \"0:PROG\",8", "the save to disk");
        const driveState = (await request("retro/devices")).devices.find(device => device.id === "disk8-0");
        assert.equal(driveState.media.changed, true, "the formatted disk is changed");
        const written = await request("retro/device", { id: "disk8-0", action: "save", supportsRetrocoreMedia: true });
        assert.equal(written.outcome, "saved", JSON.stringify(written));
        const image = readFileSync(disk);
        assert.equal(image.length, 174848);
        assert.equal(image.subarray(0x165A2, 0x165A4).toString(), "RC", "the disk ID is in the BAM");
        await command("NEW", "NEW");
        await command("LOAD \"$0\",8", "the directory's load");
        await type("LIST\r");
        await screen(screen => screen.includes("\"PROG\"") && screen.includes("BLOCKS FREE"), "the directory");

        // A second unit connects as device 9 and leaves again.
        await request("retro/hardware", { id: "ieee9", action: "add4040" });
        assert.ok((await request("retro/devices")).devices.some(device => device.id === "disk9-1"));
        await request("retro/hardware", { id: "ieee9", action: "removeCard" });
        assert.ok(!(await request("retro/devices")).devices.some(device => device.id === "disk9-0"));

        // A 2040, whose c2040 set lies beside the c4040 folder, connects as device 10 and leaves again.
        if (existsSync(join(driveRoms, "..", "c2040", "901468-06.ul1"))) {
            await request("retro/hardware", { id: "ieee10", action: "add2040" });
            const with2040 = await request("retro/devices");
            assert.equal(with2040.hardware.find(row => row.id === "ieee10").value, "2040 dual disk drive");
            assert.ok(with2040.devices.some(device => device.id === "disk10-0"));
            await request("retro/hardware", { id: "ieee10", action: "removeCard" });
            assert.ok(!(await request("retro/devices")).devices.some(device => device.id === "disk10-0"));
        } else {
            console.log(`Skipped the 2040: no c2040 ROM set beside ${driveRoms}.`);
        }

        // A disks entry that is neither a path nor null is refused, rather than leaving the drive empty unsaid.
        await assert.rejects(
            request("launch", { machine: "pet", sdkRoms, driveRomDirectory: driveRoms, diskUnits: [8], disks: [{ path: disk }] }),
            /disks\[0\] must be an image's path/);
        await assert.rejects(
            request("launch", { machine: "pet", sdkRoms, driveRomDirectory: driveRoms, diskUnits: [8], disks: disk }),
            /disks must be a list/);
        await assert.rejects(
            request("launch", { machine: "pet", model: "pet4032", sdkRoms, driveRomDirectory: driveRoms, diskUnits: 8 }),
            /diskUnits must be a list/);
        await assert.rejects(
            request("launch", { machine: "pet", sdkRoms, driveRomDirectory: driveRoms, diskUnits: [8.5] }),
            /diskUnits holds device numbers/);
    } else {
        console.log(`Skipped the 4040: no c4040 ROM set in ${driveRoms}.`);
    }

    // A 4032: BASIC 4 from the SDK's sources, 32K, no snow, and its own kernal's source.
    await launch({ model: "pet4032", diskUnits: [] });
    await screen(screen => screen.includes("*** COMMODORE BASIC 4.0 ***") && screen.includes("31743 BYTES FREE") && ready(screen), "BASIC 4's READY.");
    assert.equal((await request("threads")).threads[0].name, "PET 4032 6502");
    const rows4032 = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
    assert.equal(rows4032.model.value, "PET 4032");
    assert.equal(rows4032.rom.value, "BASIC 4, revised, from the SDK's sources");
    assert.equal(rows4032.video.value, "40x25 text");
    assert.equal(rows4032.ieee8.value, "empty", "diskUnits: [] leaves the 4040 out");
    const kernal4 = join(sdkRoms, "Basic4", "Kernal4.asm");
    const udtim4 = lineOf(kernal4, "UDTIM");
    const set4 = await request("setBreakpoints", { source: { path: kernal4 }, breakpoints: [{ line: udtim4 }] });
    assert.equal(set4.breakpoints[0].verified, true, JSON.stringify(set4.breakpoints[0]));
    assert.equal((await event("stopped")).reason, "breakpoint");
    assert.equal((await request("stackTrace", { threadId: 1 })).stackFrames[0].name, "UDTIM");
    await request("setBreakpoints", { source: { path: kernal4 }, breakpoints: [] });
    await request("continue", { threadId: 1 });
    await request("setExceptionBreakpoints", { filters: ["machineReset"] });
    await request("retro/reset");
    assert.equal((await event("stopped")).reason, "breakpoint");
    const top4 = (await request("stackTrace", { threadId: 1 })).stackFrames[0];
    assert.equal(top4.name, "START");
    assert.equal(top4.source.path.toLowerCase(), kernal4.toLowerCase());
    await request("setExceptionBreakpoints", { filters: [] });
    await request("continue", { threadId: 1 });
    await screen(ready, "READY. after the 4032's reset");

    // The 4032 comes with a 4040 as device 8; BASIC 4's HEADER formats a blank disk and DIRECTORY lists it.
    if (existsSync(join(driveRoms, "901468-14.uj1"))) {
        writeFileSync(disk, Buffer.alloc(174848));
        await launch({ model: "pet4032", driveRomDirectory: driveRoms, disks: [disk] });
        await screen(ready, "BASIC 4's READY. with a 4040");
        const rows = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
        assert.equal(rows.ieee8.value, "4040 dual disk drive");
        await type("HEADER\"RETROCORE\",D0,IRC\r");
        await screen(screen => screen.includes("ARE YOU SURE"), "HEADER's question");
        await type("Y\r");
        await screen(screen => /\?Y\nREADY\./.test(screen), "the format");
        await command("DIRECTORY", "the directory");
        await screen(screen => screen.includes("\"RETROCORE       \" RC") && screen.includes("BLOCKS FREE"), "the formatted disk's directory");

        await launch({ model: "pet4032", driveRomDirectory: driveRoms });
        await screen(ready, "BASIC 4's READY. with an empty 4040");
        const standard = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
        assert.equal(standard.ieee8.value, "4040 dual disk drive", "a 4032 comes with a 4040");
    }

    await request("disconnect", {});
    console.log("PET DAP integration passed.");
} finally {
    clearTimeout(timeout);
    close();
    for (const file of [tape, prg, hello, disk]) if (existsSync(file)) unlinkSync(file);
}

if (failure()) throw failure();
