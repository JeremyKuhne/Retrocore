// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Model I DAP integration: boots Level II to READY, stops at a breakpoint in the SDK's Level II source with the
// Z80 call stack, saves and loads a program on tape, stops where RUN and CONT start and where the machine resets,
// and boots NEWDOS/80 from a JV1 image when one is present.
// The ROMs are assembled from the SDK's sources unless RETROCORE_TRS80_ROMS names the dumps.

import { resolve, join } from "node:path";
import { readFileSync, existsSync, unlinkSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import assert from "node:assert/strict";
import { startDap } from "./DapClient.mjs";

const root = resolve(import.meta.dirname, "..");
const sdkRoms = join(root, "src", "Retrocore.Machines.Trs80", "Roms");
const level2 = join(sdkRoms, "Level2.asm");
const dos = process.env.RETROCORE_TRS80_DOS
    ?? join(process.env.RETROCORE_CACHE ?? join(process.env.USERPROFILE ?? "", "Retrocore"), "trs80-disks", "NEWDOS_80sssd_jv1.DSK");

const { request, event, events, fail, close, failure } = startDap(root);
let last = "";
const timeout = setTimeout(() => fail(new Error(`Model I DAP integration timed out; the screen was:
${last}`)), Number(process.env.RETROCORE_DAP_TIMEOUT ?? 240000));
const verbose = process.env.RETROCORE_DAP_VERBOSE === "1";
function phase(text) { if (verbose) console.log(`${new Date().toISOString()} ${text}`); }

// The line after a label: its first instruction.
function lineOf(label) {
    const lines = readFileSync(level2, "utf8").split(/\r?\n/);
    const index = lines.findIndex(line => line === `${label}:`);
    assert.ok(index >= 0, `${label} is in Level2.asm`);
    return index + 2;
}

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

// Whether a queued retro/devices event showed a device in a state, such as a drive reading.
function sawDevice(id, test) {
    return events.some(message => message.event === "retro/devices"
        && message.body.devices.some(device => device.id === id && test(device)));
}

// Forgets queued events of a kind, so a wait sees only what happens next.
function drop(name) {
    for (let index = events.length - 1; index >= 0; index--) {
        if (events[index].event === name) events.splice(index, 1);
    }
}

// Waits for the cassette motor to go on and then off.
async function tape() {
    phase("waiting for the tape");
    drop("retro/media");
    let on = false;
    for (;;) {
        const media = await event("retro/media");
        last = (await request("retro/display")).rows.join("\n");
        if (media.cassette.motor) on = true;
        else if (on) return;
    }
}

async function type(text) {
    for (const character of text) await request("retro/key", { code: character === "\r" ? 13 : character.charCodeAt(0) });
}

async function launch(args, filters) {
    events.length = 0;
    phase("launching");
    // A launch after the first starts at once, as configuration is done, so the filters are set before it.
    await request("setExceptionBreakpoints", { filters: filters ?? [] });
    await request("launch", { machine: "trs80-model1", sdkRoms, stopOnEntry: false, speed: "max", ...args });
    phase("launched");
    await request("configurationDone");
    phase("configured");
}

// Waits for a stop, checking its reason, thread and description, and returns the top frame on that thread.
async function stoppedAt(reason, threadId, description) {
    const stopped = await event("stopped");
    assert.equal(stopped.reason, reason);
    assert.equal(stopped.threadId, threadId);
    assert.equal(stopped.description, description);
    return (await request("stackTrace", { threadId })).stackFrames[0];
}

const cassette = join(tmpdir(), `retrocore-${process.pid}.cas`);
try {
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });
    phase("initialized");

    // Boot: Level II asks the memory size, and ENTER sizes all 48K.
    await launch({});
    await screen(text => text.includes("MEM SIZE?"), "MEM SIZE?");
    await type("\r");
    await screen(text => text.includes("READY"), "READY");
    assert.equal((await request("threads")).threads[0].name, "Model I Z80");
    let hardware = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
    assert.deepEqual(Object.keys(hardware), ["model", "rom", "memory", "cassette", "expansion", "disk", "lowercase"]);
    assert.equal(hardware.rom.value, "Level II BASIC 1.3");
    assert.equal(hardware.memory.value, "48 KB");
    assert.equal(hardware.expansion.value, "installed");
    assert.equal(hardware.disk.value, "none", "no disks, so no controller");
    assert.deepEqual(hardware.cassette.devices, ["cassette"]);

    // Speed: 1x keeps to the Model I's 1.774 MHz clock, 2x runs twice as many cycles, and the running frames carry
    // what the host measures. The rest of the script runs at max.
    const clock = 1_774_080;
    const rate = async () => {
        const start = (await request("retro/display")).cycles;
        const time = performance.now();
        await new Promise(resolve => setTimeout(resolve, 1500));
        return ((await request("retro/display")).cycles - start) / ((performance.now() - time) / 1000) / clock;
    };
    assert.deepEqual(await request("retro/speed", { speed: 1 }), { speed: 1 });
    const single = await rate();
    assert.ok(single > 0.85 && single < 1.15, `1x ran at ${single.toFixed(2)}x the clock`);
    await request("retro/speed", { speed: 2 });
    const double = await rate();
    assert.ok(double / single > 1.7 && double / single < 2.3, `2x ran ${(double / single).toFixed(2)} times as fast as 1x`);
    drop("retro/frame");
    let measured;
    while (typeof (measured = (await event("retro/frame")).speed).actual !== "number") { /* the first half second */ }
    assert.equal(measured.setting, 2);
    assert.ok(measured.actual > 1.7 && measured.actual < 2.3, `the frame reported ${measured.actual}x`);
    assert.ok(Math.abs(measured.hertz - measured.actual * clock) < clock / 100);
    await assert.rejects(request("retro/speed", { speed: 3 }), /speed must be 1, 2, 4, 8 or "max"/);
    assert.deepEqual(await request("retro/speed", { speed: "max" }), { speed: "max" });

    // At READY the picture holds still, so running frames leave out its pixels; a stop always sends them.
    drop("retro/frame");
    const still = [];
    while (still.length < 4) still.push(await event("retro/frame"));
    assert.ok(still.every(frame => frame.running), "the frames are from the running machine");
    assert.ok(still.slice(1).every(frame => frame.video.pixels === undefined), "a still picture is sent once");
    assert.equal(still[0].video.width, 384);
    await request("pause", { threadId: 1 });
    await event("stopped");
    const paused = await event("retro/frame");
    assert.equal(paused.running, false);
    assert.equal(Buffer.from(paused.video.pixels, "base64").length, 384 * 192 * 4);
    await request("continue", { threadId: 1 });

    // A breakpoint in a ROM routine: each echoed key reaches DISPLAY_CHAR through OUTDO's CALL.
    const display = lineOf("DISPLAY_CHAR");
    const set = await request("setBreakpoints", { source: { path: level2 }, breakpoints: [{ line: display }] });
    assert.equal(set.breakpoints[0].verified, true);
    await type("A");
    let stopped = await event("stopped");
    assert.equal(stopped.reason, "breakpoint");
    let stack = await request("stackTrace", { threadId: 1 });
    assert.equal(stack.stackFrames[0].line, display);
    assert.equal(stack.stackFrames[0].name, "DISPLAY_CHAR");
    assert.ok(stack.totalFrames >= 2, "the caller is on the call stack");
    const caller = stack.stackFrames[1];
    assert.equal(caller.source.path.toLowerCase(), level2.toLowerCase());
    assert.equal((await request("evaluate", { expression: "A" })).result, "$41 (65)");
    const scopes = await request("scopes", { frameId: 1 });
    const registers = await request("variables", { variablesReference: scopes.scopes[0].variablesReference });
    assert.ok(registers.variables.some(variable => variable.name === "HL"));
    await request("stepOut", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "step");
    stack = await request("stackTrace", { threadId: 1 });
    assert.equal(stack.stackFrames[0].name, caller.name, "step out returns to the caller");
    await request("setBreakpoints", { source: { path: level2 }, breakpoints: [] });
    await request("continue", { threadId: 1 });

    // A cassette: CSAVE records to a file when the tape is ejected, and CLOAD reads it back.
    await type("\r10 PRINT \"SAVED\";6*7\r");
    await screen(text => text.includes("10 PRINT \"SAVED\";6*7"), "the typed line");
    await request("retro/media", { device: "cassette", action: "record", path: cassette });
    drop("retro/devices");
    await type("CSAVE \"A\"\r");
    await tape();
    assert.ok(sawDevice("cassette", device => device.transport.mode === "recording" && device.activity === "writing"),
        "the cassette showed as writing while CSAVE ran");
    await request("retro/media", { device: "cassette", action: "eject" });
    assert.ok(existsSync(cassette), "the recording is saved");
    await screen(text => /CSAVE "A"\s*\n\s*READY/.test(text), "CSAVE's READY");
    // BASIC does not scan the keyboard while it carries out a command, so each command waits for READY. NEW
    // clears the screen first.
    await type("NEW\r");
    await screen(text => text.startsWith("READY") && !text.includes("CSAVE"), "NEW's READY");
    await request("retro/media", { device: "cassette", action: "insert", path: cassette });
    await type("CLOAD \"A\"\r");
    await tape();
    await screen(text => /CLOAD "A"\s*\n\s*READY/.test(text), "CLOAD's READY");
    await type("RUN\r");
    await screen(text => text.includes("SAVED 42"), "the loaded program's output");

    // BASIC program start stops on the BASIC thread at the first statement RUN runs, and where CONT resumes.
    await request("setExceptionBreakpoints", { filters: ["machineReset", "basicStart", "basicStop"] });
    await type("NEW\r");
    await screen(text => /^READY\s*\n>/.test(text), "NEW's prompt before RUN");
    for (const line of ["10 A=1", "20 STOP", "30 A=3"]) {
        await type(`${line}\r`);
        await screen(text => text.includes(`>${line}`), line);
    }
    await type("RUN\r");
    assert.equal((await stoppedAt("breakpoint", 2, "RUN starts at 10.")).name, "10: A=1");
    await request("continue", { threadId: 2 });
    assert.equal((await event("stopped")).description, "STOP in 20.");
    await request("continue", { threadId: 2 });
    await screen(text => text.includes("BREAK IN 20"), "the STOP's BREAK");
    await type("CONT\r");
    assert.equal((await stoppedAt("breakpoint", 2, "CONT resumes at 30.")).name, "30: A=3");
    await request("setExceptionBreakpoints", { filters: ["machineReset"] });
    await request("continue", { threadId: 2 });
    await new Promise(resolve => setTimeout(resolve, 300));

    // The reset button raises the Z80's NMI: Machine reset stops at its handler, once, and BASIC restarts with the
    // program kept, as no disk controller answers.
    await request("retro/reset");
    const nmi = await stoppedAt("breakpoint", 1, "The machine reset.");
    assert.equal(nmi.name, "NMI");
    assert.equal(nmi.line, lineOf("NMI"));
    await request("continue", { threadId: 1 });
    await type("PRINT 77*2\r");
    await screen(text => text.includes("154"), "BASIC answering after the reset");
    await type("LIST\r");
    await screen(text => /LIST[\s\S]*30 A=3/.test(text), "the program kept through the reset");
    await request("setExceptionBreakpoints", { filters: [] });

    // Machine reset stops as the machine powers on, at the ROM's first instruction.
    await launch({}, ["machineReset"]);
    const powerOn = await stoppedAt("breakpoint", 1, "The machine reset as it powered on.");
    assert.equal(powerOn.source.path.toLowerCase(), level2.toLowerCase());
    assert.equal((await request("evaluate", { expression: "PC" })).result, "$0 (0)");
    await request("continue", { threadId: 1 });
    await screen(text => text.includes("MEM SIZE?"), "MEM SIZE? after the power-on stop");

    // A Z80 source: stepping into its ROM call goes into Level2.asm, and stepping out comes back.
    const hello = join(root, "sample", "trs80", "hello.asm");
    const call = readFileSync(hello, "utf8").split(/\r?\n/).findIndex(line => line.trim() === "CALL DISPLAY_CHAR") + 1;

    // Without stopOnEntry, Machine reset stops a loaded program at its entry; with it, the entry stop is the only one.
    await launch({ source: hello }, ["machineReset"]);
    const entry = await stoppedAt("breakpoint", 1, "The machine reset as it powered on, and is at the program's entry.");
    assert.equal(entry.source.path.toLowerCase(), hello.toLowerCase());
    events.length = 0;
    await request("launch", { machine: "trs80-model1", sdkRoms, source: hello, stopOnEntry: true, speed: "max" });
    assert.equal((await request("setBreakpoints", { source: { path: hello }, breakpoints: [{ line: call }] })).breakpoints[0].verified, true);
    await request("setExceptionBreakpoints", { filters: ["machineReset"] });
    await request("configurationDone");
    assert.equal((await event("stopped")).reason, "entry");
    await request("continue", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "breakpoint");
    assert.equal((await request("evaluate", { expression: "A" })).result, "$48 (72)");
    await request("stepIn", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "step");
    stack = await request("stackTrace", { threadId: 1 });
    assert.equal(stack.stackFrames[0].name, "DISPLAY_CHAR");
    assert.equal(stack.stackFrames[0].source.path.toLowerCase(), level2.toLowerCase());
    assert.equal(stack.stackFrames[1].line, call);
    await request("stepOut", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "step");
    stack = await request("stackTrace", { threadId: 1 });
    assert.equal(stack.stackFrames[0].source.path.toLowerCase(), hello.toLowerCase());
    assert.equal(stack.stackFrames[0].line, call + 1);
    await request("setBreakpoints", { source: { path: hello }, breakpoints: [] });
    await request("setExceptionBreakpoints", { filters: [] });
    await request("continue", { threadId: 1 });
    await screen(text => text.includes("HELLO FROM THE Z80"), "the sample's message");

    // A DOS from a JV1 image, through the Percom doubler NEWDOS/80 expects.
    if (existsSync(dos)) {
        await launch({ doubler: "percom", disks: [dos] });
        await screen(text => text.includes("NEWDOS/80 READY"), "NEWDOS/80 READY");

        // The devices: the cassette and four drives, drive 0 holding the image and seen reading as it booted.
        let devices = (await request("retro/devices")).devices;
        assert.deepEqual(devices.map(device => device.id), ["cassette", "disk0", "disk1", "disk2", "disk3"]);
        hardware = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
        assert.equal(hardware.disk.value, "FD1771, with a Percom doubler");
        assert.deepEqual(hardware.disk.devices, ["disk0", "disk1", "disk2", "disk3"]);
        const drive = devices[1];
        assert.equal(drive.kind, "floppyDrive");
        assert.match(drive.controller, /Percom/);
        assert.deepEqual(drive.operations, ["insert", "eject", "writeProtect"]);
        assert.equal(drive.media.format, "JV1");
        assert.equal(drive.media.label.toLowerCase(), resolve(dos).toLowerCase());
        assert.equal(drive.media.writeProtected, false);
        assert.equal(devices[2].media, null);
        assert.ok(sawDevice("disk0", device => device.activity === "reading" && device.head.selected && device.head.motor),
            "drive 0 showed as reading while NEWDOS booted");
        assert.ok(sawDevice("disk0", device => device.head.track > 0), "drive 0's head moved off track 0");
        devices = (await request("retro/device", { id: "disk0", action: "writeProtect", writeProtected: true })).devices;
        assert.equal(devices[1].media.writeProtected, true);

        await type("DIR 0\r");
        await screen(text => text.includes("SUPERZAP/CMD"), "the directory");
        const media = await request("retro/media", { device: "disk", action: "eject", drive: 0 });
        assert.equal(media.disks[0].mounted, false);
        assert.equal((await request("retro/devices")).devices[1].media, null);
        await assert.rejects(
            request("retro/device", { id: "cassette", action: "writeProtect", writeProtected: true }),
            /does not support/);
    } else {
        console.log(`Skipped the DOS boot: ${dos} is missing.`);
    }

    // The lowercase modification boots with the lowercase kit's character generator from the SDK.
    await launch({ lowercase: true });
    await screen(text => text.includes("MEM SIZE?"), "MEM SIZE? with the lowercase kit");

    // At real speed, the fast cassette runs the machine as fast as it can while the motor turns, so the tape loads in
    // a fraction of its playing time; the boot and typing still run at the machine's clock.
    await launch({ speed: 1, cassette });
    await screen(text => text.includes("MEM SIZE?"), "MEM SIZE? at real speed");
    await type("\r");
    await screen(text => text.includes("READY"), "READY at real speed");
    await type("CLOAD \"A\"\r");
    const start = performance.now();
    await tape();
    const seconds = (performance.now() - start) / 1000;
    const playing = statSync(cassette).size * 8 * 0.002;
    // Paced to the clock the load cannot beat the tape's playing time, so beating it shows the acceleration even
    // on a loaded machine.
    assert.ok(seconds < playing * 0.9, `the fast cassette loaded in ${seconds.toFixed(1)} s, not faster than the tape's ${playing.toFixed(1)} s`);
    await screen(text => /CLOAD "A"\s*\n\s*READY/.test(text), "the fast CLOAD's READY");

    await request("disconnect");
    console.log("Model I DAP passed: boot to READY, a Level II source breakpoint with the Z80 call stack, a cassette round trip, RUN and CONT stops, the reset button, power-on and entry stops, 1x and 2x speed, stepping from a Z80 source into Level2.asm"
        + (existsSync(dos) ? ", a NEWDOS/80 boot" : "") + " and a fast cassette load at real speed.");
} finally {
    clearTimeout(timeout);
    close();
    if (existsSync(cassette)) unlinkSync(cassette);
}
if (failure()) throw failure();
