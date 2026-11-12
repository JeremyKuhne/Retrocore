// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as vscode from "vscode";
import * as path from "node:path";
import * as assert from "node:assert/strict";

/**
 * Breakpoints in the machine-program document, in VS Code's own list: one follows its BASIC line when the program is
 * edited, keeping its condition; one on a deleted line goes; and all go when the session ends, as the program does. A
 * IIe built from the SDK's sources runs it, so it needs no ROM dumps.
 */
export async function testProgramBreakpoints(workspace: vscode.WorkspaceFolder): Promise<void> {
    const root = workspace.uri.fsPath;
    assert.ok(await vscode.debug.startDebugging(workspace, {
        type: "retrocore", request: "launch", name: "Program breakpoints", machine: "apple2", model: "iie-enhanced",
        stopOnEntry: false, sound: "off",
        debugHost: path.join(root, "artifacts", "AnyCPU", "Release", "Retrocore.Debug", "net10.0", "Retrocore.Debug.dll")
    }));
    const session = vscode.debug.activeDebugSession;
    if (session === undefined) throw new Error("VS Code did not create the session.");
    const until = async (test: () => boolean | Promise<boolean>, what: string): Promise<void> => {
        for (const end = Date.now() + 10000; Date.now() < end; await new Promise(resolve => setTimeout(resolve, 100))) {
            if (await test()) return;
        }
        assert.fail(what);
    };

    try {
        // Machine reset, on by default, stops as the machine powers on.
        await new Promise(resolve => setTimeout(resolve, 1000));
        await Promise.resolve(session.customRequest("continue", { threadId: 1 })).catch(() => undefined);
        await until(async () => (await session.customRequest("apple2/text")).rows.join("\n").includes("]"), "AppleSoft's prompt");
        const write = async (text: string): Promise<void> =>
            assert.equal((await session.customRequest("retro/basic/write", { text })).success, true);
        await write("10 A=1\n20 PRINT A\n30 END\n");
        const program = await vscode.commands.executeCommand<vscode.Uri>("retrocore.basic.open");
        const lineOf = async (number: number): Promise<number> => (await vscode.workspace.openTextDocument(program)).getText()
            .split(/\r?\n/).findIndex(line => line.startsWith(`${number} `));
        const inProgram = (): vscode.SourceBreakpoint[] => vscode.debug.breakpoints.filter(
            (breakpoint): breakpoint is vscode.SourceBreakpoint => breakpoint instanceof vscode.SourceBreakpoint
                && breakpoint.location.uri.toString() === program.toString());

        const twenty = await lineOf(20);
        const thirty = await lineOf(30);
        vscode.debug.addBreakpoints([
            new vscode.SourceBreakpoint(new vscode.Location(program, new vscode.Position(twenty, 0)), true, "A > 0"),
            new vscode.SourceBreakpoint(new vscode.Location(program, new vscode.Position(thirty, 0)))
        ]);
        await new Promise(resolve => setTimeout(resolve, 500));

        // Line 5 goes in above both, and line 30 is deleted.
        await write("5 HOME\n10 A=1\n20 PRINT A\n");
        await until(() => inProgram().length === 1 && inProgram()[0].location.range.start.line === twenty + 1,
            "line 20's breakpoint follows it down, and line 30's goes with it");
        assert.equal(inProgram()[0].condition, "A > 0");

        await vscode.commands.executeCommand("workbench.action.closeAllEditors");
        await vscode.debug.stopDebugging(session);
        await until(() => inProgram().length === 0, "the session's end removes the program document's breakpoints");
    } finally {
        if (vscode.debug.activeDebugSession === session) await vscode.debug.stopDebugging(session);
        vscode.debug.removeBreakpoints(vscode.debug.breakpoints);
    }

    console.log("Program breakpoints passed: a breakpoint follows its BASIC line through an edit with its condition, goes with a deleted line, and all go when the session ends.");
}
