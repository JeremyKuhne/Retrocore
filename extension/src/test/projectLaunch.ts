// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import * as path from "node:path";
import * as vscode from "vscode";
import { untilStopShown } from "./stops";

/** Waits for a condition, checking every 100 milliseconds, up to a time. */
async function until(condition: () => boolean, milliseconds: number): Promise<boolean> {
    for (let waited = 0; waited < milliseconds && !condition(); waited += 100) await new Promise(resolve => setTimeout(resolve, 100));
    return condition();
}

/** The model the Machine view shows for the off machine "Project launch", once it is other than one shown before. */
async function offModel(before: string | undefined): Promise<string | undefined> {
    for (const end = Date.now() + 15000; Date.now() < end; await new Promise(resolve => setTimeout(resolve, 100))) {
        if (await vscode.commands.executeCommand<string | undefined>("retrocore.machine.off") !== "Project launch") continue;
        const rows = await vscode.commands.executeCommand<{ id: string; value: string }[]>("retrocore.device.hardware");
        const value = rows.find(row => row.id === "model")?.value;
        if (value !== undefined && value !== before) return value;
    }
    return undefined;
}

/**
 * A project launch (sample/project's retrocore.json) builds its target and debugs it, and the session's configuration
 * names the target's machine, which the views and requests read.
 */
export async function testProjectLaunch(workspace: vscode.WorkspaceFolder): Promise<void> {
    const root = workspace.uri.fsPath;
    const debugHost = path.join(root, "artifacts/AnyCPU/Release/Retrocore.Debug/net11.0/Retrocore.Debug.dll");
    const sdkRoms = path.join(root, "src/Retrocore.Machines.Apple2/Roms");
    // What the Machine view shows of the off machine each launch leaves: its model row's value.
    const offModels: string[] = [];
    try {
        for (const [target, model] of [["apple2-iiplus", "iiplus"], ["hello/apple2-iie", "iie-enhanced"]]) {
            const started = new Promise<vscode.DebugSession>(resolve => {
                const listener = vscode.debug.onDidStartDebugSession(session => { listener.dispose(); resolve(session); });
            });
            assert.equal(await vscode.debug.startDebugging(workspace, {
                type: "retrocore", request: "launch", name: "Project launch", debugHost, sdkRoms,
                project: path.join(root, "sample", "project"), target
            }), true, `the ${target} launch starts`);
            const session = await started;
            await untilStopShown(session, 30000);
            assert.equal(session.configuration.machine, "apple2", "the target's machine is the session's");
            assert.equal(session.configuration.model, model, "and its model");
            assert.equal((session.configuration.retrocoreTarget as { target?: string } | undefined)?.target,
                target.includes("/") ? target : `hello/${target}`);
            const ended = new Promise<void>(resolve => {
                const listener = vscode.debug.onDidTerminateDebugSession(done => {
                    if (done.id === session.id) { listener.dispose(); resolve(); }
                });
            });
            await vscode.debug.stopDebugging(session);
            await ended;
            // Once it ends the views show it off, as the target's machine.
            const value = await offModel(offModels.at(-1));
            assert.ok(value !== undefined, `the off machine is the ${target} target's`);
            offModels.push(value);
        }
        assert.ok(await until(() => vscode.debug.activeDebugSession === undefined, 5000));
        console.log(`The off machines were: ${offModels.join(", ")}.`);
        console.log("Isolated VS Code passed: a project launch builds and debugs each target, its session names the target's machine, and the off machine it leaves is that target's.");
    } finally {
        await vscode.debug.stopDebugging();
    }
}
