// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import { startDap } from "./DapClient.mjs";
import { resolve, join, dirname } from "node:path";
import { writeFileSync, unlinkSync, mkdirSync } from "node:fs";
import assert from "node:assert/strict";

const root = resolve(import.meta.dirname, "..");
// With RETROCORE_IIE_ROMS the machine runs the dumps; without it, ROMs assembled from the SDK's sources.
const roms = process.env.RETROCORE_IIE_ROMS || undefined;
const { request, event, events, fail, close, failure: failed } = startDap(root);
const timeout = setTimeout(() => fail(new Error("DAP integration timed out.")), 60000);
try {
    const capabilities = await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });
    assert.equal(capabilities.supportsConditionalBreakpoints, true);
    // A model the family does not have is refused.
    await assert.rejects(request("launch", { machine: "apple2", model: "iic", stopOnEntry: true }), /model must be/);
    await request("launch", {
        machine: "apple2", romDirectory: roms, model: "iie-enhanced", stopOnEntry: true,
        program: join(root, "artifacts", "iie-sample", "main.bin"),
        debugFile: join(root, "artifacts", "iie-sample", "main.dbg"),
        loadAddress: 0x6000
    });
    const breakpoints = await request("setBreakpoints", {
        source: { path: join(root, "sample", "iie", "main.s") },
        breakpoints: [{ line: 14, condition: "X == 1" }]
    });
    assert.equal(breakpoints.breakpoints[0].verified, true);
    await request("configurationDone");
    assert.equal((await event("stopped")).reason, "entry");
    await request("continue", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "breakpoint");
    let stack = await request("stackTrace", { threadId: 1 });
    assert.equal(stack.stackFrames[0].line, 14);
    assert.equal((await request("evaluate", { expression: "X" })).result, "$1 (1)");
    await request("stepIn", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "step");
    stack = await request("stackTrace", { threadId: 1 });
    assert.equal(stack.totalFrames, 2);
    assert.equal(stack.stackFrames[0].line, 22);
    assert.equal(stack.stackFrames[0].name, "increment");
    assert.equal(stack.stackFrames[1].line, 14);
    // Each line shows its latest run, and the JSR line its latest call: JSR 6 + INX 2 + RTS 6.
    assert.equal((await request("retro/cycles")).lines.find(line => line.line === 14).cycles, 6);
    assert.equal((await request("retro/cycles")).calls.find(call => call.line === 14).cycles, 14);
    await request("stepIn", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "step");
    assert.equal((await request("evaluate", { expression: "X", frameId: 1 })).result, "$2 (2)");
    assert.equal((await request("evaluate", { expression: "X", frameId: 2 })).result, "$1 (1)");
    assert.equal((await request("retro/cycles")).lines.find(line => line.line === 22).cycles, 2);
    const callerScopes = await request("scopes", { frameId: 2 });
    const callerVariables = await request("variables", { variablesReference: callerScopes.scopes[0].variablesReference });
    assert.equal(callerVariables.variables.find(variable => variable.name === "X").value, "$1");
    await request("stepOut", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "step");
    stack = await request("stackTrace", { threadId: 1 });
    assert.equal(stack.totalFrames, 1);
    assert.equal(stack.stackFrames[0].line, 16);
    assert.equal((await request("evaluate", { expression: "X" })).result, "$2 (2)");
    assert.equal((await request("evaluate", { expression: "[counter]" })).result, "$1 (1)");
    await request("setBreakpoints", {
        source: { path: join(root, "sample", "iie", "main.s") },
        breakpoints: [{ line: 14, condition: "X == 2" }]
    });
    await request("continue", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "breakpoint");
    await request("next", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "step");
    assert.equal((await request("stackTrace", { threadId: 1 })).totalFrames, 1);
    await request("retro/key", { code: 65 });
    await request("evaluate", { expression: "[$C010]" });
    const memory = await request("readMemory", { memoryReference: "0xC000", count: 1 });
    assert.equal(Buffer.from(memory.data, "base64")[0], 0xC1);
    const frame = await request("apple2/text");
    assert.equal(frame.rows.length, 24);
    assert.equal(frame.columns, 40);
    assert.equal(frame.width, 280);
    assert.equal(Buffer.from(frame.pixels, "base64").length, 280 * 192);
    assert.equal(frame.video.pixelFormat, "rgba");
    assert.equal(Buffer.from(frame.video.pixels, "base64").length, 560 * 192 * 4);
    assert.equal((await request("apple2/beam")).cycles, frame.cycles);
    const video = await request("retro/video");
    assert.equal(video.width, 560);
    assert.equal(video.height, 192);
    assert.equal(Buffer.from(video.pixels, "base64").length, 560 * 192 * 4);
    const emptyDisk = await request("apple2/disk");
    assert.equal(emptyDisk.installed, false);
    assert.equal(emptyDisk.drives.length, 2);
    // Installed hardware: the built-in parts, the 80-column card every IIe launch has, then each slot, empty ones
    // saying what fills them.
    const hardware = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
    assert.deepEqual(Object.keys(hardware),
        ["model", "memory", "builtIn", "gamePort", "auxiliary", "slot1", "slot2", "slot3", "slot4", "slot5", "slot6", "slot7"]);
    assert.equal(hardware.model.value, "Enhanced, 65C02");
    // SDL's native library loads in the host and reads controllers: none connected, or their names.
    assert.doesNotMatch(hardware.gamePort.value, /^(No controllers:|Controllers off)/, hardware.gamePort.value);
    assert.equal(hardware.auxiliary.value, "Extended 80-column card, 64 KB");
    assert.equal(hardware.slot4.value, "empty", "the Mockingboard is out unless a launch or Add Card puts it in");
    assert.equal(hardware.slot6.value, "empty");
    assert.match(hardware.slot6.description, /diskController/);
    assert.deepEqual(hardware.slot6.devices, []);

    // A Disk II card goes into a free slot while the session runs: its boot ROM answers at once, its drives take
    // disks, and removing it empties the slot again. The Mockingboard goes in slot 4, which then takes no other card.
    assert.deepEqual(hardware.slot5.actions, ["addCard"]);
    assert.deepEqual(hardware.slot4.actions, ["addCard"]);
    const slotRow = (body, id) => body.hardware.find(row => row.id === id);
    // Without the card there is only the speaker to hear; with it, the frame says so and its sound can be chosen.
    assert.equal((await request("apple2/text")).mockingboard, false);
    await assert.rejects(request("apple2/sound", { mode: "mockingboard" }), /not in slot 4/);
    let changed = await request("retro/hardware", { id: "slot4", action: "addMockingboard" });
    assert.equal((await request("apple2/text")).mockingboard, true);
    assert.equal((await request("apple2/sound", { mode: "mockingboard" })).mode, "mockingboard");
    assert.equal(slotRow(changed, "slot4").value, "Mockingboard");
    assert.deepEqual(slotRow(changed, "slot4").actions, ["removeCard"]);
    await assert.rejects(request("retro/hardware", { id: "slot4", action: "addDiskII" }), /does not support/);
    changed = await request("retro/hardware", { id: "slot5", action: "addDiskII", sectors: 16 });
    assert.equal(slotRow(changed, "slot5").value, "Disk II controller, 16-sector");
    assert.deepEqual(slotRow(changed, "slot5").devices, ["slot5disk1", "slot5disk2"]);
    assert.deepEqual(slotRow(changed, "slot5").actions, ["removeCard"]);
    assert.equal(Buffer.from((await request("readMemory", { memoryReference: "0xC5FF", count: 1 })).data, "base64")[0], 0);
    const blank = join(root, "artifacts", `slot5-${process.pid}.dsk`);
    writeFileSync(blank, Buffer.alloc(35 * 16 * 256));
    try {
        changed = await request("retro/device", { id: "slot5disk1", action: "insert", path: blank });
        assert.equal(changed.devices.find(device => device.id === "slot5disk1").media.format, "DSK");

        // The body carries the configuration the editor saves; a launch given it back has the same cards and disks.
        const saved = changed.configuration;
        assert.equal(saved.cards["4"], "mockingboard");
        assert.equal(saved.cards["5"], "diskII16");
        assert.equal(saved.media.slot5disk1.path, blank);
        assert.equal(saved.media.slot5disk2, null);
        await request("launch", {
            machine: "apple2", romDirectory: roms, model: "iie-enhanced", stopOnEntry: true,
            program: join(root, "artifacts", "iie-sample", "main.bin"), loadAddress: 0x6000, machineState: saved
        });
        assert.equal((await event("stopped")).reason, "entry", "the session's configuration is done, so it starts at once");
        const restored = await request("retro/devices");
        assert.equal(slotRow(restored, "slot4").value, "Mockingboard");
        assert.equal(slotRow(restored, "slot5").value, "Disk II controller, 16-sector");
        assert.equal(restored.devices.find(device => device.id === "slot5disk1").media.label, blank);
        assert.deepEqual(restored.configuration, saved);
    } finally {
        unlinkSync(blank);
    }
    changed = await request("retro/hardware", { id: "slot5", action: "removeCard" });
    assert.equal(slotRow(changed, "slot5").value, "empty");
    assert.ok(!changed.devices.some(device => device.id.startsWith("slot5")), "its drives are gone");
    await request("apple2/sound", { mode: "mockingboard" });
    changed = await request("retro/hardware", { id: "slot4", action: "removeCard" });
    assert.equal(slotRow(changed, "slot4").value, "empty");
    assert.equal((await request("apple2/text")).sound, "speaker", "taking the card out leaves the speaker");

    // A new monitor while stopped sends the panel a frame drawn on it.
    events.splice(0, events.length, ...events.filter(message => message.event !== "retro/frame"));
    await request("retro/screen", { screen: "green" });
    assert.equal((await event("retro/frame")).screen, "green");
    await request("retro/screen", { screen: "color" });
    assert.equal((await event("retro/frame")).screen, "color");
    await request("retro/cycles", { clear: true });
    assert.equal((await request("retro/cycles")).lines.length, 0);
    // A saved machine's mouse slot wins over the launch's, whichever slot the saved cards name first.
    for (const cards of [{ 2: "mouse", 4: "empty" }, { 4: "empty", 2: "mouse" }]) {
        await request("launch", {
            machine: "apple2", romDirectory: roms, model: "iie-enhanced", stopOnEntry: true, mouse: 4,
            machineState: { cards }
        });
        const devices = await request("retro/devices");
        assert.equal(slotRow(devices, "slot2").value, "Mouse card", JSON.stringify(cards));
        assert.equal(slotRow(devices, "slot4").value, "empty", JSON.stringify(cards));
    }

    // The 3.5 controller: the launch puts it in slot 5 with an 800K disk in drive 1, and a saved machine moves it,
    // disk and all.
    const disk35 = join(root, "artifacts", "iie-sample", "blank800k.po");
    mkdirSync(dirname(disk35), { recursive: true });
    writeFileSync(disk35, Buffer.alloc(800 * 1024));
    try {
        for (const machineState of [undefined, { cards: { 2: "disk35", 5: "empty" } }]) {
            await request("launch", {
                machine: "apple2", romDirectory: roms, model: "iie-enhanced", stopOnEntry: true, disk35: 5,
                disk35Images: [disk35], machineState
            });
            const devices = await request("retro/devices");
            const slot = machineState === undefined ? "slot5" : "slot2";
            assert.equal(slotRow(devices, slot).value, "3.5 disk controller");
            assert.deepEqual(slotRow(devices, slot).devices, ["disk35d1", "disk35d2"]);
            const drive = devices.devices.find(device => device.id === "disk35d1");
            assert.equal(drive.media.label, disk35);
            assert.deepEqual(drive.operations, ["insert", "eject", "writeProtect"]);
            assert.equal(devices.configuration.cards[slot.slice(4)], "disk35");
        }
    } finally {
        unlinkSync(disk35);
    }
    events.splice(0, events.length); // these launches' own events, such as their stops on entry

    // The same sample assembled in place by retrocore's ca65 front end debugs by line without ca65, ld65 or a .dbg file.
    await request("launch", {
        machine: "apple2", romDirectory: roms, model: "iie-enhanced", stopOnEntry: true,
        source: join(root, "sample", "iie", "main.s"), dialect: "ca65",
        linkerConfiguration: join(root, "sample", "iie", "link.cfg")
    });
    const sourceBreakpoints = await request("setBreakpoints", {
        source: { path: join(root, "sample", "iie", "main.s") },
        breakpoints: [{ line: 14, condition: "X == 1" }]
    });
    assert.equal(sourceBreakpoints.breakpoints[0].verified, true);
    await request("configurationDone");
    assert.equal((await event("stopped")).reason, "entry");
    await request("continue", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "breakpoint");
    const sourceStack = await request("stackTrace", { threadId: 1 });
    assert.equal(sourceStack.stackFrames[0].line, 14);
    assert.equal((await request("evaluate", { expression: "counter" })).result, "$6016 (24598)");
    await request("setBreakpoints", { source: { path: join(root, "sample", "iie", "main.s") }, breakpoints: [] });

    // Macros debug as inline frames: a stop on a call line steps in level by level without running, step over
    // runs a whole invocation, step out leaves one, and a body-line breakpoint stops in every expansion.
    const macros = join(root, "artifacts", "iie-sample", "macros.s");
    writeFileSync(macros, [
        ".macro inner v", "  lda #v", "  sta $10", ".endmacro",
        ".macro outer v", "  inner v", "  inx", ".endmacro",
        "start: outer 5", "  inner 7", "  nop", "done: jmp done", ""
    ].join("\n"));
    try {
        const top = async () => {
            const stack = await request("stackTrace", { threadId: 1 });
            return { line: stack.stackFrames[0].line, name: stack.stackFrames[0].name, frames: stack.totalFrames,
                pc: stack.stackFrames[0].instructionPointerReference };
        };
        const step = async command => {
            await request(command, { threadId: 1 });
            assert.equal((await event("stopped")).reason, "step");
            return top();
        };
        await request("launch", { machine: "apple2", romDirectory: roms, model: "iie-enhanced", stopOnEntry: true, source: macros });
        await request("configurationDone");
        assert.equal((await event("stopped")).reason, "entry");
        assert.deepEqual(await top(), { line: 9, name: "start", frames: 1, pc: "0x6000" });
        assert.deepEqual(await step("stepIn"), { line: 6, name: "start: outer 5", frames: 2, pc: "0x6000" });
        assert.deepEqual(await step("stepIn"), { line: 2, name: "inner v", frames: 3, pc: "0x6000" });
        assert.equal((await step("next")).line, 3);
        assert.deepEqual(await step("stepOut"), { line: 7, name: "start: outer 5", frames: 2, pc: "0x6004" });
        assert.deepEqual(await step("next"), { line: 10, name: "start", frames: 1, pc: "0x6005" });
        assert.deepEqual(await step("next"), { line: 11, name: "start", frames: 1, pc: "0x6009" });

        await request("launch", { machine: "apple2", romDirectory: roms, model: "iie-enhanced", stopOnEntry: true, source: macros });
        const body = await request("setBreakpoints", { source: { path: macros }, breakpoints: [{ line: 3 }] });
        assert.equal(body.breakpoints[0].verified, true);
        await request("configurationDone");
        assert.equal((await event("stopped")).reason, "entry");
        for (const expected of [{ pc: "0x6002", frames: 3 }, { pc: "0x6007", frames: 2 }]) {
            await request("continue", { threadId: 1 });
            assert.equal((await event("stopped")).reason, "breakpoint");
            const hit = await top();
            assert.equal(hit.line, 3);
            assert.equal(hit.pc, expected.pc);
            assert.equal(hit.frames, expected.frames);
        }
        await request("setBreakpoints", { source: { path: macros }, breakpoints: [] });
    } finally {
        unlinkSync(macros);
    }

    // A ;; Keeps: contract is checked when the call returns, and the frame's documentation is a scope.
    const contract = join(root, "artifacts", "iie-sample", "contract.s");
    writeFileSync(contract, [
        "start: ldx #1", "  jsr keeper", "  nop", "done: jmp done",
        ";; Claims to keep X but does not.", ";; In:    A = ignored", ";; Keeps: X", "keeper: inx", "  rts", ""
    ].join("\n"));
    try {
        await request("launch", { machine: "apple2", romDirectory: roms, model: "iie-enhanced", stopOnEntry: true, source: contract, checkContracts: "stop" });
        await request("configurationDone");
        assert.equal((await event("stopped")).reason, "entry");
        await request("stepIn", { threadId: 1 });
        await event("stopped");
        await request("stepIn", { threadId: 1 });
        await event("stopped");
        const inside = await request("scopes", { frameId: 1 });
        const documentation = inside.scopes.find(scope => scope.name.startsWith("keeper: Claims to keep X"));
        assert.ok(documentation, JSON.stringify(inside.scopes));
        const entries = await request("variables", { variablesReference: documentation.variablesReference });
        assert.ok(entries.variables.some(variable => variable.name === "In A" && variable.value.endsWith("— ignored")));
        await request("continue", { threadId: 1 });
        const broken = await event("stopped");
        assert.equal(broken.reason, "exception");
        assert.match(broken.description, /keeper returned with X changed: \$01 at entry, \$02 at return/);
        assert.match((await event("output")).output, /keeper returned with X changed/);
        assert.equal((await request("stackTrace", { threadId: 1 })).stackFrames[0].line, 3);
    } finally {
        unlinkSync(contract);
    }

    // Continuing from a BRK stop runs that BRK: the ROM's handler jumps through BRKV ($03F0) to the next one.
    const brks = join(root, "artifacts", "iie-sample", "brk-continue.bin");
    writeFileSync(brks, Buffer.from([0xA9,0x10,0x8D,0xF0,0x03,0xA9,0x60,0x8D,0xF1,0x03,0x00,0xEA,0xEA,0xEA,0xEA,0xEA,0x00,0xEA]));
    try {
        await request("launch", { machine: "apple2", romDirectory: roms, model: "iie-enhanced", stopOnEntry: true, program: brks, loadAddress: 0x6000 });
        await request("setExceptionBreakpoints", { filters: ["brk"] });
        await request("configurationDone");
        assert.equal((await event("stopped")).reason, "entry");
        for (const address of ["$600A", "$6010"]) {
            await request("continue", { threadId: 1 });
            const stopped = await event("stopped");
            assert.equal(stopped.reason, "exception");
            assert.equal(stopped.description, `BRK at ${address}.`);
        }

        // A breakpoint's stop at a BRK has not reported it: continuing stops there for the BRK, then runs it.
        events.length = 0;
        await request("launch", { machine: "apple2", romDirectory: roms, model: "iie-enhanced", stopOnEntry: true, program: brks, loadAddress: 0x6000 });
        await request("setExceptionBreakpoints", { filters: ["brk"] });
        await request("configurationDone");
        assert.equal((await event("stopped")).reason, "entry");
        await request("setInstructionBreakpoints", { breakpoints: [{ instructionReference: "0x600A" }] });
        await request("continue", { threadId: 1 });
        const hit = await event("stopped");
        assert.equal(hit.reason, "instruction breakpoint", hit.description);
        await request("setInstructionBreakpoints", { breakpoints: [] });
        for (const address of ["$600A", "$6010"]) {
            await request("continue", { threadId: 1 });
            const stopped = await event("stopped");
            assert.equal(stopped.reason, "exception");
            assert.equal(stopped.description, `BRK at ${address}.`);
        }
    } finally {
        unlinkSync(brks);
    }

    const nested = join(root, "artifacts", "iie-sample", "nested-stack.bin");
    writeFileSync(nested, Buffer.from([0x20,0x04,0x60,0xEA,0x20,0x08,0x60,0x60,0xE8,0x60]));
    try {
        await request("launch", { machine: "apple2", romDirectory: roms, model: "iie-enhanced", stopOnEntry: true, program: nested, loadAddress: 0x6000 });
        await request("configurationDone");
        assert.equal((await event("stopped")).reason, "entry");
        assert.equal((await request("stackTrace")).totalFrames, 1);
        for (let i = 0; i < 2; i++) {
            await request("stepIn", { threadId: 1 });
            assert.equal((await event("stopped")).reason, "step");
        }
        const nestedStack = await request("stackTrace", { threadId: 1 });
        assert.equal(nestedStack.totalFrames, 3);
        assert.deepEqual(nestedStack.stackFrames.map(frame => frame.instructionPointerReference), ["0x6008","0x6004","0x6000"]);
        const page = await request("stackTrace", { threadId: 1, startFrame: 1, levels: 1 });
        assert.equal(page.totalFrames, 3);
        assert.equal(page.stackFrames.length, 1);
        assert.equal(page.stackFrames[0].id, 2);
        for (const expectedCount of [2, 1]) {
            await request("stepOut", { threadId: 1 });
            assert.equal((await event("stopped")).reason, "step");
            assert.equal((await request("stackTrace")).totalFrames, expectedCount);
        }
    } finally {
        unlinkSync(nested);
    }
    const beamProgram = join(root, "artifacts", "iie-sample", "beam-loop.bin");
    writeFileSync(beamProgram, Buffer.from([0xEA,0x4C,0x00,0x60]));
    try {
        // Both IIe models, the first by the names launches used before the Apple II family shared one.
        for (const [machine, model] of [["apple2e", "original"], ["apple2", "iie-enhanced"]]) {
            await request("launch", { machine, romDirectory: roms, model, stopOnEntry: true, program: beamProgram, loadAddress: 0x6000 });
            await request("configurationDone");
            assert.equal((await event("stopped")).reason, "entry");
            // Scanline breakpoints are function breakpoints named "scanline S:C", listed in the Breakpoints view.
            const frame = 17030;
            const invalid = await request("setFunctionBreakpoints", { breakpoints: [{ name: "scanline 262" }, { name: "scanline 0:65" }] });
            assert.deepEqual(invalid.breakpoints.map(breakpoint => breakpoint.verified), [false, false]);
            for (const [scanline, column] of [[0,28],[191,64],[192,0],[261,64],[0,0],[0,25]]) {
                const before = await request("apple2/beam");
                const position = scanline * 65 + column;
                const expected = before.cycles + ((position - before.cycleInFrame + frame) % frame || frame);
                const set = await request("setFunctionBreakpoints", { breakpoints: [{ name: `scanline ${scanline}:${column}` }] });
                assert.equal(set.breakpoints[0].verified, true);
                await request("continue");
                const stopped = await event("stopped");
                assert.equal(stopped.reason, "function breakpoint");
                assert.deepEqual(stopped.hitBreakpointIds, [set.breakpoints[0].id]);
                assert.equal(stopped.description, `The video beam reached scanline ${scanline}, column ${column}.`);
                const beam = await request("apple2/beam");
                assert.equal(beam.scanline, scanline);
                assert.equal(beam.column, column);
                assert.equal(beam.cycleInFrame, position);
                assert.equal(beam.cycles, expected);
                assert.equal(beam.verticalBlank, scanline >= 192);
                assert.equal(beam.horizontalBlank, column < 25);
                if (scanline === 0 && column === 28) {
                    await request("stepIn");
                    assert.equal((await event("stopped")).reason, "step");
                    assert.equal((await request("apple2/beam")).cycles, beam.cycles + 1);
                }
            }
            await request("setFunctionBreakpoints", { breakpoints: [{ name: "scanline vbl" }] });
            await request("continue");
            assert.equal((await event("stopped")).reason, "function breakpoint");
            assert.equal((await request("apple2/beam")).scanline, 192);
            await request("setFunctionBreakpoints", { breakpoints: [] });

            // The standing filter, always listed for the IIe: ticked, it stops at each position its condition lists,
            // or at 192:0 without one; a condition that does not read leaves it unverified.
            const filter = events.filter(message => message.event === "capabilities").at(-1).body.capabilities
                .exceptionBreakpointFilters.find(entry => entry.filter === "scanline");
            assert.equal(filter.label, "Video beam reaches a scanline");
            assert.equal(filter.supportsCondition, true);
            const bad = await request("setExceptionBreakpoints", { filters: [], filterOptions: [{ filterId: "scanline", condition: "300:0" }] });
            assert.equal(bad.breakpoints[0].verified, false);
            const both = await request("setExceptionBreakpoints", { filters: ["brk"], filterOptions: [{ filterId: "scanline", condition: "10:30, 200:5" }] });
            assert.deepEqual(both.breakpoints.map(breakpoint => breakpoint.verified), [true, true]);
            const reached = [];
            for (let stop = 0; stop < 2; stop++) {
                await request("continue");
                const stopped = await event("stopped");
                assert.equal(stopped.reason, "breakpoint");
                const beam = await request("apple2/beam");
                assert.equal(stopped.description, `The video beam reached scanline ${beam.scanline}, column ${beam.column}.`);
                reached.push(`${beam.scanline}:${beam.column}`);
            }
            assert.deepEqual(reached.sort(), ["10:30", "200:5"]);
            await request("setExceptionBreakpoints", { filters: ["brk", "scanline"] });
            await request("continue");
            assert.equal((await event("stopped")).reason, "breakpoint");
            assert.equal((await request("apple2/beam")).cycleInFrame, 192 * 65);
            await request("setExceptionBreakpoints", { filters: ["brk"] });
            await request("stepIn");
            assert.equal((await event("stopped")).reason, "step");
        }
    } finally { unlinkSync(beamProgram); }
    const diskFiles = ["native-disk-test.woz", "native-p5-test.bin", "native-p6-test.bin", "native-io-test.bin"]
        .map(name => join(root, "artifacts", "iie-sample", name));
    const media = Buffer.alloc(2048);
    media.write("WOZ2", 0, "ascii");
    media.set([255,10,13,10], 4);
    media.write("INFO", 12, "ascii"); media.writeUInt32LE(60, 16);
    media[20] = 2; media[21] = 1; media[57] = 1; media[59] = 32;
    media.write("TMAP", 80, "ascii"); media.writeUInt32LE(160, 84);
    media.fill(255, 88, 248); media[88] = media[89] = 0;
    media.write("TRKS", 248, "ascii"); media.writeUInt32LE(1792, 252);
    media.writeUInt16LE(3, 256); media.writeUInt16LE(1, 258); media.writeUInt32LE(8, 260);
    media[1536] = 0xA5;
    writeFileSync(diskFiles[0], media);
    writeFileSync(diskFiles[1], Buffer.alloc(256, 0xEA));
    writeFileSync(diskFiles[2], Buffer.alloc(256, 8));
    writeFileSync(diskFiles[3], Buffer.from([0xAD,0xE9,0xC0,0xAD,0xE1,0xC0,0xAD,0xE3,0xC0,0x4C,0x09,0x60]));
    try {
        await request("launch", {
            machine: "apple2", romDirectory: roms, model: "iie-enhanced", stopOnEntry: true,
            program: diskFiles[3], loadAddress: 0x6000, diskImage: diskFiles[0],
            diskBootRom: diskFiles[1], diskSequencerRom: diskFiles[2]
        });
        await request("configurationDone");
        assert.equal((await event("stopped")).reason, "entry");
        assert.equal((await request("apple2/disk")).drives[0].mounted, true);
        const slot6 = (await request("retro/devices")).hardware.find(row => row.id === "slot6");
        assert.equal(slot6.value, "Disk II controller");
        assert.deepEqual(slot6.devices, ["disk1", "disk2"], "the drives sit on the card");
        for (let instruction = 0; instruction < 3; instruction++) {
            await request("stepIn");
            assert.equal((await event("stopped")).reason, "step");
        }
        const state = await request("apple2/disk");
        assert.equal(state.installed, true);
        assert.equal(state.drives[0].motor, true);
        assert.equal(state.drives[0].quarterTrack, 1);
        assert.equal(state.drives[0].track, 0.25);
        assert.equal(state.drives[0].writeProtected, true);
        assert.equal((await request("apple2/text")).disk.drives[0].quarterTrack, 1);
    } finally { for (const filename of diskFiles) unlinkSync(filename); }

    // Sound: with sound "speaker" the running machine's speaker reaches the panel as mono PCM, and the IIe beeps as
    // it boots. Turning it off stops the audio events.
    await request("launch", { machine: "apple2", romDirectory: roms, model: "iie-enhanced", stopOnEntry: true, sound: "speaker" });
    await request("configurationDone");
    assert.equal((await event("stopped")).reason, "entry");
    await request("continue", { threadId: 1 });
    await new Promise(done => setTimeout(done, 1500));
    const takeAudio = () => {
        const taken = events.filter(message => message.event === "retro/audio").map(message => message.body);
        for (let index = events.length - 1; index >= 0; index--) {
            if (events[index].event === "retro/audio") events.splice(index, 1);
        }
        return taken;
    };
    const chunks = takeAudio();
    assert.ok(chunks.length > 10, `audio events while running: ${chunks.length}`);
    assert.ok(chunks.every(chunk => chunk.rate === 48000 && chunk.channels === 1), "mono at the mixer's rate");
    const pcm = Buffer.concat(chunks.map(chunk => Buffer.from(chunk.samples, "base64")));
    let loudest = 0;
    for (let offset = 0; offset + 1 < pcm.length; offset += 2) loudest = Math.max(loudest, Math.abs(pcm.readInt16LE(offset)));
    assert.ok(loudest > 1000, `the boot beep reaches the samples: loudest ${loudest}`);
    assert.equal((await request("apple2/sound", { mode: "off" })).mode, "off");
    await new Promise(done => setTimeout(done, 100));
    takeAudio();
    await new Promise(done => setTimeout(done, 400));
    assert.equal(takeAudio().length, 0, "no audio once sound is off");
    await request("pause", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "pause");

    // Fast disk: at 1x, booting runs flat out while the Disk II motor turns. The boot sector marks $07, turns the
    // motor off and waits, and once the drive stops the IIe keeps to its clock again.
    const fastImage = join(root, "artifacts", `fastdisk-${process.pid}.dsk`);
    const sector = Buffer.alloc(143360);
    Buffer.from([0x01, 0xA9, 0xA5, 0x85, 0x07, 0xBD, 0x88, 0xC0, 0x4C, 0x08, 0x08]).copy(sector);
    writeFileSync(fastImage, sector);
    try {
        events.length = 0;
        await request("launch", { machine: "apple2", romDirectory: roms, model: "iie-enhanced", stopOnEntry: false,
            speed: 1, sound: "off", diskImage: fastImage });
        await request("configurationDone");
        // The burst is shorter than the half second the speed readout averages, so the speed is measured between
        // accelerated frames: the fastest pair, as the host is still compiling its hot paths at first.
        let fastest = 0;
        let previous;
        let last;
        for (const end = performance.now() + 8000; performance.now() < end;) {
            const frame = await event("retro/frame");
            const now = performance.now();
            assert.equal(frame.fastDisk, true, "fast disk is on by default");
            if (frame.speed.accelerated && previous?.accelerated) {
                fastest = Math.max(fastest, (frame.cycles - previous.cycles) / ((now - previous.time) / 1000) / 1_020_484);
            }
            previous = { accelerated: frame.speed.accelerated, cycles: frame.cycles, time: now };
            last = frame.speed;
            events.length = 0;
            if (fastest > 2 && !last.accelerated && last.actual > 0.8 && last.actual < 1.25) break;
        }
        assert.ok(fastest > 2, `booting ran flat out while the motor turned: at most ${fastest.toFixed(2)}x`);
        assert.equal(Buffer.from((await request("readMemory", { memoryReference: "0x07", count: 1 })).data, "base64")[0], 0xA5);
        assert.equal(last.accelerated, false, "the motor stopped");
        assert.ok(last.actual > 0.8 && last.actual < 1.25, `back at 1x: ${last.actual}x`);
        assert.deepEqual(await request("apple2/fastDisk", { enabled: false }), { enabled: false });
        events.length = 0;
        assert.equal((await event("retro/frame")).fastDisk, false);
        await request("pause", { threadId: 1 });
        await event("stopped");
    } finally {
        unlinkSync(fastImage);
    }

    // CONTROL-OPEN APPLE-RESET restarts the machine even though Machine reset stops before the firmware reads Open
    // Apple and the key is let go while stopped: the buttons down at a reset stay down while the handler runs.
    {
        const screen = async () => (await request("apple2/text")).rows.join("\n");
        const waitFor = async (test, what) => {
            for (const end = performance.now() + 10000; performance.now() < end;) {
                if (test(await screen())) return;
                await new Promise(done => setTimeout(done, 100));
            }
            assert.fail(`${what}:\n${await screen()}`);
        };
        const type = async text => { for (const key of text) await request("retro/key", { code: key.charCodeAt(0) }); };
        events.length = 0;
        await request("launch", { machine: "apple2", romDirectory: roms, model: "iie-enhanced", stopOnEntry: false, sound: "off" });
        await request("setExceptionBreakpoints", { filters: [] });
        await request("configurationDone");
        await waitFor(text => text.includes("]"), "AppleSoft's prompt");

        // Pasted text is typed whole: line endings are RETURN, smart quotes plain ones, and what has no key is left out.
        const pasted = await request("retro/type", { text: "PRINT “PASTED”; — 7☃\r\n" });
        assert.deepEqual(pasted, { typed: 20, skipped: 1 });
        await waitFor(text => text.includes("PASTED-7"), "the pasted line's output");

        await type("10 GOTO 10\r");
        await waitFor(text => text.includes("10 GOTO 10"), "the typed line");
        await request("setExceptionBreakpoints", { filters: ["machineReset"] });
        await request("apple2/button", { button: 0, pressed: true });
        events.length = 0;
        await request("retro/reset");
        assert.equal((await event("stopped")).reason, "breakpoint", "Machine reset stops at the handler");
        await request("apple2/button", { button: 0, pressed: false });
        await request("setExceptionBreakpoints", { filters: [] });
        await request("continue", { threadId: 1 });
        await new Promise(done => setTimeout(done, 1500));
        await type("LIST\r");
        await waitFor(text => /LIST\s*\n\s*\]/.test(text), "LIST after the restart");
        assert.ok(!(await screen()).includes("10  GOTO 10"), "the restart erased the program");
        await request("pause", { threadId: 1 });
        await event("stopped");
    }

    // Breakpoints in the machine-program document follow their BASIC lines as the program is edited, go with a deleted
    // line, and all go when the program is erased or replaced: retro/basic/breakpointsMoved says where each went.
    {
        events.length = 0;
        await request("launch", { machine: "apple2", romDirectory: roms, model: "iie-enhanced", stopOnEntry: true, sound: "off" });
        const path = (await request("retro/basic/document", { base: "retrocore-basic://iie/" })).uri;
        await request("configurationDone");
        assert.equal((await event("stopped")).reason, "entry");
        await request("continue", { threadId: 1 });
        await new Promise(done => setTimeout(done, 1500));
        await request("pause", { threadId: 1 });
        await event("stopped");
        const lines = async () => (await request("retro/basic/program")).text.split(/\r?\n/);
        const lineOf = async number => (await lines()).findIndex(line => line.startsWith(`${number} `)) + 1;
        const write = async text => assert.equal((await request("retro/basic/write", { text })).success, true);
        const moved = async () => (await event("retro/basic/breakpointsMoved")).moves;

        await write("10 PRINT 1\n20 PRINT 2: PRINT 22\n30 PRINT 3\n");
        const twenty = await lineOf(20);
        const thirty = await lineOf(30);
        const second = (await lines())[twenty - 1].indexOf("PRINT 22") + 1;
        assert.ok(second > 1);
        const set = await request("setBreakpoints", { source: { path },
            breakpoints: [{ line: twenty, column: second }, { line: thirty }] });
        assert.ok(set.breakpoints.every(breakpoint => breakpoint.verified));

        events.length = 0;
        await write("10 PRINT 1\n15 PRINT 15\n20 PRINT 2: PRINT 22\n30 PRINT 3\n");
        assert.deepEqual(await moved(), [
            { line: twenty, column: second, toLine: twenty + 1, toColumn: second },
            { line: thirty, column: null, toLine: thirty + 1, toColumn: null }
        ], "an inserted line moves both down, the inline one still on its statement");

        await request("setBreakpoints", { source: { path },
            breakpoints: [{ line: twenty + 1, column: second }, { line: thirty + 1 }] });
        events.length = 0;
        await write("10 PRINT 1\n15 PRINT 15\n20 PRINT 2: PRINT 22\n");
        assert.deepEqual(await moved(), [{ line: thirty + 1, column: null }], "deleting line 30 removes its breakpoint");

        await request("setBreakpoints", { source: { path }, breakpoints: [{ line: twenty + 1, column: second }] });
        events.length = 0;
        await write("100 HOME\n110 END\n");
        assert.deepEqual(await moved(), [{ line: twenty + 1, column: second }], "another program replaces this one");

        const last = await lineOf(110);
        await request("setBreakpoints", { source: { path }, breakpoints: [{ line: last }] });
        events.length = 0;
        await write("");
        assert.deepEqual(await moved(), [{ line: last, column: null }], "erasing the program removes it");
    }

    // dos: the program goes on a DOS 3.3 disk built from the SDK's sources, which the IIe boots; HELLO BRUNs the
    // program, and a breakpoint in its source stops there.
    const dosSource = join(root, "artifacts", `dos-launch-${process.pid}.s`);
    writeFileSync(dosSource, ".cpu Mos6502\nStart:\n    lda #$5A\n    sta $07\n    rts\n");
    try {
        events.length = 0;
        await request("launch", { machine: "apple2", romDirectory: roms, model: "iie-enhanced", stopOnEntry: false,
            speed: "max", sound: "off", source: dosSource, loadAddress: 0x6000, dos: "3.3" });
        const dosBreakpoints = await request("setBreakpoints", { source: { path: dosSource }, breakpoints: [{ line: 4 }] });
        assert.equal(dosBreakpoints.breakpoints[0].verified, true);
        await request("configurationDone");
        assert.equal((await event("stopped")).reason, "breakpoint", "DOS booted and BRUN reached the program");
        assert.equal((await request("stackTrace", { threadId: 1 })).stackFrames[0].line, 4);
        await request("disconnect");
    } finally {
        unlinkSync(dosSource);
    }

    console.log("DAP passed: M1 source/call-stack behavior, RGBA video, exact source cycles, cycle-level beam stops, VBL and in-flight instruction resume on both IIe models, speaker sound, fast disk and booting a program from a DOS 3.3 disk.");
} finally {
    clearTimeout(timeout);
    close();
}
if (failed()) throw failed();
