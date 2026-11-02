// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Memory view DAP integration: readMemory and writeMemory as VS Code's Hex Editor uses them, memory references on
// variables and evaluate results, the memory events that refresh open views when their bytes change, and the IIe's
// memory banks with breakpoints and disassembly in them. It also checks the breakpoints a data breakpoint's stop
// leaves for resuming, a step that lands on a breakpoint, and the logpoint limit. The Model I part needs nothing
// external; the IIe part runs when RETROCORE_IIE_ROMS names the IIe ROMs.

import { resolve, join } from "node:path";
import { readFileSync } from "node:fs";
import assert from "node:assert/strict";
import { startDap } from "./DapClient.mjs";

const root = resolve(import.meta.dirname, "..");
const sdkRoms = join(root, "src", "Retrocore.Machines.Trs80", "Roms");
const hello = join(root, "sample", "trs80", "hello.asm");
const helloLines = readFileSync(hello, "utf8").split(/\r?\n/);
const roms = process.env.RETROCORE_IIE_ROMS;

const { request, event, events, fail, close, failure } = startDap(root);
let at = "initializing";
const timeout = setTimeout(() => fail(new Error(`Memory DAP integration timed out: ${at}.`)), Number(process.env.RETROCORE_DAP_TIMEOUT ?? 120000));

function drop(name) {
    for (let index = events.length - 1; index >= 0; index--) {
        if (events[index].event === name) events.splice(index, 1);
    }
}

function queued(name) {
    return events.filter(message => message.event === name).map(message => message.body);
}

async function read(memoryReference, count, offset = 0) {
    const body = await request("readMemory", { memoryReference, count, offset });
    return { bytes: Buffer.from(body.data, "base64"), unreadable: body.unreadableBytes ?? 0, address: body.address };
}

function write(memoryReference, bytes, allowPartial = false) {
    return request("writeMemory", { memoryReference, data: Buffer.from(bytes).toString("base64"), allowPartial });
}

async function rejects(promise, pattern) {
    await assert.rejects(promise, error => pattern.test(error.message));
}

async function variables(frameId, name) {
    const scopes = (await request("scopes", { frameId })).scopes;
    const scope = scopes.find(item => item.name === name);
    assert.ok(scope, `the ${name} scope is listed`);
    return (await request("variables", { variablesReference: scope.variablesReference })).variables;
}

try {
    const capabilities = await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true, supportsMemoryEvent: true });
    assert.equal(capabilities.supportsReadMemoryRequest, true);
    assert.equal(capabilities.supportsWriteMemoryRequest, true);

    // The Model I: one address space, memory as the CPU maps it, with 16K so RAM ends at $7FFF.
    at = "launching the Model I";
    await request("launch", { machine: "trs80-model1", sdkRoms, source: hello, stopOnEntry: true, speed: "max", ramKilobytes: 16 });
    await request("configurationDone");
    assert.equal((await event("stopped")).reason, "entry");

    at = "reading memory from evaluate's memory reference";
    const message = await request("evaluate", { expression: "MESSAGE" });
    assert.match(message.memoryReference, /^0x7[0-9A-F]{3}$/);
    assert.equal((await read(message.memoryReference, 5)).bytes.toString("latin1"), "HELLO");
    assert.equal((await read("MESSAGE", 4, 6)).bytes.toString("latin1"), "FROM");
    assert.equal((await read("0x7000", 1)).bytes[0], 0x21);
    const top = await read("0xFFFE", 4);
    assert.equal(top.bytes.length, 2);
    assert.equal(top.unreadable, 2);

    at = "memory references on variables";
    const registers = await variables(1, "Registers");
    assert.match(registers.find(variable => variable.name === "HL").memoryReference, /^0x[0-9A-F]{4}$/);
    assert.equal(registers.find(variable => variable.name === "PC").memoryReference, "0x7000");
    assert.equal(registers.find(variable => variable.name === "AF").memoryReference ?? null, null);
    assert.equal(registers.find(variable => variable.name === "A").memoryReference ?? null, null);
    assert.equal((await variables(1, "Communication region"))[0].memoryReference, "0x4000");
    const memory = await variables(1, "Memory");
    assert.deepEqual(memory.map(variable => [variable.name, variable.memoryReference]), [["CPU", "0x0000"]]);
    const modelBanks = (await request("retro/memoryBanks")).banks;
    assert.deepEqual(modelBanks.map(bank => bank.name), [null]);

    at = "writing memory tells the other views";
    drop("memory");
    drop("invalidated");
    assert.equal((await write("MESSAGE", [0x4A])).bytesWritten, 1);
    assert.equal((await read(message.memoryReference, 5)).bytes.toString("latin1"), "JELLO");
    const told = queued("memory").map(body => body.memoryReference);
    assert.deepEqual(told, [message.memoryReference], "only views that read the byte written, except the writer, are told");
    assert.deepEqual(queued("invalidated").at(-1)?.areas, ["variables"]);

    at = "writes that cannot finish";
    const rom = (await read("0x0000", 1)).bytes[0];
    await rejects(write("0x0000", [rom ^ 0xFF]), /not RAM or video RAM/);
    assert.equal((await read("0x0000", 1)).bytes[0], rom);
    const last = (await read("0x7FFF", 1)).bytes[0];
    await rejects(write("0x7FFF", [last ^ 0xFF, 0]), /\$8000 is not RAM/);
    assert.equal((await read("0x7FFF", 1)).bytes[0], last, "a failed write changes nothing");
    assert.equal((await write("0x7FFF", [last ^ 0xFF, 0], true)).bytesWritten, 1);
    assert.equal((await read("0x7FFF", 1)).bytes[0], last ^ 0xFF);
    await write("0x7FFF", [last]);

    // Printing writes video memory, so a stop tells the video view and not the message's.
    at = "a stop tells the views whose bytes changed";
    await read("0x3C00", 1024);
    drop("memory");
    const inc = helloLines.findIndex(line => line.trim() === "INC HL") + 1;
    await request("setBreakpoints", { source: { path: hello }, breakpoints: [{ line: inc }] });
    await request("continue", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "breakpoint");
    await request("stackTrace", { threadId: 1 });
    assert.deepEqual(queued("memory"), [{ memoryReference: "0x3C00", offset: 0, count: 1024 }]);

    // A data breakpoint stops after LD A,[HL] reads the next character, before OR A's breakpoint was checked:
    // continuing stops there without running, and continuing again runs on.
    at = "a data stop leaves the next instruction's breakpoints to check";
    const orA = helloLines.findIndex(line => line.trim() === "OR A") + 1;
    const next = (await request("dataBreakpointInfo", { name: "[HL+1]" })).dataId;
    const [watch] = (await request("setDataBreakpoints", { breakpoints: [{ dataId: next, accessType: "read" }] })).breakpoints;
    const [line] = (await request("setBreakpoints", { source: { path: hello }, breakpoints: [{ line: orA }] })).breakpoints;
    await request("continue", { threadId: 1 });
    let stop = await event("stopped");
    assert.deepEqual([stop.reason, stop.hitBreakpointIds], ["data breakpoint", [watch.id]]);
    const dataPc = (await request("stackTrace", { threadId: 1 })).stackFrames[0].instructionPointerReference;
    await request("setDataBreakpoints", { breakpoints: [] });
    await request("continue", { threadId: 1 });
    stop = await event("stopped");
    assert.deepEqual([stop.reason, stop.hitBreakpointIds], ["breakpoint", [line.id]]);
    assert.equal((await request("stackTrace", { threadId: 1 })).stackFrames[0].instructionPointerReference, dataPc);

    // Stepping over the line before a breakpoint stops on it as a breakpoint, which counts its hit.
    at = "a step that lands on a breakpoint";
    const jr = helloLines.findIndex(line => line.trim() === "JR Z,DONE") + 1;
    const [jump] = (await request("setBreakpoints", { source: { path: hello }, breakpoints: [{ line: jr }] })).breakpoints;
    await request("next", { threadId: 1 });
    stop = await event("stopped");
    assert.deepEqual([stop.reason, stop.hitBreakpointIds], ["breakpoint", [jump.id]]);
    assert.equal((await request("retro/breakpoints")).breakpoints.find(item => item.id === jump.id).hits, 1);
    await request("setBreakpoints", { source: { path: hello }, breakpoints: [] });

    at = "banks the Model I does not have";
    await rejects(request("evaluate", { expression: "[aux:$4000]" }), /no memory banks/);
    assert.match((await request("dataBreakpointInfo", { name: "[aux:$4000]" })).description, /no memory banks/);
    await rejects(request("disassemble", { memoryReference: "aux:0x7000", instructionCount: 1 }), /no memory banks/);

    // A logpoint on every character prints the first two and counts the rest, reported when the machine stops.
    at = "the logpoint limit";
    await request("launch", { machine: "trs80-model1", sdkRoms, source: hello, stopOnEntry: true, speed: "max", logpointLimit: 2 });
    await request("configurationDone");
    assert.equal((await event("stopped")).reason, "entry");
    drop("output");
    const done = helloLines.findIndex(line => line.trim() === "JR DONE") + 1;
    await request("setBreakpoints", { source: { path: hello }, breakpoints: [{ line: orA, logMessage: "char {A,c}" }, { line: done }] });
    await request("continue", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "breakpoint");
    const output = queued("output");
    assert.deepEqual(output.filter(body => body.category === "console").map(body => body.output), ["char H\n", "char E\n"]);
    const notice = output.find(body => body.category === "important");
    assert.match(notice?.output ?? "", /^Retrocore dropped 18 logpoint lines: logpoints write at most 2 a second/);
    await request("setBreakpoints", { source: { path: hello }, breakpoints: [] });
    console.log("Memory DAP integration passed on the Model I.");

    if (!roms) {
        console.log("Skipped the IIe's memory banks: RETROCORE_IIE_ROMS is not set.");
    } else {
        at = "launching the IIe";
        await request("launch", {
            machine: "apple2", romDirectory: roms, model: "iie-enhanced", stopOnEntry: true,
            program: join(root, "artifacts", "iie-sample", "main.bin"),
            debugFile: join(root, "artifacts", "iie-sample", "main.dbg"),
            loadAddress: 0x6000
        });
        await request("configurationDone");
        assert.equal((await event("stopped")).reason, "entry");

        at = "the IIe's banks and where they are mapped";
        const banks = (await request("retro/memoryBanks")).banks;
        assert.deepEqual(banks.map(bank => bank.name), [null, "main", "aux", "bank1", "auxbank1", "rom"]);
        const bank = name => banks.find(item => item.name === name);
        assert.equal(bank("main").reads, "$0000-$BFFF");
        assert.equal(bank("main").memoryReference, "main:0x0000");
        assert.equal(bank("aux").reads, "nowhere");
        assert.equal(bank("bank1").memoryReference, "bank1:0xD000");
        assert.equal(bank("rom").readOnly, true);
        assert.equal(bank("rom").writes, null);
        assert.ok(bank("rom").reads.endsWith("$D000-$FFFF"));
        const listed = await variables(1, "Memory");
        assert.deepEqual(listed.map(variable => variable.name), ["CPU", "main", "aux", "bank1", "auxbank1", "rom"]);
        assert.match(listed.find(variable => variable.name === "aux").value, /^Auxiliary RAM: read at nowhere; written at nowhere$/);
        assert.deepEqual(listed.find(variable => variable.name === "rom").presentationHint.attributes, ["readOnly"]);
        const stack = (await variables(1, "Registers")).find(variable => variable.name === "S");
        assert.match(stack.memoryReference, /^0x01[0-9A-F]{2}$/);

        at = "reading and writing a bank the CPU does not map";
        const main = (await read("0x0400", 1)).bytes[0];
        await write("aux:0x0400", [0x55]);
        assert.equal((await read("aux:0x0400", 1)).bytes[0], 0x55);
        assert.equal((await read("0x0400", 1)).bytes[0], main);
        assert.equal((await request("evaluate", { expression: "[aux:$0400]" })).result, "$55 (85)");
        const reference = await request("evaluate", { expression: "aux:$0400" });
        assert.equal(reference.result, "aux:$0400");
        assert.equal(reference.memoryReference, "aux:0x0400");
        const hole = await read("main:0xBFFE", 4);
        assert.equal(hole.bytes.length, 2);
        assert.equal(hole.unreadable, 2);
        assert.deepEqual((await read("rom:0xD000", 4)).bytes, (await read("0xD000", 4)).bytes);
        await rejects(write("rom:0xD000", [0]), /System ROM is read-only/);
        await rejects(write("0xD000", [0]), /reads the system ROM now, not RAM/);
        await rejects(write("bank1:0xE000", [0]), /bank 1 has no byte at \$E000/);

        // A bank disassembles as if it were mapped: aux RAM holds zeros where main RAM holds the program.
        at = "disassembling a bank";
        const disassemble = async memoryReference =>
            (await request("disassemble", { memoryReference, instructionCount: 2 })).instructions;
        const program = await disassemble("0x6000");
        assert.equal(program[0].instructionBytes, "A9 C1");
        assert.equal(program[0].symbol, "entry");
        assert.deepEqual((await disassemble("main:0x6000")).map(item => item.instruction), program.map(item => item.instruction));
        const auxiliary = await disassemble("aux:0x6000");
        assert.match(auxiliary[0].instructionBytes, /^00/);
        assert.equal(auxiliary[0].symbol ?? null, null, "the program's labels are main RAM's");
        assert.equal(auxiliary[0].address, "0x6000");
        assert.deepEqual(await disassemble("rom:0xFA62"), await disassemble("0xFA62"));

        at = "data breakpoints on a bank";
        assert.match((await request("dataBreakpointInfo", { name: "[aux:$C000]" })).description, /Auxiliary RAM has no byte at \$C000/);
        const auxWatch = await request("dataBreakpointInfo", { name: "[aux:$0400]" });
        assert.equal(auxWatch.dataId, "bank:aux:0400:1");
        assert.equal(auxWatch.description, "aux:$0400");
        const mainWatch = await request("dataBreakpointInfo", { name: "main:$0400", asAddress: true, bytes: 1 });
        assert.equal(mainWatch.dataId, "bank:main:0400:1");
        const set = (await request("setDataBreakpoints", {
            breakpoints: [{ dataId: auxWatch.dataId, accessType: "write" }, { dataId: mainWatch.dataId, accessType: "write" }]
        })).breakpoints;
        assert.ok(set.every(breakpoint => breakpoint.verified));

        // The sample's "sta $0400" writes main RAM, as 80STORE is off: the main watch stops and the aux watch does not.
        await request("continue", { threadId: 1 });
        const stopped = await event("stopped");
        assert.equal(stopped.reason, "data breakpoint");
        assert.deepEqual(stopped.hitBreakpointIds, [set[1].id]);
        assert.equal(stopped.description, "Wrote $C1 to main:$0400.");
        await request("setDataBreakpoints", { breakpoints: [] });

        // Breakpoints on a bank stop only while the CPU runs that bank's code at the address.
        at = "breakpoints on a bank";
        const functions = (await request("setFunctionBreakpoints", {
            breakpoints: [{ name: "aux:after_call" }, { name: "main:after_call" }, { name: "bank1:$E000" }]
        })).breakpoints;
        assert.deepEqual(functions.map(item => item.verified), [true, true, false]);
        assert.match(functions[2].message, /bank 1 has no byte at \$E000/);
        const instructions = (await request("setInstructionBreakpoints", {
            breakpoints: [{ instructionReference: "aux:0x6005" }]
        })).breakpoints;
        assert.equal(instructions[0].verified, true);
        await request("continue", { threadId: 1 });
        const banked = await event("stopped");
        assert.deepEqual([banked.reason, banked.hitBreakpointIds], ["function breakpoint", [functions[1].id]]);
        const listing = (await request("retro/breakpoints")).breakpoints;
        assert.ok(listing.some(item => item.location === "main:after_call (main:$600A)"));
        assert.ok(listing.some(item => item.location === "aux:$6005"));
        await request("setFunctionBreakpoints", { breakpoints: [] });
        await request("setInstructionBreakpoints", { breakpoints: [] });
        console.log("Memory DAP integration passed on the IIe's memory banks.");
    }

    await request("disconnect");
} catch (error) {
    if (failure()) throw failure();
    throw error;
} finally {
    clearTimeout(timeout);
    close();
}
