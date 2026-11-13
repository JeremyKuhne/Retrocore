// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Apple Pascal DAP integration, on the Apple III (Apple III Pascal 1.1) and a 64K Apple II Plus (Apple Pascal 1.1):
// boots Pascal, stops on the Pascal thread at a pascal function breakpoint on the Filer's main procedure, reads its
// frames, scopes and the p-machine's registers, steps over a p-code, and steps out to the system once Q quits the
// Filer.
// The disks are Apple3Pascal1.1Disk1.dsk and Disk2.dsk in RETROCORE_APPLE3_DISKS (by default <cache>\apple3-disks)
// and UCSD Pascal 1.1_1.dsk in RETROCORE_APPLE2_PASCAL_DISKS (by default <cache>\apple2-pascal-disks); a machine
// whose disks are missing is skipped. The ROMs are assembled from the SDK's sources.

import { resolve, join } from "node:path";
import { existsSync } from "node:fs";
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
    drop();
    for (;;) {
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

    await request("disconnect");
    console.log(`Apple Pascal DAP passed on ${passed.length === 0 ? "no machine" : passed.join(" and ")}: the Pascal thread, `
        + "a pascal function breakpoint in the Filer, its frames, scopes and registers, Step Over and Step Out.");
} finally {
    clearTimeout(timeout);
    close();
}
