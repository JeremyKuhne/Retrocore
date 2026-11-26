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

/**
 * A project launch (sample/project's retrocore.json) builds its target and debugs it, and the session's configuration
 * names the target's machine, which the views and requests read.
 */
export async function testProjectLaunch(workspace: vscode.WorkspaceFolder): Promise<void> {
    const root = workspace.uri.fsPath;
    const debugHost = path.join(root, "artifacts/AnyCPU/Release/Retrocore.Debug/net11.0/Retrocore.Debug.dll");
    const sdkRoms = path.join(root, "src/Retrocore.Machines.Apple2/Roms");
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
        }
        assert.ok(await until(() => vscode.debug.activeDebugSession === undefined, 5000));
        console.log("Isolated VS Code passed: a project launch builds and debugs each target, and its session names the target's machine.");
    } finally {
        await vscode.debug.stopDebugging();
    }
}
