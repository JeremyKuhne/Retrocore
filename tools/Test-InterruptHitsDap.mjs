// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Breakpoints and interrupts: a logpoint, a breakpoint or a step meets its instruction once each time the
// instruction runs, though the CPU takes an interrupt at its address first and runs it after the handler returns,
// and a logpoint on the handler's first instruction logs once an interrupt. Each machine runs a loop many times
// while an interrupt comes in, on the SDK's ROMs or none, so it needs no dumps: a PET (6502, the kernal's 60 Hz
// IRQ), a CoCo 2 (6809, the field sync IRQ), a TRS-80 Model III (Z80, its 30 Hz clock) and an Altair (8080, the
// 88-2SIO's transmitter, which interrupts every run). On each, steps in, over and out and continuing cross an
// interrupt taken at a breakpoint, and a breakpoint set in the handler stops where it returns. On the Model III, a
// logpoint after HALT logs once each time an interrupt wakes it.

import { resolve, join } from "node:path";
import { writeFileSync, existsSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import assert from "node:assert/strict";
import { startDap } from "./DapClient.mjs";

const root = resolve(import.meta.dirname, "..");
const { request, event, events, fail, close, failure } = startDap(root);
let at = "initializing";
const timeout = setTimeout(() => fail(new Error(`Interrupt hit DAP integration timed out: ${at}.`)),
    Number(process.env.RETROCORE_DAP_TIMEOUT ?? 240000));

function drop(name) {
    for (let index = events.length - 1; index >= 0; index--) {
        if (events[index].event === name) events.splice(index, 1);
    }
}

const queued = name => events.filter(message => message.event === name).map(message => message.body);
const logged = text => queued("output").filter(body => body.output === `${text}\n`).length;

// The hits a breakpoint's latest changed event reports.
function hits(id) {
    const changed = queued("breakpoint").filter(body => body.breakpoint.id === id).at(-1);
    const message = changed?.breakpoint.message ?? "Not hit";
    if (message === "Not hit") return 0;
    if (message === "Hit once") return 1;
    const count = /^Hit (\d+) times$/.exec(message);
    assert.ok(count, `a hit count: ${message}`);
    return Number(count[1]);
}

const evaluate = async expression => parseInt((await request("evaluate", { expression })).result.slice(1), 16);
const pc = () => evaluate("PC");

async function stop(command, args = {}) {
    await request(command, { threadId: 1, ...args });
    return event("stopped");
}

// Each machine's program: a loop whose instruction at Tick runs a known number of times, and the instruction it
// ends at, Done. Its own interrupt hook counts the interrupts in Irqs, and entry is the handler's first instruction.
const machines = [
    {
        name: "PET (6502)",
        launch: { machine: "pet", sdkRoms: join(root, "src", "Retrocore.Machines.Commodore", "Roms") },
        // X and Y count 65,536 runs of INX in about a third of a second: some twenty IRQs, most taken at INX. The
        // hook goes in the kernal's CINV. S starts at $01, so each IRQ's six pushes wrap page one.
        lines: [
            ".cpu Mos6502",
            "CINV = $90",
            "        sei",
            "Ready:  lda CINV",
            "        sta Kernal",
            "        lda CINV+1",
            "        sta Kernal+1",
            "        lda #<Count",
            "        sta CINV",
            "        lda #>Count",
            "        sta CINV+1",
            "        ldx #$01",
            "        txs",
            "        ldx #0",
            "        ldy #0",
            "        cli",
            "Tick:   inx",
            "        bne Tick",
            "        iny",
            "        bne Tick",
            "Done:   jmp Done",
            "Count:  inc Irqs",
            "        jmp (Kernal)",
            "Kernal: .word 0",
            "Irqs:   .byte 0"
        ],
        runs: 65536,
        entry: "[$FFFE].w",
        interrupts: "[Irqs]",
        // For the steps, a loop that waits, with IRQs masked, for PIA 1 to flag the retrace. CLI unmasks them after
        // the instruction that follows it, so the IRQ is taken at Tick.
        steps: {
            lines: [
                ".cpu Mos6502",
                "Wait:   sei",
                "Poll:   lda $E813",
                "        bpl Poll",
                "        cli",
                "        nop",
                "Tick:   inc Runs",
                "        jmp Wait",
                "Runs:   .byte 0"
            ],
            runs: "[Runs]"
        }
    },
    {
        name: "CoCo 2 (6809)",
        launch: { machine: "coco", model: "coco2", sdkRoms: join(root, "src", "Retrocore.Machines.Coco", "Roms") },
        // X counts 65,536 runs of LEAX in about six tenths of a second: some thirty-five IRQs. The hook goes in
        // Color BASIC's IRQVEC.
        lines: [
            ".cpu M6809",
            "IRQVEC = $010C",
            ".org $3000",
            "        orcc #$50",
            "Ready:  ldx IRQVEC+1",
            "        stx Basic",
            "        ldx #Count",
            "        stx IRQVEC+1",
            "        ldx #0",
            "        andcc #$EF",
            "Tick:   leax 1,x",
            "        bne Tick",
            "Done:   bra Done",
            "Count:  inc Irqs",
            "        jmp [Basic]",
            "Basic:  .word 0",
            "Irqs:   .byte 0"
        ],
        runs: 65536,
        entry: "$010C",
        interrupts: "[Irqs]",
        // For the steps, a loop that waits, with IRQs masked, for PIA 0 to flag the field sync. The IRQ is taken
        // after the ANDCC that unmasks it, at Tick.
        steps: {
            lines: [
                ".cpu M6809",
                ".org $3000",
                "Wait:   orcc #$10",
                "Poll:   lda $FF03",
                "        bpl Poll",
                "        andcc #$EF",
                "Tick:   inc Runs",
                "        bra Wait",
                "Runs:   .byte 0"
            ],
            runs: "[Runs]"
        }
    },
    {
        name: "Model III (Z80)",
        launch: { machine: "trs80-model3", sdkRoms: join(root, "src", "Retrocore.Machines.Trs80", "Roms") },
        // HL counts 65,536 runs of INC HL in about eight tenths of a second: some twenty-five clock interrupts. The
        // hook goes in the ROM's CLOCK_VECTOR, whose JP it chains on to.
        lines: [
            ".cpu Z80",
            "CLOCK_VECTOR = $4046",
            ".org $7000",
            "        DI",
            "Ready:  LD HL,[CLOCK_VECTOR+1]",
            "        LD [Chain+1],HL",
            "        LD HL,Count",
            "        LD [CLOCK_VECTOR+1],HL",
            "        LD HL,0",
            "        EI",
            "Tick:   INC HL",
            "        LD A,H",
            "        OR L",
            "        JR NZ,Tick",
            "Done:   JR Done",
            "Count:  LD HL,[Irqs]",
            "        INC HL",
            "        LD [Irqs],HL",
            "Chain:  JP 0",
            "Irqs:   .word 0"
        ],
        runs: 65536,
        entry: "$0038",
        interrupts: "[Irqs].w",
        // HALT waits for each of ten clock interrupts, which return to Tick: halted, the Z80 refreshes every four
        // T-states without leaving Tick's boundary, so Tick's logpoint logs once a wake.
        idle: [
            ".cpu Z80",
            ".org $7000",
            "        LD HL,Runs",
            "        EI",
            "Wait:   HALT",
            "Tick:   INC [HL]",
            "        LD A,[HL]",
            "        CP 10",
            "        JR NZ,Wait",
            "Done:   JR Done",
            "Runs:   .byte 0"
        ],
        // For the steps, a loop that waits, with interrupts off, for the clock's active-low bit in the interrupt
        // status. EI turns them on after the NOP that follows it, so the interrupt is taken at Tick.
        steps: {
            lines: [
                ".cpu Z80",
                ".org $7000",
                "        LD HL,Runs",
                "Wait:   DI",
                "Poll:   IN A,[$E0]",
                "        AND $04",
                "        JR NZ,Poll",
                "        EI",
                "        NOP",
                "Tick:   INC [HL]",
                "        JR Wait",
                "Runs:   .byte 0"
            ],
            runs: "[Runs]"
        }
    },
    {
        name: "Altair (8080)",
        launch: { machine: "altair", loadAddress: 0x38, entryAddress: 0x100 },
        // The 88-2SIO's transmitter is ready, so with its interrupt on it holds INT. The handler returns with
        // interrupts off, and EI turns them on after the instruction that follows it, so each of the 4,096 runs of
        // INX is interrupted first.
        lines: [
            ".cpu I8080",
            "        .org $38",
            "Handler: push h",
            "        lhld Irqs",
            "        inx h",
            "        shld Irqs",
            "        pop h",
            "        ret",
            "Irqs:   .word 0",
            "        .org $100",
            "Start:  lxi sp,$1000",
            "Ready:  mvi a,3",
            "        out $10",
            "        mvi a,$35           ; transmit interrupt enabled",
            "        out $10",
            "        lxi b,0",
            "Loop:   ei",
            "        nop",
            "Tick:   inx b",
            "        mov a,b",
            "        cpi $10",
            "        jnz Loop",
            "Done:   jmp Done"
        ],
        runs: 4096,
        entry: "$38",
        interrupts: "[Irqs].w",
        everyRun: true,
        steps: { runs: "BC" }
    }
];

// A breakpoint at Tick stops each run, with the interrupt due: stepping in goes into the handler, stepping out
// comes back to Tick, and stepping on runs it once. Continuing from Tick runs it and stops at its next run, not
// where the interrupt returns. Stepping over Tick from its stop runs the handler and Tick, and meets Tick no more;
// its next run meets Tick's logpoint once.
async function steps(machine, source, tick, entry) {
    at = `${machine.name}: stepping across the interrupt`;
    const lines = machine.steps.lines ?? machine.lines;
    const line = lines.findIndex(text => text.startsWith("Tick:")) + 1;
    const runs = () => evaluate(machine.steps.runs);
    const shown = async () => (await request("stackTrace", { threadId: 1 })).stackFrames[0].line;
    await request("setBreakpoints", { source: { path: source }, breakpoints: [{ line }] });
    const stopped = await stop("continue");
    assert.equal(stopped.reason, "breakpoint", `${machine.name}: the breakpoint at Tick stops`);
    assert.equal(await pc(), tick);
    const first = await runs();

    const into = await stop("stepIn", { granularity: "instruction" });
    assert.equal(into.reason, "step");
    assert.equal(await pc(), entry, `${machine.name}: stepping in with the interrupt due goes to its handler`);

    const back = await stop("stepOut");
    assert.equal(back.reason, "step", `${machine.name}: stepping out of the handler stops as a step`);
    assert.equal(await pc(), tick, `${machine.name}: stepping out of the handler comes back to Tick`);
    assert.equal(await shown(), line);
    assert.equal(await runs(), first, `${machine.name}: Tick has not run`);

    const on = await stop("stepIn", { granularity: "instruction" });
    assert.equal(on.reason, "step");
    assert.equal(await shown(), line + 1, `${machine.name}: stepping on from Tick runs it`);
    assert.equal(await runs(), first + 1);

    // Continuing from a stop at Tick's breakpoint, with the interrupt due, stops at its next run.
    const next = await stop("continue");
    assert.equal(next.reason, "breakpoint");
    assert.equal(await pc(), tick);
    const second = await runs();
    assert.equal(second, first + 1, `${machine.name}: Tick's breakpoint stops before its next run`);
    const after = await stop("continue");
    assert.equal(after.reason, "breakpoint");
    assert.equal(await pc(), tick);
    assert.equal(await runs(), second + 1, `${machine.name}: continuing from Tick runs it once, then stops at the next run`);

    // Over: a logpoint at Tick's address counts the runs it meets, beside the breakpoint on its line.
    await request("setInstructionBreakpoints", { breakpoints: [{ instructionReference: `0x${tick.toString(16)}`, logMessage: "met" }] });
    drop("output");
    const over = await stop("next");
    assert.equal(over.reason, "step", `${machine.name}: stepping over Tick with the interrupt due ends as a step`);
    assert.equal(await shown(), line + 1);
    assert.equal(await runs(), second + 2);
    assert.equal(logged("met"), 0, `${machine.name}: stepping over Tick from its stop meets it no more`);
    const later = await stop("continue");
    assert.equal(later.reason, "breakpoint");
    assert.equal(await pc(), tick);
    assert.equal(logged("met"), 1, `${machine.name}: Tick's next run meets its logpoint`);

    // A breakpoint set in the handler stops where it returns; the line's breakpoint, met there already, does not.
    await request("setInstructionBreakpoints", { breakpoints: [] });
    const third = await runs();
    assert.equal((await stop("stepIn", { granularity: "instruction" })).reason, "step");
    assert.equal(await pc(), entry);
    const set = await request("setInstructionBreakpoints", { breakpoints: [{ instructionReference: `0x${tick.toString(16)}` }] });
    const returned = await stop("continue");
    assert.equal(returned.reason, "instruction breakpoint");
    assert.deepEqual(returned.hitBreakpointIds, [set.breakpoints[0].id],
        `${machine.name}: the breakpoint set in the handler stops at Tick, which the line's met before`);
    assert.equal(await pc(), tick);
    assert.equal(await runs(), third, `${machine.name}: the return stops before Tick runs`);
    await request("setInstructionBreakpoints", { breakpoints: [] });
}

const files = [];
try {
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });
    for (const machine of machines) {
        at = `${machine.name}: launching`;
        const source = join(tmpdir(), `retrocore-irq-${process.pid}-${machine.launch.machine}.asm`);
        files.push(source);
        writeFileSync(source, [...machine.lines, ""].join("\n"));
        const lineOf = label => machine.lines.findIndex(text => text.startsWith(`${label}:`)) + 1;
        const line = { ready: lineOf("Ready"), tick: lineOf("Tick"), done: lineOf("Done") };

        // The count starts at Ready, where interrupts are masked: one the ROM left due may be taken at entry,
        // before the program's hook can count it.
        events.length = 0;
        await request("launch", { ...machine.launch, source, stopOnEntry: true, speed: "max", sound: "off", logpointLimit: 0 });
        await request("setExceptionBreakpoints", { filters: [] });
        await request("setBreakpoints", { source: { path: source }, breakpoints: [{ line: line.ready }] });
        await request("configurationDone");
        assert.equal((await event("stopped")).reason, "entry");
        assert.equal((await stop("continue")).reason, "breakpoint", `${machine.name}: the program reaches Ready`);
        const set = await request("setBreakpoints", { source: { path: source }, breakpoints: [
            { line: line.tick, logMessage: "tick" }, { line: line.done }
        ] });
        assert.ok(set.breakpoints.every(breakpoint => breakpoint.verified), `${machine.name}: the breakpoints map`);
        const entry = await evaluate(machine.entry);
        const tick = await evaluate("Tick");
        const handler = await request("setInstructionBreakpoints", { breakpoints: [
            { instructionReference: `0x${entry.toString(16)}`, logMessage: "interrupt" }
        ] });
        assert.ok(handler.breakpoints[0].verified, `${machine.name}: the handler's logpoint is set`);

        // The loop's logpoint logs once a run, and counts a hit a run; the handler's logs once an interrupt.
        at = `${machine.name}: running the loop`;
        drop("output");
        const stopped = await stop("continue");
        assert.equal(stopped.reason, "breakpoint", `${machine.name}: the loop ends at Done`);
        assert.deepEqual(stopped.hitBreakpointIds, [set.breakpoints[1].id]);
        const interrupts = await evaluate(machine.interrupts);
        const runs = logged("tick");
        const entries = logged("interrupt");
        console.log(`${machine.name}: ${runs} logs for ${machine.runs} runs, ${entries} for ${interrupts} interrupts.`);
        assert.ok(interrupts >= (machine.everyRun ? machine.runs : 10), `${machine.name}: the loop is interrupted`);
        assert.equal(runs, machine.runs, `${machine.name}: the loop's logpoint logs once a run`);
        assert.equal(hits(set.breakpoints[0].id), machine.runs, `${machine.name}: the loop's logpoint counts a hit a run`);
        assert.equal(entries, interrupts, `${machine.name}: the handler's logpoint logs once an interrupt`);

        if (machine.idle) {
            at = `${machine.name}: waking from HALT`;
            writeFileSync(source, [...machine.idle, ""].join("\n"));
            const lineIn = label => machine.idle.findIndex(text => text.startsWith(`${label}:`)) + 1;
            events.length = 0;
            await request("launch", { ...machine.launch, source, stopOnEntry: true, speed: "max", sound: "off", logpointLimit: 0 });
            await request("setExceptionBreakpoints", { filters: [] });
            await request("setBreakpoints", { source: { path: source }, breakpoints: [
                { line: lineIn("Tick"), logMessage: "woke" }, { line: lineIn("Done") }
            ] });
            await request("configurationDone");
            assert.equal((await event("stopped")).reason, "entry");
            assert.equal((await stop("continue")).reason, "breakpoint", `${machine.name}: the waits end at Done`);
            assert.equal(await evaluate("[Runs]"), 10);
            assert.equal(logged("woke"), 10, `${machine.name}: the logpoint after HALT logs once a wake`);
        }

        if (machine.steps) {
            // A relaunch runs the steps' program, or the loop again from the start.
            if (machine.steps.lines) writeFileSync(source, [...machine.steps.lines, ""].join("\n"));
            events.length = 0;
            await request("launch", { ...machine.launch, source, stopOnEntry: true, speed: "max", sound: "off" });
            await request("setExceptionBreakpoints", { filters: [] });
            await request("configurationDone");
            assert.equal((await event("stopped")).reason, "entry");
            await steps(machine, source, await evaluate("Tick"), entry);
        }
    }

    console.log("Interrupt hit DAP integration passed.");
} finally {
    clearTimeout(timeout);
    close();
    for (const file of files) if (existsSync(file)) unlinkSync(file);
}

if (failure()) throw failure();
