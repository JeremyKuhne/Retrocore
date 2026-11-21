// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Memory view DAP integration: readMemory and writeMemory for other clients, retro/memory/read as Retrocore Memory
// uses it with retro/memory/labels, retro/memory/characters and retro/memory/freeze, memory references on variables
// and evaluate results, the memory events that refresh open views when their bytes change, and the IIe's memory banks
// with breakpoints and disassembly in them. It also checks the breakpoints a data breakpoint's stop
// leaves for resuming, a step that lands on a breakpoint, and the logpoint limit. The Model I part needs nothing
// external; the IIe part runs when RETROCORE_IIE_ROMS names the IIe ROMs.

import { resolve, join } from "node:path";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
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

async function scopeReference(frameId, name) {
    const scopes = (await request("scopes", { frameId })).scopes;
    const scope = scopes.find(item => item.name === name);
    assert.ok(scope, `the ${name} scope is listed`);
    return scope.variablesReference;
}

async function variables(frameId, name) {
    return (await request("variables", { variablesReference: await scopeReference(frameId, name) })).variables;
}

// A variable's memory reference, which Open in Retrocore Memory asks for, as VS Code is sent none.
async function addressOf(frameId, scope, name) {
    try {
        return (await request("retro/memory/variable", { variablesReference: await scopeReference(frameId, scope), name })).memoryReference;
    } catch {
        return null;
    }
}

try {
    const capabilities = await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true, supportsMemoryEvent: true });
    // VS Code's own memory icon opens only the Hex Editor, so VS Code is not told of readMemory; it still answers.
    assert.equal(capabilities.supportsReadMemoryRequest, true);
    assert.equal(capabilities.supportsWriteMemoryRequest, true);
    assert.equal(capabilities.supportsRetrocoreMemorySubscriptions, true);

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

    // A hover on a mnemonic fails, so the editor shows the language server's hover with the instruction's summary,
    // rather than Level II's BASIC variable LD. Registers and labels still evaluate, and a BASIC file's CP is BASIC's.
    at = "hovering mnemonics";
    const source = { path: hello };
    await rejects(request("evaluate", { expression: "LD", context: "hover", frameId: 1, source }), /./);
    await rejects(request("evaluate", { expression: "djnz", context: "hover", frameId: 1 }), /./);
    assert.match((await request("evaluate", { expression: "HL", context: "hover", frameId: 1, source })).result, /^\$[0-9A-F]+ \(\d+\)$/);
    assert.match((await request("evaluate", { expression: "MESSAGE", context: "hover", frameId: 1, source })).result, /^\$700F/);
    assert.equal((await request("evaluate", { expression: "CP", context: "hover", frameId: 1, source: { path: join(root, "game.bas") } })).result, "0");
    assert.equal((await request("evaluate", { expression: "LD", context: "watch", frameId: 1 })).result, "0");
    const top = await read("0xFFFE", 4);
    assert.equal(top.bytes.length, 2);
    assert.equal(top.unreadable, 2);

    // Retrocore Memory reads past gaps, with the unreadable runs marked and read as zero.
    at = "reading a range with gaps";
    const range = await request("retro/memory/read", { memoryReference: "0xFFFE", count: 4 });
    assert.equal(range.address, "0xFFFE");
    assert.deepEqual([...Buffer.from(range.data, "base64").subarray(0, 2)], [...top.bytes]);
    assert.deepEqual([...Buffer.from(range.data, "base64").subarray(2)], [0, 0]);
    assert.deepEqual(range.unreadable, [{ offset: 2, count: 2 }]);

    // It marks the bytes a write cannot reach: the keyboard, but not video RAM after it.
    at = "reading which bytes are read-only";
    assert.deepEqual((await request("retro/memory/read", { memoryReference: "0x3BFE", count: 4 })).readOnly, [{ offset: 0, count: 2 }]);
    assert.deepEqual((await request("retro/memory/read", { memoryReference: "0x3C00", count: 4 })).readOnly, []);
    // Level II's single and double floats keep the exponent last.
    assert.deepEqual((await request("retro/memory/numbers", { memoryReference: "0x0000", value: "1000" })).formats, [
        { label: "Single, 4 bytes", bytes: [0, 0, 0x7A, 0x8A] },
        { label: "Double, 8 bytes", bytes: [0, 0, 0, 0, 0, 0, 0x7A, 0x8A] }
    ]);
    // The double's 56 bits hold 2^53 + 1, which the text keeps and a JavaScript or C# double would not.
    assert.deepEqual((await request("retro/memory/numbers", { memoryReference: "0x0000", value: "9007199254740993" })).formats[1].bytes,
        [0x04, 0, 0, 0, 0, 0, 0, 0xB6]);
    // A line assembles in the Z80's syntax, its conditions no symbols.
    const z80 = async line => (await request("retro/memory/assemble", { memoryReference: "0x0000", address: 0x7000, line })).bytes;
    assert.deepEqual([await z80("LD A,[HL]"), await z80("JP NZ,$0000"), await z80("XOR A")], [[0x7E], [0xC2, 0, 0], [0xAF]]);
    // AF's apostrophe opens no quoted text.
    assert.deepEqual(await z80("EX AF,AF'"), [0x08]);
    // The ROM's start saved as Z80 assembly, which assembles back to the same bytes.
    const saved = await request("retro/memory/export", { memoryReference: "0x0000", address: 0x0000, count: 0x40 });
    assert.equal(saved.exact, true, saved.source);
    assert.ok(saved.source.includes(".cpu Z80") && saved.source.includes("DI"), saved.source);
    // The instruction at the ROM's start, with the T-states the Z80's instruction set gives.
    const reset = (await request("retro/memory/inspect", { memoryReference: "0x0000", address: 0 })).instruction;
    assert.deepEqual([reset.text, reset.size, reset.cycles, reset.cyclesTaken], ["DI", 1, 4, null], JSON.stringify(reset));

    // Labels come from the program and the SDK's ROM source, where their code is in memory now.
    at = "reading memory labels";
    const labels = new Map((await request("retro/memory/labels", { memoryReference: "0x0000" })).labels.map(label => [label.name, label.address]));
    assert.equal(labels.get("RESET"), 0x0000);
    assert.equal(labels.get("START"), 0x7000);
    assert.equal(labels.get("MESSAGE"), Number(message.memoryReference));
    assert.equal(labels.get("DISPLAY_CHAR"), 0x0033, "the ROM's label, which the program's constant names too");
    assert.equal(labels.has("ERR_SN"), false, "a constant is not a label");

    // A restart's target is the address its opcode implies, which the listing names and goes to.
    at = "listing a restart";
    const restart = (await request("retro/memory/listing", { memoryReference: "0x0000", address: 0x0000, count: 0x1000 })).lines
        .find(line => line.text.startsWith("RST") && line.target !== null && line.target > 0);
    assert.ok(restart, "Level II calls its restarts");
    assert.equal(restart.text.includes("$"), false, "the restart's label names it: " + restart.text);

    // The character set is the Model I's: 6x12, with block graphics from $80.
    at = "reading the character set";
    const characters = await request("retro/memory/characters");
    assert.deepEqual([characters.width, characters.height], [6, 12]);
    assert.equal(characters.text.length, 256);
    assert.equal(characters.text[0x41], "A");
    assert.equal(characters.text[0x01], "A", "without the lowercase modification, $01 shows A");
    assert.equal(characters.text[0x80], "\0");
    const glyphs = Buffer.from(characters.glyphs, "base64");
    assert.equal(glyphs.length, 256 * 12);
    assert.ok(glyphs.subarray(0x80 * 12, 0x81 * 12).every(row => row === 0), "$80 is blocks all off");
    assert.ok(glyphs.subarray(0xBF * 12, 0xC0 * 12).every(row => row === 0xFC), "$BF is blocks all on");
    assert.ok(glyphs.subarray(0x41 * 12, 0x41 * 12 + 8).some(row => row !== 0), "A draws");
    assert.equal(characters.flashed ?? null, null, "nothing flashes");

    at = "memory references on variables";
    const registers = await variables(1, "Registers");
    assert.match(await addressOf(1, "Registers", "HL"), /^0x[0-9A-F]{4}$/);
    assert.equal(await addressOf(1, "Registers", "PC"), "0x7000");
    assert.equal(await addressOf(1, "Registers", "AF"), null);
    assert.equal(await addressOf(1, "Registers", "A"), null);
    const region = await variables(1, "Communication region");
    assert.equal(await addressOf(1, "Communication region", region[0].name), "0x4000");
    // VS Code shows its Hex Editor icon on anything with a memory reference, so its views are sent none.
    assert.ok(registers.every(variable => !("memoryReference" in variable)), "no register has a memory reference");
    assert.ok(region.every(variable => !("memoryReference" in variable)), "no byte has a memory reference");
    assert.equal("memoryReference" in await request("evaluate", { expression: "$4000", context: "watch" }), false);
    assert.equal("memoryReference" in await request("evaluate", { expression: "$4000", context: "hover" }), false);
    assert.equal((await request("evaluate", { expression: "$4000", context: "retrocore" })).memoryReference, "0x4000");
    assert.equal((await request("evaluate", { expression: "$4000" })).memoryReference, "0x4000");
    // A variable that holds an address is marked for Open in Retrocore Memory.
    assert.equal(registers.find(variable => variable.name === "PC").__vscodeVariableMenuContext, "memory");
    assert.equal(registers.find(variable => variable.name === "A").__vscodeVariableMenuContext ?? null, null);
    assert.equal((await variables(1, "Communication region"))[0].__vscodeVariableMenuContext, "memory");
    const scopeNames = (await request("scopes", { frameId: 1 })).scopes.map(scope => scope.name);
    assert.equal(scopeNames.includes("Memory"), false, "the banks are in Open Memory, not a scope");
    const modelBanks = (await request("retro/memoryBanks")).banks;
    assert.deepEqual(modelBanks.map(bank => bank.name), [null]);
    // cpu: names memory as the CPU maps it, on a machine with no banks too.
    assert.equal((await request("evaluate", { expression: "[cpu:$3C00]" })).result, (await request("evaluate", { expression: "[$3C00]" })).result);
    assert.equal((await request("evaluate", { expression: "cpu:$3C00", context: "retrocore" })).memoryReference, "0x3C00");
    assert.equal(modelBanks[0].coprocessor, false);

    at = "writing memory tells the other views";
    drop("memory");
    drop("invalidated");
    assert.equal((await write("MESSAGE", [0x4A])).bytesWritten, 1);
    assert.equal((await read(message.memoryReference, 5)).bytes.toString("latin1"), "JELLO");
    const told = queued("memory").map(body => body.memoryReference);
    assert.deepEqual(told, [message.memoryReference], "only views that read the byte written, except the writer, are told");
    assert.deepEqual(queued("invalidated").at(-1)?.areas, ["variables"]);

    at = "tracking separate read ranges";
    const low = (await read("0x4000", 1)).bytes[0];
    await read("0x4000", 1, 0x1000);
    const middle = (await read("0x4800", 1)).bytes[0];
    drop("memory");
    await write("0x4800", [middle ^ 0xFF]);
    assert.equal(queued("memory").some(body => body.memoryReference === "0x4000"), false,
        "a write between two read ranges does not invalidate either");
    drop("memory");
    await write("4000", [low ^ 0xFF]);
    assert.deepEqual(queued("memory").find(body => body.memoryReference === "0x4000"),
        { memoryReference: "0x4000", offset: 0, count: 0x1001 }, "a read range still notifies the view");
    await write("0x4800", [middle]);
    await write("4000", [low]);

    at = "closing one memory subscriber";
    const savedBytes = (await read("6100", 0x21)).bytes;
    await request("retro/memory/read", { memoryReference: "0x6100", offset: 0, count: 1, subscriber: "first" });
    await request("retro/memory/read", { memoryReference: "0x6100", offset: 0x10, count: 1, subscriber: "second" });
    await read("0x6100", 1, 0x20);
    await request("retro/memory/unsubscribe", { subscriber: "first" });
    drop("memory");
    await write("6100", [savedBytes[0] ^ 0xFF]);
    assert.equal(queued("memory").some(body => body.memoryReference === "0x6100"), false,
        "the closed editor no longer tracks its bytes");
    await write("6110", [savedBytes[0x10] ^ 0xFF]);
    assert.ok(queued("memory").some(body => body.memoryReference === "0x6100"), "the other editor remains subscribed");
    await request("retro/memory/unsubscribe", { subscriber: "second" });
    for (let index = 0; index < 33; index++) {
        await request("retro/memory/read", { memoryReference: "0x6100", count: 1, subscriber: `extra-${index}` });
    }
    for (let index = 0; index < 33; index++) {
        await request("retro/memory/unsubscribe", { subscriber: `extra-${index}` });
    }
    drop("memory");
    await write("6120", [savedBytes[0x20] ^ 0xFF]);
    assert.ok(queued("memory").some(body => body.memoryReference === "0x6100"),
        "unsubscribing many editors does not evict a standard DAP reader of the same reference");
    await write("6100", [savedBytes[0]]);
    await write("6110", [savedBytes[0x10]]);
    await write("6120", [savedBytes[0x20]]);

    at = "retaining live subscriptions while limiting unscoped readers";
    await read("0x6100", 1);
    for (let index = 0; index < 33; index++) {
        await request("retro/memory/read", { memoryReference: "0x6100", count: 1, subscriber: `live-${index}` });
    }
    for (let index = 0; index < 32; index++) {
        await read(`0x${(0x7000 + index).toString(16)}`, 1);
    }
    drop("memory");
    await write("6100", [savedBytes[0] ^ 0xFF]);
    assert.ok(queued("memory").some(body => body.memoryReference === "0x6100"),
        "adding unscoped references does not evict live editor subscriptions");
    await write("6100", [savedBytes[0]]);
    for (let index = 0; index < 33; index++) {
        await request("retro/memory/unsubscribe", { subscriber: `live-${index}` });
    }

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

    // A frozen byte is written at once and held while the machine runs; ROM cannot be frozen.
    at = "freezing a byte";
    const frozen = await request("retro/memory/freeze", { memoryReference: "0x0000", freeze: [{ offset: 0x5000, value: 0x55 }] });
    assert.deepEqual(frozen.frozen, [{ address: 0x5000, value: 0x55 }]);
    assert.equal((await read("0x5000", 1)).bytes[0], 0x55);
    await rejects(request("retro/memory/freeze", { memoryReference: "0x0000", freeze: [{ offset: 0, value: 0 }] }), /not RAM now/);
    // A request with any byte that cannot be frozen freezes none of them, and writes nothing.
    const before = (await read("0x5001", 1)).bytes[0];
    await rejects(request("retro/memory/freeze", { memoryReference: "0x0000", freeze: [{ offset: 0x5001, value: before ^ 0xFF }, { offset: 0, value: 0 }] }), /not RAM now/);
    assert.equal((await read("0x5001", 1)).bytes[0], before, "the RAM byte is not written");
    assert.deepEqual((await request("retro/memory/freeze", { memoryReference: "0x0000" })).frozen, [{ address: 0x5000, value: 0x55 }], "nor frozen");
    // A value a byte cannot hold, or a byte with no offset, is refused rather than written as something else.
    await rejects(request("retro/memory/freeze", { memoryReference: "0x0000", freeze: [{ offset: 0x5001, value: 0x12C }] }), /0 to 255, not 300/);
    await rejects(request("retro/memory/freeze", { memoryReference: "0x0000", freeze: [{ offset: 0x5001, value: -1 }] }), /0 to 255, not -1/);
    await rejects(request("retro/memory/freeze", { memoryReference: "0x5001", freeze: [{ value: 1 }] }), /needs an offset/);
    assert.equal((await read("0x5001", 1)).bytes[0], before, "none of them is written");
    await write("0x5000", [0x11]);

    // Retrocore Memory watches a byte as the expression [$5000], which says when it is frozen and which a data
    // breakpoint can watch.
    at = "watching a frozen byte";
    assert.equal((await request("evaluate", { expression: "[$5000]", context: "watch" })).result, "$11 (17) (frozen)");
    assert.equal((await request("evaluate", { expression: "[$4FFF].w", context: "watch" })).result.endsWith("(frozen)"), true);
    assert.equal((await request("evaluate", { expression: "[$5001]", context: "watch" })).result.endsWith("(frozen)"), false);
    // The brackets' address reads as the evaluator reads it: bare digits are decimal, so [20480] is $5000.
    assert.equal((await request("evaluate", { expression: "[20480]", context: "watch" })).result.endsWith("(frozen)"), true);
    assert.equal((await request("evaluate", { expression: "[5000]", context: "watch" })).result.endsWith("(frozen)"), false);
    assert.equal((await request("dataBreakpointInfo", { name: "[$5000]" })).dataId, "mem:5000:1");

    at = "running with a frozen byte";
    drop("stopped");
    await request("continue", { threadId: 1 });
    await new Promise(resolve => setTimeout(resolve, 200));
    await request("pause", { threadId: 1 });
    await event("stopped");
    assert.equal((await read("0x5000", 1)).bytes[0], 0x55, "the run wrote the frozen value back");
    // A frozen byte goes back as soon as the instruction that writes it ends, so the program never reads a value of
    // its own there: LD ($5000),A then LD A,($5000) reads the frozen $55, which LD ($5001),A copies out.
    at = "an instruction writing a frozen byte";
    const stoppedAt = (await request("stackTrace", { threadId: 1 })).stackFrames[0].instructionPointerReference;
    assert.ok(Number(stoppedAt) >= 0x7000 && Number(stoppedAt) < 0x8000, `stopped in the program's RAM, at ${stoppedAt}`);
    await write(stoppedAt, [0x3E, 0x05, 0x32, 0x00, 0x50, 0x3A, 0x00, 0x50, 0x32, 0x01, 0x50, 0x18, 0xFE]);
    await write("0x5001", [0x00]);
    for (let step = 0; step < 4; step++) {
        drop("stopped");
        await request("next", { threadId: 1, granularity: "instruction" });
        await event("stopped");
    }
    assert.deepEqual([(await read("0x5000", 1)).bytes[0], (await read("0x5001", 1)).bytes[0]], [0x55, 0x55]);
    assert.deepEqual((await request("retro/memory/freeze", { memoryReference: "0x0000", thaw: [0x5000] })).frozen, []);
    assert.equal((await request("evaluate", { expression: "[$5000]", context: "watch" })).result.endsWith("(frozen)"), false);
    console.log("Memory DAP integration passed on the Model I.");

    // A byte frozen in the CPU's memory stays in the RAM it was frozen in: frozen at $D000 with the language card's
    // bank 2 mapped, it is not written into bank 1 when the program maps that instead. The IIe runs ROMs built from
    // the SDK's sources, and a short program switches the card.
    at = "a frozen byte stays in its language-card bank";
    const switching = join(root, "artifacts", "memory-tests", "language-card.asm");
    mkdirSync(join(root, "artifacts", "memory-tests"), { recursive: true });
    const program = [
        ".cpu Mos6502",
        "BANK2:",
        "    LDA $C083",
        "    LDA $C083",
        "    LDA #$11",
        "    STA $D000",
        "FROZEN:",
        "    NOP",
        "    LDA $C08B",
        "    LDA $C08B",
        "    LDA #$22",
        "    STA $D000",
        "SWITCHED:",
        "    JMP SWITCHED",
        "TABLE:",
        "    .byte $01, $02, $03, $04, $05, $06, $07, $08, $09, $0A, $0B",
        ".proc Main",
        "@1loop:",
        "    BNE @1loop",
        "    RTS",
        ".endproc",
    ];
    writeFileSync(switching, program.join("\n") + "\n");
    const hintsFile = join(root, "artifacts", "memory-tests", "language-card.hints.json");
    rmSync(hintsFile, { force: true });
    await request("launch", { machine: "apple2", model: "iie-enhanced", source: switching, loadAddress: 0x0300, stopOnEntry: true, speed: "max" });
    await request("setBreakpoints", { source: { path: switching }, breakpoints: [{ line: program.indexOf("FROZEN:") + 2 }] });
    await request("configurationDone");
    assert.equal((await event("stopped")).reason, "entry");
    await request("continue", { threadId: 1 });
    assert.equal((await event("stopped")).reason, "breakpoint");
    assert.equal((await read("main:0xD000", 1)).bytes[0], 0x11, "bank 2 holds what the program wrote");

    // The Monitor's equates name the bytes its instructions address, as STA CH and (BASL),Y do, but not a value it
    // only compares with, as CMP #CR does.
    at = "naming RAM by the Monitor's equates";
    const named = new Map((await request("retro/memory/labels", { memoryReference: "0x0000" })).labels.map(label => [label.address, label.name]));
    assert.equal(named.get(0x24), "CH");
    assert.equal(named.get(0x28), "BASL");
    assert.equal(named.get(0xC000), "KBD");
    // $0D is the firmware's RamTest::R6H, which it stores to, but never CR, which is only compared with.
    assert.notEqual(named.get(0x0D), "CR");

    // The listing starts at the statement around the address asked for, lists the program's lines with their
    // labels and source, names an operand's label, lists data as .byte, and names the Monitor's code by its labels.
    at = "listing the program";
    const listing = async (address, count, starts) => (await request("retro/memory/listing", { memoryReference: "0x0000", address, count, starts })).lines;
    let lines = await listing(0x0301, 40);
    assert.equal(lines[0].address, 0x0300, "the statement around $0301 starts at $0300");
    assert.deepEqual([lines[0].text, lines[0].kind, lines[0].label, lines[0].line], ["LDA LCBANK2", "code", "BANK2", program.indexOf("BANK2:") + 2]);
    assert.equal(lines[0].path, switching);
    assert.equal(lines[0].target, 0xC083, "the CPU's view goes to the soft switch");
    // A view of main RAM has no soft switches, so the operand goes nowhere from it.
    const mainLines = (await request("retro/memory/listing", { memoryReference: "main:0x0000", address: 0x0300, count: 3 })).lines;
    assert.deepEqual([mainLines[0].text, mainLines[0].target], ["LDA $C083", null], JSON.stringify(mainLines[0]));
    const loop = lines.find(line => line.text.startsWith("JMP"));
    assert.equal(loop.text, "JMP SWITCHED", "an operand's label names it");
    assert.equal(loop.target, loop.address, "and the line says where it goes");
    // A statement of data lists eight bytes a line, all of it data.
    const table = lines.find(line => line.label === "TABLE");
    assert.deepEqual([table.text, table.kind, table.size], [".byte $01, $02, $03, $04, $05, $06, $07, $08", "data", 8]);
    const rest = lines.find(line => line.address === table.address + 8);
    assert.deepEqual([rest.text, rest.kind, rest.size], [".byte $09, $0A, $0B", "data", 3]);
    // Decode from here in data starts an instruction there, the data before it ending early.
    lines = await listing(table.address, 11, [table.address + 2]);
    assert.deepEqual(lines.slice(0, 2).map(line => [line.address, line.kind, line.size]),
        [[table.address, "data", 2], [table.address + 2, "code", 1]], "the 65C02 runs $03 as a one-byte NOP");
    // The language card's RAM is mapped over the Monitor now, so its code lists from the ROM's bank.
    lines = (await request("retro/memory/listing", { memoryReference: "rom:0x0000", address: 0xFDED, count: 3 })).lines;
    assert.deepEqual([lines[0].address, lines[0].label, lines[0].kind], [0xFDED, "COUT", "code"]);
    assert.equal((await listing(0xFDED, 3))[0].kind, "unknown", "RAM is mapped there, which no source describes");
    // Decode from here starts where it is told, inside the instruction at $0300.
    lines = await listing(0x0301, 2, [0x0301]);
    assert.deepEqual([lines[0].address, lines[0].kind], [0x0301, "code"]);
    // A start from Decode from here holds farther back than the listing looks for a statement: in a run of
    // three-byte LDA $ADAD, a start at $6001 puts an instruction at $602E, which covers $6030.
    await write("0x6000", Array(96).fill(0xAD));
    assert.equal((await listing(0x6030, 6))[0].address, 0x6030, "nothing known starts an instruction near $6030");
    lines = await listing(0x6030, 6, [0x6001]);
    assert.deepEqual([lines[0].address, lines[0].size], [0x602E, 3], JSON.stringify(lines));
    // Analysis guesses at what no source describes, from a start: JSR $6110 and RTS, and at the subroutine it calls,
    // LDA #$01 and RTS, are code; the text between, which nothing reaches, is not guessed.
    at = "guessing at code no source describes";
    await write("0x6100", [0x20, 0x10, 0x61, 0x60, 0xC8, 0xC5, 0xCC, 0xCC, 0xCF, 0, 0, 0, 0, 0, 0, 0, 0xA9, 0x01, 0x60]);
    lines = await listing(0x6100, 0x13, [0x6100]);
    const at6 = address => lines.find(line => line.address === address);
    assert.deepEqual([at6(0x6100).text, at6(0x6100).guess], ["JSR $6110", false], "a start from Decode from here is the user's, not a guess");
    assert.deepEqual([at6(0x6103).text, at6(0x6103).kind, at6(0x6103).guess], ["RTS", "code", true]);
    assert.deepEqual([at6(0x6104).kind, at6(0x6104).guess], ["unknown", false]);
    assert.deepEqual([at6(0x6110).text, at6(0x6110).kind, at6(0x6110).guess], ["LDA #$01", "code", true], JSON.stringify(lines));
    // JMP ($6150) makes its pointer data and where it points code.
    await write("0x6140", [0x6C, 0x50, 0x61]);
    await write("0x6150", [0x60, 0x61]);
    await write("0x6160", [0x60]);
    lines = await listing(0x6140, 0x21, [0x6140]);
    assert.deepEqual([at6(0x6150).text, at6(0x6150).kind, at6(0x6150).guess], [".byte $60, $61", "data", true], JSON.stringify(lines));
    assert.deepEqual([at6(0x6160).text, at6(0x6160).kind, at6(0x6160).guess], ["RTS", "code", true]);
    // A start is the user's: a jump analysis follows into its instruction does not split it.
    await write("0x6200", [0xA9, 0x60, 0x60]);
    await write("0x6210", [0x4C, 0x01, 0x62]);
    lines = await listing(0x6200, 0x13, [0x6200, 0x6210]);
    assert.deepEqual([at6(0x6200).text, at6(0x6200).size], ["LDA #$60", 2], JSON.stringify(lines));
    // Analysis keeps out of what the sources make data: a jump into TABLE does not run through it as code, so the
    // bytes after it are not guessed.
    const tableStart = table.address, tableEnd = table.address + 11;
    await write("0x6220", [0x4C, tableStart & 0xFF, tableStart >> 8]);
    lines = await listing(tableEnd, 4, [0x6220]);
    assert.ok(lines.every(line => !line.guess), JSON.stringify(lines));
    // A pointer that cannot be read is not followed: main RAM has no $C100, so JMP ($C100) there guesses nothing at
    // $0000, where unreadable bytes read as zero would point.
    await write("main:0x6230", [0x6C, 0x00, 0xC1]);
    lines = (await request("retro/memory/listing", { memoryReference: "main:0x0000", address: 0x0000, count: 4, starts: [0x6230] })).lines;
    assert.ok(lines.every(line => !line.guess), JSON.stringify(lines));
    const mainListing = async (address, count, starts) =>
        (await request("retro/memory/listing", { memoryReference: "main:0x0000", address, count, starts })).lines;
    // A call across main RAM's gap at $C000 still reaches what it calls: JSR $D100 from $6300 guesses $D100.
    await write("main:0x6300", [0x20, 0x00, 0xD1, 0x60]);
    await write("main:0xD100", [0xA9, 0x05, 0x60]);
    lines = await mainListing(0xD100, 3, [0x6300]);
    assert.deepEqual([lines[0].text, lines[0].kind, lines[0].guess], ["LDA #$05", "code", true], JSON.stringify(lines));
    // A bank of RAM still follows an indirect jump's pointer, though it holds no CPU vectors.
    await write("main:0x6340", [0x6C, 0x50, 0x63]);
    await write("main:0x6350", [0x60, 0x63]);
    await write("main:0x6360", [0x60]);
    lines = await mainListing(0x6340, 0x21, [0x6340]);
    assert.deepEqual([at6(0x6350).kind, at6(0x6350).guess, at6(0x6360).text, at6(0x6360).guess], ["data", true, "RTS", true], JSON.stringify(lines));
    // A jump through a pointer across the gap is followed: JMP ($D200) from $6380, which points at $6390.
    await write("main:0x6380", [0x6C, 0x00, 0xD2]);
    await write("main:0xD200", [0x90, 0x63]);
    await write("main:0x6390", [0x60]);
    lines = await mainListing(0x6390, 1, [0x6380]);
    assert.deepEqual([lines[0].text, lines[0].guess], ["RTS", true], JSON.stringify(lines));
    lines = await mainListing(0xD200, 2, [0x6380]);
    assert.deepEqual([lines[0].kind, lines[0].guess, lines[0].size], ["data", true, 2], JSON.stringify(lines));
    // An entry that the pointer then makes data, such as the next instruction after a NOP at $D1FF, is dropped
    // rather than failing the whole run: the call from $6300 still guesses $D100 there.
    await write("main:0xD1FF", [0xEA]);
    lines = await mainListing(0xD100, 2, [0x6300, 0x6380, 0xD1FF]);
    assert.deepEqual([lines[0].text, lines[0].guess], ["LDA #$05", true], JSON.stringify(lines));
    // A pointer the sources already make data is read: JMP (TABLE) from $D300 goes where TABLE's $01, $02 point.
    await write("main:0xD300", [0x6C, table.address & 0xFF, table.address >> 8]);
    lines = await mainListing(0x0201, 1, [0xD300]);
    assert.deepEqual([lines[0].address, lines[0].kind, lines[0].guess], [0x0201, "code", true], JSON.stringify(lines));
    // Guessed data starts a line, so a byte before it does not decode through it: $AD would be LDA $6420.
    await write("main:0x6400", [0x6C, 0x10, 0x64]);
    await write("main:0x640F", [0xAD, 0x20, 0x64]);
    await write("main:0x6420", [0x60]);
    lines = await mainListing(0x640F, 3, [0x6400]);
    assert.deepEqual(lines.map(line => [line.address, line.kind]), [[0x640F, "unknown"], [0x6410, "data"]], JSON.stringify(lines));
    // Marks, names and comments go in the hints file beside the source, and show at once: a name wins over the
    // sources' labels, data marked lists as data, code marked starts an instruction, and a comment follows its line.
    at = "marking memory";
    const mark = args => request("retro/memory/mark", { memoryReference: "0x0000", ...args });
    assert.equal((await mark({ address: 0x6500, name: "MYTABLE" })).path, hintsFile);
    await mark({ address: 0xFDED, name: "MYCOUT" });
    await write("0x6500", [0xA9, 0x01, 0x60, 0xEA]);
    await mark({ address: 0x6500, count: 3, kind: "data" });
    await mark({ address: 0x6503, kind: "code" });
    await mark({ address: 0x6503, comment: "Marked as code" });
    const marked = new Map((await request("retro/memory/labels", { memoryReference: "0x0000" })).labels.map(label => [label.address, label.name]));
    assert.deepEqual([marked.get(0x6500), marked.get(0xFDED)], ["MYTABLE", "MYCOUT"]);
    lines = await listing(0x6500, 4);
    assert.deepEqual(lines.map(line => [line.address, line.kind, line.guess, line.label, line.comment]),
        [[0x6500, "data", false, "MYTABLE", null], [0x6503, "code", false, null, "Marked as code"]], JSON.stringify(lines));
    // A bank's marks keep its name.
    await request("retro/memory/mark", { memoryReference: "aux:0x0000", address: 0x0400, name: "AUXTEXT" });
    const hints = JSON.parse(readFileSync(hintsFile, "utf8"));
    assert.deepEqual(hints.names, { "$6500": "MYTABLE", "$FDED": "MYCOUT", "aux:$0400": "AUXTEXT" });
    assert.deepEqual([hints.entries, hints.data, hints.comments], [["$6503"], [{ start: "$6500", length: 3 }], { "$6503": "Marked as code" }]);
    // The hints file's name and comment at an address, whatever is listed.
    assert.deepEqual(await request("retro/memory/note", { memoryReference: "0x0000", address: 0x6503 }), { name: null, comment: "Marked as code" });
    // Decode from here starts give way to a mark over their instructions, except a code mark's own.
    const startsLeft = await request("retro/memory/starts", { memoryReference: "0x0000", address: 0x6501, count: 1, starts: [0x6500, 0x6502, 0x6503] });
    assert.deepEqual(startsLeft.starts, [0x6502, 0x6503]);
    // A comment inside a data line starts one, and one inside an instruction shows on it.
    await mark({ address: 0x6501, comment: "Inside" });
    lines = await listing(0x6500, 3);
    assert.deepEqual(lines.map(line => [line.address, line.size, line.comment]), [[0x6500, 1, null], [0x6501, 2, "Inside"]], JSON.stringify(lines));
    await mark({ address: 0x6501, comment: "" });
    // Data marked wins over a source's instruction.
    await mark({ address: 0x0300, count: 3, kind: "data" });
    lines = await listing(0x0300, 3);
    assert.deepEqual([lines[0].kind, lines[0].guess, lines[0].text.startsWith(".byte")], ["data", false, true], JSON.stringify(lines));
    await mark({ address: 0x0300, count: 3, kind: "clear" });
    // A name the disassembler would refuse is refused, as is one another address has.
    await rejects(mark({ address: 0x6600, name: "my table" }), /not a name/);
    await rejects(mark({ address: 0x6600, name: "MYTABLE" }), /already named/);
    // A mark is made to the file as it is now, keeping what was put there since.
    writeFileSync(hintsFile, JSON.stringify({ ...JSON.parse(readFileSync(hintsFile, "utf8")), noReturn: ["$6600"] }));
    await mark({ address: 0x6600, name: "LATER" });
    assert.deepEqual(JSON.parse(readFileSync(hintsFile, "utf8")).noReturn, ["$6600"]);
    // A file that cannot be read is left alone.
    const kept = readFileSync(hintsFile, "utf8");
    writeFileSync(hintsFile, "{ not json");
    await rejects(mark({ address: 0x6601, name: "BROKEN" }), /could not be read/);
    assert.equal(readFileSync(hintsFile, "utf8"), "{ not json");
    writeFileSync(hintsFile, kept);
    // Unmarking and an empty name take them away.
    await mark({ address: 0x6500, count: 4, kind: "clear" });
    await mark({ address: 0xFDED, name: "" });
    const cleared = JSON.parse(readFileSync(hintsFile, "utf8"));
    assert.deepEqual([cleared.entries, cleared.data, cleared.names["$FDED"]], [undefined, undefined, undefined]);
    // A marked instruction is one line whatever label starts inside it, even listing from there.
    await write("0x6500", [0xA9, 0x01]);
    await mark({ address: 0x6500, kind: "code" });
    await mark({ address: 0x6501, name: "INSIDE" });
    lines = await listing(0x6501, 1);
    assert.deepEqual([lines[0].address, lines[0].text], [0x6500, "LDA #$01"], JSON.stringify(lines));
    // The hints file's names are symbols in expressions, a bank's in that bank.
    at = "hint names in expressions";
    assert.equal((await request("evaluate", { expression: "INSIDE", context: "retrocore" })).memoryReference, "0x6501");
    assert.equal((await request("evaluate", { expression: "INSIDE+1" })).result.startsWith("$6502"), true);
    assert.equal((await request("evaluate", { expression: "aux:AUXTEXT", context: "retrocore" })).memoryReference, "aux:0x0400");
    assert.equal((await request("evaluate", { expression: "[aux:AUXTEXT]" })).result, (await request("evaluate", { expression: "[aux:$0400]" })).result);
    await rejects(request("evaluate", { expression: "AUXTEXT" }), /Unknown label/);
    await mark({ address: 0x6502, name: "CAFÉ" });
    assert.equal((await request("evaluate", { expression: "CAFÉ", context: "retrocore" })).memoryReference, "0x6502");
    await mark({ address: 0x6502, name: "" });
    // Find by instruction: ? is any character and * any run, and an operand matches by number or by label.
    at = "finding an instruction";
    await write("0x6510", [0x20, 0x01, 0x65]);
    const findFrom = (pattern, from, backward = false) =>
        request("retro/memory/find", { memoryReference: "0x0000", pattern, from, backward });
    assert.deepEqual(await findFrom("lda  #$0?", 0x6500), { address: 0x6500, size: 2, text: "LDA #$01" });
    assert.deepEqual(await findFrom("JSR INSIDE", 0x6500), { address: 0x6510, size: 3, text: "JSR INSIDE" });
    assert.equal((await findFrom("JSR $65*", 0x6500)).address, 0x6510);
    assert.equal((await findFrom("LDA #$01", 0x650F, true)).address, 0x6500);
    await rejects(findFrom("  ", 0), /instruction/);
    // A listing line gives the breakpoints that stop at its address, a bank's only in that bank's listing.
    // The inspector: the region an address is in and where in it, the map, the label and its documentation, the
    // source line and the BASIC's floats.
    at = "inspecting an address";
    const inspect = async (address, memoryReference = "0x0000") => request("retro/memory/inspect", { memoryReference, address });
    let inspected = await inspect(0x0528);
    assert.deepEqual([inspected.region, inspected.kind, inspected.detail], ["Text page 1", "video", "row 10, column 0"]);
    assert.equal((await inspect(0x0478)).detail, "screen hole");
    assert.deepEqual([(await inspect(0x2D2D)).region, (await inspect(0x2D2D)).detail], ["Hi-res page 1", "line 83, byte 5 (dots 35-41)"]);
    inspected = await inspect(0x0024);
    assert.deepEqual([inspected.region, inspected.label, inspected.offset], ["Zero page", "CH", 0]);
    assert.ok(inspected.summary?.length > 0, JSON.stringify(inspected));
    assert.match(inspected.mapped, /^Reads and writes /);
    inspected = await inspect(0x0301);
    assert.deepEqual([inspected.label, inspected.offset, inspected.path, inspected.line], ["BANK2", 1, switching, program.indexOf("BANK2:") + 2]);
    assert.match((await inspect(0x0400, "aux:0x0000")).mapped, /^Not mapped now: the CPU reads /);
    await write("0x6600", [0x81, 0x00, 0x00, 0x00, 0x00]);
    assert.deepEqual((await inspect(0x6600)).values, [{ label: "Float, 5 bytes", value: "1" }]);
    // A bank's gap holds no number, nor does a float that runs into it.
    assert.deepEqual((await inspect(0xC000, "main:0x0000")).values, []);
    assert.deepEqual((await inspect(0xBFFE, "main:0x0000")).values, []);
    // The instruction where code starts, with its cycles, run on a 65C02 of its own, and the flags it changes; none
    // inside one, nor in I/O or a table.
    at = "the instruction at the cursor";
    assert.deepEqual((await inspect(0x0300)).instruction,
        { text: "LDA LCBANK2", size: 3, cycles: 4, cyclesTaken: null, flags: "N Z", summary: "Loads A from memory." });
    assert.equal((await inspect(0x0317)).instruction.cycles, 3);
    for (const address of [0x0301, 0xC000, 0x0024, 0x031A]) {
        assert.equal((await inspect(address)).instruction, null, "no instruction at $" + address.toString(16));
    }
    // A branch takes a cycle more when taken.
    await write("0x6520", [0xD0, 0x02]);
    await mark({ address: 0x6520, kind: "code" });
    assert.deepEqual([(await inspect(0x6520)).instruction.cycles, (await inspect(0x6520)).instruction.cyclesTaken], [2, 3]);
    await mark({ address: 0x6520, count: 2, kind: "clear" });
    // No instruction runs over a Decode from here start, as the listing has it.
    await write("0x6530", [0xAD, 0x00, 0x03]);
    const at6530 = starts => request("retro/memory/inspect", { memoryReference: "0x0000", address: 0x6530, starts });
    assert.equal((await at6530([0x6530])).instruction.text, "LDA BANK2");
    assert.equal((await at6530([0x6530, 0x6531])).instruction, null);
    // Nor are references counted from it; but from $6530 alone, LDA $0300 reads BANK2.
    const readers = async starts => (await request("retro/memory/inspect", { memoryReference: "0x0000", address: 0x0300, starts }))
        .references.filter(reference => reference.address === 0x6530);
    assert.equal((await readers([0x6530])).length, 1);
    assert.equal((await readers([0x6530, 0x6531])).length, 0);
    // A start the listing keeps that overlaps an earlier one, which analysis skips, still reads what it names.
    await write("0x6530", [0x4C, 0xAD, 0x00, 0x03]);
    assert.deepEqual((await readers([0x6530, 0x6531])).length, 0);
    const overlapped = (await request("retro/memory/inspect", { memoryReference: "0x0000", address: 0x0300, starts: [0x6530, 0x6531] }))
        .references.filter(reference => reference.address === 0x6531);
    assert.deepEqual(overlapped.map(reference => [reference.text, reference.kind]), [["LDA BANK2", "reads"]]);
    // An overlapping BBR0 $10 both reads $10 and branches.
    await write("0x654F", [0x4C, 0x0F, 0x10, 0x00]);
    const bbr = async address => (await request("retro/memory/inspect", { memoryReference: "0x0000", address, starts: [0x654F, 0x6550] }))
        .references.filter(reference => reference.address === 0x6550).map(reference => reference.kind);
    assert.deepEqual([await bbr(0x0010), await bbr(0x6553)], [["reads"], ["branches"]]);
    // Immediate BIT changes only Z.
    await write("0x6540", [0x89, 0x80]);
    assert.equal((await request("retro/memory/inspect", { memoryReference: "0x0000", address: 0x6540, starts: [0x6540] })).instruction.flags, "Z");
    await write("0x6530", [0xAD, 0x00, 0x03, 0x00]);
    // A start inside a marked instruction the listing rejects for running over it still shows its own.
    await mark({ address: 0x6530, kind: "code" });
    const inside = await request("retro/memory/inspect", { memoryReference: "0x0000", address: 0x6531, starts: [0x6531] });
    assert.equal(inside.instruction?.text, "BRK", JSON.stringify(inside.instruction));
    await mark({ address: 0x6530, count: 3, kind: "clear" });
    // The code that writes, reads or jumps to an address, in the program and the firmware.
    at = "references to an address";
    inspected = await inspect(0xD000);
    assert.deepEqual([inspected.referenceCount, inspected.references], [2, [
        { address: 0x0308, text: "STA $D000", label: "BANK2+8", kind: "writes" },
        { address: 0x0314, text: "STA $D000", label: "FROZEN+9", kind: "writes" }
    ]]);
    assert.deepEqual((await inspect(0x0317)).references, [{ address: 0x0317, text: "JMP SWITCHED", label: "SWITCHED", kind: "jumps" }]);
    assert.ok((await inspect(0xC013)).references.some(reference => reference.text === "LDA RDRAMRD" && reference.kind === "reads"));
    // A soft switch's bits, from what its documentation says of them.
    at = "named bits";
    assert.deepEqual((await inspect(0xC013)).bits, [{ bit: 7, name: null, meaning: "whether RAMRD is on" }]);
    assert.equal((await inspect(0x0024)).bits, null, "CH says nothing of its bits");
    // The IIe's KBDSTRB reports in bit 7 whether a key is down: its own bit, unlike "clears bit 7 of KBD".
    assert.deepEqual((await inspect(0xC010)).bits, [{ bit: 7, name: null, meaning: "whether a key is down" }]);
    // Assembling in place: one line at an address, with the session's labels, written by the editor, not here.
    at = "assembling a line";
    const assemble = line => request("retro/memory/assemble", { memoryReference: "0x0000", address: 0x6560, line });
    const unassembled = (await read("0x6560", 3)).bytes;
    assert.deepEqual(await assemble("LDA KBD"), { bytes: [0xAD, 0x00, 0xC0], text: "LDA KBD", nop: [0xEA] });
    assert.deepEqual((await assemble("STA CH")).bytes, [0x85, 0x24], "a zero-page label assembles to zero page");
    assert.deepEqual((await assemble("JSR COUT")).bytes, [0x20, 0xED, 0xFD]);
    assert.deepEqual((await assemble("LDA BANK2,X")).bytes, [0xBD, 0x00, 0x03]);
    assert.deepEqual((await assemble("BNE *+4")).bytes, [0xD0, 0x02]);
    // A scoped name stands in the line as an alias, as a constant cannot be called RamTest::R6H.
    assert.deepEqual((await assemble("STA RamTest::R6H")).bytes, [0x85, 0x0D]);
    // A name with a combining mark, as a decomposed é is, assembles as the assembler reads it.
    await mark({ address: 0x6600, name: "CAFÉ" });
    assert.deepEqual((await assemble("LDA CAFÉ")).bytes, [0xAD, 0x00, 0x66]);
    await mark({ address: 0x6600, name: "" });
    // A scope's cheap local, whose name may start with a digit after @.
    assert.deepEqual((await request("retro/memory/assemble", { memoryReference: "0x0000", address: 0x0325, line: "BNE Main::@1loop" })).bytes, [0xD0, 0xFE]);
    // The outermost scope's name, and a dotted operator after a name.
    assert.deepEqual([(await assemble("JSR ::COUT")).bytes, (await assemble("LDA #(CH.mod 16)")).bytes], [[0x20, 0xED, 0xFD], [0xA9, 0x04]]);
    // An alias is never a name the line already has.
    await mark({ address: 0x6600, name: "__RETROCORE0" });
    assert.deepEqual((await assemble(".word RamTest::R6H,__RETROCORE0")).bytes, [0x0D, 0x00, 0x00, 0x66]);
    await mark({ address: 0x6600, name: "" });
    // Quoted text stays as typed; a width prefix's name is still the session's.
    assert.deepEqual((await assemble('.byte "RamTest::R6H"')).bytes, Array.from(Buffer.from("RamTest::R6H", "ascii")));
    assert.deepEqual([(await assemble("STA z:CH")).bytes, (await assemble("LDA a:CH")).bytes], [[0x85, 0x24], [0xAD, 0x24, 0x00]]);
    // A label spelled as a register or condition is still the label where the register would not assemble.
    await mark({ address: 0x6600, name: "Z" });
    assert.deepEqual((await assemble("LDA Z")).bytes, [0xAD, 0x00, 0x66]);
    assert.deepEqual((await assemble("LDA $10,X")).bytes, [0xB5, 0x10]);
    await mark({ address: 0x6600, name: "" });
    await rejects(assemble("FOO"), /Unknown instruction/);
    await rejects(assemble("LDA NOSUCH"), /NOSUCH/);
    await rejects(assemble("  "), /Type an instruction/);
    assert.deepEqual((await read("0x6560", 3)).bytes, unassembled, "assembling writes nothing");
    // Each label's kind, and the size of a label's data, which the editor shades.
    at = "the kinds and data sizes of labels";
    const labelled = new Map((await request("retro/memory/labels", { memoryReference: "0x0000" })).labels.map(label => [label.name, label]));
    assert.deepEqual([labelled.get("TABLE").kind, labelled.get("TABLE").size], ["data", 11], JSON.stringify(labelled.get("TABLE")));
    assert.deepEqual([labelled.get("BANK2").kind, labelled.get("BANK2").size], ["code", null]);
    assert.equal(labelled.get("CH").kind, "constant", JSON.stringify(labelled.get("CH")));
    // A constant names main RAM's byte, which the CPU reads, not auxiliary RAM's at the same address.
    assert.equal(labelled.get("BRKV")?.address, 0x03F0);
    const auxNames = (await request("retro/memory/labels", { memoryReference: "aux:0x0000" })).labels;
    assert.equal(auxNames.find(label => label.address === 0x03F0), undefined, JSON.stringify(auxNames.filter(label => label.address < 0x0400)));
    // Saving as assembly: the program as native source that assembles back to its bytes, by the session's labels.
    at = "saving memory as assembly";
    const exported = await request("retro/memory/export", { memoryReference: "0x0000", address: 0x0300, count: 0x28 });
    assert.equal(exported.exact, true, exported.source);
    for (const expected of ["BANK2:", "SWITCHED:", "JMP SWITCHED", "TABLE:", ".byte $01, $02", "RTS", ".org $0300"]) {
        assert.ok(exported.source.includes(expected), `${expected} in:\n${exported.source}`);
    }
    assert.ok(exported.source.startsWith("; Memory: $0300-$0327, 40 bytes, saved from Retrocore Memory."), exported.source);
    await rejects(request("retro/memory/export", { memoryReference: "0x0000", address: 0xFFFF, count: 2 }), /\$0000-\$FFFF/);
    // A count too large for 64K is refused before it is added to the address, which it would otherwise overflow.
    await rejects(request("retro/memory/export", { memoryReference: "0x0000", address: 0x8000, count: 0x7FFF9000 }), /\$0000-\$FFFF/);
    // A Decode from here start in data saves the whole instruction the listing shows there: TABLE's $01, $02 as ORA.
    const decoded = await request("retro/memory/export", { memoryReference: "0x0000", address: 0x031A, count: 4, starts: [0x031A] });
    assert.equal(decoded.exact, true, decoded.source);
    assert.match(decoded.source, /^\s+ORA /m, decoded.source);
    // Find by value: a number's bytes as AppleSoft stores it, rounded as BASIC rounds it.
    at = "a number as the BASIC's floats";
    const numbers = async value => (await request("retro/memory/numbers", { memoryReference: "0x0000", value })).formats;
    assert.deepEqual(await numbers("1000"), [{ label: "Float, 5 bytes", bytes: [0x8A, 0x7A, 0, 0, 0] }]);
    assert.deepEqual(await numbers("-.5"), [{ label: "Float, 5 bytes", bytes: [0x80, 0x80, 0, 0, 0] }]);
    assert.deepEqual(await numbers("1E40"), [], "too large for AppleSoft");
    await rejects(request("retro/memory/numbers", { memoryReference: "0x0000", value: "TEN" }), /not a number/);
    // The map: the regions, and runs of addresses that read the same part of the machine now, covering the space.
    at = "the memory map";
    const memoryMap = async memoryReference => request("retro/memory/map", { memoryReference });
    let mapped = await memoryMap("0x0000");
    assert.ok(mapped.regions.some(region => region.name === "Text page 1" && region.start === 0x0400 && region.length === 0x400));
    assert.deepEqual([mapped.areas[0].start, mapped.areas.at(-1).start + mapped.areas.at(-1).length], [0, 0x10000]);
    mapped.areas.slice(1).forEach((area, index) => assert.equal(area.start, mapped.areas[index].start + mapped.areas[index].length));
    const areaAt = (areas, address) => areas.find(area => address >= area.start && address < area.start + area.length);
    assert.deepEqual([areaAt(mapped.areas, 0x0400).name, areaAt(mapped.areas, 0x0400).kind], ["main RAM", "ram"]);
    assert.equal(areaAt(mapped.areas, 0xC000).kind, "io");
    // In auxiliary RAM's editor, what the CPU does not read now is dimmed, and the bank's gap is none.
    mapped = await memoryMap("aux:0x0000");
    assert.equal(areaAt(mapped.areas, 0x0400).mapped, false);
    assert.equal(areaAt(mapped.areas, 0xC000).kind, "none");
    // Its runs split at the parts one switch puts in the CPU's view, each named by that switch, with whether the CPU
    // reads and writes it now: at power-on, neither.
    const zeroPage = areaAt(mapped.areas, 0x0000);
    assert.deepEqual([zeroPage.start, zeroPage.length, zeroPage.mapped, zeroPage.written], [0x0000, 0x0200, false, false]);
    assert.equal(zeroPage.name, "Alternate zero page and stack (ALTZP): the CPU reads main RAM here now");
    assert.match(areaAt(mapped.areas, 0x0400).name, /^Text page 1 \(80STORE with PAGE2, else RAMRD and RAMWRT\): /);
    assert.match(areaAt(mapped.areas, 0x0800).name, /^RAM from \$0200 \(RAMRD and RAMWRT\): /);
    assert.match(areaAt(mapped.areas, 0xD000).name, /^Alternate language card bank 2 \(ALTZP and the language card's switches\): /);
    // A read-only bank is never written, though the CPU's writes there go to its area's address.
    const romArea = areaAt((await memoryMap("rom:0x0000")).areas, 0xE000);
    assert.equal(romArea.written, false, JSON.stringify(romArea));
    at = "breakpoints in the listing";
    const gutter = (await request("setFunctionBreakpoints", { breakpoints: [{ name: "$6500" }, { name: "aux:$6510" }] })).breakpoints;
    lines = await listing(0x6500, 2);
    assert.deepEqual(lines[0].breakpoints, [gutter[0].id], JSON.stringify(lines));
    // The extension asks for one byte's line, started there, to know what stops at an address it toggles.
    lines = await listing(0x6500, 1, [0x6500]);
    assert.deepEqual(lines.find(line => line.address === 0x6500)?.breakpoints, [gutter[0].id], JSON.stringify(lines));
    lines = (await request("retro/memory/listing", { memoryReference: "aux:0x0000", address: 0x6510, count: 1 })).lines;
    assert.deepEqual(lines[0].breakpoints, [gutter[1].id], JSON.stringify(lines));
    assert.equal((await listing(0x6510, 1))[0].breakpoints, null);
    // Naming an address binds the function breakpoints that use the name, and renaming moves them.
    drop("breakpoint");
    const [moving] = (await request("setFunctionBreakpoints", { breakpoints: [{ name: "MOVING" }] })).breakpoints;
    assert.equal(moving.verified, false);
    await mark({ address: 0x6520, name: "MOVING" });
    let changed = queued("breakpoint").map(body => body.breakpoint).filter(breakpoint => breakpoint.id === moving.id);
    assert.equal(changed.at(-1)?.verified, true, JSON.stringify(changed));
    assert.deepEqual((await listing(0x6520, 1))[0].breakpoints, [moving.id]);
    // A name moved in the file by hand moves its breakpoint at the next mark of any kind, which reads the file again.
    const edited = JSON.parse(readFileSync(hintsFile, "utf8"));
    delete edited.names["$6520"];
    edited.names["$6530"] = "MOVING";
    writeFileSync(hintsFile, JSON.stringify(edited, null, 2));
    await mark({ address: 0x6540, comment: "Moved by hand" });
    await mark({ address: 0x6540, comment: "" });
    assert.equal((await listing(0x6520, 1))[0].breakpoints, null);
    assert.deepEqual((await listing(0x6530, 1))[0].breakpoints, [moving.id]);
    await mark({ address: 0x6530, name: "" });
    changed = queued("breakpoint").map(body => body.breakpoint).filter(breakpoint => breakpoint.id === moving.id);
    assert.equal(changed.at(-1)?.verified, false, JSON.stringify(changed));
    await request("setFunctionBreakpoints", { breakpoints: [] });
    assert.equal((await listing(0x6500, 2))[0].breakpoints, null);
    at = "marking memory";
    await mark({ address: 0x6500, count: 2, kind: "clear" });
    await mark({ address: 0x6501, name: "" });
    // A name a source's label has elsewhere is refused.
    await rejects(mark({ address: 0x6600, name: "BANK2" }), /already named BANK2/);

    // A start whose instruction falls into the sources' data stops there, and the rest of the analysis still runs.
    lines = await listing(0x6110, 3, [table.address - 1, 0x6100]);
    assert.deepEqual([lines[0].text, lines[0].guess], ["LDA #$01", true], JSON.stringify(lines));
    // A bank's listing stops where the bank does: LDA's opcode in bank 1's last byte has no operand past $DFFF.
    const lastByte = (await read("bank1:0x0000", 1, 0xDFFF)).bytes[0];
    await write("bank1:0xDFFF", [0xAD]);
    lines = (await request("retro/memory/listing", { memoryReference: "bank1:0xD000", address: 0xDFFD, count: 6, starts: [0xDFFF] })).lines;
    await write("bank1:0xDFFF", [lastByte]);
    assert.deepEqual(lines.at(-1), { ...lines.at(-1), address: 0xDFFF, size: 1, text: ".byte $AD" }, JSON.stringify(lines));
    assert.equal((await request("retro/memory/listing", { memoryReference: "bank1:0xD000", address: 0xE000, count: 16 })).lines.length, 0,
        "nothing lists where the bank has no bytes");
    await request("retro/memory/freeze", { memoryReference: "0x0000", freeze: [{ offset: 0xD000, value: 0x55 }] });
    assert.equal((await read("main:0xD000", 1)).bytes[0], 0x55, "the freeze writes bank 2");
    assert.equal((await request("evaluate", { expression: "[$D000]", context: "watch" })).result.endsWith("(frozen)"), true, "a watch on bank 2 says it is frozen");
    const bank1 = (await read("bank1:0xD000", 1)).bytes[0];
    await request("setBreakpoints", { source: { path: switching }, breakpoints: [] });
    drop("stopped");
    await request("continue", { threadId: 1 });
    await new Promise(resolve => setTimeout(resolve, 300));
    await request("pause", { threadId: 1 });
    await event("stopped");
    assert.equal((await read("bank1:0xD000", 1)).bytes[0], 0x22, `bank 1 holds what the program wrote, not the frozen value (it held $${bank1.toString(16)})`);
    assert.equal((await read("main:0xD000", 1)).bytes[0], 0x55, "bank 2 keeps the frozen value");
    assert.deepEqual((await request("retro/memory/freeze", { memoryReference: "0x0000" })).frozen, [{ address: 0xD000, value: 0x55 }], "the byte stays frozen, waiting");
    // With bank 1 mapped, a watch on $D000 reads bank 1's byte, which is not the frozen one.
    const watched = (await request("evaluate", { expression: "[$D000]", context: "watch" })).result;
    assert.equal(watched.endsWith("(frozen)"), false, `a watch on bank 1 is not frozen: ${watched}`);
    console.log("Memory DAP integration passed on a language-card freeze.");

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
        assert.equal(bank("aux").writes, "nowhere");
        assert.match(await addressOf(1, "Registers", "S"), /^0x01[0-9A-F]{2}$/);

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
        const lead = await request("retro/memory/read", { memoryReference: "bank1:0x0000", offset: 0xCFFE, count: 4 });
        assert.deepEqual(lead.unreadable, [{ offset: 0, count: 2 }], "a range reads on past a bank's gap");
        assert.deepEqual([...Buffer.from(lead.data, "base64").subarray(2)], [...(await read("bank1:0xD000", 2)).bytes]);
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
