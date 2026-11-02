// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Integer BASIC through the debug adapter, on a II with the SDK's ROMs: a file launched on the BASIC thread, stopping
// on its first statement; stepping statement by statement through colons; a breakpoint inside a GOSUB, with the
// GOSUB's frame below it; the program in memory read and written as text; and Control-C as the program's stop.

import { startDap } from "./DapClient.mjs";
import { resolve, join } from "node:path";
import { writeFileSync, unlinkSync, mkdirSync } from "node:fs";
import assert from "node:assert/strict";

const root = resolve(import.meta.dirname, "..");
const { request, event, events, fail, close, failure: failed } = startDap(root);
const timeout = setTimeout(() => fail(new Error("Integer BASIC DAP integration timed out.")), 90000);
const frames = async () => (await request("stackTrace", { threadId: 2 })).stackFrames;
const stopped = async reason => assert.equal((await event("stopped")).reason, reason);

const folder = join(root, "artifacts", "integer-dap");
mkdirSync(folder, { recursive: true });
const file = join(folder, `loop-${process.pid}.integer.bas`);
writeFileSync(file, [
    "REM retrocore integer",
    "10 A=1: B=2",
    "20 FOR I=1 TO 3: GOSUB 100: NEXT I",
    "30 PRINT A;\" \";B",
    "40 END",
    "100 A=A+I",
    "110 RETURN",
    ""
].join("\n"));

try {
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });
    await request("launch", { machine: "apple2", model: "ii", basic: file, stopOnEntry: true });
    await request("configurationDone");

    // The BASIC thread, stopped on the first statement, in the file's own line.
    await stopped("entry");
    const threads = (await request("threads")).threads.map(thread => thread.name);
    assert.equal(threads[1], "BASIC");
    let top = (await frames())[0];
    assert.equal(top.name, "10: A=1");
    assert.equal(top.source.path.toLowerCase(), file.toLowerCase());
    assert.deepEqual([top.line, top.column], [2, 4]);

    // A step goes to the statement after the colon, then to the next line.
    await request("next", { threadId: 2 });
    await stopped("step");
    top = (await frames())[0];
    assert.equal(top.name, "10: B=2");
    assert.equal(top.line, 2);
    await request("next", { threadId: 2 });
    await stopped("step");
    assert.equal((await frames())[0].name, "20: FOR I=1 TO 3");

    // A breakpoint in the subroutine stops with the GOSUB's frame below it.
    const set = await request("setBreakpoints", { source: { path: file }, breakpoints: [{ line: 6 }] });
    assert.equal(set.breakpoints[0].verified, true, JSON.stringify(set.breakpoints[0]));
    await request("continue", { threadId: 2 });
    await stopped("breakpoint");
    const inside = await frames();
    assert.deepEqual(inside.map(frame => frame.name), ["100: A=A+I", "20: GOSUB 100 (GOSUB)"]);

    // The variables, the FOR loop, and expressions in Integer BASIC's arithmetic.
    const scopes = Object.fromEntries((await request("scopes", { frameId: inside[0].id })).scopes.map(scope => [scope.name, scope.variablesReference]));
    const values = Object.fromEntries((await request("variables", { variablesReference: scopes.Variables })).variables.map(item => [item.name, item.value]));
    assert.deepEqual([values.A, values.B, values.I], ["1", "2", "1"]);
    const loops = (await request("variables", { variablesReference: scopes.Loops })).variables;
    assert.equal(loops[0].name, "I");
    assert.equal(loops[0].value, "1 TO 3 STEP 1 (FOR in line 20)");
    const evaluate = async expression => (await request("evaluate", { expression, frameId: inside[0].id, context: "watch" })).result;
    assert.equal(await evaluate("A*10+B MOD 2"), "10");
    assert.equal(await evaluate("7/2"), "3");
    assert.equal(await evaluate("B#2"), "0");
    await request("setVariable", { variablesReference: scopes.Variables, name: "B", value: "7" });
    assert.equal(await evaluate("B"), "7");
    await request("setBreakpoints", { source: { path: file }, breakpoints: [] });

    // Step out returns to the statement after the GOSUB; step over a GOSUB runs it whole.
    await request("stepOut", { threadId: 2 });
    await stopped("step");
    assert.equal((await frames())[0].name, "20: NEXT I");
    await request("next", { threadId: 2 });
    await stopped("step");
    assert.equal((await frames())[0].name, "20: GOSUB 100");
    await request("next", { threadId: 2 });
    await stopped("step");
    assert.deepEqual((await frames()).map(frame => frame.name), ["20: NEXT I"]);

    // Set Next Statement moves to another statement: line 30's PRINT.
    const targets = (await request("gotoTargets", { source: { path: file }, line: 4 })).targets;
    assert.equal(targets[0].label, "30: PRINT A;\" \";B");
    await request("goto", { threadId: 2, targetId: targets[0].id });
    await stopped("goto");
    assert.equal((await frames())[0].name, "30: PRINT A;\" \";B");
    await request("next", { threadId: 2 });
    await stopped("step");
    assert.equal((await frames())[0].name, "40: END");

    // The program in memory reads as text, and writing text puts a new program in.
    const program = await request("retro/basic/program");
    assert.equal(program.dialect, "integer");
    assert.equal(program.text.split("\n")[0], "10 A=1: B=2");
    const written = await request("retro/basic/write", { text: "10 PRINT \"NEW\"\n20 GOTO 10\n" });
    assert.equal(written.success, true, JSON.stringify(written.diagnostics));
    assert.equal((await request("retro/basic/program")).text, "10 PRINT \"NEW\"\n20 GOTO 10\n");
    const refused = await request("retro/basic/write", { text: "10 PRINT (\n" });
    assert.equal(refused.success, false);
    assert.match(refused.diagnostics[0].message, /SYNTAX/);

    // An error stops at its statement with Integer BASIC's message.
    await request("setExceptionBreakpoints", { filters: ["basicErrors"] });
    assert.equal((await request("retro/basic/write", { text: "10 A=1: GOTO 999\n" })).success, true);
    await request("continue", { threadId: 1 });
    for (const key of "RUN\r") await request("retro/key", { code: key.charCodeAt(0) });
    const error = await event("stopped");
    assert.equal(error.reason, "exception");
    assert.equal(error.description, "*** BAD BRANCH ERR in 10 (code 55).");
    assert.equal((await frames())[0].name, "10: GOTO 999");
    assert.equal((await request("retro/basic/write", { text: "10 PRINT \"NEW\"\n20 GOTO 10\n" })).success, true);

    // RUN it, then Control-C stops the program.
    await request("setExceptionBreakpoints", { filters: ["basicStop"] });
    await request("continue", { threadId: 1 });
    for (const key of "RUN\r") await request("retro/key", { code: key.charCodeAt(0) });
    await new Promise(done => setTimeout(done, 500));
    await request("retro/key", { code: 3 });
    const stop = await event("stopped");
    assert.equal(stop.reason, "exception");
    assert.match(stop.description, /Ctrl-C in (10|20)\./);

    console.log("Integer BASIC DAP passed: the BASIC thread stops on entry, steps through colons, stops in a GOSUB with its caller below, steps out and over GOSUBs, sets the next statement, reads and writes the program, and stops on an error and on Control-C.");
} catch (error) {
    fail(error);
} finally {
    clearTimeout(timeout);
    close();
    unlinkSync(file);
}

if (failed()) {
    console.error(failed());
    process.exit(1);
}
