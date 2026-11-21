// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import assert from "node:assert/strict";
import { writeFileSync, unlinkSync } from "node:fs";
import { join, resolve } from "node:path";
import { startDap } from "./DapClient.mjs";

const root = resolve(import.meta.dirname, "..");
const program = join(root, "artifacts", `cycle-events-${process.pid}.bin`);
writeFileSync(program, Buffer.from([0x4C, 0x00, 0x60]), { flag: "wx" });
const dap = startDap(root);
const timeout = setTimeout(() => dap.fail(new Error("Cycle event test timed out.")), 30000);
const cycles = () => dap.events.filter(message => message.event === "retro/cycles").map(message => message.body);
const clear = () => {
    for (let index = dap.events.length - 1; index >= 0; index--) {
        if (dap.events[index].event === "retro/cycles") dap.events.splice(index, 1);
    }
};

try {
    await dap.request("initialize", { adapterID: "retrocore" });
    await dap.request("launch", { machine: "apple2", model: "iie-enhanced", program, loadAddress: 0x6000, stopOnEntry: false });
    await dap.request("retro/cycles", { changesOnly: true });
    await dap.request("configurationDone");
    await new Promise(resolve => setTimeout(resolve, 500));
    assert.equal(cycles().length, 1, "an unchanged snapshot is sent once while running");
    assert.deepEqual(cycles()[0].lines, []);
    assert.deepEqual(cycles()[0].calls, []);

    clear();
    const stopped = dap.event("stopped");
    await dap.request("pause", { threadId: 1 });
    await stopped;
    const snapshot = await dap.request("retro/cycles");
    assert.ok(snapshot.cycles > 0);
    assert.deepEqual(cycles().at(-1), snapshot, "a stop always sends the complete current snapshot");

    await dap.request("retro/cycles", { changesOnly: false });
    clear();
    await dap.request("continue", { threadId: 1 });
    await new Promise(resolve => setTimeout(resolve, 300));
    assert.ok(cycles().length >= 2, "ordinary clients still receive periodic snapshots");
    await dap.request("disconnect");
    console.log("Cycle event integration passed.");
} finally {
    clearTimeout(timeout);
    dap.close();
    unlinkSync(program);
}

const source = join(root, "artifacts", `cycle-events-${process.pid}.asm`);
const sourceLines = [
    ".cpu Z80", ".org $7000", "start:", "    CALL sub", "    JR start",
    ";; Executes one of two equal-time branches, with an optional longer return.", "sub:",
    "    LD A,[choice]", "    OR A", "    JP Z,zero", "    INC BC", "    JP finish",
    "zero:", "    INC DE", "    JP finish", "finish:", "    LD A,[choice]", "    CP 2",
    "    RET NZ", "    NOP", "    RET", "choice:", "    .byte 0", ""
];
writeFileSync(source, sourceLines.join("\n"), { flag: "wx" });
const callLine = sourceLines.indexOf("    CALL sub") + 1;
const alternateLine = sourceLines.indexOf("    INC BC") + 1;
const mapped = startDap(root);
const mappedTimeout = setTimeout(() => mapped.fail(new Error("Mapped cycle event test timed out.")), 30000);
try {
    await mapped.request("initialize", { adapterID: "retrocore" });
    await mapped.request("launch", {
        machine: "trs80-model1", sdkRoms: join(root, "src", "Retrocore.Machines.Trs80", "Roms"),
        source, stopOnEntry: true, speed: "max"
    });
    const entry = mapped.event("stopped");
    await mapped.request("configurationDone");
    assert.equal((await entry).reason, "entry");
    await mapped.request("retro/cycles", { changesOnly: true });
    await mapped.request("continue", { threadId: 1 });
    await new Promise(resolve => setTimeout(resolve, 500));
    mapped.events.length = 0;
    await new Promise(resolve => setTimeout(resolve, 700));
    const frames = mapped.events.filter(event => event.event === "retro/frame").length;
    const updates = mapped.events.filter(event => event.event === "retro/cycles");
    const current = await mapped.request("retro/cycles");
    const call = current.calls.find(row => row.path === source && row.line === callLine);
    assert.ok(current.lines.length >= 5 && call?.cycles > 0, "the loop records its source lines and call");
    assert.ok(frames >= 8, "the running loop produces frames");
    assert.ok(updates.length < frames / 2, `unchanged cycle counts suppress most updates (${updates.length} updates, ${frames} frames)`);

    const pause = async () => {
        const stopped = mapped.event("stopped");
        await mapped.request("pause", { threadId: 1 });
        await stopped;
    };
    const choose = value => mapped.request("writeMemory", {
        memoryReference: "choice", data: Buffer.from([value]).toString("base64")
    });
    await pause();
    await choose(1);
    mapped.events.length = 0;
    await mapped.request("continue", { threadId: 1 });
    await new Promise(resolve => setTimeout(resolve, 400));
    const changed = await mapped.request("retro/cycles");
    assert.equal(changed.calls.find(row => row.path === source && row.line === callLine)?.cycles, call.cycles);
    assert.ok(mapped.events.some(event => event.event === "retro/cycles"
        && event.body.lines.some(row => row.path === source && row.line === alternateLine && row.cycles === 6)
        && event.body.calls.some(row => row.path === source && row.line === callLine && row.cycles === call.cycles)),
    "a new line count sends an update even when the call count is unchanged");

    await pause();
    await choose(2);
    mapped.events.length = 0;
    await mapped.request("continue", { threadId: 1 });
    await new Promise(resolve => setTimeout(resolve, 400));
    assert.ok(mapped.events.some(event => event.event === "retro/cycles"
        && event.body.calls.some(row => row.path === source && row.line === callLine && row.cycles > call.cycles)),
    "a changed call count sends an update");
    await mapped.request("disconnect");
    console.log(`Mapped cycle event integration passed (${updates.length} updates / ${frames} frames).`);
} finally {
    clearTimeout(mappedTimeout);
    mapped.close();
    unlinkSync(source);
}
