// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Apple-1 DAP integration: boots the Monitor to its prompt, examines memory, stops at a breakpoint in the SDK's
// Monitor source with the 6502 call stack, stops where the machine resets, clears the screen, saves and loads memory
// on a WAV tape through the cassette interface, and runs a launched source that prints through the Monitor's ECHO.
// The ROMs are assembled from the SDK's sources unless RETROCORE_APPLE1_ROMS names the dumps.

import { resolve, join } from "node:path";
import { readFileSync, writeFileSync, existsSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import assert from "node:assert/strict";
import { startDap } from "./DapClient.mjs";

const root = resolve(import.meta.dirname, "..");
const sdkRoms = join(root, "src", "Retrocore.Machines.Apple1", "Roms");
const monitor = join(sdkRoms, "WozMonitor.asm");

const { request, event, events, fail, close, failure } = startDap(root);
let last = "";
const timeout = setTimeout(() => fail(new Error(`Apple-1 DAP integration timed out; the screen was:
${last}`)), Number(process.env.RETROCORE_DAP_TIMEOUT ?? 240000));
const verbose = process.env.RETROCORE_DAP_VERBOSE === "1";
function phase(text) { if (verbose) console.log(`${new Date().toISOString()} ${text}`); }

// The line after a label: its first instruction.
function lineOf(label) {
    const lines = readFileSync(monitor, "utf8").split(/\r?\n/);
    const index = lines.findIndex(line => line === `${label}:`);
    assert.ok(index >= 0, `${label} is in WozMonitor.asm`);
    return index + 2;
}

// Forgets queued events of a kind, so a wait sees only what happens next.
function drop(name) {
    for (let index = events.length - 1; index >= 0; index--) {
        if (events[index].event === name) events.splice(index, 1);
    }
}

// The screen's lines, without their trailing blanks.
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

async function type(line) {
    for (const character of line) await request("retro/key", { code: character === "\r" ? 13 : character.charCodeAt(0) });
}

async function launch(args, filters) {
    events.length = 0;
    phase("launching");
    // A launch after the first starts at once, as configuration is done, so the filters are set before it.
    await request("setExceptionBreakpoints", { filters: filters ?? [] });
    await request("launch", { machine: "apple1", sdkRoms, stopOnEntry: false, speed: "max", ...args });
    await request("configurationDone");
}

// Waits for a stop, checking its reason, thread and description, and returns the top frame.
async function stoppedAt(reason, description) {
    const stopped = await event("stopped");
    assert.equal(stopped.reason, reason);
    assert.equal(stopped.threadId, 1);
    assert.equal(stopped.description, description);
    return (await request("stackTrace", { threadId: 1 })).stackFrames[0];
}

const tape = join(tmpdir(), `retrocore-apple1-${process.pid}.wav`);
const hello = join(tmpdir(), `retrocore-apple1-${process.pid}.asm`);
try {
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });

    // Boot: the Monitor shows its backslash.
    await launch({});
    await screen(screen => screen.startsWith("\\"), "the Monitor's prompt");
    assert.equal((await request("threads")).threads[0].name, "Apple-1 CPU");
    const hardware = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
    assert.deepEqual(Object.keys(hardware), ["model", "memory", "terminal", "cassette"]);
    assert.equal(hardware.memory.value, "4 KB at $0000, 4 KB at $E000");
    assert.deepEqual(hardware.cassette.devices, ["cassette"]);

    // The Monitor examines its own first bytes, after the blank line its Return leaves.
    await type("FF00.FF07\r");
    await screen(screen => screen.includes("FF00.FF07\n\nFF00: D8 58 A0 7F 8C 12 D0 A9"), "the examined bytes");

    // A stop shows the 40x24 picture.
    await request("pause", { threadId: 1 });
    await event("stopped");
    const paused = await event("retro/frame");
    assert.equal(paused.running, false);
    assert.equal(paused.machine, "apple1");
    assert.equal(Buffer.from(paused.video.pixels, "base64").length, 280 * 192 * 4);
    assert.equal(paused.screen, "green", "a green monitor by default");
    assert.deepEqual(paused.screens, ["green", "white", "amber"], "the terminal has no color to show");

    // The characters light in the monitor's phosphor; a new monitor sends a stopped frame drawn on it.
    const brightest = frame => {
        const pixels = Buffer.from(frame.video.pixels, "base64");
        let best = [0, 0, 0];
        for (let i = 0; i < pixels.length; i += 4) if (pixels[i + 1] > best[1]) best = [pixels[i], pixels[i + 1], pixels[i + 2]];
        return best;
    };
    assert.deepEqual(brightest(paused), [51, 255, 102]);
    await request("retro/screen", { screen: "white" });
    const white = await event("retro/frame");
    assert.equal(white.screen, "white");
    assert.deepEqual(brightest(white), [240, 240, 240]);
    await assert.rejects(request("retro/screen", { screen: "color" }), /screen must be green, white or amber/);
    await request("retro/screen", { screen: "green" });
    await event("retro/frame");
    await request("continue", { threadId: 1 });

    // A breakpoint in the Monitor: each typed key is echoed through ECHO, called from NEXTCHAR.
    const echo = lineOf("ECHO");
    const set = await request("setBreakpoints", { source: { path: monitor }, breakpoints: [{ line: echo }] });
    assert.equal(set.breakpoints[0].verified, true);
    await type("A");
    assert.equal((await event("stopped")).reason, "breakpoint");
    let stack = await request("stackTrace", { threadId: 1 });
    assert.equal(stack.stackFrames[0].line, echo);
    assert.equal(stack.stackFrames[0].name, "ECHO");
    assert.ok(stack.totalFrames >= 2, "the caller is on the call stack");
    assert.equal(stack.stackFrames[1].name, "NEXTCHAR");
    assert.equal((await request("evaluate", { expression: "A" })).result, "$C1 (193)");
    // While debugging, the editor's hover is the debugger's: a documented name brings its ;; summary.
    assert.equal((await request("evaluate", { expression: "XAML", context: "hover", frameId: 1 })).result,
        "$24 (36) · The low byte of the address being examined, the last one opened.");
    assert.equal((await request("evaluate", { expression: "XAML", context: "watch", frameId: 1 })).result, "$24 (36)", "a watch is the value alone");
    // ECHO starts with its wait for the terminal, which loops back to ECHO while the terminal is busy, so the
    // breakpoint comes out first or step out could stop on it again.
    await request("setBreakpoints", { source: { path: monitor }, breakpoints: [] });
    await request("stepOut", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "step");
    stack = await request("stackTrace", { threadId: 1 });
    assert.equal(stack.stackFrames[0].name, "NEXTCHAR", "step out returns to the caller");
    await request("continue", { threadId: 1 });
    await type("\u001b");

    // RESET: Machine reset stops at the Monitor's first instruction, once, and the Monitor starts again.
    await request("setExceptionBreakpoints", { filters: ["machineReset"] });
    await request("retro/reset");
    const reset = await stoppedAt("breakpoint", "The machine reset.");
    assert.equal(reset.name, "RESET");
    assert.equal(reset.line, lineOf("RESET"));
    await request("continue", { threadId: 1 });
    await request("setExceptionBreakpoints", { filters: [] });
    // The Monitor shows its backslash after the reset, before the screen is cleared.
    await new Promise(resolve => setTimeout(resolve, 500));

    // CLEAR SCREEN blanks the screen and puts the cursor at the top left.
    await request("apple1/clearScreen");
    await type("300: 11 22 33 44\r");
    await screen(screen => screen.startsWith("300: 11 22 33 44\n\n0300: "), "the store after CLEAR SCREEN");

    // The cassette interface writes the bytes to a WAV file, which is saved when the tape is ejected.
    await request("retro/media", { device: "cassette", action: "record", path: tape });
    await type("C100R\r");
    await screen(screen => screen.includes("C100: A9*"), "the cassette interface's prompt");
    await type("300.303W\r");
    await screen(screen => /300\.303W\n\\/.test(screen), "the Monitor again after writing");
    await request("retro/media", { device: "cassette", action: "eject" });
    assert.ok(existsSync(tape), "the recording is saved");
    assert.equal(readFileSync(tape).subarray(0, 4).toString(), "RIFF");

    // Reading it back restores the bytes.
    await request("apple1/clearScreen");
    await type("300: 0 0 0 0\r");
    await request("retro/media", { device: "cassette", action: "insert", path: tape });
    await type("C100R\r");
    await screen(screen => screen.includes("C100: A9*"), "the cassette interface's prompt again");
    await type("300.303R\r");
    await screen(screen => /300\.303R\n\\/.test(screen), "the Monitor again after reading");
    await type("300.303\r");
    await screen(screen => screen.includes("0300: 11 22 33 44"), "the bytes read from tape");

    // Machine reset stops as the machine powers on, at the Monitor's first instruction.
    await launch({}, ["machineReset"]);
    const powerOn = await stoppedAt("breakpoint", "The machine reset as it powered on.");
    assert.equal(powerOn.source.path.toLowerCase(), monitor.toLowerCase());
    assert.equal((await request("evaluate", { expression: "PC" })).result, "$FF00 (65280)");
    await request("continue", { threadId: 1 });
    await screen(screen => screen.startsWith("\\"), "the prompt after the power-on stop");

    // A launched source loads at $0300 and prints through the Monitor's ECHO, which the boot has set the PIA up for.
    writeFileSync(hello, [
        ".cpu Mos6502",
        "ECHO = $FFEF",
        "GETLINE = $FF1F",
        "        LDX #0",
        "Next:   LDA Message,X",
        "        BEQ Done",
        "        JSR ECHO",
        "        INX",
        "        BNE Next",
        "Done:   JMP GETLINE",
        "Message: .byte $C8, $C5, $CC, $CC, $CF, 0",
        ""
    ].join("\n"));
    events.length = 0;
    await request("launch", { machine: "apple1", sdkRoms, source: hello, stopOnEntry: true, speed: "max" });
    await request("setExceptionBreakpoints", { filters: [] });
    await request("configurationDone");
    assert.equal((await event("stopped")).reason, "entry");
    assert.equal((await request("evaluate", { expression: "PC" })).result, "$300 (768)");
    await request("continue", { threadId: 1 });
    await screen(screen => screen.includes("HELLO"), "the program's output");

    await request("disconnect", {});
    console.log("Apple-1 DAP integration passed.");
} finally {
    clearTimeout(timeout);
    close();
    for (const file of [tape, hello]) if (existsSync(file)) unlinkSync(file);
}

if (failure()) throw failure();
