// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The Z80 SoftCard through the debug adapter, from the SDK's ROMs. A .cpu Z80 source launched on a II Plus with the
// card loads where the Z80's addresses reach and stops at its entry on the "SoftCard Z80" thread; it steps by line,
// into and out of a call, logs the Z80's registers from a logpoint, stops at a source breakpoint and at a data
// breakpoint on the Z80's own addresses, and shows both threads' registers and the Z80's disassembly.
// The card is a hardware row that comes out and goes back in. When the SoftCard CP/M disk is there
// (RETROCORE_SOFTCARD_DISKS, or softcard-disks under the external-files folder), CP/M boots to an instruction
// breakpoint at the Z80's first instruction and then to its prompt.

import { startDap } from "./DapClient.mjs";
import { resolve, join } from "node:path";
import { existsSync, writeFileSync, unlinkSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import assert from "node:assert/strict";

const root = resolve(import.meta.dirname, "..");
const disks = process.env.RETROCORE_SOFTCARD_DISKS
    || join(process.env.RETROCORE_CACHE || join(homedir(), "Retrocore"), "softcard-disks");
const cpm = join(disks, "CPM_Z80SoftCard.dsk");

const { request, event, events, fail, close, failure: failed } = startDap(root);
const timeout = setTimeout(() => fail(new Error("SoftCard DAP integration timed out.")), 120000);
const screen = async () => (await request("apple2/text")).rows.join("\n");

// The Z80 thread's frames are numbered from 1001.
const z80Frame = 1001;
const top = async threadId => (await request("stackTrace", { threadId })).stackFrames[0];
const register = async (frameId, name) => {
    const scopes = (await request("scopes", { frameId })).scopes;
    const variables = (await request("variables", { variablesReference: scopes[0].variablesReference })).variables;
    return variables.find(variable => variable.name === name)?.value;
};

const stoppedOn = async (reason, threadId) => {
    const stopped = await event("stopped");
    assert.equal(stopped.reason, reason, JSON.stringify(stopped));
    assert.equal(stopped.threadId, threadId, JSON.stringify(stopped));
    return top(threadId);
};

mkdirSync(join(root, "artifacts"), { recursive: true });
const source = join(root, "artifacts", `softcard-${process.pid}.asm`);
const lines = [
    "        .cpu Z80",
    "start:  ld a,$12",
    "        ld b,$34",
    "        call bump",
    "        ld [$0200],a",
    "        ld [$E400],a",
    "spin:   jr spin",
    "bump:   inc a",
    "        ret"
];
const line = text => lines.findIndex(entry => entry.includes(text)) + 1;
const second = join(root, "artifacts", `softcard-calls-${process.pid}.asm`);
writeFileSync(source, lines.join("\n") + "\n");

try {
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });
    await assert.rejects(
        request("launch", { machine: "apple2", model: "iie", softCard: 3, stopOnEntry: true }),
        /slot 3 is not free/);

    events.length = 0;
    await request("launch", { machine: "apple2", model: "iiplus", softCard: 4, source, stopOnEntry: true, speed: "max" });
    await request("configurationDone");
    let frame = await stoppedOn("entry", 4);
    assert.equal(frame.line, line("ld a,$12"));
    assert.equal(frame.instructionPointerReference, "z80:0x0100");
    assert.deepEqual((await request("threads")).threads.map(thread => [thread.id, thread.name]),
        [[1, "II Plus CPU"], [2, "BASIC"], [4, "SoftCard Z80"]]);

    // The 6502 waits; its thread still shows its registers, and the Z80's its own.
    assert.match(await register(1, "PC"), /^\$[0-9A-F]+$/);
    assert.equal(await register(z80Frame, "PC"), "$100");

    // The Z80's code disassembles as Z80 instructions, and its memory reads through the card's translation.
    const disassembly = await request("disassemble", { memoryReference: "z80:0x0100", instructionCount: 2 });
    assert.deepEqual(disassembly.instructions.map(instruction => instruction.address), ["z80:0x0100", "z80:0x0102"]);
    // An instruction breakpoint from the disassembly keeps its address space, and a Z80 value opens Z80 memory.
    const fromDisassembly = await request("setInstructionBreakpoints",
        { breakpoints: [{ instructionReference: disassembly.instructions[1].address }] });
    assert.equal(fromDisassembly.breakpoints[0].instructionReference, "z80:0x0102");
    await request("setInstructionBreakpoints", { breakpoints: [] });
    assert.equal((await request("evaluate", { expression: "PC", frameId: z80Frame })).memoryReference, "z80:0x0100");
    assert.match(disassembly.instructions[0].instruction, /ld\s+a,\$12/i);
    assert.equal((await request("evaluate", { expression: "[z80:$0100]", frameId: z80Frame })).result, "$3E (62)");

    await request("next", { threadId: 4 });
    frame = await stoppedOn("step", 4);
    assert.equal(frame.line, line("ld b,$34"));
    assert.equal((await request("evaluate", { expression: "A", frameId: z80Frame })).result, "$12 (18)");

    await request("next", { threadId: 4 });
    frame = await stoppedOn("step", 4);
    assert.equal(frame.line, line("call bump"));
    // A logpoint on the Z80's code writes the Z80's registers.
    await request("setBreakpoints", { source: { path: source }, breakpoints: [{ line: line("inc a"), logMessage: "A={A} B={B}" }] });
    await request("stepIn", { threadId: 4 });
    frame = await stoppedOn("step", 4);
    assert.equal(frame.line, line("inc a"));
    const logged = events.filter(message => message.event === "output" && message.body.output.startsWith("A="));
    assert.deepEqual(logged.map(message => message.body.output.trim()), ["A=$12 B=$34"]);

    // A source breakpoint in the Z80's code stops the Z80's thread.
    const set = await request("setBreakpoints", { source: { path: source }, breakpoints: [{ line: line("ret") }] });
    assert.equal(set.breakpoints[0].verified, true);
    await request("continue", { threadId: 4 });
    frame = await stoppedOn("breakpoint", 4);
    assert.equal(frame.line, line("ret"));
    await request("setBreakpoints", { source: { path: source }, breakpoints: [] });
    assert.equal((await request("stackTrace", { threadId: 4 })).stackFrames[1].line, line("call bump"));
    await request("stepOut", { threadId: 4 });
    frame = await stoppedOn("step", 4);
    assert.equal(frame.line, line("ld [$0200],a"));
    assert.equal((await request("evaluate", { expression: "A", frameId: z80Frame })).result, "$13 (19)");

    // A data breakpoint on the Z80's address space watches the Z80's own addresses: z80:$0200 is the Apple's $1200.
    const info = await request("dataBreakpointInfo", { name: "z80:$0200", asAddress: true });
    assert.equal(info.dataId, "bank:z80:0200:1");
    await request("setDataBreakpoints", { breakpoints: [{ dataId: info.dataId, accessType: "write" }] });
    await request("continue", { threadId: 4 });
    frame = await stoppedOn("data breakpoint", 4);
    assert.equal(frame.line, line("ld [$E400],a"));
    await request("setDataBreakpoints", { breakpoints: [] });

    // Giving the bus back: the step ends on the Z80 thread, waiting at its next instruction, and the 6502 runs on
    // when continued; a pause stops it on its own thread.
    await request("next", { threadId: 4 });
    frame = await stoppedOn("step", 4);
    assert.equal(frame.line, line("spin:"));
    await request("continue", { threadId: 1 });
    await new Promise(done => setTimeout(done, 300));
    await request("pause", { threadId: 1 });
    await stoppedOn("pause", 1);
    assert.equal((await top(4)).line, line("spin:"));

    // The card is a slot's hardware, saved with the machine.
    let devices = await request("retro/devices");
    let slot4 = devices.hardware.find(row => row.id === "slot4");
    assert.equal(slot4.value, "Z80 SoftCard");
    assert.deepEqual(slot4.actions, ["removeCard"]);
    assert.equal(devices.configuration.cards["4"], "softCard");

    // Its switches are settings on the row: with translation off, the Z80's $0100 is the Apple's.
    assert.deepEqual(slot4.settings.map(setting => [setting.id, setting.value]), [["translation", true], ["refresh", true]]);
    devices = await request("retro/hardware", { id: "slot4", action: "setSetting", setting: "translation", value: false });
    slot4 = devices.hardware.find(row => row.id === "slot4");
    assert.equal(slot4.settings.find(setting => setting.id === "translation").value, false);
    assert.deepEqual(devices.configuration.settings, { slot4: { translation: false, refresh: true } });
    const apple = (await request("evaluate", { expression: "[$0100]" })).result;
    assert.equal((await request("evaluate", { expression: "[z80:$0100]", frameId: z80Frame })).result, apple);
    await assert.rejects(
        request("retro/hardware", { id: "slot4", action: "setSetting", setting: "speed", value: true }),
        /no setting 'speed'/);
    devices = await request("retro/hardware", { id: "slot4", action: "setSetting", setting: "translation", value: true });
    assert.equal((await request("evaluate", { expression: "[z80:$0100]", frameId: z80Frame })).result, "$3E (62)");
    devices = await request("retro/hardware", { id: "slot4", action: "removeCard" });
    assert.equal(devices.hardware.find(row => row.id === "slot4").value, "empty");
    assert.deepEqual((await request("threads")).threads.map(thread => thread.id), [1, 2]);
    devices = await request("retro/hardware", { id: "slot5", action: "addSoftCard" });
    assert.equal(devices.hardware.find(row => row.id === "slot5").value, "Z80 SoftCard");
    assert.equal(devices.configuration.cards["5"], "softCard");

    // A saved machine brings the card back with its switches.
    events.length = 0;
    await request("launch", {
        machine: "apple2", model: "iiplus", stopOnEntry: true, speed: "max",
        machineState: { cards: { "4": "softCard" }, settings: { slot4: { refresh: false } } }
    });
    await request("configurationDone");
    await event("stopped");
    slot4 = (await request("retro/devices")).hardware.find(row => row.id === "slot4");
    assert.equal(slot4.value, "Z80 SoftCard");
    assert.deepEqual(slot4.settings.map(setting => [setting.id, setting.value]), [["translation", true], ["refresh", false]]);

    // A program whose first instruction is a call has that call on the Z80's stack. A data breakpoint on the Z80's
    // write to the switch stops the Z80's thread and evaluates its condition on the Z80, though the 6502 has the bus
    // once the write ends.
    const calls = [
        "        .cpu Z80",
        "start:  call work",
        "        ld [$E400],a",
        "spin:   jr spin",
        "work:   ld a,$13",
        "        ret"
    ];
    writeFileSync(second, calls.join("\n") + "\n");
    const callLine = text => calls.findIndex(entry => entry.includes(text)) + 1;
    events.length = 0;
    await request("launch", { machine: "apple2", model: "iiplus", softCard: 4, source: second, stopOnEntry: true, speed: "max" });
    await request("configurationDone");
    await stoppedOn("entry", 4);
    await request("stepIn", { threadId: 4 });
    frame = await stoppedOn("step", 4);
    assert.equal(frame.line, callLine("ld a,$13"));
    const callers = (await request("stackTrace", { threadId: 4 })).stackFrames;
    assert.equal(callers[1].line, callLine("call work"), JSON.stringify(callers));
    const switchInfo = await request("dataBreakpointInfo", { name: "z80:$E400", asAddress: true });
    await request("setDataBreakpoints", { breakpoints: [{ dataId: switchInfo.dataId, accessType: "write", condition: "A == $13" }] });
    await request("continue", { threadId: 4 });
    frame = await stoppedOn("data breakpoint", 4);
    assert.equal(frame.line, callLine("spin:"));
    await request("setDataBreakpoints", { breakpoints: [] });

    // The 6502 resumes beside the Z80 finishing its write to the switch: a breakpoint where it resumes stops it there.
    const handBack = ["        .cpu Z80", "start:  ld [$E400],a", "spin:   jr spin"];
    writeFileSync(second, handBack.join("\n") + "\n");
    events.length = 0;
    await request("launch", { machine: "apple2", model: "iiplus", softCard: 4, source: second, stopOnEntry: true, speed: "max" });
    await request("configurationDone");
    await stoppedOn("entry", 4);
    const resume = (await top(1)).instructionPointerReference;
    await request("setInstructionBreakpoints", { breakpoints: [{ instructionReference: resume }] });
    await request("continue", { threadId: 4 });
    frame = await stoppedOn("instruction breakpoint", 1);
    assert.equal(frame.instructionPointerReference, resume);
    await request("setInstructionBreakpoints", { breakpoints: [] });

    if (!existsSync(cpm)) {
        console.log("SoftCard CP/M boot skipped: set RETROCORE_SOFTCARD_DISKS to the SoftCard CP/M disks.");
    } else {
        // CP/M: the 6502 boots the disk and hands the bus to the Z80, which starts at zero.
        events.length = 0;
        await request("launch", { machine: "apple2", model: "iiplus", softCard: 4, diskImage: cpm, stopOnEntry: false, speed: "max" });
        await request("setInstructionBreakpoints", { breakpoints: [{ instructionReference: "z80:0x0000" }] });
        await request("configurationDone");
        frame = await stoppedOn("instruction breakpoint", 4);
        assert.equal(frame.instructionPointerReference, "z80:0x0000");
        await request("setInstructionBreakpoints", { breakpoints: [] });
        await request("continue", { threadId: 4 });
        for (const end = performance.now() + 30000; !(await screen()).includes("A>");) {
            assert.ok(performance.now() < end, `CP/M's prompt never appeared:\n${await screen()}`);
            await new Promise(done => setTimeout(done, 200));
        }
    }

    console.log("SoftCard DAP integration passed.");
} catch (error) {
    console.error(error);
    process.exitCode = 1;
} finally {
    clearTimeout(timeout);
    close();
    if (existsSync(source)) unlinkSync(source);
    if (existsSync(second)) unlinkSync(second);
    if (failed()) {
        console.error(failed());
        process.exitCode = 1;
    }
}
