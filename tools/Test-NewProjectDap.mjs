// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// A project `retrocore new` makes, built and run. The 6502 template, with a machine of each of its families, and the
// enhanced IIe and the business PET, which show lowercase where their families' first machines do not, writes a project that `retrocore build --all` builds for every target; then each target,
// launched as F5 launches it, boots its environment from the disk, tape or hex the build wrote, runs the program to
// its environment's Exit, and shows the greeting on the machine's screen: in capitals where the machine has no
// lowercase, and in lowercase where the target's LOWERCASE switch is 1.
//
//   node tools/Test-NewProjectDap.mjs              # every target
//   node tools/Test-NewProjectDap.mjs apple3-sos   # one

import { startDap } from "./DapClient.mjs";
import { resolve, join } from "node:path";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { spawnSync } from "node:child_process";
import assert from "node:assert/strict";

const root = resolve(import.meta.dirname, "..");
const host = join(root, "artifacts", "AnyCPU", "Release", "Retrocore.Debug", "net11.0", "Retrocore.Debug.dll");
const retrocore = (cwd, ...args) => process.env.RETROCORE_DAP_HOST
    ? spawnSync(resolve(process.env.RETROCORE_DAP_HOST), args, { cwd, encoding: "utf8" })
    : spawnSync("dotnet", [host, ...args], { cwd, encoding: "utf8" });

// Each target, with the greeting its screen shows and what shows that its environment has the machine again once the
// program has ended: the prompt AppleSoft, BASIC and BBC BASIC show, ], READY. (ready. in the business PET's
// lowercase set) and >; the Woz Monitor running in its ROM, at $FF00-$FFFF, where its command line waits with no
// prompt; nothing under SOS, where the program waits.
const capitals = "HELLO, WORLD!";
const lowercase = "Hello, world!";
const greetings = {
    "apple1-wozmon": [capitals, 0xFF00],
    "apple2-dos": [capitals, "]"],
    "apple2-iie-enhanced-dos": [lowercase, "]"],
    "apple3-sos": [lowercase, null],
    "pet-basic": [capitals, "READY."],
    "pet4032-business-basic": [lowercase, "ready."],
    "bbc-dfs": [lowercase, ">"]
};
const targets = process.argv.length > 2 ? process.argv.slice(2) : Object.keys(greetings);

const folder = mkdtempSync(join(tmpdir(), "retrocore-new-"));
process.on("exit", () => rmSync(folder, { recursive: true, force: true }));
const project = join(folder, "greeting");
const made = retrocore(folder, "new", "6502", "greeting", "--machines", "apple1,apple2,apple2-iie-enhanced,apple3,pet,pet4032-business,bbc");
assert.equal(made.status, 0, `retrocore new failed:\n${made.stdout}${made.stderr}`);
const built = retrocore(project, "build", "--all");
assert.equal(built.status, 0, `retrocore build --all failed:\n${built.stdout}${built.stderr}`);
for (const target of Object.keys(greetings)) {
    assert.match(built.stdout, new RegExp(`^greeting/${target}: `, "m"), `${target} built`);
}

const { request, event, fail, close, failure } = startDap(root);
// Each boot takes the machine a few seconds; the PET's tape takes longest.
const timeout = setTimeout(() => fail(new Error("New project DAP integration timed out.")), 120000 * targets.length);

// The line of an exit.s's Exit, its only instruction.
function exitLine(source) {
    const lines = readFileSync(source, "utf8").split(/\r?\n/);
    const start = lines.indexOf(".proc Exit");
    assert.ok(start >= 0, `Exit is in ${source}`);
    return start + 2;
}

try {
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });
    for (const target of targets) {
        const environment = JSON.parse(readFileSync(join(project, "retrocore.json"), "utf8").replace(/^\/\/.*$/gm, ""))
            .targets[target].environment;
        const exit = join(project, "src", "platform", environment, "exit.s");
        await request("launch", { project, target, stopOnEntry: false, speed: "max", sound: "off", checkContracts: "stop" });
        const set = await request("setBreakpoints", { source: { path: exit }, breakpoints: [{ line: exitLine(exit) }] });
        assert.equal(set.breakpoints[0].verified, true, `${target}: a breakpoint at Exit binds in ${exit}`);
        await request("configurationDone");

        const stop = await event("stopped");
        assert.equal(stop.reason, "breakpoint", `${target}: the program reaches Exit: ${JSON.stringify(stop)}`);
        const [greeting, prompt] = greetings[target];
        const screen = async () => (await request("retro/display")).rows.join("\n");
        const shown = await screen();
        assert.ok(shown.includes(greeting), `${target}: the screen shows "${greeting}":\n${shown}`);

        // The environment takes over again: the Woz Monitor runs in its ROM, and the others show their prompts on a line
        // below the greeting.
        if (typeof prompt === "number") {
            await request("setBreakpoints", { source: { path: exit }, breakpoints: [] });
            await request("continue", { threadId: 1 });
            await new Promise(done => setTimeout(done, 1000));
            await request("pause", { threadId: 1 });
            await event("stopped");
            const frame = (await request("stackTrace", { threadId: 1 })).stackFrames[0];
            const address = parseInt(frame.instructionPointerReference, 16);
            assert.ok(address >= prompt, `${target}: the machine runs the Monitor's ROM again, at ${frame.instructionPointerReference}`);
        } else if (prompt !== null) {
            await request("setBreakpoints", { source: { path: exit }, breakpoints: [] });
            await request("continue", { threadId: 1 });
            const below = text => text.slice(text.indexOf(greeting) + greeting.length).split("\n")
                .some(line => line.trimEnd() === prompt);
            let last = "";
            for (const end = performance.now() + 20000; performance.now() < end && !below(last = await screen());) {
                await new Promise(done => setTimeout(done, 100));
            }
            assert.ok(below(last), `${target}: the screen shows "${prompt}" below the greeting:\n${last}`);
            await request("pause", { threadId: 1 });
            await event("stopped");
        }
        console.log(`${target}: reached Exit with "${greeting}" on the screen${prompt === null ? "" : typeof prompt === "number" ? ", then the Monitor" : `, then ${prompt}`}.`);
    }

    await request("disconnect");
    console.log(`New project DAP passed: retrocore new's 6502 project builds every target, and ${targets.join(", ")} each boot, run to Exit and show the greeting, and all but apple3-sos, which waits, go back to their environments.`);
} finally {
    clearTimeout(timeout);
    close();
}
if (failure()) throw failure();
