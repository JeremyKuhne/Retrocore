// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Breakpoint DAP integration on the Model I's Z80 sample, which needs nothing external: hit counts, hit count
// conditions, conditions, logpoints, function, instruction and data breakpoints, the disassembly they are set
// in, instruction stepping, and steps that stop at a breakpoint in the call they step over.

import { resolve, join } from "node:path";
import { readFileSync } from "node:fs";
import assert from "node:assert/strict";
import { startDap } from "./DapClient.mjs";

const root = resolve(import.meta.dirname, "..");
const sdkRoms = join(root, "src", "Retrocore.Machines.Trs80", "Roms");
const level2 = join(sdkRoms, "Level2.asm");
const hello = join(root, "sample", "trs80", "hello.asm");
const helloLines = readFileSync(hello, "utf8").split(/\r?\n/);
const lineOf = text => helloLines.findIndex(line => line.trim() === text) + 1;
const call = lineOf("CALL DISPLAY_CHAR");
const done = lineOf("JR DONE");

const { request, event, events, fail, close, failure } = startDap(root);
let at = "initializing";
const timeout = setTimeout(() => fail(new Error(`Breakpoint DAP integration timed out: ${at}.`)), Number(process.env.RETROCORE_DAP_TIMEOUT ?? 120000));

// The first instruction of a routine in Level2.asm: the line after its label.
function level2Line(label) {
    const lines = readFileSync(level2, "utf8").split(/\r?\n/);
    const index = lines.findIndex(line => line === `${label}:`);
    assert.ok(index >= 0, `${label} is in Level2.asm`);
    return index + 2;
}

function drop(name) {
    for (let index = events.length - 1; index >= 0; index--) {
        if (events[index].event === name) events.splice(index, 1);
    }
}

function queued(name) {
    return events.filter(message => message.event === name).map(message => message.body);
}

async function launch() {
    events.length = 0;
    await request("launch", { machine: "trs80-model1", sdkRoms, source: hello, stopOnEntry: true, speed: "max" });
}

async function start() {
    await request("configurationDone");
    assert.equal((await event("stopped")).reason, "entry");
}

async function resume() {
    await request("continue", { threadId: 1 });
    return await event("stopped");
}

async function evaluate(expression) {
    return (await request("evaluate", { expression })).result;
}

async function pc() {
    return (await request("stackTrace", { threadId: 1 })).stackFrames[0].instructionPointerReference;
}

function source(breakpoints) {
    return request("setBreakpoints", { source: { path: hello }, breakpoints });
}

try {
    const capabilities = await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });
    for (const name of ["supportsDataBreakpointBytes", "supportsExceptionFilterOptions", "supportsConditionalBreakpoints", "supportsHitConditionalBreakpoints", "supportsLogPoints",
        "supportsFunctionBreakpoints", "supportsInstructionBreakpoints", "supportsDataBreakpoints",
        "supportsDisassembleRequest", "supportsSteppingGranularity", "supportsExceptionInfoRequest"]) {
        assert.equal(capabilities[name], true, name);
    }
    const basicFilters = ["basicStart", "basicErrors", "basicHandledErrors", "basicStop"];
    const filters = capabilities.exceptionBreakpointFilters;
    assert.deepEqual(filters.map(filter => filter.filter), ["machineReset", "brk", "scanline", "contracts", ...basicFilters]);
    const named = Object.fromEntries(filters.map(filter => [filter.filter, filter]));
    assert.equal(named.machineReset.label, "Machine reset");
    assert.equal(named.machineReset.default, true);
    assert.equal(named.contracts.label, "Routine broke its Keeps: promise");
    assert.equal(named.basicStart.label, "BASIC program start");
    assert.equal(named.basicStart.default, true);
    assert.equal(named.basicStop.label, "BASIC program end");
    assert.equal(named.basicStop.default, false);
    // Every hover says what the filter stops at.
    assert.ok(filters.every(filter => filter.description.startsWith("Stops")), "every hover starts with Stops");
    // Every filter has its hover from the start, and the scanline filter its condition hint.
    assert.ok(capabilities.exceptionBreakpointFilters.every(filter => filter.description?.length > 0));
    assert.equal(named.scanline.conditionDescription, "Scanline:column positions, such as 192:0 or 0:25, 100:25");

    // The launch narrows the exception filters to the Model I's, without the contracts filter as none of its sources
    // has a ;; Keeps: contract.
    at = `The launch narrows the exception filters to the Model I's`;
    await launch();
    const launched = queued("capabilities")[0].capabilities;
    assert.deepEqual(launched.exceptionBreakpointFilters.map(filter => filter.filter), ["machineReset", ...basicFilters]);

    // A scanline breakpoint needs the IIe's video beam: on the Model I it is listed but unverified, saying why.
    at = `A scanline breakpoint needs the IIe's video beam: on the Model I it is listed but unverified, saying why`;
    const scanline = (await request("setFunctionBreakpoints", { breakpoints: [{ name: "scanline 192:0" }] })).breakpoints[0];
    assert.equal(scanline.verified, false);
    assert.equal(scanline.message, "Only the IIe has a video beam to stop on.");
    await request("setFunctionBreakpoints", { breakpoints: [] });

    // A hit count: the CALL runs once per character, so the third hit shows the third, L.
    at = `A hit count: the CALL runs once per character, so the third hit shows the third, L`;
    let set = await source([{ line: call, hitCondition: "3" }]);
    assert.equal(set.breakpoints[0].verified, true);
    const id = set.breakpoints[0].id;
    await start();
    let stopped = await resume();
    assert.equal(stopped.reason, "breakpoint");
    assert.deepEqual(stopped.hitBreakpointIds, [id]);
    assert.equal(await evaluate("A"), "$4C (76)");
    let listed = (await request("retro/breakpoints")).breakpoints;
    assert.equal(listed[0].hits, 3);
    assert.equal(listed[0].hitCondition, "3");
    const changed = queued("breakpoint").filter(body => body.breakpoint.id === id).at(-1);
    assert.equal(changed.reason, "changed");
    assert.equal(changed.breakpoint.message, "Hit 3 times");
    assert.equal(changed.breakpoint.line, call);

    // A malformed hit count leaves the breakpoint unverified.
    at = `A malformed hit count leaves the breakpoint unverified`;
    set = await source([{ line: call, hitCondition: "three" }]);
    assert.equal(set.breakpoints[0].verified, false);
    assert.match(set.breakpoints[0].message, /hit count/i);

    // A condition, set again on the same line, keeps the breakpoint's id and hits, and counts only true hits.
    at = `A condition, set again on the same line, keeps the breakpoint's id and hits, and counts only true hits`;
    set = await source([{ line: call, condition: "A == $5A" }]);
    assert.equal(set.breakpoints[0].id, id);
    stopped = await resume();
    assert.equal(stopped.reason, "breakpoint");
    assert.equal(await evaluate("A"), "$5A (90)");
    assert.equal((await request("retro/breakpoints")).breakpoints[0].hits, 4);

    // A logpoint writes instead of stopping; the breakpoint on DONE stops after the last character.
    at = `A logpoint writes instead of stopping; the breakpoint on DONE stops after the last character`;
    drop("output");
    await source([{ line: call, logMessage: "char {A,c} = {A} at {HL,x} {{ok}} {NOSUCH}" }, { line: done }]);
    stopped = await resume();
    assert.equal(stopped.reason, "breakpoint");
    const logs = queued("output").filter(body => body.output.startsWith("char "));
    assert.deepEqual(logs.map(body => body.output.split(" at ")[0]), ["char 8 = $38", "char 0 = $30", "char \r = $D"]);
    assert.match(logs[0].output, /at 70[0-9A-F]{2} \{ok\} \{NOSUCH: Unknown label 'NOSUCH'\.\}\n$/);
    assert.equal(logs[0].source.path.toLowerCase(), hello.toLowerCase());
    assert.equal(logs[0].line, call);

    // A new launch: function, instruction and data breakpoints, and the disassembly.
    at = `A new launch: function, instruction and data breakpoints, and the disassembly`;
    await launch();
    await source([]);
    set = await request("setFunctionBreakpoints", { breakpoints: [{ name: "DISPLAY_CHAR" }, { name: "NOT_A_LABEL" }] });
    assert.equal(set.breakpoints[0].verified, true);
    assert.equal(set.breakpoints[0].instructionReference, "0x0033");
    assert.equal(set.breakpoints[1].verified, false);
    await start();
    const entry = await pc();
    assert.equal(entry, "0x7000");

    // The disassembly: the sample's instructions with its labels and source lines, and counting back from PRINT.
    at = `The disassembly: the sample's instructions with its labels and source lines, and counting back from PRINT`;
    let disassembly = (await request("disassemble", { memoryReference: entry, instructionCount: 4 })).instructions;
    assert.equal(disassembly[0].address, "0x7000");
    assert.equal(disassembly[0].symbol, "START");
    assert.match(disassembly[0].instruction, /^LD\s+HL,/);
    assert.equal(disassembly[0].location.path.toLowerCase(), hello.toLowerCase());
    assert.equal(disassembly[0].line, lineOf("LD HL,MESSAGE"));
    assert.equal(disassembly[1].address, "0x7003");
    assert.equal(disassembly[1].symbol, "PRINT");
    disassembly = (await request("disassemble", { memoryReference: "0x7003", instructionOffset: -1, instructionCount: 2 })).instructions;
    assert.deepEqual(disassembly.map(instruction => instruction.address), ["0x7000", "0x7003"]);

    // The function breakpoint stops in the ROM, at DISPLAY_CHAR's address.
    at = `The function breakpoint stops in the ROM, at DISPLAY_CHAR's address`;
    stopped = await resume();
    assert.equal(stopped.reason, "function breakpoint");
    assert.equal(await pc(), "0x0033");
    await request("setFunctionBreakpoints", { breakpoints: [] });

    // An instruction breakpoint, from the Disassembly view, and stepping one instruction.
    at = `An instruction breakpoint, from the Disassembly view, and stepping one instruction`;
    set = await request("setInstructionBreakpoints", { breakpoints: [{ instructionReference: "0x7003" }] });
    assert.equal(set.breakpoints[0].verified, true);
    stopped = await resume();
    assert.equal(stopped.reason, "instruction breakpoint");
    assert.equal(await pc(), "0x7003");
    await request("next", { threadId: 1, granularity: "instruction" });
    assert.equal((await event("stopped")).reason, "step");
    assert.equal(await pc(), "0x7004");
    await request("setInstructionBreakpoints", { breakpoints: [] });

    // Data breakpoints: what each kind of name watches.
    at = `Data breakpoints: what each kind of name watches`;
    let info = await request("dataBreakpointInfo", { name: "MESSAGE" });
    assert.match(info.dataId, /^mem:[0-9A-F]{4}:1$/);
    assert.match(info.description, /^MESSAGE \(\$70[0-9A-F]{2}\)$/);
    assert.deepEqual(info.accessTypes, ["write", "read", "readWrite"]);
    assert.equal((await request("dataBreakpointInfo", { name: "A" })).dataId, null);
    assert.equal((await request("dataBreakpointInfo", { name: "[$3C00].w" })).dataId, "mem:3C00:2");
    assert.equal((await request("dataBreakpointInfo", { name: "port $FF" })).dataId, "port:00FF:1");
    const screen = await request("dataBreakpointInfo", { name: "$3C00", bytes: 1024, asAddress: true });
    assert.equal(screen.dataId, "mem:3C00:1024");
    assert.equal(screen.description, "$3C00-$3FFF");
    const memory = (await request("scopes", { frameId: 1 })).scopes[1].variablesReference;
    assert.equal((await request("dataBreakpointInfo", { variablesReference: memory, name: "$4000" })).dataId, "mem:4000:1");
    assert.equal((await request("dataBreakpointInfo", { variablesReference: memory - 1, name: "A" })).dataId, null);

    // A read: the third character's LD A,[HL] reads L, the message's third byte, with a condition on it.
    at = `A read: the third character's LD A,[HL] reads L, the message's third byte, with a condition on it`;
    const third = `$${(parseInt(info.dataId.slice(4, 8), 16) + 2).toString(16).toUpperCase()}`;
    const read = (await request("dataBreakpointInfo", { name: `[${third}]` })).dataId;
    set = await request("setDataBreakpoints", { breakpoints: [{ dataId: read, accessType: "read", condition: "[HL] == $4C" }] });
    assert.equal(set.breakpoints[0].verified, true);
    stopped = await resume();
    assert.equal(stopped.reason, "data breakpoint");
    assert.equal(stopped.description, `Read $4C from ${third}.`);
    assert.equal(await evaluate("A"), "$4C (76)");

    // A write: DISPLAY_CHAR puts a character in video memory.
    at = `A write: DISPLAY_CHAR puts a character in video memory`;
    set = await request("setDataBreakpoints", { breakpoints: [{ dataId: screen.dataId, accessType: "write" }] });
    stopped = await resume();
    assert.equal(stopped.reason, "data breakpoint");
    assert.match(stopped.description, /^Wrote \$[0-9A-F]{2} to \$3[C-F][0-9A-F]{2}\.$/);
    await request("setDataBreakpoints", { breakpoints: [] });

    // Stepping over the CALL stops at a breakpoint inside DISPLAY_CHAR.
    at = `Stepping over the CALL stops at a breakpoint inside DISPLAY_CHAR`;
    await source([{ line: call }]);
    await request("setBreakpoints", { source: { path: level2 }, breakpoints: [{ line: level2Line("DISPLAY_CHAR") }] });
    stopped = await resume();
    assert.equal(stopped.reason, "breakpoint");
    let frames = (await request("stackTrace", { threadId: 1 })).stackFrames;
    assert.equal(frames[0].line, call);
    await request("next", { threadId: 1 });
    stopped = await event("stopped");
    assert.equal(stopped.reason, "breakpoint");
    frames = (await request("stackTrace", { threadId: 1 })).stackFrames;
    assert.equal(frames[0].name, "DISPLAY_CHAR");

    // No exception has stopped the machine, so there is no exception to describe.
    at = `No exception has stopped the machine, so there is no exception to describe`;
    await assert.rejects(request("exceptionInfo", { threadId: 1 }));

    // The condition that cannot be evaluated stops at its line, saying why.
    at = `The condition that cannot be evaluated stops at its line, saying why`;
    await request("setBreakpoints", { source: { path: level2 }, breakpoints: [] });
    await source([{ line: lineOf("LD A,[HL]"), condition: "NOSUCH == 1" }]);
    stopped = await resume();
    assert.equal(stopped.reason, "breakpoint");
    assert.match(stopped.description, /condition 'NOSUCH == 1' failed: Unknown label 'NOSUCH'/);

    // Resetting the hit counts reports each breakpoint as not hit.
    at = `Resetting the hit counts reports each breakpoint as not hit`;
    drop("breakpoint");
    listed = (await request("retro/breakpoints", { reset: true })).breakpoints;
    assert.ok(listed.length !== 0 && listed.every(breakpoint => breakpoint.hits === 0));
    assert.ok(queued("breakpoint").some(body => body.breakpoint.message === "Not hit"));

    await request("disconnect");
    console.log("Breakpoint DAP integration passed.");
} catch (error) {
    if (failure()) throw failure();
    throw error;
} finally {
    clearTimeout(timeout);
    close();
}
