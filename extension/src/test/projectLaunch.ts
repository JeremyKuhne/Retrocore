// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import * as fs from "node:fs";
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

        // The active target: picked by its project's file and name, as the status bar's quick pick does, named by
        // retrocore.activeTarget, and launched through ${command:retrocore.activeTarget}.
        const file = path.join(root, "sample", "project", "retrocore.json");
        assert.equal(await vscode.commands.executeCommand("retrocore.pickTarget", file, "apple2-iiplus"), "hello/apple2-iiplus");
        assert.equal(await vscode.commands.executeCommand("retrocore.activeTarget"), "hello/apple2-iiplus");
        assert.equal(await vscode.commands.executeCommand("retrocore.pickTarget", file, "apple2-iie"), "hello/apple2-iie");
        assert.equal(await vscode.commands.executeCommand("retrocore.activeTarget"), "hello/apple2-iie", "the pick is kept");
        assert.deepEqual(await vscode.commands.executeCommand("retrocore.activeTarget.statusBar"),
            { text: "$(target) hello · apple2-iie", command: "retrocore.pickTarget", visible: true }, "the status bar shows it");
        const started = new Promise<vscode.DebugSession>(resolve => {
            const listener = vscode.debug.onDidStartDebugSession(session => { listener.dispose(); resolve(session); });
        });
        assert.equal(await vscode.debug.startDebugging(workspace, {
            type: "retrocore", request: "launch", name: "Active target", debugHost, sdkRoms,
            project: "${workspaceFolder}/sample/project", target: "${command:retrocore.activeTarget}"
        }), true, "the active target's launch starts");
        const session = await started;
        await untilStopShown(session, 30000);
        assert.equal(session.configuration.target, "hello/apple2-iie");
        assert.equal(session.configuration.model, "iie-enhanced");
        await vscode.debug.stopDebugging(session);
        assert.ok(await until(() => vscode.debug.activeDebugSession === undefined, 10000));
        console.log("Isolated VS Code passed: the active target is picked, kept, named by retrocore.activeTarget and debugged through it.");

        // The project file's schema checks a retrocore.json: here one with a field the schema lacks.
        const folder = path.join(root, "artifacts", "schema-check");
        fs.mkdirSync(folder, { recursive: true });
        const checked = path.join(folder, "retrocore.json");
        // A $schema line would make VS Code load the schema from its id, which it does not serve; the file's name is
        // enough.
        fs.writeFileSync(checked, `// A project file, with comments and a trailing comma.
{ "sdk": "1", "name": "check", "cpu": "6502",
  "sources": ["a.s"], "bogus": 1, "targets": { "a": { "machine": "pet4032", "environment": "bare" } }, }
`);
        const document = await vscode.workspace.openTextDocument(checked);
        await vscode.window.showTextDocument(document);
        const problems = (): vscode.Diagnostic[] => vscode.languages.getDiagnostics(document.uri);
        assert.ok(await until(() => problems().some(problem => problem.message.includes("bogus")), 20000),
            "the schema reports the unknown field: " + JSON.stringify(problems().map(problem => problem.message)));
        assert.equal(document.languageId, "jsonc", "a project file is JSON with comments");
        assert.deepEqual(problems().map(problem => problem.message).filter(message => !message.includes("bogus")), [],
            "and only the unknown field is a problem");
        await vscode.commands.executeCommand("workbench.action.closeActiveEditor");
        console.log("Isolated VS Code passed: the project file's schema checks retrocore.json.");
        console.log("Isolated VS Code passed: a project launch builds and debugs each target, its session names the target's machine, and the off machine it leaves is that target's.");
    } finally {
        await vscode.debug.stopDebugging();
    }
}
