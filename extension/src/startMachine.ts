// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Retrocore: Start Machine, Start Last Machine and Save Last Machine as Launch Configuration: quick picks for a
// machine and what it runs, then Start, Options… or Save as Launch Configuration. startFlow.ts builds the launch
// configuration; this shows the picks and starts it.

import * as path from "node:path";
import * as vscode from "vscode";
import { machines, type Machine } from "./machines";
import {
    describeSetup, isUsable, optionValue, runChoices, setupConfiguration, withOption, type RunChoice, type Setup
} from "./startFlow";

const lastKey = "retrocore.lastSetup";

type MachineItem = vscode.QuickPickItem & { machine?: Machine; last?: Setup };
type RunItem = vscode.QuickPickItem & { choice: RunChoice; path?: string };
type ActionItem = vscode.QuickPickItem & { action: "start" | "options" | "save" };

function folder(): vscode.WorkspaceFolder | undefined {
    return vscode.workspace.workspaceFolders?.[0];
}

/** Registers the commands. */
export function registerStartMachine(context: vscode.ExtensionContext): void {
    const state = context.workspaceState;
    const last = (): Setup | undefined => {
        const setup = state.get<Setup>(lastKey);
        return isUsable(setup) ? setup : undefined;
    };

    const start = async (setup: Setup): Promise<boolean> => {
        await state.update(lastKey, setup);
        return vscode.debug.startDebugging(folder(), setupConfiguration(setup) as vscode.DebugConfiguration);
    };

    context.subscriptions.push(vscode.commands.registerCommand("retrocore.startMachine", async (given?: Setup) => {
        if (given !== undefined) return start(given);
        const picked = await pickSetup(last());
        if (picked === undefined) return false;
        if (picked.action === "save") return save(picked.setup);
        return start(picked.setup);
    }));

    context.subscriptions.push(vscode.commands.registerCommand("retrocore.startLastMachine", async () => {
        const setup = last();
        return setup === undefined ? vscode.commands.executeCommand("retrocore.startMachine") : start(setup);
    }));

    context.subscriptions.push(vscode.commands.registerCommand("retrocore.saveLaunchConfiguration", async (name?: string) => {
        const setup = last();
        if (setup === undefined) {
            await vscode.window.showInformationMessage("Retrocore: start a machine with Start Machine first, then save it.");
            return false;
        }

        return save(setup, name);
    }));
}

// The picks: the machine (or the last setup), what it runs, then Start, Options… or Save.
async function pickSetup(previous: Setup | undefined): Promise<{ setup: Setup; action: "start" | "save" } | undefined> {
    const items: MachineItem[] = [];
    if (previous !== undefined) {
        items.push({ label: "$(history) " + describeSetup(previous), detail: "Start what was started last", last: previous });
        items.push({ label: "Machines", kind: vscode.QuickPickItemKind.Separator });
    }

    for (const machine of machines) items.push({ label: machine.label, detail: machine.detail, machine });
    const chosen = await vscode.window.showQuickPick(items, { title: "Start a machine", placeHolder: "Which machine?" });
    if (chosen === undefined) return undefined;
    if (chosen.last !== undefined) return { setup: chosen.last, action: "start" };
    const machine = chosen.machine;
    if (machine === undefined) return undefined;

    const run = await pickRun(machine);
    if (run === undefined) return undefined;
    let setup: Setup = { machineId: machine.id, kind: run.kind, path: run.path, options: {} };

    // Start or save, after any options.
    for (;;) {
        const actions: ActionItem[] = [{ label: "$(play) Start", detail: describeSetup(setup), action: "start" }];
        if (machine.choices.length !== 0) {
            actions.push({ label: "$(settings) Options…", detail: "Change " + machine.choices.map(choice => choice.label.toLowerCase()).join(", "), action: "options" });
        }

        actions.push({ label: "$(save) Save as Launch Configuration", detail: "Adds it to the workspace's launch.json", action: "save" });
        const action = await vscode.window.showQuickPick(actions, { title: `Start ${machine.label}` });
        if (action === undefined) return undefined;
        if (action.action !== "options") return { setup, action: action.action };
        setup = await pickOptions(machine, setup);
    }
}

// What the machine runs: a choice, and the file for every choice but the bare machine. The active editor's file comes
// first when the machine can run it.
async function pickRun(machine: Machine): Promise<{ kind: RunChoice["kind"]; path?: string } | undefined> {
    const active = vscode.window.activeTextEditor?.document.uri;
    const activeExtension = active?.scheme === "file" ? path.extname(active.fsPath).slice(1).toLowerCase() : "";
    const items: RunItem[] = [];
    for (const choice of runChoices(machine)) {
        if (active !== undefined && choice.kind !== "dosSource" && choice.extensions.includes(activeExtension)) {
            items.push({ label: `$(file) ${path.basename(active.fsPath)}`, detail: `${choice.label}: the open file`, choice, path: active.fsPath });
        }
    }

    for (const choice of runChoices(machine)) items.push({ label: choice.label, detail: choice.detail, choice });
    const picked = await vscode.window.showQuickPick(items, { title: `Start ${machine.label}`, placeHolder: "What should it run?" });
    if (picked === undefined) return undefined;
    if (picked.choice.kind === "machine" || picked.path !== undefined) return { kind: picked.choice.kind, path: picked.path };

    const files = await vscode.window.showOpenDialog({
        title: picked.choice.label,
        canSelectMany: false,
        defaultUri: folder()?.uri,
        filters: { [picked.choice.label]: picked.choice.extensions }
    });

    return files?.[0] === undefined ? undefined : { kind: picked.choice.kind, path: files[0].fsPath };
}

// One option at a time: which, then its value; back to Start when nothing more is picked.
async function pickOptions(machine: Machine, setup: Setup): Promise<Setup> {
    let current = setup;
    for (;;) {
        const items = machine.choices.map(choice => {
            const value = optionValue(machine, current, choice.option);
            return { label: choice.label, description: choice.values.find(candidate => candidate.value === value)?.label, choice };
        });

        const picked = await vscode.window.showQuickPick(items, { title: `${machine.label} options`, placeHolder: "Change which? Esc when done" });
        if (picked === undefined) return current;
        const value = await vscode.window.showQuickPick(
            picked.choice.values.map(candidate => ({
                label: candidate.label,
                detail: candidate.detail,
                description: candidate.value === picked.choice.default ? "default" : undefined,
                picked: candidate.value === optionValue(machine, current, picked.choice.option),
                value: candidate.value
            })),
            { title: picked.choice.label });

        if (value !== undefined) current = withOption(machine, current, picked.choice.option, value.value);
    }
}

// Adds a setup to the workspace's launch.json, under a name the user confirms; a configuration of that name is
// replaced.
async function save(setup: Setup, given?: string): Promise<boolean> {
    const workspace = folder();
    if (workspace === undefined) {
        await vscode.window.showWarningMessage("Retrocore: open a folder to save a launch configuration in.");
        return false;
    }

    const configuration = setupConfiguration(setup);
    const name = given ?? await vscode.window.showInputBox({ title: "Save as Launch Configuration", prompt: "Its name", value: String(configuration.name) });
    if (name === undefined || name.trim().length === 0) return false;
    configuration.name = name.trim();
    const launch = vscode.workspace.getConfiguration("launch", workspace.uri);
    const existing = (launch.get<Record<string, unknown>[]>("configurations") ?? []).filter(entry => entry.name !== configuration.name);
    await launch.update("configurations", [...existing, configuration], vscode.ConfigurationTarget.WorkspaceFolder);
    if (given === undefined) {
        await vscode.window.showInformationMessage(`Retrocore: saved "${configuration.name}" in launch.json.`);
    }

    return true;
}
