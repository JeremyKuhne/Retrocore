// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as vscode from "vscode";
import * as path from "node:path";
import * as assert from "node:assert/strict";
import { testAssemblyLanguage } from "./language";
import { testLanguageServer } from "./languageServer";
import { testBasicEditor } from "./basicEditor";
import { testBasicLanguage } from "./basicLanguage";
import { testBasicThread } from "./basicThread";
import { testBasicVariables } from "./basicVariables";
import { testAppleSoftLaunch, testBasicLaunch } from "./basicLaunch";
import { testMachineMenu } from "./machineMenu";
import type { BreakpointHits } from "../breakpoints";
import { memoryUri, type MemoryBank } from "../memory";

export async function run(): Promise<void> {
    const workspace = vscode.workspace.workspaceFolders?.[0];
    if (workspace === undefined) throw new Error("M1 tests need the project workspace.");
    await testAssemblyLanguage(workspace.uri.fsPath);
    await testLanguageServer(workspace.uri.fsPath);
    await testBasicLanguage(workspace.uri.fsPath);
    if (process.env.RETROCORE_TEST_LANGUAGE_ONLY === "1") return;
    await testMachineMenu(workspace);
    const romDirectory = process.env.RETROCORE_IIE_ROMS;
    if (romDirectory === undefined) throw new Error("RETROCORE_IIE_ROMS is required.");
    const root = workspace.uri.fsPath;
    const stops: { reason: string }[] = [];
    const waiters: ((reason: string) => void)[] = [];
    const tracker = vscode.debug.registerDebugAdapterTrackerFactory("retrocore", {
        createDebugAdapterTracker() {
            return {
                onDidSendMessage(message: unknown) {
                    if (typeof message !== "object" || message === null || !("event" in message) || message.event !== "stopped" || !("body" in message)) return;
                    const body: unknown = message.body;
                    if (typeof body !== "object" || body === null || !("reason" in body) || typeof body.reason !== "string") return;
                    const waiter = waiters.shift();
                    if (waiter !== undefined) waiter(body.reason);
                    else stops.push({ reason: body.reason });
                }
            };
        }
    });
    const stop = (): Promise<string> => {
        const queued = stops.shift();
        if (queued !== undefined) return Promise.resolve(queued.reason);
        return new Promise((resolve, reject) => {
            const timer = setTimeout(() => reject(new Error("VS Code did not receive a stopped event.")), 15000);
            waiters.push(reason => { clearTimeout(timer); resolve(reason); });
        });
    };
    try {
        const source = path.join(root, "sample", "iie", "main.s");
        const document = await vscode.languages.setTextDocumentLanguage(
            await vscode.workspace.openTextDocument(source), "retrocore-asm");
        await vscode.window.showTextDocument(document);
        const breakpoint = new vscode.SourceBreakpoint(new vscode.Location(vscode.Uri.file(source), new vscode.Position(13, 0)), true, "X == 1");
        vscode.debug.addBreakpoints([breakpoint]);
        assert.equal(await vscode.debug.startDebugging(workspace, {
            type: "retrocore", request: "launch", name: "M1 integration",
            machine: "apple2", romDirectory, stopOnEntry: true, model: "iie-enhanced",
            debugHost: path.join(root, "artifacts", "AnyCPU", "Release", "Retrocore.Debug", "net10.0", "Retrocore.Debug.dll"),
            program: path.join(root, "artifacts", "iie-sample", "main.bin"),
            debugFile: path.join(root, "artifacts", "iie-sample", "main.dbg"), loadAddress: 0x6000
        }), true);
        assert.equal(await stop(), "entry");
        const session = vscode.debug.activeDebugSession;
        if (session === undefined) throw new Error("VS Code did not create a debug session.");
        await session.customRequest("continue", { threadId: 1 });
        assert.equal(await stop(), "breakpoint");
        const frame = await session.customRequest("stackTrace", { threadId: 1 });
        assert.equal(frame.stackFrames[0].line, 14);
        assert.equal(frame.stackFrames[0].source.path.toLowerCase(), source.toLowerCase());
        await session.customRequest("stepIn", { threadId: 1 });
        assert.equal(await stop(), "step");
        const inside = await session.customRequest("stackTrace", { threadId: 1 });
        assert.equal(inside.totalFrames, 2);
        assert.equal(inside.stackFrames[0].name, "increment");
        assert.equal(inside.stackFrames[0].line, 22);
        assert.equal(inside.stackFrames[1].line, 14);
        await session.customRequest("stepIn", { threadId: 1 });
        assert.equal(await stop(), "step");
        assert.equal((await session.customRequest("evaluate", { expression: "X", frameId: 2 })).result, "$1 (1)");
        await session.customRequest("stepOut", { threadId: 1 });
        assert.equal(await stop(), "step");
        const after = await session.customRequest("stackTrace", { threadId: 1 });
        assert.equal(after.stackFrames[0].line, 16);
        assert.equal(after.totalFrames, 1);
        assert.equal((await session.customRequest("evaluate", { expression: "X" })).result, "$2 (2)");
        const cycleCounts = await session.customRequest("retro/cycles");
        assert.equal(cycleCounts.lines.find((line: { line: number }) => line.line === 14).cycles, 6);
        assert.equal(cycleCounts.calls.find((call: { line: number }) => call.line === 14).cycles, 14);
        const video = await session.customRequest("retro/video");
        assert.equal(video.pixelFormat, "rgba");
        assert.equal(Buffer.from(video.pixels, "base64").length, 560 * 192 * 4);
        // A scanline breakpoint is a function breakpoint, so it is listed in the Breakpoints view.
        const before = await session.customRequest("apple2/beam");
        const scanline = new vscode.FunctionBreakpoint("scanline 3:25");
        vscode.debug.addBreakpoints([scanline]);
        assert.equal(await scanlineBound(session, 3, 25), true);
        await session.customRequest("continue", { threadId: 1 });
        assert.equal(await stop(), "function breakpoint");
        const beam = await session.customRequest("apple2/beam");
        assert.equal(beam.scanline, 3);
        assert.equal(beam.column, 25);
        assert.equal(beam.cycles, before.cycles + (((3 * 65 + 25) - before.cycleInFrame + 17030) % 17030 || 17030));
        vscode.debug.removeBreakpoints([scanline]);
        await vscode.commands.executeCommand("retrocore.clearCycles");
        assert.equal((await session.customRequest("retro/cycles")).lines.length, 0);
        await vscode.debug.stopDebugging(session);
        vscode.debug.removeBreakpoints([breakpoint]);
        console.log("Isolated VS Code passed: M1 source/caller debugging, RGBA video, source cycle counts, exact beam breakpoint and cycle-reset command.");

        // The workspace's boot configuration stops first at the Monitor's RESET, as Machine reset is on by default.
        assert.equal(await vscode.debug.startDebugging(workspace, "IIe: boot with SDK ROM sources"), true);
        assert.equal(await stop(), "breakpoint");
        const boot = vscode.debug.activeDebugSession;
        if (boot === undefined) throw new Error("VS Code did not create the boot session.");
        const reset = await boot.customRequest("stackTrace", { threadId: 1 });
        assert.equal(path.basename(reset.stackFrames[0].source.path), "Monitor.asm");
        assert.equal(reset.stackFrames[0].name, "RESET");

        // Then, once booted to the ] prompt, at AppleSoft's PRINT through a function breakpoint.
        vscode.debug.addBreakpoints([new vscode.FunctionBreakpoint("PRINT")]);
        await new Promise(resolve => setTimeout(resolve, 500));
        await boot.customRequest("continue", { threadId: 1 });
        await new Promise(resolve => setTimeout(resolve, 4000));
        for (const character of "PRINT 1\r") await boot.customRequest("retro/key", { code: character.charCodeAt(0) });
        assert.equal(await stop(), "function breakpoint");
        const print = await boot.customRequest("stackTrace", { threadId: 1 });
        assert.equal(path.basename(print.stackFrames[0].source.path), "applesoft.mac");
        assert.equal(print.stackFrames[0].name, "PRINT");

        // RESET's "jsr SETNORM" returned by then: JSR 6, LDY # 2, STY zp 3, RTS 6.
        const calls: { path: string; line: number; cycles: number }[] = (await boot.customRequest("retro/cycles")).calls;
        const monitor = path.join(root, "src", "Retrocore.Machines.Apple2", "Roms", "System", "Monitor.asm");
        const setnormLine = (await vscode.workspace.fs.readFile(vscode.Uri.file(monitor))).toString()
            .split("\n").findIndex(line => /^\s+jsr SETNORM\s+; \$FA63/.test(line)) + 1;
        const setnorm = calls.find(call => path.basename(call.path) === "Monitor.asm" && call.line === setnormLine);
        assert.equal(setnorm?.cycles, 17);

        // CONTROL-RESET stops again at RESET.
        vscode.debug.removeBreakpoints(vscode.debug.breakpoints);
        await new Promise(resolve => setTimeout(resolve, 500));
        await boot.customRequest("continue", { threadId: 1 });
        await boot.customRequest("retro/reset");
        assert.equal(await stop(), "breakpoint");
        assert.equal((await boot.customRequest("stackTrace", { threadId: 1 })).stackFrames[0].name, "RESET");
        await boot.customRequest("continue", { threadId: 1 });
        await new Promise(resolve => setTimeout(resolve, 1000));

        // AppleSoft on the BASIC thread: RUN stops at its first statement, as BASIC program start is on by
        // default, and a breakpoint on a program statement stops there.
        const text = "10 A=1\n20 PRINT A: A=2: GOSUB 100\n30 END\n100 B$=\"IIE\": RETURN\n";
        assert.equal((await boot.customRequest("retro/basic/write", { text })).success, true);
        const program = await vscode.commands.executeCommand<vscode.Uri>("retrocore.basic.open");
        await boot.customRequest("setBreakpoints", { source: { path: program.toString() }, breakpoints: [{ line: 2, column: 13 }, { line: 4, column: 16 }] });
        await boot.customRequest("continue", { threadId: 1 });
        for (const character of "RUN\r") await boot.customRequest("retro/key", { code: character.charCodeAt(0) });
        assert.equal(await stop(), "breakpoint");
        assert.equal((await boot.customRequest("stackTrace", { threadId: 2 })).stackFrames[0].name, "10: A=1");
        await boot.customRequest("continue", { threadId: 2 });
        assert.equal(await stop(), "breakpoint");
        const statement = await boot.customRequest("stackTrace", { threadId: 2 });
        assert.equal(statement.stackFrames[0].name, "20: A=2");

        // In the GOSUB, its frame is below, read from AppleSoft's stack; and AppleSoft's variables evaluate.
        await boot.customRequest("continue", { threadId: 2 });
        assert.equal(await stop(), "breakpoint");
        const gosub = await boot.customRequest("stackTrace", { threadId: 2 });
        assert.deepEqual(gosub.stackFrames.map((frame: { name: string }) => frame.name), ["100: RETURN", "20: GOSUB 100 (GOSUB)"]);
        const top = gosub.stackFrames[0].id;
        assert.equal((await boot.customRequest("evaluate", { expression: "A*10", frameId: top, context: "watch" })).result, "20");
        assert.equal((await boot.customRequest("evaluate", { expression: "B$", frameId: top, context: "watch" })).result, "\"IIE\"");
        await vscode.commands.executeCommand("workbench.action.closeAllEditors");
        await vscode.debug.stopDebugging(boot);
        vscode.debug.removeBreakpoints(vscode.debug.breakpoints);
        console.log("Isolated VS Code passed: the boot configuration stops at RESET as it powers on, at PRINT, at RESET after CONTROL-RESET, and at RUN's first statement.");

        // The Model I's boot configuration stops as it powers on, then at Level II's READY in the SDK source once
        // ENTER answers MEM SIZE?; its ROMs are assembled from those sources, so it needs no dumps.
        assert.equal(await vscode.debug.startDebugging(workspace, "Model I: boot Level II with SDK ROM sources"), true);
        assert.equal(await stop(), "breakpoint");
        const model = vscode.debug.activeDebugSession;
        if (model === undefined) throw new Error("VS Code did not create the Model I session.");
        const powerOn = await model.customRequest("stackTrace", { threadId: 1 });
        assert.equal(path.basename(powerOn.stackFrames[0].source.path), "Level2.asm");
        vscode.debug.addBreakpoints([new vscode.FunctionBreakpoint("READY")]);
        await new Promise(resolve => setTimeout(resolve, 500));
        await model.customRequest("continue", { threadId: 1 });
        await new Promise(resolve => setTimeout(resolve, 1500));
        await model.customRequest("retro/key", { code: 13 });
        assert.equal(await stop(), "function breakpoint");
        const ready = await model.customRequest("stackTrace", { threadId: 1 });
        assert.equal(path.basename(ready.stackFrames[0].source.path), "Level2.asm");
        assert.equal(ready.stackFrames[0].name, "READY");
        const display = await model.customRequest("retro/display");
        assert.equal(display.machine, "trs80-model1");
        assert.ok(display.rows.join("\n").includes("MEM SIZE?"));
        assert.equal(Buffer.from(display.video.pixels, "base64").length, 384 * 192 * 4);

        // The Retro Devices view has the machine's devices from retro/devices: this configuration has no disk
        // controller, so the cassette alone, empty and stopped.
        let listed: { id: string; media: unknown; transport?: { mode: string } }[] = [];
        for (let attempt = 0; attempt < 20 && listed.length === 0; attempt++) {
            await vscode.commands.executeCommand("retrocore.device.refresh");
            await new Promise(resolve => setTimeout(resolve, 150));
            listed = await vscode.commands.executeCommand("retrocore.device.list");
        }
        assert.deepEqual(listed.map(device => device.id), ["cassette"]);
        const installed: { id: string; value: string; devices: string[] }[] = await vscode.commands.executeCommand("retrocore.device.hardware");
        assert.deepEqual(installed.find(row => row.id === "cassette")?.devices, ["cassette"], "the cassette sits under its row");
        assert.equal(installed.find(row => row.id === "disk")?.value, "none");
        assert.equal(listed[0].media, null);
        assert.equal(listed[0].transport?.mode, "stopped");

        // Memory views open through VS Code's debug memory file system, as the Hex Editor does: it reads and writes
        // through readMemory and writeMemory, and the Model I has no banks beside the CPU's memory.
        const banks: MemoryBank[] = await vscode.commands.executeCommand("retrocore.memory.banks");
        assert.deepEqual(banks.map(bank => bank.name), [null]);
        const videoRam = memoryUri(model, "0x3C00", "video", { from: 0, to: 64 });
        const direct = Buffer.from((await model.customRequest("readMemory", { memoryReference: "0x3C00", count: 64 })).data, "base64");
        assert.deepEqual(Buffer.from(await vscode.workspace.fs.readFile(videoRam)), direct);
        assert.equal((await vscode.workspace.fs.stat(videoRam)).permissions, undefined, "the memory view is writable");
        await vscode.workspace.fs.writeFile(memoryUri(model, "0x3C00", "video", { from: 0, to: 1 }), Uint8Array.of(0x2A));
        assert.equal(Buffer.from((await model.customRequest("readMemory", { memoryReference: "0x3C00", count: 1 })).data, "base64")[0], 0x2A);

        // A function breakpoint from the Breakpoints view, with a hit count: Level II prints READY through
        // DISPLAY_CHAR, and the second character stops there. The hit count command reads its hits.
        vscode.debug.removeBreakpoints(vscode.debug.breakpoints);
        vscode.debug.addBreakpoints([new vscode.FunctionBreakpoint("DISPLAY_CHAR", true, undefined, "2")]);
        await new Promise(resolve => setTimeout(resolve, 500));
        await model.customRequest("continue", { threadId: 1 });
        assert.equal(await stop(), "function breakpoint");
        const hits: BreakpointHits[] = await vscode.commands.executeCommand("retrocore.breakpoints.list");
        const echo = hits.find(breakpoint => breakpoint.kind === "function breakpoint");
        assert.equal(echo?.location, "DISPLAY_CHAR ($0033)");
        assert.equal(echo?.hits, 2);
        assert.equal(echo?.hitCondition, "2");
        await vscode.commands.executeCommand("retrocore.breakpoints.resetHits");
        assert.equal((await vscode.commands.executeCommand<BreakpointHits[]>("retrocore.breakpoints.list"))[0].hits, 0);

        // The reset button stops at the non-maskable interrupt's handler, and restarts BASIC.
        vscode.debug.removeBreakpoints(vscode.debug.breakpoints);
        await new Promise(resolve => setTimeout(resolve, 500));
        await model.customRequest("continue", { threadId: 1 });
        await model.customRequest("retro/reset");
        assert.equal(await stop(), "breakpoint");
        assert.equal((await model.customRequest("stackTrace", { threadId: 1 })).stackFrames[0].name, "NMI");

        // The BASIC program editor, with the machine running at its prompt; RUN there runs without stopping.
        await model.customRequest("setExceptionBreakpoints", { filters: [] });
        await model.customRequest("continue", { threadId: 1 });
        await new Promise(resolve => setTimeout(resolve, 1000));
        await testBasicEditor(model, root);
        await testBasicThread(model, stop);
        await testBasicVariables(model, stop);
        await vscode.debug.stopDebugging(model);
        vscode.debug.removeBreakpoints(vscode.debug.breakpoints);
        console.log("Isolated VS Code passed: the Model I boot configuration stops as it powers on, at Level II's READY and at the reset button's NMI, lists its devices, reads and writes memory views, counts a function breakpoint's hits, edits, saves, imports and exports its BASIC program, and debugs it on the BASIC thread with its variables.");

        // A labeled BASIC file launched and debugged in place.
        await testBasicLaunch(root, stop);
        await testAppleSoftLaunch(root, romDirectory, stop);
        console.log("Isolated VS Code passed: a labeled Level II file and an AppleSoft file launch, stop on their first statements and debug in their own lines.");
    } finally {
        tracker.dispose();
        await vscode.debug.stopDebugging();
    }
}

/**
 * Waits, up to a second, for the debug host to list a scanline breakpoint as set. VS Code sends a breakpoint added
 * through its API on its own schedule, and does not report function breakpoints' state back to extensions.
 * @returns Whether the host has it.
 */
async function scanlineBound(session: vscode.DebugSession, scanline: number, column: number): Promise<boolean> {
    const location = `scanline ${scanline}:${column} (video beam)`;
    for (let attempt = 0; attempt < 40; attempt++) {
        const listed: unknown = await session.customRequest("retro/breakpoints");
        const breakpoints = typeof listed === "object" && listed !== null && "breakpoints" in listed && Array.isArray(listed.breakpoints)
            ? listed.breakpoints as unknown[] : [];
        if (breakpoints.some(breakpoint => typeof breakpoint === "object" && breakpoint !== null
            && "location" in breakpoint && breakpoint.location === location && "verified" in breakpoint && breakpoint.verified === true)) {
            return true;
        }
        await new Promise(done => setTimeout(done, 25));
    }
    return false;
}
