// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import * as path from "node:path";
import * as vscode from "vscode";
import { untilStopShown } from "./stops";

/**
 * In a project folder with no launch.json (sample/project, opened by itself), the status bar picks a target and F5
 * builds and debugs it. The extension starts for the folder's retrocore.json, and finds the repository's debug host
 * above the folder.
 */
export async function testNoLaunchJson(workspace: vscode.WorkspaceFolder): Promise<void> {
    const file = path.join(workspace.uri.fsPath, "retrocore.json");
    for (const end = Date.now() + 30000; !(await vscode.commands.getCommands(true)).includes("retrocore.pickTarget");) {
        if (Date.now() > end) throw new Error("The extension did not start for the folder's retrocore.json.");
        await new Promise(resolve => setTimeout(resolve, 200));
    }
    assert.equal(await vscode.commands.executeCommand("retrocore.pickTarget", file, "apple2-iie"), "hello/apple2-iie");
    assert.deepEqual(await vscode.commands.executeCommand("retrocore.activeTarget.statusBar"),
        { text: "$(target) hello · apple2-iie", command: "retrocore.pickTarget", visible: true });

    // F5: VS Code's own Start Debugging, which sends the empty configuration a folder without a launch.json gives.
    const source = await vscode.workspace.openTextDocument(path.join(workspace.uri.fsPath, "src", "hello.s"));
    await vscode.window.showTextDocument(source);
    const started = new Promise<vscode.DebugSession>((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error("F5 started no debug session.")), 60000);
        const listener = vscode.debug.onDidStartDebugSession(session => { clearTimeout(timer); listener.dispose(); resolve(session); });
    });
    await vscode.commands.executeCommand("workbench.action.debug.start");
    const session = await started;
    try {
        await untilStopShown(session, 30000);
        assert.equal(session.configuration.name, "hello · apple2-iie (Retrocore)");
        assert.equal(session.configuration.project, file);
        assert.equal(session.configuration.target, "hello/apple2-iie");
        assert.equal(session.configuration.model, "iie-enhanced");
        console.log("Isolated VS Code passed: in sample/project with no launch.json, the status bar's target is picked and F5 builds and debugs it.");
    } finally {
        await vscode.debug.stopDebugging(session);
    }
}
