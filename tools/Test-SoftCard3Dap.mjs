// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The SoftCard /// on the Apple III through the debug adapter, from the SDK's ROMs. A .cpu Z80 source launched on an
// Apple III with the card loads where the Z80's addresses reach and stops at its entry on the "SoftCard /// Z80"
// thread; it steps by line, into and out of a call, stops at a source breakpoint and at a data breakpoint on the
// Z80's own addresses, and gives the bus back with OUT ($00),A. The card is a slot's hardware row that comes out and
// goes back in, and a saved machine brings it back. When the SoftCard /// CP/M Master disk is there
// (RETROCORE_SOFTCARD3, or softcard3 under the external-files folder), CP/M boots to an instruction breakpoint at
// the Z80's first instruction and then to its prompt.

import { startDap } from "./DapClient.mjs";
import { resolve, join } from "node:path";
import { existsSync, writeFileSync, unlinkSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import assert from "node:assert/strict";

const root = resolve(import.meta.dirname, "..");
const sdkRoms = join(root, "src", "Retrocore.Machines.Apple3", "Roms");
const fixtures = process.env.RETROCORE_SOFTCARD3
    || join(process.env.RETROCORE_CACHE || join(homedir(), "Retrocore"), "softcard3");
const cpm = join(fixtures, "Apple Softcard III CPM Master Diskette (076-0002) Apple 1982.dsk");

const { request, event, events, fail, close, failure: failed } = startDap(root);
const timeout = setTimeout(() => fail(new Error("SoftCard /// DAP integration timed out.")), 180000);

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
const source = join(root, "artifacts", `softcard3-${process.pid}.asm`);
const lines = [
    "        .cpu Z80",
    "start:  ld a,$12",
    "        ld b,$34",
    "        call bump",
    "        ld [$0200],a",
    "        out [$00],a",
    "spin:   jr spin",
    "bump:   inc a",
    "        ret"
];
const line = text => lines.findIndex(entry => entry.includes(text)) + 1;
writeFileSync(source, lines.join("\n") + "\n");

try {
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });
    await assert.rejects(
        request("launch", { machine: "apple3", sdkRoms, softCard3: 5, stopOnEntry: true }),
        /slot 5 is not free/);
    await assert.rejects(
        request("launch", { machine: "apple3", sdkRoms, proFiles: [{ slot: 4 }], softCard3: 4, stopOnEntry: true }),
        /slot 4 is not free/);

    events.length = 0;
    await request("launch", { machine: "apple3", sdkRoms, softCard3: 4, source, stopOnEntry: true, speed: "max" });
    await request("configurationDone");
    let frame = await stoppedOn("entry", 4);
    assert.equal(frame.line, line("ld a,$12"));
    assert.equal(frame.instructionPointerReference, "z80:0x0100");
    const threads = (await request("threads")).threads.map(thread => [thread.id, thread.name]);
    assert.deepEqual(threads.filter(([id]) => id === 1 || id === 4), [[1, "Apple III 6502"], [4, "SoftCard /// Z80"]]);

    // The 6502 waits; its thread still shows its registers, and the Z80's its own.
    assert.match(await register(1, "PC"), /^\$[0-9A-F]+$/);
    assert.equal(await register(z80Frame, "PC"), "$100");

    // The Z80's code disassembles as Z80 instructions, and its memory reads through the card's PROM: the Z80's $0100
    // is the Apple's $2100.
    const disassembly = await request("disassemble", { memoryReference: "z80:0x0100", instructionCount: 2 });
    assert.deepEqual(disassembly.instructions.map(instruction => instruction.address), ["z80:0x0100", "z80:0x0102"]);
    assert.match(disassembly.instructions[0].instruction, /ld\s+a,\$12/i);
    assert.equal((await request("evaluate", { expression: "[z80:$0100]", frameId: z80Frame })).result, "$3E (62)");
    assert.equal((await request("evaluate", { expression: "[$2100]" })).result, "$3E (62)");
    const coprocessors = (await request("retro/memoryBanks")).banks.filter(bank => bank.coprocessor).map(bank => bank.name);
    assert.deepEqual(coprocessors, ["z80"]);

    // Z80 $A000 is the Apple's I/O page, read-only in Retrocore Memory.
    assert.deepEqual((await request("retro/memory/read", { memoryReference: "z80:0x0000", offset: 0xA000, count: 2 })).readOnly, [{ offset: 0, count: 2 }]);
    assert.deepEqual((await request("retro/memory/read", { memoryReference: "z80:0x0000", offset: 0x0100, count: 2 })).readOnly, []);

    await request("next", { threadId: 4 });
    frame = await stoppedOn("step", 4);
    assert.equal(frame.line, line("ld b,$34"));
    assert.equal((await request("evaluate", { expression: "A", frameId: z80Frame })).result, "$12 (18)");

    await request("next", { threadId: 4 });
    frame = await stoppedOn("step", 4);
    assert.equal(frame.line, line("call bump"));
    await request("stepIn", { threadId: 4 });
    frame = await stoppedOn("step", 4);
    assert.equal(frame.line, line("inc a"));

    // A source breakpoint in the Z80's code stops the Z80's thread, with its caller on the stack.
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

    // A data breakpoint on the Z80's address space watches the Z80's own addresses: z80:$0200 is the Apple's $2200.
    const info = await request("dataBreakpointInfo", { name: "z80:$0200", asAddress: true });
    assert.equal(info.dataId, "bank:z80:0200:1");
    await request("setDataBreakpoints", { breakpoints: [{ dataId: info.dataId, accessType: "write" }] });
    await request("continue", { threadId: 4 });
    frame = await stoppedOn("data breakpoint", 4);
    assert.equal(frame.line, line("out [$00],a"));
    await request("setDataBreakpoints", { breakpoints: [] });
    assert.equal((await request("evaluate", { expression: "[$2200]" })).result, "$13 (19)");

    // Giving the bus back: the step ends on the Z80 thread, waiting at its next instruction, and the 6502 runs on
    // when continued; a pause stops it on its own thread. The 6502 is in the boot ROM's diagnostics, whose memory
    // test overwrites the program, so the Z80's place shows as its address.
    await request("next", { threadId: 4 });
    frame = await stoppedOn("step", 4);
    assert.equal(frame.line, line("spin:"));
    await request("continue", { threadId: 1 });
    await new Promise(done => setTimeout(done, 300));
    await request("pause", { threadId: 1 });
    await stoppedOn("pause", 1);
    assert.equal((await top(4)).instructionPointerReference, frame.instructionPointerReference);

    // The card is a slot's hardware, saved with the machine, with no switches.
    let devices = await request("retro/devices");
    let slot4 = devices.hardware.find(row => row.id === "slot4");
    assert.equal(slot4.value, "SoftCard ///");
    assert.deepEqual(slot4.actions, ["removeCard"]);
    assert.ok(!slot4.settings?.length, JSON.stringify(slot4));
    assert.equal(devices.configuration.cards["4"], "softCard3");

    // Taking the card out ends the Z80's thread, and putting one in starts it; there is one SoftCard /// at a time.
    const threadEvents = () => events.filter(message => message.event === "thread" && message.body.threadId === 4)
        .map(message => message.body.reason);
    events.length = 0;
    devices = await request("retro/hardware", { id: "slot4", action: "removeCard" });
    assert.equal(devices.hardware.find(row => row.id === "slot4").value, "empty");
    assert.ok(!(await request("threads")).threads.some(thread => thread.id === 4));
    assert.deepEqual(threadEvents(), ["exited"]);
    devices = await request("retro/hardware", { id: "slot2", action: "addSoftCard3" });
    assert.equal(devices.hardware.find(row => row.id === "slot2").value, "SoftCard ///");
    assert.deepEqual(threadEvents(), ["exited", "started"]);
    assert.equal(devices.configuration.cards["2"], "softCard3");
    await assert.rejects(request("retro/hardware", { id: "slot3", action: "addSoftCard3" }), /does not support addSoftCard3/);

    // A saved machine brings the card back in its saved slot, over the launch's.
    events.length = 0;
    await request("launch", {
        machine: "apple3", sdkRoms, softCard3: 4, stopOnEntry: true, speed: "max",
        machineState: { cards: { "2": "softCard3", "4": "empty" } }
    });
    await request("configurationDone");
    await event("stopped");
    devices = await request("retro/devices");
    assert.equal(devices.hardware.find(row => row.id === "slot2").value, "SoftCard ///");
    assert.equal(devices.hardware.find(row => row.id === "slot4").value, "empty");

    if (!existsSync(cpm)) {
        console.log("SoftCard /// CP/M boot skipped: set RETROCORE_SOFTCARD3 to the folder with the CP/M Master disk.");
    } else {
        // CP/M: the 6502 boots the disk and hands the bus to the Z80, which starts at zero.
        events.length = 0;
        await request("launch", { machine: "apple3", sdkRoms, softCard3: 4, disks: [cpm], stopOnEntry: false, speed: "max" });
        await request("setInstructionBreakpoints", { breakpoints: [{ instructionReference: "z80:0x0000" }] });
        await request("configurationDone");
        frame = await stoppedOn("instruction breakpoint", 4);
        assert.equal(frame.instructionPointerReference, "z80:0x0000");
        await request("setInstructionBreakpoints", { breakpoints: [] });
        // Frames sent while stopped are behind; the prompt comes in a running one.
        for (let index = events.length - 1; index >= 0; index--) {
            if (events[index].event === "retro/frame") events.splice(index, 1);
        }

        await request("continue", { threadId: 4 });
        let rows = "";
        for (;;) {
            const shown = await event("retro/frame");
            rows = shown.rows.join("\n");
            if (/^A>/m.test(rows)) break;
            assert.ok(shown.running, `CP/M stopped before its prompt:\n${rows}`);
        }

        assert.match(rows, /SoftCard \/\/\/ CP\/M/i);
    }

    console.log("SoftCard /// DAP integration passed.");
} catch (error) {
    console.error(error);
    process.exitCode = 1;
} finally {
    clearTimeout(timeout);
    close();
    if (existsSync(source)) unlinkSync(source);
    if (failed()) {
        console.error(failed());
        process.exitCode = 1;
    }
}
