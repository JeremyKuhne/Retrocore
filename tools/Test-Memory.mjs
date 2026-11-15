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
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
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
    ];
    writeFileSync(switching, program.join("\n") + "\n");
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
