// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The machine each launch configuration last ran with: the cards in its slots and the media in its drives, as the
// debug host reports them with retro/devices, or as they were changed while the machine was off. The next launch of
// the same configuration gets them back, until the configuration's own hardware options change or Reset Saved Machine
// clears them.

import * as vscode from "vscode";
import { randomUUID } from "node:crypto";
import { fingerprint, restorable, type SavedMachine } from "./hardware";

// Each launch configuration's saved machine is under this prefix and its name.
const prefix = "retrocore.savedMachine:";

// Each launch configuration's recovery id, which names the journal its machine keeps its unsaved disks in.
const recoveryPrefix = "retrocore.recoveryId:";
// The recovery id a configuration gives itself, by the same key, so its journal is found as a made one is.
const givenPrefix = "retrocore.givenRecoveryId:";

/** The saved machines, by launch configuration. */
export interface SavedMachines {
    /** The saved machine a launch of this configuration restores, if any. */
    get(configuration: Record<string, unknown>): unknown;
    /** Saves the machine for later launches of this configuration. */
    set(configuration: Record<string, unknown>, machine: unknown): Promise<void>;
    /** Fires when Reset Saved Machine clears any. */
    readonly onDidReset: vscode.Event<void>;
    /**
     * The recovery id of a configuration in a workspace folder (by its URI), which names the journal its machine keeps
     * its unsaved disks in: its own, or one made the first time it is asked for.
     */
    recoveryId(configuration: Record<string, unknown>, folder: string | undefined): string | undefined;
    /** The configuration a recovery id was made for: its name and workspace folder's URI, if any. */
    recoveryOf(id: string): { name: string; folder: string | undefined } | undefined;
}

/** Saves each session's machine as it changes, and gives it back to the next launch of the same configuration. */
export function registerSavedMachines(context: vscode.ExtensionContext): SavedMachines {
    const state = context.workspaceState;
    const key = (name: string): string => prefix + name;
    const reset = new vscode.EventEmitter<void>();
    context.subscriptions.push(reset);

    // retro/devices comes on each stop and as devices change while running; only a change is written.
    const last = new Map<string, string>();
    const saved: SavedMachines = {
        get(configuration) {
            const name = configuration.name;
            return typeof name === "string" ? restorable(state.get<SavedMachine>(key(name)), configuration) : undefined;
        },
        async set(configuration, machine) {
            const name = configuration.name;
            if (typeof name !== "string") return;
            // The same cards and media under other settings are saved again, under those settings' fingerprint.
            const text = JSON.stringify({ fingerprint: fingerprint(configuration), machine });
            if (last.get(name) === text) return;
            last.set(name, text);
            await state.update(key(name), { fingerprint: fingerprint(configuration), configuration: machine } satisfies SavedMachine);
        },
        onDidReset: reset.event,
        // Configurations of one name in the folders of a multi-root workspace are each their own.
        recoveryId(configuration, folder) {
            const name = configuration.name;
            if (typeof configuration.recoveryId === "string") {
                // Kept apart from the one made for the name, which still finds that id's journal.
                const givenKey = `${givenPrefix}${folder ?? ""}|${name}`;
                if (typeof name === "string" && state.get(givenKey) !== configuration.recoveryId) void state.update(givenKey, configuration.recoveryId);
                return configuration.recoveryId;
            }
            if (typeof name !== "string") return undefined;
            const recoveryKey = `${recoveryPrefix}${folder ?? ""}|${name}`;
            let recoveryId = state.get<string>(recoveryKey);
            if (recoveryId === undefined) {
                recoveryId = randomUUID();
                void state.update(recoveryKey, recoveryId);
            }
            return recoveryId;
        },
        recoveryOf(id) {
            const owns = (prefix: string): string | undefined => state.keys().find(name => name.startsWith(prefix) && state.get(name) === id)?.slice(prefix.length);
            const rest = owns(recoveryPrefix) ?? owns(givenPrefix);
            if (rest === undefined) return undefined;
            const bar = rest.indexOf("|");
            return { name: rest.slice(bar + 1), folder: bar > 0 ? rest.slice(0, bar) : undefined };
        }
    };

    context.subscriptions.push(vscode.debug.registerDebugConfigurationProvider("retrocore", {
        resolveDebugConfigurationWithSubstitutedVariables(folder, configuration) {
            const name = configuration.name;
            if (typeof name !== "string") return configuration;

            // The machine keeps its changed disks for the next launch of the same configuration, under one id for
            // it, made the first time it launches; a configuration can give its own.
            configuration = { ...configuration, recoveryId: saved.recoveryId(configuration, folder?.uri.toString()) };
            const machine = saved.get(configuration);
            if (machine !== undefined) return { ...configuration, machineState: machine };

            // The launch's hardware changed, so what was saved for the old hardware no longer applies.
            if (state.get(key(name)) !== undefined) void state.update(key(name), undefined);
            return configuration;
        }
    }));

    context.subscriptions.push(vscode.debug.onDidReceiveDebugSessionCustomEvent(event => {
        if (event.session.type !== "retrocore" || event.event !== "retro/devices") return;
        const machine: unknown = event.body?.configuration;
        if (machine !== undefined) void saved.set(event.session.configuration, machine);
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
        reset.fire();
        await vscode.window.showInformationMessage(
            "Retrocore: the next launch starts from the launch configuration's own hardware and disks.");
    }));

    return saved;
}
