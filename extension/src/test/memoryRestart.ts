// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import * as path from "node:path";
import * as vscode from "vscode";
import { openMemory } from "../memory";

/** The Retrocore Memory tabs open, each as its title and the session its URI names. */
function memoryTabs(): string[] {
    return vscode.window.tabGroups.all.flatMap(group => group.tabs)
        .filter(tab => tab.input instanceof vscode.TabInputCustom && tab.input.viewType === "retrocore.memory")
        .map(tab => `${tab.label} @${(tab.input as vscode.TabInputCustom).uri.authority}`);
}

/** Waits for a condition, checking every 100 milliseconds, up to a time. */
async function until(condition: () => boolean, milliseconds: number): Promise<boolean> {
    for (let waited = 0; waited < milliseconds && !condition(); waited += 100) await new Promise(resolve => setTimeout(resolve, 100));
    return condition();
}

/**
 * Restarting a session keeps its Retrocore Memory editors, which read the new machine, and stopping it closes them.
 * VS Code restarts a session by ending it with restart set and starting it again with the same id.
 */
export async function testMemoryRestart(workspace: vscode.WorkspaceFolder): Promise<void> {
    const root = workspace.uri.fsPath;
    let ready = 0;
    const tracker = vscode.debug.registerDebugAdapterTrackerFactory("retrocore", {
        createDebugAdapterTracker() {
            return {
                onDidSendMessage(message: { command?: string }) {
                    if (message.command === "configurationDone") ready++;
                }
            };
        }
    });
    try {
        // The Z80 sample, without its build task, which the editor tests' build has done.
        const configuration = {
            type: "retrocore", request: "launch", name: "Memory restart", machine: "trs80-model1",
            debugHost: path.join(root, "artifacts/AnyCPU/Release/Retrocore.Debug/net11.0/Retrocore.Debug.dll"),
            sdkRoms: path.join(root, "src/Retrocore.Machines.Trs80/Roms"),
            source: path.join(root, "sample/trs80/hello.asm"),
            stopOnEntry: true
        };
        assert.equal(await vscode.debug.startDebugging(workspace, configuration), true);
        assert.ok(await until(() => ready === 1, 15000), "the session starts");
        const session = vscode.debug.activeDebugSession;
        if (session === undefined) throw new Error("VS Code did not create the session.");
        await openMemory(session, "0x4000");
        const open = [`Memory $4000 @${session.id}`];
        assert.deepEqual(memoryTabs(), open);

        await vscode.commands.executeCommand("workbench.action.debug.restart");
        assert.ok(await until(() => ready === 2, 15000), "the session restarts");
        assert.equal(vscode.debug.activeDebugSession?.id, session.id, "a restart keeps the session's id");
        assert.deepEqual(memoryTabs(), open, "the editor stays open");
        const state = await vscode.commands.executeCommand<{ ended: boolean; cursor: number }>("retrocore.memory.test", [{ goto: 0x4001 }]);
        assert.deepEqual([state.ended, state.cursor], [false, 0x4001], "and reads the restarted machine");

        await vscode.commands.executeCommand("workbench.action.debug.stop");
        assert.ok(await until(() => memoryTabs().length === 0, 10000), "stopping closes the editor: " + JSON.stringify(memoryTabs()));
        // A tab whose session is gone, as VS Code restores after a reload, closes as it opens.
        const gone = vscode.Uri.from({ scheme: "retrocore-memory", authority: "ended-session", path: "/0x4000/Memory $4000" });
        await vscode.commands.executeCommand("vscode.openWith", gone, "retrocore.memory");
        assert.ok(await until(() => memoryTabs().length === 0, 5000), "an ended session's tab closes: " + JSON.stringify(memoryTabs()));
        console.log("Isolated VS Code passed: Retrocore Memory stays open and reads the machine again when its session restarts, and closes when it stops or its session is gone.");

        // The space list puts a bank in an editor's place, at the cursor's address: the IIe's auxiliary RAM here.
        const iie = {
            type: "retrocore", request: "launch", name: "Memory spaces", machine: "apple2", model: "iie-enhanced",
            debugHost: configuration.debugHost, sdkRoms: path.join(root, "src/Retrocore.Machines.Apple2/Roms"), stopOnEntry: true
        };
        assert.equal(await vscode.debug.startDebugging(workspace, iie), true);
        assert.ok(await until(() => ready === 3, 20000), "the IIe starts");
        const apple = vscode.debug.activeDebugSession;
        if (apple === undefined) throw new Error("VS Code did not create the IIe session.");
        await openMemory(apple, "0x0400");
        assert.deepEqual(memoryTabs(), [`Memory $0400 @${apple.id}`]);
        await vscode.commands.executeCommand("retrocore.memory.test", [{ goto: 0x0410 }, { space: "aux" }]);
        assert.ok(await until(() => memoryTabs().length === 1 && memoryTabs()[0] === `Memory aux:$0410 @${apple.id}`, 5000),
            "the bank opens in the editor's place: " + JSON.stringify(memoryTabs()));
        await vscode.debug.stopDebugging(apple);
        console.log("Isolated VS Code passed: the space list opens a bank in a Retrocore Memory editor's place.");
    } finally {
        tracker.dispose();
        await vscode.debug.stopDebugging();
    }
}
