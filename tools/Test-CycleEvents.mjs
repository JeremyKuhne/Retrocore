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
