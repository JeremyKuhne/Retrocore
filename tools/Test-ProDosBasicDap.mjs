// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// AppleSoft under ProDOS's BASIC.SYSTEM through the debug adapter, on an enhanced IIe with the SDK's ROMs. BASIC.SYSTEM
// turns TRACE on and takes the "#" it prints to see every statement start, then jumps past GONE into the statement, so
// the BASIC thread finds statements there too: RUN stops at its first statement, a breakpoint stops once each time its
// statement runs, stepping goes statement by statement and into a GOSUB, an inline breakpoint stops at its own
// statement, Set Next Statement moves BASIC, and an error stops at its statement. The ProDOS 2.4.3 image is
// m1-dependencies\ProDOS_2_4_3.po under the external-files folder (RETROCORE_CACHE, or %USERPROFILE%\Retrocore), from
// Fetch-M1Dependencies.ps1.

import { startDap } from "./DapClient.mjs";
import { resolve, join } from "node:path";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import assert from "node:assert/strict";

const root = resolve(import.meta.dirname, "..");
const image = join(process.env.RETROCORE_CACHE || join(homedir(), "Retrocore"), "m1-dependencies", "ProDOS_2_4_3.po");
if (!existsSync(image)) {
    console.log("ProDOS BASIC DAP skipped: run Fetch-M1Dependencies.ps1 for the ProDOS 2.4.3 image.");
    process.exit(0);
}

const { request, event, events, fail, close, failure: failed } = startDap(root);
const timeout = setTimeout(() => fail(new Error("ProDOS BASIC DAP integration timed out.")), 120000);
const screen = async () => (await request("apple2/text")).rows.join("\n");
const waitFor = async (test, what) => {
    for (const end = performance.now() + 30000; performance.now() < end;) {
        if (test(await screen())) return;
        await new Promise(done => setTimeout(done, 100));
    }
    assert.fail(`${what} never appeared:\n${await screen()}`);
};

const frames = async () => (await request("stackTrace", { threadId: 2 })).stackFrames;
const stopped = async (reason, what) => {
    const body = await event("stopped");
    assert.equal(body.reason, reason, what);
    return body;
};

const valueOf = async name => (await request("evaluate", { expression: name, frameId: (await frames())[0].id })).result;
const hits = async () => (await request("retro/breakpoints")).breakpoints.map(breakpoint => breakpoint.hits);

try {
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });
    await request("launch", {
        machine: "apple2", model: "iie-enhanced", stopOnEntry: false, sound: "off", speed: "max", diskImage: image
    });

    const path = (await request("retro/basic/document", { base: "retrocore-basic://iie/" })).uri;
    await request("setExceptionBreakpoints", { filters: ["basicStart", "basicErrors"] });
    await request("configurationDone");

    // The disk boots into Bitsy Bye; BASIC.SYSTEM is the fourth entry.
    await waitFor(text => text.includes("BITSY"), "Bitsy Bye");
    for (const key of [10, 10, 10, 13]) {
        await request("retro/key", { code: key });
        await new Promise(done => setTimeout(done, 200));
    }

    await waitFor(text => text.includes("PRODOS BASIC") && /^\]/m.test(text), "BASIC.SYSTEM's prompt");
    await request("retro/type", {
        text: "10 A=1\r20 PRINT \"B\": A=A+1\r30 GOSUB 100\r40 IF A < 4 GOTO 20\r50 X=1/0\r100 PRINT \"S\"\r110 RETURN\r"
    });

    await waitFor(text => text.includes("110 RETURN"), "the typed program");
    const lines = (await request("retro/basic/program")).text.split(/\r?\n/);
    const lineOf = number => lines.findIndex(line => line.startsWith(`${number} `)) + 1;
    const second = lines[lineOf(20) - 1].indexOf("A=A+1") + 1;
    assert.ok(second > 1, lines.join("\n"));

    let set = await request("setBreakpoints", { source: { path }, breakpoints: [{ line: lineOf(20) }] });
    assert.equal(set.breakpoints[0].verified, true);

    // BASIC.SYSTEM's RUN stops at the program's first statement.
    events.length = 0;
    await request("retro/type", { text: "RUN\r" });
    const start = await stopped("breakpoint", "BASIC program start");
    assert.match(start.description, /RUN starts/);
    assert.equal(start.threadId, 2);
    assert.equal((await frames())[0].line, lineOf(10));

    // The breakpoint stops once each time line 20 runs.
    await request("continue", { threadId: 2 });
    await stopped("breakpoint", "the breakpoint on line 20");
    assert.equal((await frames())[0].line, lineOf(20));
    assert.match(await valueOf("A"), /^1\b/);
    await request("continue", { threadId: 2 });
    await stopped("breakpoint", "line 20 again");
    assert.match(await valueOf("A"), /^2\b/);
    assert.deepEqual(await hits(), [2], "each pass is one hit");

    // Stepping goes to the next statement on the line, then the next line, then into the GOSUB.
    await request("next", { threadId: 2 });
    await stopped("step");
    let top = (await frames())[0];
    assert.deepEqual([top.line, top.column], [lineOf(20), second]);
    await request("next", { threadId: 2 });
    await stopped("step");
    assert.equal((await frames())[0].line, lineOf(30));
    await request("stepIn", { threadId: 2 });
    await stopped("step");
    const inside = await frames();
    assert.equal(inside[0].line, lineOf(100));
    assert.equal(inside[1].line, lineOf(30), "the GOSUB's frame is below");

    // An inline breakpoint stops at its own statement.
    set = await request("setBreakpoints", { source: { path }, breakpoints: [{ line: lineOf(20), column: second }] });
    assert.equal(set.breakpoints[0].verified, true);
    await request("continue", { threadId: 2 });
    await stopped("breakpoint", "the inline breakpoint");
    top = (await frames())[0];
    assert.deepEqual([top.line, top.column], [lineOf(20), second]);

    // Set Next Statement moves BASIC back to line 10, which runs from there.
    const targets = await request("gotoTargets", { source: { path }, line: lineOf(10) });
    await request("goto", { threadId: 2, targetId: targets.targets[0].id });
    await stopped("goto");
    assert.equal((await frames())[0].line, lineOf(10));
    await request("continue", { threadId: 2 });
    await stopped("breakpoint", "the inline breakpoint after Set Next Statement");
    assert.match(await valueOf("A"), /^1\b/, "line 10 ran again");

    // The division by zero stops at its statement.
    await request("setBreakpoints", { source: { path }, breakpoints: [] });
    await request("continue", { threadId: 2 });
    const error = await stopped("exception", "the BASIC error");
    assert.match(error.description, /DIVISION BY ZERO/);
    assert.equal((await frames())[0].line, lineOf(50));

    await request("disconnect");
    console.log("ProDOS BASIC DAP passed: under BASIC.SYSTEM, RUN stops at its first statement, a breakpoint stops once per pass, stepping goes by statement and into a GOSUB, an inline breakpoint stops at its statement, Set Next Statement moves BASIC, and an error stops at its statement.");
} finally {
    clearTimeout(timeout);
    close();
}

if (failed()) throw failed();
