// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// VIC-20 BASIC through the debug adapter, from the SDK's sources, on NTSC and PAL, unexpanded and with the 3K and
// 8K expansions, which move BASIC's program to $0401 and $1201: a file launched on the BASIC thread, stopping on its
// first statement; stepping statement by statement through colons; a breakpoint inside a GOSUB, with the GOSUB's
// frame below it; the variables and the FOR loop; the program in memory read and written as text; an error with
// BASIC's message, which the VIC-20 finds by number; Step Into on SYS stopping in the machine code; and a statement
// started once though an interrupt returns to GONE.

import { startDap } from "./DapClient.mjs";
import { resolve, join } from "node:path";
import { writeFileSync, unlinkSync, mkdirSync } from "node:fs";
import assert from "node:assert/strict";

const root = resolve(import.meta.dirname, "..");
const sdkRoms = join(root, "src", "Retrocore.Machines.Commodore", "Roms");
const folder = join(root, "artifacts", "vic20-basic-dap");
mkdirSync(folder, { recursive: true });
const file = join(folder, `loop-${process.pid}.petbasic.bas`);
writeFileSync(file, [
    "10 A=1: B=2",
    "20 FOR I=1 TO 3: GOSUB 100: NEXT I",
    "30 PRINT A;B",
    "40 END",
    "100 A=A+I",
    "110 RETURN",
    ""
].join("\n"));

async function session(video, ramExpansion) {
    const model = `${video}, ${ramExpansion}`;
    const { request, event, fail, close, failure } = startDap(root);
    const timeout = setTimeout(() => fail(new Error(`VIC-20 BASIC DAP (${model}) timed out.`)), 120000);
    const frames = async () => (await request("stackTrace", { threadId: 2 })).stackFrames;
    const stopped = async reason => assert.equal((await event("stopped")).reason, reason);
    try {
        await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });
        await request("launch", { machine: "vic20", video, ramExpansion, sdkRoms, basic: file, stopOnEntry: true, speed: "max" });
        await request("configurationDone");

        // The BASIC thread, stopped on the first statement, in the file's own line.
        await stopped("entry");
        assert.equal((await request("threads")).threads[1].name, "BASIC");
        let top = (await frames())[0];
        assert.equal(top.name, "10: A=1");
        assert.equal(top.source.path.toLowerCase(), file.toLowerCase());

        // A step goes to the statement after the colon, then to the next line.
        await request("next", { threadId: 2 });
        await stopped("step");
        assert.equal((await frames())[0].name, "10: B=2");
        await request("next", { threadId: 2 });
        await stopped("step");
        assert.equal((await frames())[0].name, "20: FOR I=1 TO 3");

        // A breakpoint in the subroutine stops with the GOSUB's frame below it.
        const set = await request("setBreakpoints", { source: { path: file }, breakpoints: [{ line: 5 }] });
        assert.equal(set.breakpoints[0].verified, true, JSON.stringify(set.breakpoints[0]));
        await request("continue", { threadId: 2 });
        await stopped("breakpoint");
        const inside = await frames();
        assert.deepEqual(inside.map(frame => frame.name), ["100: A=A+I", "20: GOSUB 100 (GOSUB)"]);

        // The variables and the FOR loop.
        const scopes = Object.fromEntries((await request("scopes", { frameId: inside[0].id })).scopes.map(scope => [scope.name, scope.variablesReference]));
        const values = Object.fromEntries((await request("variables", { variablesReference: scopes.Variables })).variables.map(item => [item.name, item.value]));
        assert.deepEqual([values.A, values.B, values.I], ["1", "2", "1"]);
        const loops = (await request("variables", { variablesReference: scopes.Loops })).variables;
        assert.equal(loops[0].name, "I");
        assert.equal(loops[0].value, "1 TO 3 STEP 1 (FOR in line 20)");
        const evaluate = async expression => (await request("evaluate", { expression, frameId: inside[0].id, context: "watch" })).result;
        assert.equal(await evaluate("A*10+B"), "12");
        await request("setBreakpoints", { source: { path: file }, breakpoints: [] });

        // The program in memory reads as text, and writing text puts a new program in.
        const program = await request("retro/basic/program");
        assert.equal(program.dialect, "petbasic");
        assert.equal(program.text.split("\n")[0], "10 A=1: B=2");
        const written = await request("retro/basic/write", { text: "10 PRINT \"NEW\"\n20 GOTO 10\n" });
        assert.equal(written.success, true, JSON.stringify(written.diagnostics));
        assert.equal((await request("retro/basic/program")).text, "10 PRINT \"NEW\"\n20 GOTO 10\n");

        // An error stops at its statement with BASIC's own message.
        await request("setExceptionBreakpoints", { filters: ["basicErrors"] });
        assert.equal((await request("retro/basic/write", { text: "10 A=1: GOTO 999\n" })).success, true);
        await request("continue", { threadId: 1 });
        for (const key of "RUN\r") await request("retro/key", { code: key.charCodeAt(0) });
        const error = await event("stopped");
        assert.equal(error.reason, "exception");
        assert.match(error.description, /^\?UNDEF'D STATEMENT ERROR in 10/);
        assert.equal((await frames())[0].name, "10: GOTO 999");

        // Step Into on SYS stops in the machine code it calls, at its first instruction: LDA #1, STA $03F0, RTS at
        // $033A, in the bytes the kernal leaves unused below the cassette buffer.
        await request("setExceptionBreakpoints", { filters: [] });
        const routine = Buffer.from([0xA9, 0x01, 0x8D, 0xF0, 0x03, 0x60]).toString("base64");
        await request("writeMemory", { memoryReference: "0x33A", data: routine });
        const document = (await request("retro/basic/document", { base: "retrocore-basic://vic20/" })).uri;
        const looping = "10 SYS 826\n20 FOR I=1 TO 2000\n30 A=A+1\n40 NEXT I\n50 PRINT \"DONE\"\n";
        assert.equal((await request("retro/basic/write", { text: looping })).success, true);
        await request("setBreakpoints", { source: { path: document }, breakpoints: [{ line: 1 }] });
        await request("continue", { threadId: 1 });
        for (const key of "RUN\r") await request("retro/key", { code: key.charCodeAt(0) });
        await stopped("breakpoint");
        await request("stepIn", { threadId: 2 });
        const into = await event("stopped");
        assert.equal(into.reason, "step");
        assert.match(into.description ?? "", /^Machine code at \$033A/);

        // The jiffy clock interrupts sixty times a second; returning from one taken at GONE starts no statement again,
        // so each pass of the loop is one hit.
        await request("setBreakpoints", {
            source: { path: document },
            breakpoints: [{ line: 3, hitCondition: ">100000" }, { line: 5 }]
        });
        await request("continue", { threadId: 1 });
        await stopped("breakpoint");
        const hits = (await request("retro/breakpoints")).breakpoints.map(breakpoint => breakpoint.hits);
        assert.equal(hits[0], 2000, `each pass is one hit: ${JSON.stringify(hits)}`);

        await request("disconnect", {});
    } finally {
        clearTimeout(timeout);
        close();
    }

    if (failure()) throw failure();
}

try {
    await session("ntsc", "none");
    await session("pal", "none");
    await session("ntsc", "3k");
    await session("ntsc", "8k");
    console.log("VIC-20 BASIC DAP passed on NTSC and PAL, unexpanded and with 3K and 8K: stops on entry, steps through colons, stops in a GOSUB with its caller below, shows the variables and the FOR loop, reads and writes the program, stops on an error with BASIC's message, steps into SYS's machine code, and starts no statement twice for an interrupt.");
} finally {
    unlinkSync(file);
}
