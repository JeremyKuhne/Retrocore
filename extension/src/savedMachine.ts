// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The machine each launch configuration last ran with: the cards in its slots and the media in its drives, as the
// debug host reports them with retro/devices. The next launch of the same configuration gets them back, until the
// configuration's own hardware options change or Reset Saved Machine clears them.

import * as vscode from "vscode";
import { fingerprint, restorable, type SavedMachine } from "./hardware";

// Each launch configuration's saved machine is under this prefix and its name.
const prefix = "retrocore.savedMachine:";

/** Saves each session's machine as it changes, and gives it back to the next launch of the same configuration. */
export function registerSavedMachines(context: vscode.ExtensionContext): void {
    const state = context.workspaceState;
    const key = (name: string): string => prefix + name;

    context.subscriptions.push(vscode.debug.registerDebugConfigurationProvider("retrocore", {
        resolveDebugConfigurationWithSubstitutedVariables(_folder, configuration) {
            const name = configuration.name;
            if (typeof name !== "string") return configuration;
            const saved = state.get<SavedMachine>(key(name));
            const machine = restorable(saved, configuration);
            if (machine !== undefined) return { ...configuration, machineState: machine };

            // The launch's hardware changed, so what was saved for the old hardware no longer applies.
            if (saved !== undefined) void state.update(key(name), undefined);
            return configuration;
        }
    }));

    // retro/devices comes on each stop and as devices change while running; only a change is written.
    const last = new Map<string, string>();
    context.subscriptions.push(vscode.debug.onDidReceiveDebugSessionCustomEvent(event => {
        if (event.session.type !== "retrocore" || event.event !== "retro/devices") return;
        const configuration: unknown = event.body?.configuration;
        const name = event.session.configuration.name;
        if (configuration === undefined || typeof name !== "string") return;
        const text = JSON.stringify(configuration);
        if (last.get(name) === text) return;
        last.set(name, text);
        const saved: SavedMachine = { fingerprint: fingerprint(event.session.configuration), configuration };
        void state.update(key(name), saved);
    }));

    context.subscriptions.push(vscode.commands.registerCommand("retrocore.resetSavedMachine", async () => {
        const names = state.keys().filter(name => name.startsWith(prefix)).map(name => name.slice(prefix.length));
        if (names.length === 0) {
            await vscode.window.showInformationMessage("Retrocore: no launch configuration has a saved machine.");
            return;
        }
        const all = "All launch configurations";
        const picked = await vscode.window.showQuickPick([...names, all], {
            title: "Reset the saved machine (cards and disks) of"
        });
        if (picked === undefined) return;
        for (const name of picked === all ? names : [picked]) {
            last.delete(name);
            await state.update(key(name), undefined);
        }
        await vscode.window.showInformationMessage(
            "Retrocore: the next launch starts from the launch configuration's own hardware and disks.");
    }));
}
