// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Apple Pascal DAP integration, on the Apple III (Apple III Pascal 1.1) and a 64K Apple II Plus (Apple Pascal 1.1):
// boots Pascal, stops on the Pascal thread at a pascal function breakpoint on the Filer's main procedure, reads its
// frames, scopes and the p-machine's registers, steps over a p-code, and steps out to the system once Q quits the
// Filer. On the Apple III it then compiles a program with a listing, and stops at a source breakpoint in a copy of
// its source on the host, reads the program's variable by name, steps by line, and stops there again on the loop's
// next pass.
// The disks are Apple3Pascal1.1Disk1.dsk and Disk2.dsk in RETROCORE_APPLE3_DISKS (by default <cache>\apple3-disks)
// and UCSD Pascal 1.1_1.dsk in RETROCORE_APPLE2_PASCAL_DISKS (by default <cache>\apple2-pascal-disks); a machine
// whose disks are missing is skipped. The ROMs are assembled from the SDK's sources.

import { resolve, join } from "node:path";
import { existsSync, mkdtempSync, writeFileSync, rmSync, statSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import assert from "node:assert/strict";
import { startDap } from "./DapClient.mjs";

const root = resolve(import.meta.dirname, "..");
const cache = process.env.RETROCORE_CACHE ?? join(process.env.USERPROFILE ?? "", "Retrocore");
const apple3Disks = process.env.RETROCORE_APPLE3_DISKS ?? join(cache, "apple3-disks");
const apple2Disks = process.env.RETROCORE_APPLE2_PASCAL_DISKS ?? join(cache, "apple2-pascal-disks");

const machines = [
    {
        name: "Apple III",
        thread: "Apple III 6502",
        disks: [join(apple3Disks, "Apple3Pascal1.1Disk1.dsk"), join(apple3Disks, "Apple3Pascal1.1Disk2.dsk")],
        launch: disks => ({ machine: "apple3", sdkRoms: join(root, "src", "Retrocore.Machines.Apple3", "Roms"), disks }),
        title: "Based on  U.C.S.D. Pascal II.1",
        start: "\r",
        command: "Command: E(dit, R(un, F(ile",
        filer: "PASCALFI",
        prompt: "Filer: L(dir"
    },
    {
        name: "Apple II Plus",
        thread: "II Plus CPU",
        disks: [join(apple2Disks, "UCSD Pascal 1.1_1.dsk")],
        launch: disks => ({ machine: "apple2", model: "iiplus", diskImage: disks[0] }),
        title: "WELCOME APPLE1, TO APPLE II PASCAL 1.1",
        start: "",
        command: "COMMAND: E(DIT, R(UN, F(ILE",
        filer: "FILEHAND",
        prompt: "FILER: G, S, N"
    }
];

const { request, event, events, fail, close } = startDap(root);
let last = "";
const timeout = setTimeout(() => fail(new Error(`Apple Pascal DAP integration timed out; the screen was:
${last}`)), Number(process.env.RETROCORE_DAP_TIMEOUT ?? 400000));

// Drops what the run sends meanwhile: frames, sound, cycle counts and drive lights.
function drop() {
    for (let index = events.length - 1; index >= 0; index--) {
        if (events[index].event !== "stopped") events.splice(index, 1);
    }
}

// Waits for a running frame whose screen satisfies a test.
async function screen(test, what) {
    for (;;) {
        drop();
        const frame = await event("retro/frame");
        last = `${frame.rows.join("\n")}\n(${frame.cycles} cycles)`;
        if (test(frame.rows.join("\n"))) return frame;
        if (!frame.running) throw new Error(`Stopped before ${what}.`);
    }
}

// Waits for a stop.
async function stop() {
    for (;;) {
        const index = events.findIndex(message => message.event === "stopped");
        if (index >= 0) return events.splice(index, 1)[0].body;
        drop();
        const frame = await event("retro/frame");
        last = `${frame.rows.join("\n")}\n(${frame.cycles} cycles)`;
    }
}

// HELLO, as the Editor is given it and as its copy on the host reads.
const hello = ["PROGRAM HELLO;", "VAR I: INTEGER;", "PROCEDURE SHOW(N: INTEGER);", "BEGIN", "WRITELN(N*7)", "END;", "BEGIN",
    "FOR I := 1 TO 3 DO", "SHOW(I)", "END."];

// Types keys, a moment after the last prompt appeared, and waits for the screen to show something.
async function type(text, until) {
    await new Promise(done => setTimeout(done, 300));
    await request("retro/type", { text });
    await screen(screenText => screenText.includes(until), until);
}

// Compiles HELLO on the Apple III with a listing on /PASCAL2, then stops at line 9 of the host's copy, SHOW(I).
async function sourceBreakpoints(machine) {
    const folder = mkdtempSync(join(tmpdir(), "retrocore-pascal-"));
    const source = join(folder, "hello.pas");
    writeFileSync(source, hello.join("\n") + "\n");
    try {
        events.length = 0;
        await request("launch", { ...machine.launch(machine.disks), stopOnEntry: false, speed: "max" });
        await request("setExceptionBreakpoints", { filters: [] });
        await request("configurationDone");
        await request("retro/device", { id: "disk2", action: "writeProtect", writeProtected: false });
        await screen(text => text.includes(machine.title), "the title");
        await type("\r", machine.command);
        await type("E", "No workfile is present");
        await type("\r", ">Edit: A(djst");
        await type("I", ">Insert:");
        // Pasted whole: the machine's typing pace keeps the Editor from losing keys as it scrolls.
        await request("retro/type", { text: hello.join("\n") + "\n" });
        await screen(text => hello.every(line => text.includes(line)), "the pasted program");
        await request("retro/key", { code: 3 });
        await screen(text => text.includes(">Edit: A(djst"), "the Editor's prompt");
        await type("Q", "W(rite to a new file name");
        await type("W", "Name of output file");
        await type("/PASCAL2/HELLO\r", "bytes long");
        await type("E", machine.command);
        await type("C", "Compile what text?");
        await type("/PASCAL2/HELLO\r", "To what codefile?");
        await type("/PASCAL2/HELLO\r", "Listing file");
        await type("/PASCAL2/HELLO.LST.TEXT\r", "Smallest available space");
        await new Promise(done => setTimeout(done, 1000));

        // The listing on /PASCAL2 binds the source's lines: SHOW(I) has code, and VAR I declares.
        const set = await request("setBreakpoints", { source: { path: source }, breakpoints: [{ line: 9 }, { line: 2 }] });
        assert.equal(set.breakpoints[0].verified, true, set.breakpoints[0].message);
        assert.equal(set.breakpoints[1].verified, false);
        assert.match(set.breakpoints[1].message, /no code on line 2/);

        await type("X", "Execute what file?");
        await request("retro/type", { text: "/PASCAL2/HELLO\r" });
        const stopped = await stop();
        assert.equal(stopped.reason, "breakpoint");
        assert.equal(stopped.threadId, 3);
        let frames = (await request("stackTrace", { threadId: 3 })).stackFrames;
        assert.equal(frames[0].source?.path, source);
        assert.equal(frames[0].line, 9);
        assert.match(frames[0].name, /^HELLO \(HELLO\.1\+\$000D\): SLDO3$/);

        // The listing names the program's variable, I, in its locals and for evaluating.
        const locals = (await request("scopes", { frameId: frames[0].id })).scopes.find(scope => scope.name === "Locals");
        const named = (await request("variables", { variablesReference: locals.variablesReference })).variables;
        assert.deepEqual(named.find(variable => variable.name === "I"), { name: "I", value: "1", type: "INTEGER", variablesReference: 0, memoryReference: named.find(variable => variable.name === "I").memoryReference });
        assert.equal((await request("evaluate", { expression: "I", frameId: frames[0].id, context: "hover" })).result, "1");

        // Step Over goes by line: the call, which the listing counts in line 10, where the compiler read END.
        await request("next", { threadId: 3 });
        assert.equal((await stop()).reason, "step");
        frames = (await request("stackTrace", { threadId: 3 })).stackFrames;
        assert.equal(frames[0].source?.path, source);
        assert.notEqual(frames[0].line, 9);

        // The loop's next pass stops at SHOW(I) again.
        await request("continue", { threadId: 1 });
        const again = await stop();
        assert.equal(again.reason, "breakpoint");
        const second = (await request("stackTrace", { threadId: 3 })).stackFrames[0];
        assert.equal(second.line, 9);
        assert.equal((await request("evaluate", { expression: "I", frameId: second.id })).result, "2");
        await request("setBreakpoints", { source: { path: source }, breakpoints: [] });
        await request("continue", { threadId: 1 });
        await screen(text => /\n21 /.test(text), "the program's output");

        // The disk the Editor and Compiler wrote saves to an image, as WOZ or as sectors, and lists the new files.
        const disk2 = () => request("retro/devices").then(body => body.devices.find(device => device.id === "disk2"));
        assert.equal((await disk2()).media.changed, true);
        assert.ok((await disk2()).operations.includes("save"));
        const woz = join(folder, "PASCAL2.woz");
        const sectors = join(folder, "PASCAL2.dsk");
        await request("retro/device", { id: "disk2", action: "save", path: woz });
        await request("retro/device", { id: "disk2", action: "save", path: sectors });
        const saved = await disk2();
        assert.deepEqual([saved.media.label, saved.media.format, saved.media.changed], [sectors, "DSK", false]);
        assert.equal(statSync(sectors).size, 143360);
        // The same host the session runs: RETROCORE_DAP_HOST, such as a native build, or the Release build.
        const native = process.env.RETROCORE_DAP_HOST;
        const host = join(root, "artifacts", "AnyCPU", "Release", "Retrocore.Debug", "net10.0", "Retrocore.Debug.dll");
        for (const image of [woz, sectors]) {
            const args = ["--pascal", "catalog", image];
            const catalog = native
                ? execFileSync(native, args, { encoding: "utf8" })
                : execFileSync("dotnet", [host, ...args], { encoding: "utf8" });
            assert.match(catalog, /HELLO\.CODE/i, image);
            assert.match(catalog, /HELLO\.LST\.TEXT/i, image);
        }
    } finally {
        rmSync(folder, { recursive: true, force: true });
    }
}

const passed = [];
try {
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });
    for (const machine of machines) {
        if (!machine.disks.every(disk => existsSync(disk))) {
            console.log(`Skipped ${machine.name}: ${machine.disks.join(" or ")} is missing.`);
            continue;
        }

        events.length = 0;
        await request("launch", { ...machine.launch(machine.disks), stopOnEntry: false, speed: "max" });
        await request("setExceptionBreakpoints", { filters: [] });
        const filer = `pascal ${machine.filer}.1`;
        const set = await request("setFunctionBreakpoints", { breakpoints: [{ name: filer }, { name: "pascal 7.1+$10" }] });
        assert.deepEqual(set.breakpoints.map(breakpoint => breakpoint.verified), [true, true]);
        await request("setFunctionBreakpoints", { breakpoints: [{ name: filer }] });
        await request("configurationDone");

        await screen(text => text.includes(machine.title), "the title");
        if (machine.start) await request("retro/type", { text: machine.start });
        await screen(text => text.includes(machine.command), "the command line");
        // The debugger looks for the interpreter about once a second, and the thread appears once it finds it.
        let threads = [];
        for (let tries = 0; tries < 50 && !threads.includes("Pascal"); tries++) {
            threads = (await request("threads")).threads.map(thread => thread.name);
            await new Promise(done => setTimeout(done, 100));
            drop();
        }

        assert.equal(threads[0], machine.thread);
        assert.equal(threads.at(-1), "Pascal", "the Pascal thread appears once the interpreter runs");

        // The Filer's main procedure stops at its first p-code.
        await request("retro/type", { text: "F" });
        const stopped = await stop();
        assert.equal(stopped.threadId, 3);
        assert.equal(stopped.reason, "function breakpoint");
        assert.equal(stopped.description, `${machine.filer}.1+$0000`);

        const frames = (await request("stackTrace", { threadId: 3 })).stackFrames;
        assert.match(frames[0].name, new RegExp(`^${machine.filer}\\.1\\+\\$0000: \\S`));
        assert.ok(frames.length >= 2, "the system called the Filer");
        assert.match(frames.at(-1).name, /^PASCALSY\.\d+\+\$[0-9A-F]{4}$/, "the system's outer block is at the bottom");

        const scopes = (await request("scopes", { frameId: frames[0].id })).scopes;
        assert.deepEqual(scopes.map(scope => scope.name).filter(name => name !== "Globals"), ["Locals", "P-machine"]);
        const registers = (await request("variables", { variablesReference: scopes.at(-1).variablesReference })).variables;
        assert.deepEqual(registers.map(register => register.name), ["IPC", "MP", "BASE", "JTAB", "SEG"]);
        assert.match(registers[0].value, /^(x8[0-9A-F]:)?\$[0-9A-F]{4}$/);

        // Step Over runs one p-code of the procedure.
        await request("next", { threadId: 3 });
        const step = await stop();
        assert.equal(step.reason, "step");
        assert.equal(step.threadId, 3);
        const after = (await request("stackTrace", { threadId: 3 })).stackFrames[0].name;
        assert.match(after, new RegExp(`^${machine.filer}\\.1\\+\\$0*[1-9A-F][0-9A-F]*: `), after);

        // Step Out runs until the Filer returns, once Q quits it, to the p-code after the system's call.
        await request("setFunctionBreakpoints", { breakpoints: [] });
        await request("stepOut", { threadId: 3 });
        await screen(text => text.includes(machine.prompt), "the Filer's prompt");
        await request("retro/type", { text: "Q" });
        const returned = await stop();
        assert.equal(returned.reason, "step");
        const out = (await request("stackTrace", { threadId: 3 })).stackFrames[0].name;
        assert.match(out, /^PASCALSY\.\d+\+/, out);
        passed.push(machine.name);
    }

    const sources = passed.includes("Apple III");
    if (sources) { await sourceBreakpoints(machines[0]); }

    await request("disconnect");
    console.log(`Apple Pascal DAP passed on ${passed.length === 0 ? "no machine" : passed.join(" and ")}: the Pascal thread, `
        + "a pascal function breakpoint in the Filer, its frames, scopes and registers, Step Over and Step Out"
        + (sources ? "; and on the Apple III a source breakpoint through a listing the Compiler wrote, with line steps." : "."));
} finally {
    clearTimeout(timeout);
    close();
}
