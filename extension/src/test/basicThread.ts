// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import * as vscode from "vscode";

interface Frame { name: string; line: number; column: number; source?: { path: string } }

const program = [
    "10 A=1",
    "20 GOSUB 100: A=A+1",
    "30 GOTO 20",
    "100 B=2: RETURN",
    ""
].join("\n");

/** Drives the BASIC thread on a running Level II machine at its prompt: breakpoints, frames, steps and stops. */
export async function testBasicThread(session: vscode.DebugSession, stop: () => Promise<string>): Promise<void> {
    const basic = 2;
    const write = async (text: string): Promise<void> => {
        assert.equal((await session.customRequest("retro/basic/write", { text }) as { success: boolean }).success, true);
    };
    const type = async (text: string): Promise<void> => {
        for (const character of text) await session.customRequest("retro/key", { code: character.charCodeAt(0) });
    };
    const frames = async (): Promise<Frame[]> => (await session.customRequest("stackTrace", { threadId: basic })).stackFrames;
    const top = async (): Promise<string> => (await frames())[0].name;

    const threads = (await session.customRequest("threads")).threads as { id: number; name: string }[];
    assert.deepEqual(threads.map(thread => thread.name), ["Model I Z80", "BASIC"]);
    assert.equal(await top(), "BASIC: ready");

    // A breakpoint in the machine's program stops the BASIC thread there, with the GOSUB that called it below.
    await write(program);
    const uri = await vscode.commands.executeCommand<vscode.Uri>("retrocore.basic.open");
    const inSubroutine = new vscode.SourceBreakpoint(new vscode.Location(uri, new vscode.Position(3, 0)));
    vscode.debug.addBreakpoints([inSubroutine]);
    await new Promise(resolve => setTimeout(resolve, 500));

    // BASIC program start stops at the first statement RUN runs.
    await session.customRequest("setExceptionBreakpoints", { filters: ["basicStart"] });
    await type("RUN\r");
    assert.equal(await stop(), "breakpoint");
    assert.equal(await top(), "10: A=1");
    await session.customRequest("setExceptionBreakpoints", { filters: [] });
    await session.customRequest("continue", { threadId: basic });
    assert.equal(await stop(), "breakpoint");
    const stack = await frames();
    assert.deepEqual(stack.map(frame => frame.name), ["100: B=2", "20: GOSUB 100 (GOSUB)"]);
    assert.deepEqual([stack[0].line, stack[0].column, stack[1].line], [4, 5, 2]);
    assert.equal(stack[0].source?.path, uri.toString());
    vscode.debug.removeBreakpoints([inSubroutine]);
    await new Promise(resolve => setTimeout(resolve, 300));

    // Step Into goes statement by statement; Step Out runs to the statement after the GOSUB; Step Over runs a
    // GOSUB without stopping in it.
    await session.customRequest("stepIn", { threadId: basic });
    assert.equal(await stop(), "step");
    assert.equal(await top(), "100: RETURN");
    await session.customRequest("stepOut", { threadId: basic });
    assert.equal(await stop(), "step");
    assert.equal(await top(), "20: A=A+1");
    await session.customRequest("next", { threadId: basic });
    assert.equal(await stop(), "step");
    assert.equal(await top(), "30: GOTO 20");
    await session.customRequest("next", { threadId: basic });
    assert.equal(await stop(), "step");
    assert.equal(await top(), "20: GOSUB 100");
    await session.customRequest("next", { threadId: basic });
    assert.equal(await stop(), "step");
    assert.equal(await top(), "20: A=A+1", "Step Over ran the GOSUB");

    // Set Next Statement moves BASIC as a GOTO would.
    const targets = (await session.customRequest("gotoTargets", { source: { path: uri.toString() }, line: 1 })).targets as { id: number; label: string }[];
    assert.equal(targets[0].label, "10: A=1");
    await session.customRequest("goto", { threadId: basic, targetId: targets[0].id });
    assert.equal(await stop(), "goto");
    assert.equal(await top(), "10: A=1");

    // An inline breakpoint stops at a later statement on its line.
    const locations = (await session.customRequest("breakpointLocations", { source: { path: uri.toString() }, line: 2 })).breakpoints as { column: number }[];
    assert.deepEqual(locations.map(location => location.column), [4, 15]);
    const inline = new vscode.SourceBreakpoint(new vscode.Location(uri, new vscode.Position(1, 14)));
    vscode.debug.addBreakpoints([inline]);
    await new Promise(resolve => setTimeout(resolve, 300));
    await session.customRequest("continue", { threadId: basic });
    assert.equal(await stop(), "breakpoint");
    assert.deepEqual((await frames())[0].column, 15);
    vscode.debug.removeBreakpoints([inline]);
    await new Promise(resolve => setTimeout(resolve, 300));

    // Pause on the BASIC thread stops at a statement.
    await session.customRequest("continue", { threadId: basic });
    await new Promise(resolve => setTimeout(resolve, 300));
    await session.customRequest("pause", { threadId: basic });
    assert.equal(await stop(), "pause");
    assert.match(await top(), /^(10|20|30|100): /);

    // A BASIC error stops at the statement that failed; STOP stops when its filter is on.
    await session.customRequest("setExceptionBreakpoints", { filters: ["basicErrors", "basicStop"] });
    await write("10 PRINT 1/0\n");
    await session.customRequest("continue", { threadId: basic });
    await type("RUN\r");
    assert.equal(await stop(), "exception");
    assert.match((await session.customRequest("exceptionInfo", { threadId: basic })).description, /\?\/0 ERROR in 10/);
    assert.equal(await top(), "10: PRINT 1/0");
    await write("10 STOP\n20 A=3\n");
    await session.customRequest("continue", { threadId: basic });
    await type("RUN\r");
    assert.equal(await stop(), "exception");
    assert.match((await session.customRequest("exceptionInfo", { threadId: basic })).description, /^STOP in 10/);

    // BASIC program start also stops where CONT resumes.
    await session.customRequest("setExceptionBreakpoints", { filters: ["basicStart"] });
    await session.customRequest("continue", { threadId: basic });
    await new Promise(resolve => setTimeout(resolve, 300));
    await type("CONT\r");
    assert.equal(await stop(), "breakpoint");
    assert.equal(await top(), "20: A=3");
    await session.customRequest("setExceptionBreakpoints", { filters: [] });
    await session.customRequest("continue", { threadId: basic });
    await vscode.commands.executeCommand("workbench.action.closeAllEditors");
}
