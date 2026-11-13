// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Business BASIC through the debug adapter, on the Apple III from Apple's Business BASIC 1.23 disk: a program typed at
// its prompt is read back from banked memory; a breakpoint in a GOSUB stops on the BASIC thread with the GOSUB's frame
// below it, with its variables, FOR loop, expressions and a condition; stepping out and over, and Set Next Statement; an error stops at its statement with BASIC's message; and
// STOP and CONTROL-C stop the program; a program written while one runs; and a basic launch of a workspace file.
// Skips without the disk, as CI runs it.

import { resolve, join } from "node:path";
import { existsSync, mkdirSync, writeFileSync, unlinkSync } from "node:fs";
import assert from "node:assert/strict";
import { startDap } from "./DapClient.mjs";

const root = resolve(import.meta.dirname, "..");
const sdkRoms = join(root, "src", "Retrocore.Machines.Apple3", "Roms");
const disk = process.env.RETROCORE_APPLE3_BUSINESS_BASIC
    ?? join(process.env.RETROCORE_CACHE ?? join(process.env.USERPROFILE ?? "", "Retrocore"), "apple3-disks", "Apple3BusBasic1.23.dsk");
if (!existsSync(disk)) {
    console.log(`Business BASIC DAP skipped: ${disk} is missing.`);
    process.exit(0);
}

const { request, event, events, fail, close, failure } = startDap(root);
let last = "";
const timeout = setTimeout(() => fail(new Error(`Business BASIC DAP timed out; the screen was:\n${last}`)), 240000);
const frames = async () => (await request("stackTrace", { threadId: 2 })).stackFrames;
const names = async () => (await frames()).map(frame => frame.name);
const stopped = async reason => {
    const stop = await event("stopped");
    assert.equal(stop.reason, reason, JSON.stringify(stop));
    return stop;
};

// Waits for a running frame whose screen satisfies a test.
async function screen(test, what) {
    for (let index = events.length - 1; index >= 0; index--) {
        if (events[index].event === "retro/frame") events.splice(index, 1);
    }

    for (;;) {
        const frame = await event("retro/frame");
        last = frame.rows.join("\n");
        if (test(last)) return;
        if (!frame.running) throw new Error(`Stopped before ${what}.`);
    }
}

const program = [
    "10 A=1:B=2",
    "20 FOR I=1 TO 3:GOSUB 100:NEXT I",
    "30 PRINT A;B",
    "40 END",
    "100 A=A+I",
    "110 RETURN"
];

try {
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });
    await request("launch", { machine: "apple3", sdkRoms, stopOnEntry: false, speed: "max", disks: [disk] });
    await request("configurationDone");

    // HELLO ends with a catalog and NEW, at BASIC's prompt; a program typed there is in banked memory.
    await screen(text => text.includes("TOTAL BLOCKS"), "HELLO's catalog");
    const document = (await request("retro/basic/document", { base: "retrocore-basic://apple3/" })).uri;
    assert.equal(document, "retrocore-basic://apple3/Program.business.bas");
    await request("retro/type", { text: "HOME\r" + program.join("\r") + "\r" });
    for (let tries = 0; ; tries++) {
        const text = (await request("retro/basic/program")).text;
        if (text === program.join("\n") + "\n") break;
        assert.ok(tries < 200, `the program in memory reads as typed, not:\n${text}`);
        await new Promise(done => setTimeout(done, 100));
    }

    assert.equal((await request("retro/basic/program")).dialect, "business");
    assert.equal((await request("threads")).threads[1].name, "BASIC");

    // A breakpoint in the subroutine stops on the BASIC thread with the GOSUB's frame below it.
    const set = await request("setBreakpoints", { source: { path: document }, breakpoints: [{ line: 5 }] });
    assert.equal(set.breakpoints[0].verified, true, JSON.stringify(set.breakpoints[0]));
    await request("retro/type", { text: "RUN\r" });
    await stopped("breakpoint");
    assert.deepEqual(await names(), ["100: A=A+I", "20: GOSUB 100 (GOSUB)"]);
    assert.equal((await frames())[0].source.path, document);

    // The variables, the FOR loop, and expressions, read from banked memory; a variable set from the debugger.
    const inside = await frames();
    const scopes = Object.fromEntries((await request("scopes", { frameId: inside[0].id })).scopes
        .map(scope => [scope.name, scope.variablesReference]));
    assert.deepEqual(Object.keys(scopes), ["Variables", "Arrays", "Loops", "Program"]);
    const values = Object.fromEntries((await request("variables", { variablesReference: scopes.Variables })).variables
        .map(item => [item.name, item.value]));
    assert.deepEqual([values.A, values.B, values.I], ["1", "2", "1"]);
    const loops = (await request("variables", { variablesReference: scopes.Loops })).variables;
    assert.deepEqual([loops[0].name, loops[0].value], ["I", "1 TO 3 STEP 1 (FOR in line 20)"]);
    const evaluate = async expression => (await request("evaluate", { expression, frameId: inside[0].id, context: "watch" })).result;
    assert.equal(await evaluate("A*10+B"), "12");
    assert.equal(await evaluate("I/3"), ".333333");
    await request("setVariable", { variablesReference: scopes.Variables, name: "B", value: "7" });
    assert.equal(await evaluate("B"), "7");

    // A condition stops only when it holds.
    await request("setBreakpoints", { source: { path: document }, breakpoints: [{ line: 5, condition: "I=2" }] });
    await request("continue", { threadId: 2 });
    await stopped("breakpoint");
    assert.equal(await evaluate("I"), "2");
    assert.equal(await evaluate("A"), "2");
    await request("setBreakpoints", { source: { path: document }, breakpoints: [] });

    // Step out returns to the statement after the GOSUB; step over a GOSUB runs it whole.
    await request("stepOut", { threadId: 2 });
    await stopped("step");
    assert.deepEqual(await names(), ["20: NEXT I"]);
    await request("next", { threadId: 2 });
    await stopped("step");
    assert.deepEqual(await names(), ["20: GOSUB 100"]);
    await request("next", { threadId: 2 });
    await stopped("step");
    assert.deepEqual(await names(), ["20: NEXT I"]);

    // The program scope says where the program is, in banked memory.
    const programScope = Object.fromEntries((await request("scopes", { frameId: (await frames())[0].id })).scopes
        .map(scope => [scope.name, scope.variablesReference])).Program;
    const places = Object.fromEntries((await request("variables", { variablesReference: programScope }))
        .variables.map(item => [item.name, item.value]));
    assert.match(places.Program, /^x8[0-9A-F]:\$[0-9A-F]{4}-x8[0-9A-F]:\$[0-9A-F]{4} \(\d+ bytes\)$/);
    assert.equal(places["Current line"], "20");

    // Set Next Statement moves to line 30's PRINT.
    const targets = (await request("gotoTargets", { source: { path: document }, line: 3 })).targets;
    assert.equal(targets[0].label, "30: PRINT A;B");
    await request("goto", { threadId: 2, targetId: targets[0].id });
    await stopped("goto");
    assert.deepEqual(await names(), ["30: PRINT A;B"]);
    await request("next", { threadId: 2 });
    await stopped("step");
    assert.deepEqual(await names(), ["40: END"]);

    // An error stops at its statement with Business BASIC's message.
    await request("setExceptionBreakpoints", { filters: ["basicErrors"] });
    await request("continue", { threadId: 1 });
    await screen(text => /\)\s*$/m.test(text), "the prompt after END");
    await request("retro/type", { text: "40 GOTO 999\rRUN\r" });
    const error = await stopped("exception");
    assert.equal(error.description, "?UNDEF'D STATEMENT ERROR in 40 (code 8).");
    assert.deepEqual(await names(), ["40: GOTO 999"]);

    // STOP, and CONTROL-C in a loop, stop the program where it is.
    await request("setExceptionBreakpoints", { filters: ["basicStop"] });
    await request("continue", { threadId: 1 });
    await screen(text => text.includes("UNDEF'D STATEMENT"), "the error's message");
    await request("retro/type", { text: "40 STOP\rRUN\r" });
    assert.equal((await stopped("exception")).description, "STOP in 40.");
    assert.deepEqual(await names(), ["40: STOP"]);

    // STOP's message, after the type-ahead buffer is emptied, then a loop that CONTROL-C stops.
    await request("continue", { threadId: 1 });
    await screen(text => text.includes("PROGRAM INTERRUPTED"), "STOP's message");
    await request("retro/type", { text: "40 GOTO 40\rRUN\r" });
    await new Promise(done => setTimeout(done, 1500));
    await request("retro/key", { code: 3 });
    assert.equal((await stopped("exception")).description, "Ctrl-C in 40.");
    assert.deepEqual(await names(), ["40: GOTO 40"]);

    // A basic launch boots the disk, puts a workspace file in, with a label for a line number, and stops at its first
    // statement in the file.
    const folder = join(root, "artifacts", "business-dap");
    mkdirSync(folder, { recursive: true });
    const file = join(folder, `count-${process.pid}.business.bas`);
    writeFileSync(file, ["REM retrocore business", "10 T=0", "loop:", "T=T+1", "30 IF T<3 THEN GOTO loop", "40 PRINT \"T=\";T", "50 END", ""].join("\n"));
    try {
        events.length = 0;
        await request("launch", { machine: "apple3", sdkRoms, speed: "max", disks: [disk], basic: file, stopOnEntry: true });
        await request("configurationDone");
        await stopped("entry");
        const entry = (await frames())[0];
        assert.deepEqual([entry.name, entry.source.path.toLowerCase(), entry.line], ["10: T=0", file.toLowerCase(), 2]);

        // Writing a program while one runs puts BASIC back at its prompt, where RUN runs the new one.
        const written = await request("retro/basic/write", { text: "10 PRINT \"NEW\";2*3\n" });
        assert.equal(written.success, true, JSON.stringify(written.diagnostics));
        assert.equal(written.returnedToPrompt, true);
        assert.equal((await request("retro/basic/program")).text, "10 PRINT\"NEW\";2*3\n");
        await request("continue", { threadId: 1 });
        await request("retro/type", { text: "RUN\r" });
        await screen(text => text.includes("NEW6"), "the new program's output");

        // The file itself runs through its label's loop.
        events.length = 0;
        await request("launch", { machine: "apple3", sdkRoms, speed: "max", disks: [disk], basic: file, stopOnEntry: false });
        await request("configurationDone");
        await screen(text => text.includes("T=3"), "the file's output");
    } finally {
        unlinkSync(file);
    }

    await request("disconnect");
    console.log("Business BASIC DAP passed: a typed program read back from banked memory, a breakpoint in a GOSUB with "
        + "its caller below, variables, loops, expressions and a condition, stepping out and over, Set Next Statement, the "
        + "program scope, stops at an error, STOP and CONTROL-C, a program written into memory, and a basic launch of a "
        + "workspace file with a label.");
} catch (error) {
    fail(error);
} finally {
    clearTimeout(timeout);
    close();
}
if (failure()) throw failure();
