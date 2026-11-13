// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Model III, 4, 4P and II DAP integration: launches each from stand-in ROM dumps under MAME's names, which show READY
// on the screen, and checks the display, the thread, the hardware rows, the reset stop and the error a launch without
// dumps gives. The stand-ins are a few hand-assembled instructions, so the script needs no real ROMs.

import { resolve, join } from "node:path";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import assert from "node:assert/strict";
import { startDap } from "./DapClient.mjs";

const root = resolve(import.meta.dirname, "..");
const { request, event, events, fail, close, failure } = startDap(root);
const timeout = setTimeout(() => fail(new Error("Model III and II DAP integration timed out.")), Number(process.env.RETROCORE_DAP_TIMEOUT ?? 120000));

// Copies READY to video RAM and waits: the Model III's at $3C00, and the Model II's at $F800 once port $FF maps it.
const ready = [...Buffer.from("READY")];
const model3 = [0xF3, 0x31, 0x00, 0x80, 0x21, 0x11, 0x00, 0x11, 0x00, 0x3C, 0x01, 0x05, 0x00, 0xED, 0xB0, 0x18, 0xFE, ...ready];
const model2 = [
    0xF3, 0x31, 0x00, 0x80, 0x3E, 0x80, 0xD3, 0xFF, 0x21, 0x15, 0x00, 0x11, 0x00, 0xF8, 0x01, 0x05, 0x00, 0xED, 0xB0,
    0x18, 0xFE, ...ready
];

function image(size, code) {
    const bytes = Buffer.alloc(size);
    Buffer.from(code).copy(bytes);
    return bytes;
}

const roms = mkdtempSync(join(tmpdir(), "retrocore-trs80-"));
writeFileSync(join(roms, "8041364.u104"), image(0x2000, model3));
writeFileSync(join(roms, "8040332.u105"), image(0x1000, []));
writeFileSync(join(roms, "8040316c.u106"), image(0x800, []));
writeFileSync(join(roms, "8044316a.u36"), image(0x800, []));
writeFileSync(join(roms, "8075332.u69"), image(0x1000, model3));
writeFileSync(join(roms, "8049007.u103"), image(0x800, []));
writeFileSync(join(roms, "u54.u11"), image(0x800, model2));
writeFileSync(join(roms, "8043316.u9"), image(0x800, []));

function drop(name) {
    for (let index = events.length - 1; index >= 0; index--) {
        if (events[index].event === name) events.splice(index, 1);
    }
}

async function launch(args, filters) {
    events.length = 0;
    await request("setExceptionBreakpoints", { filters: filters ?? [] });
    await request("launch", { romDirectory: roms, stopOnEntry: false, speed: "max", ...args });
    await request("configurationDone");
}

async function screen(text) {
    drop("retro/frame");
    for (;;) {
        const frame = await event("retro/frame");
        if (frame.rows.join("\n").includes(text)) return frame;
        if (!frame.running) throw new Error(`Stopped before ${text}.`);
    }
}

try {
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });

    await assert.rejects(
        request("launch", { machine: "trs80-model3", romDirectory: join(roms, "none") }),
        /8040316c\.u106 \(or 8040316b\.u106\) is missing/);

    const cases = [
        { args: { machine: "trs80-model3" }, thread: "Model III Z80", model: "Model III", columns: 64 },
        { args: { machine: "trs80-model4" }, thread: "Model 4 Z80", model: "Model 4", columns: 64 },
        { args: { machine: "trs80-model3", model: "4p" }, thread: "Model 4P Z80", model: "Model 4P", columns: 64 },
        { args: { machine: "trs80-model2" }, thread: "Model II Z80", model: "Model II", columns: 80 },
        { args: { machine: "trs80-model2", model: "16" }, thread: "Model 16 Z80", model: "Model 16", columns: 80 }
    ];

    for (const test of cases) {
        if (process.env.RETROCORE_DAP_VERBOSE === "1") console.log(`launching ${JSON.stringify(test.args)}`);
        await launch(test.args);
        const frame = await screen("READY");
        assert.equal(frame.model, test.model);
        assert.equal(frame.columns, test.columns);
        assert.equal((await request("threads")).threads[0].name, test.thread);
        const hardware = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
        assert.equal(hardware.model.name, `TRS-80 ${test.model}`);
    }

    if (process.env.RETROCORE_DAP_VERBOSE === "1") console.log("reset");
    // Machine reset stops at power-on, at $0000, and the Model II's reset switch restarts the boot ROM there too.
    await launch({ machine: "trs80-model2" }, ["machineReset"]);
    let stopped = await event("stopped");
    assert.equal(stopped.description, "The machine reset as it powered on.");
    await request("continue", { threadId: 1 });
    await screen("READY");
    drop("stopped");
    await request("retro/reset");
    stopped = await event("stopped");
    assert.equal(stopped.reason, "breakpoint");
    assert.equal(stopped.description, "The machine reset.");
    const top = (await request("stackTrace", { threadId: 1 })).stackFrames[0];
    assert.equal(top.instructionPointerReference, "0x0000");

    await request("disconnect");
    console.log("Model III, 4, 4P, II and 16 DAP passed: missing dumps, each machine's boot from stand-in dumps, threads, hardware and the Model II's reset stop.");
} finally {
    clearTimeout(timeout);
    close();
    rmSync(roms, { recursive: true, force: true });
}
if (failure()) throw failure();
