// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Altair 8800 DAP integration: launches an 8080 source that greets and echoes on the 88-2SIO's terminal, stops at a
// breakpoint in its Print routine with the 8080 call stack and registers, steps out to the caller, shows the terminal's
// frames and hardware, echoes typed keys, stops on a write to the serial data port, and stops where the machine resets.
// The Altair has no ROM, so nothing is needed but the repository.

import { resolve, join } from "node:path";
import { writeFileSync, existsSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
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
    const hardware = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
    assert.deepEqual(Object.keys(hardware), ["model", "memory", "serial", "terminal", "panel"]);
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

    // Typed keys echo.
    await request("continue", { threadId: 1 });
    await type("Hello, 8080!");
    await screen(screen => screen.includes("ALTAIR 8800\nHello, 8080!"), "the echoed keys");

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

    await request("disconnect", {});
    console.log("Altair DAP integration passed.");
} finally {
    clearTimeout(timeout);
    close();
    if (existsSync(source)) unlinkSync(source);
}

if (failure()) throw failure();
