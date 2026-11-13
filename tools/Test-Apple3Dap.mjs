// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Apple III DAP integration: stops at a breakpoint in the SDK's boot ROM source at power-on, runs the diagnostics to
// RETRY, lists the hardware, drives and memory banks, reads memory through a bank and an X-byte, and boots SOS 1.3's
// System Utilities to their menu when the disk is present, stopping at an sos function breakpoint's call, tracing
// another's, and stopping at a BRK that is no SOS call. With Business BASIC 1.23's disk, it stops in the
// interpreter's source as HELLO runs.
// The ROM is assembled from the SDK's BootRom.asm unless RETROCORE_APPLE3_ROMS names MAME's apple3 set.

import { resolve, join } from "node:path";
import { readFileSync, existsSync } from "node:fs";
import assert from "node:assert/strict";
import { startDap } from "./DapClient.mjs";

const root = resolve(import.meta.dirname, "..");
const sdkRoms = join(root, "src", "Retrocore.Machines.Apple3", "Roms");
const bootRom = join(sdkRoms, "BootRom.asm");
const utilities = process.env.RETROCORE_APPLE3_UTILITIES
    ?? join(process.env.RETROCORE_CACHE ?? join(process.env.USERPROFILE ?? "", "Retrocore"), "apple3-disks", "Apple3SOS1.3SysUtils.dsk");
const businessBasic = process.env.RETROCORE_APPLE3_BUSINESS_BASIC
    ?? join(process.env.RETROCORE_CACHE ?? join(process.env.USERPROFILE ?? "", "Retrocore"), "apple3-disks", "Apple3BusBasic1.23.dsk");

const { request, event, events, fail, close, failure } = startDap(root);
let last = "";
const timeout = setTimeout(() => fail(new Error(`Apple III DAP integration timed out; the screen was:
${last}`)), Number(process.env.RETROCORE_DAP_TIMEOUT ?? 240000));

// The line after a label: its first instruction.
function lineOf(label, file = bootRom) {
    const lines = readFileSync(file, "utf8").split(/\r?\n/);
    const index = lines.findIndex(line => line === `${label}:`);
    assert.ok(index >= 0, `${label} is in ${file}`);
    let next = index + 1;
    while (/^\s*(;.*)?$/.test(lines[next])) next++;
    return next + 1;
}

// Waits for a running frame whose screen satisfies a test.
async function screen(test, what) {
    for (let index = events.length - 1; index >= 0; index--) {
        if (events[index].event === "retro/frame") events.splice(index, 1);
    }

    for (;;) {
        const frame = await event("retro/frame");
        last = `${frame.rows.join("\n")}\n(${frame.cycles} cycles)`;
        if (test(frame.rows.join("\n"))) return frame;
        if (!frame.running) throw new Error(`Stopped before ${what}.`);
    }
}

function phase(text) { if (process.env.RETROCORE_DAP_VERBOSE === "1") console.log(`${new Date().toISOString()} ${text}`); }

try {
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });

    // Power-on: a breakpoint on the reset vector's target, in the SDK's source, stops before it runs.
    events.length = 0;
    await request("setExceptionBreakpoints", { filters: [] });
    phase("launching");
    await request("launch", { machine: "apple3", sdkRoms, stopOnEntry: false, speed: "max", checkContracts: "log" });
    phase("launched");
    const set = await request("setBreakpoints", { source: { path: bootRom }, breakpoints: [{ line: lineOf("DIAGN") }] });
    assert.equal(set.breakpoints[0].verified, true, "the boot ROM's source maps where the ROM is");
    await request("configurationDone");
    phase("configured");
    const stopped = await event("stopped");
    phase(`stopped: ${JSON.stringify(stopped)}`);
    assert.equal(stopped.reason, "breakpoint");
    const frame = (await request("stackTrace", { threadId: 1 })).stackFrames[0];
    assert.equal(frame.source.path.toLowerCase(), bootRom.toLowerCase());
    assert.equal((await request("evaluate", { expression: "PC" })).result, "$F4EE (62702)");
    assert.equal((await request("threads")).threads[0].name, "Apple III 6502");

    // The diagnostics run to RETRY: there is no disk.
    await request("setBreakpoints", { source: { path: bootRom }, breakpoints: [] });
    await request("continue", { threadId: 1 });
    await screen(text => text.startsWith("RETRY"), "RETRY");

    // The boot ROM's routines keep what their ;; Keeps: comments promise, through the diagnostics' output.
    const broken = events.filter(message => message.event === "output" && /returned with/.test(message.body.output));
    assert.deepEqual(broken.map(message => message.body.output), [], "no Keeps: contract is broken");

    const devices = await request("retro/devices");
    const hardware = Object.fromEntries(devices.hardware.map(row => [row.id, row]));
    assert.deepEqual(Object.keys(hardware), ["model", "memory", "rom", "disk", "environment"]);
    assert.equal(hardware.memory.value, "256 KB, 7 switchable banks");
    assert.deepEqual(devices.devices.map(device => device.id), ["disk1", "disk2", "disk3", "disk4"]);

    // The display panel's requests: the Apple keys, sound, fast disk and the drive lights.
    assert.deepEqual(await request("apple3/button", { button: 0, pressed: true }), { button: 0, pressed: true });
    await request("apple3/button", { button: 0, pressed: false });
    assert.deepEqual(await request("apple3/sound", { mode: "off" }), { mode: "off" });
    assert.deepEqual(await request("apple3/fastDisk", { enabled: true }), { fastDisk: true });
    assert.equal(typeof await request("apple3/disk"), "object");

    // Banks: the system bank, the switchable ones, the ROM and each X-byte's 64K.
    const banks = (await request("retro/memoryBanks")).banks.map(bank => bank.name);
    assert.deepEqual(banks.slice(0, 10), [null, "system", "bank0", "bank1", "bank2", "bank3", "bank4", "bank5", "bank6", "rom"]);
    assert.ok(banks.includes("x81") && banks.includes("x8f"), "an X-byte names its 64K");
    const reference = (await request("evaluate", { expression: "rom:$FFFC" })).memoryReference;
    const vector = Buffer.from((await request("readMemory", { memoryReference: reference, count: 2 })).data, "base64");
    assert.deepEqual([...vector], [0xEE, 0xF4], "the ROM bank reads the reset vector");

    // SOS calls are BRKs: the BRK filter stops at the rest, and an sos function breakpoint at calls.
    const filters = events.filter(message => message.event === "capabilities").at(-1).body.capabilities.exceptionBreakpointFilters;
    assert.deepEqual(filters.map(filter => filter.filter), ["machineReset", "brk", "contracts"]);
    if (existsSync(utilities)) {
        events.length = 0;
        await request("launch", { machine: "apple3", sdkRoms, stopOnEntry: false, speed: "max", disks: [utilities], logpointLimit: 0 });
        await request("setExceptionBreakpoints", { filters: ["brk"] });
        const set = await request("setFunctionBreakpoints", { breakpoints: [
            { name: "sos OPNE" },
            { name: "sos open" },
            { name: "sos $84", logMessage: "{sos} from {PC}" }
        ] });
        assert.deepEqual(set.breakpoints.map(breakpoint => breakpoint.verified), [false, true, true]);
        await request("configurationDone");
        const open = await event("stopped");
        assert.equal(open.reason, "function breakpoint");
        assert.match(open.description, /^SOS call OPEN \(\$C8\) at \$[0-9A-F]{4}\.$/);

        // A trace point names each call with its parameters; with only BRK ticked, the calls run to the menu.
        await request("setFunctionBreakpoints", { breakpoints: [{ name: "sos $84", logMessage: "{sos} from {PC}" }] });
        await request("continue", { threadId: 1 });
        await screen(text => text.includes("Please select a command"), "the System Utilities' menu");
        const traced = events.filter(message => message.event === "output").map(message => message.body.output);
        assert.ok(traced.some(line => /^GET_DEV_NUM "\.CONSOLE" from \$[0-9A-F]{4}\n$/.test(line)), traced.join(""));
        await request("setFunctionBreakpoints", { breakpoints: [] });

        // A BRK $00 is no SOS call: it traps where it is. Continuing runs the paused instruction, a JMP to the BRK.
        await request("pause", { threadId: 1 });
        await event("stopped");
        const pc = Number.parseInt((await request("evaluate", { expression: "PC" })).result.slice(1, 5), 16);
        const brk = pc + 3;
        const here = (await request("evaluate", { expression: `$${pc.toString(16)}` })).memoryReference;
        const code = Buffer.from([0x4C, brk & 0xFF, brk >> 8, 0x00, 0x00]);
        await request("writeMemory", { memoryReference: here, data: code.toString("base64") });
        events.length = 0;
        await request("continue", { threadId: 1 });
        const trap = await event("stopped");
        assert.equal(trap.reason, "exception");
        const at = `$${brk.toString(16).toUpperCase().padStart(4, "0")}`;
        assert.ok(trap.description.startsWith(`BRK at ${at}`), trap.description);

        // SOS's kernel debugs at its source: every SOS call passes through the system call manager.
        events.length = 0;
        await request("launch", { machine: "apple3", sdkRoms, stopOnEntry: false, speed: "max", disks: [utilities] });
        await request("setExceptionBreakpoints", { filters: [] });
        const scmgr = join(sdkRoms, "Sos", "Kernel", "ScMgr.asm");
        const kernelSet = await request("setBreakpoints", { source: { path: scmgr }, breakpoints: [{ line: lineOf("SCMGR", scmgr) }] });
        assert.equal(kernelSet.breakpoints[0].verified, true, "the kernel's source maps where SOS runs");
        await request("configurationDone");
        assert.equal((await event("stopped")).reason, "breakpoint");
        const kernelFrame = (await request("stackTrace", { threadId: 1 })).stackFrames[0];
        assert.equal(kernelFrame.source.path.toLowerCase(), scmgr.toLowerCase());
        assert.equal(kernelFrame.line, lineOf("SCMGR", scmgr));

        // SOS's drivers map to their sources where SOS loaded them: the formatter's lines bind once it is loaded.
        await request("setBreakpoints", { source: { path: scmgr }, breakpoints: [] });
        await request("continue", { threadId: 1 });
        await screen(text => text.includes("Please select a command"), "the System Utilities' menu");
        await request("pause", { threadId: 1 });
        await event("stopped");
        const fmtd1 = join(sdkRoms, "Sos", "Drivers", "Fmtd1", "Fmtd1.asm");
        const driverSet = await request("setBreakpoints", { source: { path: fmtd1 }, breakpoints: [{ line: lineOf("FMTMAIN", fmtd1) }] });
        assert.equal(driverSet.breakpoints[0].verified, true, `the formatter's source maps where SOS loaded it: ${driverSet.breakpoints[0].message}`);
    } else {
        console.log(`Skipped the SOS boot: ${utilities} is missing.`);
    }

    // Business BASIC debugs at its source where SOS loaded it: HELLO's first statement passes through GONE.
    if (existsSync(businessBasic)) {
        events.length = 0;
        await request("launch", { machine: "apple3", sdkRoms, stopOnEntry: false, speed: "max", disks: [businessBasic] });
        await request("setExceptionBreakpoints", { filters: [] });
        const listd = join(sdkRoms, "BusinessBasic", "B3ListD.asm");
        const basicSet = await request("setBreakpoints", { source: { path: listd }, breakpoints: [{ line: lineOf("GONE", listd) }] });
        assert.equal(basicSet.breakpoints[0].verified, true, "Business BASIC's source maps where SOS loads it");
        await request("configurationDone");
        assert.equal((await event("stopped")).reason, "breakpoint");
        const basicFrame = (await request("stackTrace", { threadId: 1 })).stackFrames[0];
        assert.equal(basicFrame.source.path.toLowerCase(), listd.toLowerCase());
        assert.equal(basicFrame.line, lineOf("GONE", listd));
        assert.equal((await request("evaluate", { expression: "PC" })).result, "$683E (26686)");
    } else {
        console.log(`Skipped Business BASIC: ${businessBasic} is missing.`);
    }

    await request("disconnect");
    console.log("Apple III DAP passed: a power-on breakpoint in BootRom.asm, the diagnostics to RETRY, the hardware, "
        + "drives and memory banks" + (existsSync(utilities) ? ", SOS 1.3's System Utilities, SOS call breakpoints and trace points, the BRK filter, and breakpoints in SOS's kernel and driver sources" : "")
        + (existsSync(businessBasic) ? ", and a breakpoint in Business BASIC's source." : "."));
} finally {
    clearTimeout(timeout);
    close();
}
if (failure()) throw failure();
