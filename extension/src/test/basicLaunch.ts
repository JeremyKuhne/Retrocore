// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as vscode from "vscode";

interface Frame { id: number; name: string; line: number; column: number; source?: { path: string } }

async function until<T>(what: string, probe: () => Promise<T | undefined> | T | undefined, timeout = 20000): Promise<T> {
    for (const end = Date.now() + timeout; ;) {
        const value = await probe();
        if (value !== undefined) return value;
        if (Date.now() > end) throw new Error(`Timed out waiting for ${what}.`);
        await new Promise(resolve => setTimeout(resolve, 200));
    }
}

const programDocument = (session: vscode.DebugSession): vscode.TextDocument | undefined =>
    vscode.workspace.textDocuments.find(document => document.uri.scheme === "retrocore-basic" && document.uri.authority === session.id);

const programTabs = (): vscode.Tab[] => vscode.window.tabGroups.all.flatMap(group => group.tabs)
    .filter(tab => tab.input instanceof vscode.TabInputText && tab.input.uri.scheme === "retrocore-basic");

const program = [
    "' retrocore level2",
    "    CLS",
    "loop:",
    "    A = A + 1",
    "    IF A < 3 THEN loop",
    "    GOSUB @show",
    "    END",
    "@show",
    "    PRINT \"DONE\"; A",
    "    RETURN",
    ""
].join("\n");

/** Launches an AppleSoft file on the IIe, which boots to AppleSoft's prompt, and stops on its first statement. */
export async function testAppleSoftLaunch(root: string, romDirectory: string, stop: () => Promise<string>): Promise<void> {
    const folder = path.join(root, "artifacts", "vscode-m1-tests", "basic-launch");
    fs.mkdirSync(folder, { recursive: true });
    const file = path.join(folder, "hello.applesoft.bas");
    fs.writeFileSync(file, "REM retrocore applesoft\n    HOME\nagain:\n    PRINT \"HELLO\": GOTO again\n");
    assert.ok(await vscode.debug.startDebugging(vscode.workspace.workspaceFolders?.[0], {
        type: "retrocore", request: "launch", name: "AppleSoft file", machine: "apple2", romDirectory, basic: file, stopOnEntry: true,
        debugHost: path.join(root, "artifacts", "AnyCPU", "Release", "Retrocore.Debug", "net10.0", "Retrocore.Debug.dll")
    }));
    const session = vscode.debug.activeDebugSession;
    if (session === undefined) throw new Error("VS Code did not create the AppleSoft session.");
    try {
        assert.equal(await stop(), "entry");
        const first = (await session.customRequest("stackTrace", { threadId: 2 })).stackFrames[0] as Frame;
        assert.equal(first.name, "10: HOME");
        assert.equal(first.source?.path.toLowerCase(), file.toLowerCase());
        await session.customRequest("next", { threadId: 2 });
        assert.equal(await stop(), "step");
        assert.equal(((await session.customRequest("stackTrace", { threadId: 2 })).stackFrames[0] as Frame).line, 4);
    } finally {
        await vscode.debug.stopDebugging(session);
    }
}

/** Launches a labeled Level II file on a Model I and debugs it in place: its frames and breakpoints are its lines. */
export async function testBasicLaunch(root: string, stop: () => Promise<string>): Promise<void> {
    const folder = path.join(root, "artifacts", "vscode-m1-tests", "basic-launch");
    fs.mkdirSync(folder, { recursive: true });
    const file = path.join(folder, "loop.level2.bas");
    fs.writeFileSync(file, program);
    const workspace = vscode.workspace.workspaceFolders?.[0];
    assert.ok(await vscode.debug.startDebugging(workspace, {
        type: "retrocore", request: "launch", name: "BASIC file", machine: "trs80-model1", basic: file, stopOnEntry: true,
        debugHost: path.join(root, "artifacts", "AnyCPU", "Release", "Retrocore.Debug", "net10.0", "Retrocore.Debug.dll")
    }));
    const session = vscode.debug.activeDebugSession;
    if (session === undefined) throw new Error("VS Code did not create the BASIC session.");
    try {
        const frames = async (): Promise<Frame[]> => (await session.customRequest("stackTrace", { threadId: 2 })).stackFrames;

        // It stops on the first statement, in the file, through its line map.
        assert.equal(await stop(), "entry");
        const first = (await frames())[0];
        assert.equal(first.name, "10: CLS");
        assert.equal(first.source?.path.toLowerCase(), file.toLowerCase());
        assert.deepEqual([first.line, first.column], [2, 5]);

        // A BASIC launch opens the program in memory in its editor, and Retro Devices lists it.
        const document = await until("the program editor to open", () => programDocument(session));
        assert.match(document.getText(), /^10 CLS/);
        assert.match(await until("the BASIC program row", async () => await vscode.commands.executeCommand<string | undefined>("retrocore.device.basic")) ?? "",
            /BASIC · \d+ lines$/);

        // A breakpoint in the file stops in the subroutine, with the GOSUB below it in the file too.
        const breakpoint = new vscode.SourceBreakpoint(new vscode.Location(vscode.Uri.file(file), new vscode.Position(8, 0)));
        vscode.debug.addBreakpoints([breakpoint]);
        await new Promise(resolve => setTimeout(resolve, 500));
        await session.customRequest("continue", { threadId: 2 });
        assert.equal(await stop(), "breakpoint");
        const inside = await frames();
        assert.deepEqual(inside.map(frame => [frame.name, frame.line]), [["60: PRINT \"DONE\"; A", 9], ["40: GOSUB 60 (GOSUB)", 6]]);
        assert.equal((await session.customRequest("evaluate", { expression: "A", frameId: inside[0].id, context: "watch" })).result, "3");

        // Once the program in memory changes, the file no longer matches it and its breakpoint is not bound.
        assert.equal((await session.customRequest("retro/basic/write", { text: "10 PRINT 1\n" })).success, true);
        await new Promise(resolve => setTimeout(resolve, 500));
        const listed = (await session.customRequest("retro/breakpoints")).breakpoints as { path?: string; verified: boolean; message?: string }[];
        const mine = listed.find(entry => entry.path?.toLowerCase() === file.toLowerCase());
        assert.equal(mine?.verified, false);
        assert.match(mine?.message ?? "", /does not match/);
        vscode.debug.removeBreakpoints([breakpoint]);

        // Edits not saved when the session ends move to an unsaved copy, and the program's editor closes.
        await until("the editor to follow the write", () => document.getText() === "10 PRINT 1\n" ? true : undefined);
        const edit = new vscode.WorkspaceEdit();
        edit.insert(document.uri, new vscode.Position(1, 0), "20 PRINT 2\n");
        assert.ok(await vscode.workspace.applyEdit(edit));
        assert.ok(document.isDirty);
    } finally {
        await vscode.debug.stopDebugging(session);
    }

    const copies = await until("the unsaved copy", async () => {
        const found = await vscode.commands.executeCommand<string[]>("retrocore.basic.endedCopies");
        return found.length !== 0 && programTabs().length === 0 ? found : undefined;
    });
    const copy = vscode.workspace.textDocuments.find(document => document.uri.toString() === copies.at(-1));
    assert.equal(copy?.getText(), "10 PRINT 1\n20 PRINT 2\n");
    assert.equal(copy?.isUntitled, true);
    assert.equal(copy?.languageId, "retrocore-level2");
    assert.equal(await vscode.commands.executeCommand<string | undefined>("retrocore.device.basic"), undefined, "an ended machine has no program row");
    if (copy !== undefined) {
        await vscode.window.showTextDocument(copy);
        await vscode.commands.executeCommand("workbench.action.revertAndCloseActiveEditor");
    }
}
