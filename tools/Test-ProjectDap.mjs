// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// A Retrocore project through the command line and the debug adapter. sample/project's retrocore.json builds with
// `retrocore build` for its bare II Plus target, and a launch that gives its project and target, and no machine or
// program, builds the same bytes, starts the target's machine on the ROMs built from the SDK's sources, stops at the program's entry in its
// source, stops at a breakpoint there, and prints the program's line on the screen. A launch naming a target the
// project lacks fails, listing the targets it has.

import { startDap } from "./DapClient.mjs";
import { resolve, join } from "node:path";
import { readFileSync, rmSync } from "node:fs";
import { spawnSync } from "node:child_process";
import assert from "node:assert/strict";

const root = resolve(import.meta.dirname, "..");
const project = join(root, "sample", "project");
const source = join(project, "src", "hello.s");
const binary = join(project, "artifacts", "apple2-iiplus", "hello.bin");
const host = join(root, "artifacts", "AnyCPU", "Release", "Retrocore.Debug", "net11.0", "Retrocore.Debug.dll");
const build = (...args) => process.env.RETROCORE_DAP_HOST
    ? spawnSync(process.env.RETROCORE_DAP_HOST, ["build", ...args], { cwd: project, encoding: "utf8" })
    : spawnSync("dotnet", [host, "build", ...args], { cwd: project, encoding: "utf8" });

// retrocore build, from the project's folder.
rmSync(join(project, "artifacts"), { recursive: true, force: true });
rmSync(join(project, "obj"), { recursive: true, force: true });
const built = build("--target", "apple2-iiplus");
assert.equal(built.status, 0, `retrocore build failed:\n${built.stdout}${built.stderr}`);
assert.match(built.stdout, /^hello\/apple2-iiplus: .*hello\.bin \(\$6000-\$6026, 39 bytes, entry \$6000\)/m);
const cli = readFileSync(binary);
assert.match(readFileSync(join(project, "artifacts", "apple2-iiplus", "hello.map"), "utf8"), /^entry \$6000$/m);

const { request, event, fail, close, failure: failed } = startDap(root);
const timeout = setTimeout(() => fail(new Error("Project DAP integration timed out.")), 60000);
const screen = async () => (await request("apple2/text")).rows.join("\n");
const waitFor = async (text, what) => {
    for (const end = performance.now() + 10000; performance.now() < end;) {
        if ((await screen()).includes(text)) return;
        await new Promise(done => setTimeout(done, 100));
    }
    assert.fail(`${what}: "${text}" never appeared:\n${await screen()}`);
};

try {
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });
    await assert.rejects(
        request("launch", { project, target: "pet" }),
        /There is no target 'pet'; the targets are hello\/apple2-iiplus, hello\/apple2-iie\./);

    // The launch builds the target again, to the same bytes, and gives the machine the target's: a II Plus.
    const launched = await request("launch", { project, target: "apple2-iiplus", stopOnEntry: true, speed: "max", sound: "off" });
    assert.equal(launched.project.machine, "apple2");
    assert.equal(launched.project.model, "iiplus");
    assert.deepEqual(readFileSync(binary), cli, "the launch builds the bytes retrocore build does");
    const breakpoints = await request("setBreakpoints", { source: { path: source }, breakpoints: [{ line: 18 }] });
    assert.equal(breakpoints.breakpoints[0].verified, true, "a breakpoint at DONE binds in the project's source");
    await request("configurationDone");

    assert.equal((await event("stopped")).reason, "entry");
    let frame = (await request("stackTrace", { threadId: 1 })).stackFrames[0];
    assert.equal(frame.source.path, source);
    assert.equal(frame.line, 10, "the entry is START's first instruction");

    await request("continue", { threadId: 1 });
    const stop = await event("stopped");
    assert.equal(stop.reason, "breakpoint", JSON.stringify(stop));
    frame = (await request("stackTrace", { threadId: 1 })).stackFrames[0];
    assert.equal(frame.line, 18);
    await waitFor("HELLO FROM A PROJECT", "the program's line");
    await request("disconnect");

    console.log("Project DAP passed: retrocore build of sample/project's II Plus target, and a project launch that builds the same bytes, stops at the entry and a breakpoint in its source, and prints its line; an unknown target lists the project's targets.");
} finally {
    clearTimeout(timeout);
    close();
}
if (failed()) throw failed();
