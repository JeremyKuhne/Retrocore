// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// TRS-80 Model 100 DAP integration. A launch with no ROM says which ROM it needs. With the US Model 100's ROM in the
// external test data (RETROCORE_TRS80M100_ROMS, or the cache's trs80m100-roms folder), the ROM boots to its menu, and
// an 8085 source loaded at $E000 prints through the ROM's RST 4 onto the LCD; it stops at a breakpoint in its Print
// routine with the 80C85's call stack and registers, stops in the ROM's LCD routine in the SDK's source for the ROM,
// steps out to the callers, and shows the LCD's frames and the hardware. A logpoint in a loop the ROM's RST 7.5 keeps
// interrupting logs once per run, and one at $003C once per interrupt. Then a launch with no program boots to the menu,
// enters BASIC with ENTER, runs a line typed at it, and turns the power off and back on with Reset. A launch's files go
// on the menu, BASIC's program is read and written through the debugger, and a program goes onto a tape with CSAVE and
// back with CLOAD. The Tandy 102's ROM, when present, boots to the menu too. Without the ROM, everything after the
// first launch is skipped, which is not a pass.

import { resolve, join } from "node:path";
import { writeFileSync, readFileSync, existsSync, unlinkSync, statSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir, homedir } from "node:os";
import assert from "node:assert/strict";
import { startDap } from "./DapClient.mjs";

const root = resolve(import.meta.dirname, "..");
// The SDK's source for the ROM, which the debugger maps the US Model 100's ROM to.
const sdkRoms = join(root, "src", "Retrocore.Machines.Trs80Model100", "Roms");
const output = join(sdkRoms, "Output.asm");
const { request, event, events, fail, close, failure } = startDap(root);
let last = "";
const timeout = setTimeout(() => fail(new Error(`Model 100 DAP integration timed out; the screen was:
${last}`)), Number(process.env.RETROCORE_DAP_TIMEOUT ?? 240000));
const verbose = process.env.RETROCORE_DAP_VERBOSE === "1";
function phase(text) { if (verbose) console.log(`${new Date().toISOString()} ${text}`); }

const cache = process.env.RETROCORE_CACHE || join(homedir(), "Retrocore");
const roms = process.env.RETROCORE_TRS80M100_ROMS || join(cache, "trs80m100-roms");
const model100 = join(roms, "m100.bin");
const tandy102 = join(roms, "t102.bin");

const program = [
    ".cpu I8085",
    "Start:  lxi h,Greeting",
    "        call Print",
    "Loop:   jmp Loop",
    ";; Prints the zero-terminated string at HL through the ROM's RST 4, which writes A to the LCD.",
    "Print:  mov a,m",
    "        ora a",
    "        rz",
    "        rst 4",
    "        inx h",
    "        jmp Print",
    "Greeting: .byte \"HELLO M100\", 13, 10, 0",
    ""
];
const lineOf = label => program.findIndex(line => line.startsWith(`${label}:`)) + 1;

// Counts down 30,000 times with interrupts on, so the ROM's RST 7.5 lands on the loop's instructions dozens of times.
const counting = [
    ".cpu I8085",
    "Start:  ei",
    "        lxi b,30000",
    "Tick:   dcx b",
    "        mov a,b",
    "        ora c",
    "        jnz Tick",
    "Done:   jmp Done",
    ""
];
const countingLine = label => counting.findIndex(line => line.startsWith(`${label}:`)) + 1;
const logged = text => events.filter(message => message.event === "output" && message.body.output === `${text}\n`).length;

// Forgets queued events of a kind, so a wait sees only what happens next.
function drop(name) {
    for (let index = events.length - 1; index >= 0; index--) {
        if (events[index].event === name) events.splice(index, 1);
    }
}

const text = frame => frame.rows.map(row => row.trimEnd()).join("\n");

// Waits for a running frame whose screen satisfies a test, while the machine runs.
async function screen(test, what) {
    phase(`waiting for ${what}`);
    drop("retro/frame");
    for (;;) {
        const frame = await event("retro/frame");
        last = `${text(frame)}\n(${frame.cycles} cycles)`;
        if (test(text(frame), frame)) return frame;
        if (!frame.running) throw new Error(`Stopped before ${what}.`);
    }
}

async function type(line) {
    for (const character of line) await request("retro/key", { code: character.charCodeAt(0) });
}

const source = join(tmpdir(), `retrocore-model100-${process.pid}.asm`);
const ramImage = join(tmpdir(), `retrocore-model100-${process.pid}.ram`);
const files = mkdtempSync(join(tmpdir(), "retrocore-model100-files-"));
const skipped = [];
try {
    writeFileSync(source, program.join("\n"));
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });

    // With no ROM, the launch says what it needs.
    const empty = join(tmpdir(), `retrocore-model100-noroms-${process.pid}`);
    await assert.rejects(
        request("launch", { machine: "trs80-model100", romDirectory: empty }),
        error => /Model 100's ROM is missing/.test(error.message));
    await assert.rejects(
        request("launch", { machine: "trs80-model100", model: "102", romDirectory: empty }),
        error => /Tandy 102's ROM is missing/.test(error.message) && /m102rom\.m12/.test(error.message));

    if (!existsSync(model100)) {
        skipped.push(`everything that needs the Model 100's ROM (${model100} is missing)`);
    } else {
        // The ROM boots, then the source loads at $E000 and stops on entry.
        phase("launching the source");
        events.length = 0;
        await request("launch", { machine: "trs80-model100", romDirectory: roms, sdkRoms, source, stopOnEntry: true, speed: "max" });
        await request("setExceptionBreakpoints", { filters: [] });
        const print = lineOf("Print");
        const set = await request("setBreakpoints", { source: { path: source }, breakpoints: [{ line: print }] });
        assert.equal(set.breakpoints[0].verified, true);
        await request("configurationDone");
        assert.equal((await event("stopped")).reason, "entry");
        assert.equal((await request("evaluate", { expression: "PC" })).result, "$E000 (57344)");
        assert.equal((await request("threads")).threads[0].name, "TRS-80 Model 100 80C85");
        const hardware = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
        assert.deepEqual(Object.keys(hardware), ["model", "rom", "optionRom", "memory", "lcd", "clock", "power", "ramImage", "files", "cassette", "sound", "io"]);
        assert.equal(hardware.rom.value, "32 KB, the US Model 100's");
        assert.equal(hardware.memory.value, "32 KB at $8000-$FFFF");
        assert.equal(hardware.clock.value, "uPD1990AC, TP at 256 Hz on RST 7.5");

        // The breakpoint in Print, called from Start.
        await request("continue", { threadId: 1 });
        assert.equal((await event("stopped")).reason, "breakpoint");
        let stack = await request("stackTrace", { threadId: 1 });
        assert.equal(stack.stackFrames[0].line, print);
        assert.equal(stack.stackFrames[0].name, "Print");
        assert.match(stack.stackFrames[1].name, /^Start/);
        const scopes = await request("scopes", { frameId: stack.stackFrames[0].id });
        const registers = await request("variables", { variablesReference: scopes.scopes[0].variablesReference });
        assert.ok(registers.variables.some(variable => variable.name === "HL"), "the 8085's register pairs are shown");
        assert.equal((await request("evaluate", { expression: "HL" })).result.startsWith("$E0"), true);

        // RST 4 reaches LCD, Tandy's documented entry, in the SDK's source for the ROM; stepping out of it returns to
        // Print.
        await request("setBreakpoints", { source: { path: source }, breakpoints: [] });
        const lcd = readFileSync(output, "utf8").split(/\r?\n/).indexOf("LCD:") + 2;
        const inRom = await request("setBreakpoints", { source: { path: output }, breakpoints: [{ line: lcd }] });
        assert.equal(inRom.breakpoints[0].verified, true, "the ROM's source is mapped");
        await request("continue", { threadId: 1 });
        assert.equal((await event("stopped")).reason, "breakpoint");
        stack = await request("stackTrace", { threadId: 1 });
        assert.equal(stack.stackFrames[0].name, "LCD");
        assert.equal(stack.stackFrames[0].source.path.toLowerCase(), output.toLowerCase());
        assert.equal(stack.stackFrames[1].name, "Print");
        await request("setBreakpoints", { source: { path: output }, breakpoints: [] });
        await request("stepOut", { threadId: 1 });
        assert.equal((await event("stopped")).reason, "step");
        assert.equal((await request("stackTrace", { threadId: 1 })).stackFrames[0].name, "Print");

        // Stepping out again returns to Start, after the CALL.
        await request("stepOut", { threadId: 1 });
        assert.equal((await event("stopped")).reason, "step");
        stack = await request("stackTrace", { threadId: 1 });
        assert.equal(stack.stackFrames[0].line, lineOf("Loop"));

        // The greeting is on the LCD, in the frame's text and its pixels.
        const frame = (await request("retro/video", {}));
        assert.equal(frame.width, 240);
        assert.equal(frame.height, 64);
        assert.equal(Buffer.from(frame.pixels, "base64").length, 240 * 64 * 4);
        await request("continue", { threadId: 1 });
        await screen(screenText => screenText.includes("HELLO M100"), "the greeting");

        // A logpoint in a loop RST 7.5 keeps interrupting logs once a run, though the interrupt is taken at its
        // instruction first, and one on the handler's entry at $003C logs once an interrupt.
        phase("counting through interrupts");
        writeFileSync(source, counting.join("\n"));
        events.length = 0;
        await request("launch", { machine: "trs80-model100", romDirectory: roms, source, stopOnEntry: true, speed: "max", logpointLimit: 0 });
        await request("setExceptionBreakpoints", { filters: [] });
        await request("setBreakpoints", { source: { path: source }, breakpoints: [
            { line: countingLine("Tick"), logMessage: "tick" }, { line: countingLine("Done") }
        ] });
        await request("setInstructionBreakpoints", { breakpoints: [{ instructionReference: "0x3c", logMessage: "interrupt" }] });
        await request("configurationDone");
        assert.equal((await event("stopped")).reason, "entry");
        const startCycles = (await request("retro/video", {})).cycles;
        await request("continue", { threadId: 1 });
        assert.equal((await event("stopped")).reason, "breakpoint");
        assert.equal((await request("stackTrace", { threadId: 1 })).stackFrames[0].line, countingLine("Done"));

        // RST 7.5 comes once each 9,600 cycles, 256 Hz, so the handler's logpoint logs that often, give or take one.
        const periods = ((await request("retro/video", {})).cycles - startCycles) / 9600;
        const interrupts = logged("interrupt");
        assert.ok(interrupts >= 20, `the loop is interrupted (${interrupts} times)`);
        assert.ok(Math.abs(interrupts - periods) <= 1.5, `the handler's logpoint logs once an interrupt (${interrupts} for ${periods.toFixed(1)} periods)`);
        assert.equal(logged("tick"), 30000, "the loop's logpoint logs once per run");
        await request("setInstructionBreakpoints", { breakpoints: [] });
        await request("setBreakpoints", { source: { path: source }, breakpoints: [] });
        writeFileSync(source, program.join("\n"));

        // No program: the menu, then BASIC.
        phase("launching to the menu");
        events.length = 0;
        await request("launch", {
            machine: "trs80-model100", romDirectory: roms, ramImage, stopOnEntry: false, speed: "max", time: "2026-11-26T09:30:00"
        });
        await request("setExceptionBreakpoints", { filters: [] });
        await request("configurationDone");
        // The ROM ignores the keyboard for its first second or so after a cold start (its scan counter at $FF90 starts
        // near 116 scans), though the menu is up sooner, so the clock shows two seconds before the first key.
        await screen(
            screenText => screenText.includes("29638 Bytes free") && /Sun 00:00:0[2-9]/.test(screenText),
            "the menu, two seconds after power-on");
        await type("\r");
        await screen(screenText => screenText.includes("29382 Bytes free") && /^Ok$/m.test(screenText), "BASIC");
        await type("a=42:print 6*7;date$\r");
        // A cold start sets the clock to January 1, as MAME's does, whatever the launch's time.
        await screen(screenText => screenText.includes(" 42 01/01/00"), "BASIC's answer");

        // POWER OFF stops the CPU; Reset turns the machine back on, to the menu.
        await type("power off\r");
        await screen((_, running) => running.poweredOff === true, "the power to go off");
        await request("retro/reset", {});
        const reset = await screen((screenText, running) => running.poweredOff === false && screenText.includes("Select:"), "the menu after Reset");

        // The ROM ignores the keyboard for a second or so after the power comes on, warm or cold, so two emulated
        // seconds pass before the next key, however fast the host runs the machine.
        await screen((_, running) => running.cycles > reset.cycles + 2 * 2457600, "two seconds after Reset");

        // The RAM image is written as another launch replaces the machine, and the next session resumes from it: BASIC
        // after POWER OFF,RESUME, with its variable.
        assert.ok(!existsSync(ramImage), "nothing is written while the session runs");
        await type("\ra=42\rpower off,resume\r");
        await screen((_, running) => running.poweredOff === true, "the power to go off again");
        events.length = 0;
        await request("launch", { machine: "trs80-model100", romDirectory: roms, ramImage, stopOnEntry: false, speed: "max" });
        assert.equal(statSync(ramImage).size, 32768, "the relaunch saved the RAM");
        await request("setExceptionBreakpoints", { filters: [] });
        await request("configurationDone");
        await screen((_, running) => running.cycles > 3 * 2457600, "the resumed machine to settle");
        await type("?a\r");
        await screen(screenText => /^ 42$/m.test(screenText), "BASIC to resume with its variable");
        const ramHardware = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
        assert.equal(ramHardware.ramImage.value, ramImage);

        // A launch's files go into RAM's directory and on the menu; BASIC loads one, and the debugger reads its program
        // and writes another over it, which BASIC then runs.
        phase("launching with files");
        writeFileSync(join(files, "hello.model100.bas"), "10 PRINT \"HELLO\"\n");
        writeFileSync(join(files, "notes.txt"), "a note\n");
        events.length = 0;
        await request("launch", {
            machine: "trs80-model100", romDirectory: roms, stopOnEntry: false, speed: "max",
            files: [join(files, "hello.model100.bas"), join(files, "notes.txt")]
        });
        await request("setExceptionBreakpoints", { filters: [] });
        await request("configurationDone");
        const listed = await screen(screenText => screenText.includes("HELLO.BA") && screenText.includes("NOTES.DO"), "the menu with the files");
        const filesHardware = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
        assert.equal(filesHardware.files.value, "HELLO.BA, NOTES.DO");
        await screen((_, running) => running.cycles > listed.cycles + 2 * 2457600, "two seconds at the menu");
        await type("BASIC\r");
        await screen(screenText => /^Ok$/m.test(screenText), "BASIC from the menu");
        await type("load \"HELLO\"\r");
        await screen(screenText => (screenText.match(/^Ok$/gm) ?? []).length >= 2, "LOAD");
        const loaded = await request("retro/basic/program");
        assert.equal(loaded.dialect, "model100");
        assert.equal(loaded.text, "10 PRINT \"HELLO\"\n");
        const written = await request("retro/basic/write", { text: "10 PRINT \"CHANGED\";6*7\n" });
        assert.equal(written.success, true, JSON.stringify(written));
        await type("run\r");
        await screen(screenText => screenText.includes("CHANGED 42"), "the written program's output");

        // CSAVE records onto a tape in the recorder, a changed tape that saving writes to its WAV file, and a launch
        // with that file as its cassette CLOADs the program back.
        phase("recording a tape");
        const tape = join(files, "prog.wav");
        await request("retro/media", { device: "cassette", action: "record", path: tape });
        const blank = statSync(tape).size;
        await type("csave \"PROG\"\r");
        await screen(screenText => /csave "PROG"\nOk/i.test(screenText), "CSAVE");
        assert.equal(statSync(tape).size, blank, "nothing but a save writes the recording");
        const saved = await request("retro/device", { id: "cassette", action: "save", supportsRetrocoreMedia: 1 });
        assert.equal(saved.outcome, "saved", JSON.stringify(saved));
        const ejected = await request("retro/media", { device: "cassette", action: "eject" });
        assert.equal(ejected.cassette.path, null);
        assert.ok(statSync(tape).size > 100000, "the WAV file holds the recording");
        events.length = 0;
        await request("launch", { machine: "trs80-model100", romDirectory: roms, stopOnEntry: false, speed: "max", cassette: tape });
        await request("setExceptionBreakpoints", { filters: [] });
        await request("configurationDone");
        const tapeMenu = await screen(screenText => screenText.includes("Select:"), "the menu with a tape in");
        const tapeHardware = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
        assert.equal(tapeHardware.cassette.value, tape);
        await screen((_, running) => running.cycles > tapeMenu.cycles + 2 * 2457600, "two seconds at the menu");
        await type("BASIC\r");
        await screen(screenText => /^Ok$/m.test(screenText), "BASIC from the menu");
        await type("cload \"PROG\"\r");
        await screen(screenText => screenText.includes("Found:PROG") && /Found:PROG\nOk/.test(screenText), "CLOAD");
        await type("run\r");
        await screen(screenText => screenText.includes("CHANGED 42\nOk"), "the loaded program's output");

        if (existsSync(tandy102)) {
            phase("launching the Tandy 102");
            events.length = 0;
            await request("launch", { machine: "trs80-model100", model: "102", romDirectory: roms, stopOnEntry: false, speed: "max" });
            await request("setExceptionBreakpoints", { filters: [] });
            await request("configurationDone");
            await screen(screenText => screenText.includes("29638 Bytes free"), "the 102's menu");
            const hardware102 = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
            assert.equal(hardware102.model.value, "OKI 80C85 at 2.4576 MHz");
            assert.equal(hardware102.model.name, "Tandy 102");
        } else {
            skipped.push(`the Tandy 102 (${tandy102} is missing)`);
        }
    }

    await request("disconnect", {});
    clearTimeout(timeout);
    if (failure()) throw failure();
    console.log(skipped.length === 0
        ? "Model 100 DAP integration passed: the missing-ROM messages, a source's breakpoint, call stack, registers, a breakpoint in the ROM's SDK source, "
            + "step out and LCD output, a logpoint met once a run through RST 7.5, the menu, BASIC, POWER OFF and Reset, a RAM image resumed in a new session, "
            + "a launch's files on the menu, BASIC's program read and written, a tape CSAVEd and CLOADed, and the "
            + "Tandy 102's menu."
        : `Model 100 DAP integration checked the missing-ROM messages${skipped.length === 1 && existsSync(model100) ? " and the Model 100" : ""}; `
            + `skipped (inconclusive, not passed): ${skipped.join("; ")}.`);
} finally {
    clearTimeout(timeout);
    if (existsSync(source)) unlinkSync(source);
    if (existsSync(ramImage)) unlinkSync(ramImage);
    rmSync(files, { recursive: true, force: true });
    await close();
}
