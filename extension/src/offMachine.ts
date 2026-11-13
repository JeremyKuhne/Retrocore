// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The machine the Machine and Drives views show while no Retrocore session runs: the last one started, or the one
// Switch Machine picked, powered off. The language server builds it (retrocore/machine/describe and change), and
// what is changed while it is off is its launch configuration's saved machine, which its next launch restores.

import * as vscode from "vscode";
import { resolveVariables } from "./favorite";
import { changesFrom } from "./hardware";
import { languageRequest } from "./languageClient";
import { catalogMachine, launchConfiguration, machineById, machines, withSetting, type Machine, type MachineChoice } from "./machines";
import type { SavedMachines } from "./savedMachine";
import { describeSetup, isUsable, setupConfiguration, setupFromConfiguration, withOption, type Setup } from "./startFlow";

/** Where an off machine came from, which decides how it boots. */
export type OffSource =
    | { kind: "setup"; setup: Setup }
    | { kind: "launch"; name: string }
    | { kind: "configuration" };

/** The machine shown while off: its launch configuration, resolved, and where it came from. */
export interface OffTarget {
    configuration: Record<string, unknown>;
    source: OffSource;
}

/** What the language server answers: retrocore/machine/describe's body. */
export interface OffBody {
    devices: unknown[];
    hardware: unknown[];
    configuration: unknown;
    problems: string[];
}

const targetKey = "retrocore.offMachine";
const lastSetupKey = "retrocore.lastSetup";

export function folder(): vscode.WorkspaceFolder | undefined {
    return vscode.workspace.workspaceFolders?.[0];
}

/** The workspace's Retrocore launch configurations in launch.json. */
function launchConfigurations(): Record<string, unknown>[] {
    const launch = vscode.workspace.getConfiguration("launch", folder()?.uri);
    return (launch.get<Record<string, unknown>[]>("configurations") ?? [])
        .filter(entry => entry.type === "retrocore" && entry.request === "launch" && typeof entry.name === "string");
}

/** Sets one choice in a launch.json configuration, keeping its variables as written. */
async function updateLaunch(name: string, choice: MachineChoice, value: string | number | boolean): Promise<void> {
    const workspace = folder();
    if (workspace === undefined) return;
    const launch = vscode.workspace.getConfiguration("launch", workspace.uri);
    const entries = launch.get<Record<string, unknown>[]>("configurations") ?? [];
    await launch.update("configurations",
        entries.map(entry => entry.type === "retrocore" && entry.name === name ? withSetting(entry, choice, value) : entry),
        vscode.ConfigurationTarget.WorkspaceFolder);
}

/** The off machine, its description, and the actions on it. */
export class OffMachine {
    private readonly changed = new vscode.EventEmitter<void>();
    readonly onDidChange = this.changed.event;
    target: OffTarget | undefined;
    body: OffBody | undefined;
    /** Why the machine could not be described, if it could not. */
    error: string | undefined;
    private shownProblems = "";
    // The work that reads or writes the saved machine, one at a time: two changes in quick succession would otherwise
    // both start from the same saved machine, and the second's answer undo the first.
    private queue: Promise<unknown> = Promise.resolve();

    private serially<T>(work: () => Promise<T>): Promise<T> {
        const run = this.queue.then(work, work);
        this.queue = run.catch(() => undefined);
        return run;
    }

    constructor(private readonly state: vscode.Memento, private readonly saved: SavedMachines) {
        this.target = state.get<OffTarget>(targetKey);
        if (this.target === undefined) {
            const setup = state.get<Setup>(lastSetupKey);
            if (isUsable(setup)) this.target = { configuration: setupConfiguration(setup), source: { kind: "setup", setup } };
        }
    }

    /** The configuration's name, which its saved machine is kept under. */
    get name(): string | undefined {
        const name = this.target?.configuration.name;
        return typeof name === "string" ? name : undefined;
    }

    /**
     * Makes a machine the off one, and describes it; with a saved machine, as a favorite brings, that becomes its
     * cards and media.
     */
    async select(target: OffTarget, machineState?: unknown): Promise<void> {
        await this.serially(() => this.selectNow(target, machineState));
    }

    private async selectNow(target: OffTarget, machineState?: unknown): Promise<void> {
        const { machineState: _saved, ...configuration } = target.configuration;
        this.target = { ...target, configuration };
        this.body = undefined;
        if (machineState !== undefined) await this.saved.set(configuration, machineState);
        await this.state.update(targetKey, this.target);
        await this.describeNow();
    }

    /**
     * Notes the machine a session started, so the views show it, off, once it ends: from the setup Start Machine
     * last started when the names match, else the launch.json configuration of that name, else the configuration
     * as it is.
     */
    async started(session: vscode.DebugSession): Promise<void> {
        const configuration = session.configuration as Record<string, unknown>;
        const name = configuration.name;
        const setup = this.state.get<Setup>(lastSetupKey);
        const machine = catalogMachine(configuration);
        let source: OffSource = { kind: "configuration" };
        if (isUsable(setup) && setupConfiguration(setup).name === name) source = { kind: "setup", setup };
        else if (typeof name === "string" && launchConfigurations().some(entry => entry.name === name)) source = { kind: "launch", name };
        else if (machine !== undefined && launchConfiguration(machine).name === name) {
            const setup = setupFromConfiguration(configuration);
            if (setup !== undefined) source = { kind: "setup", setup };
        }
        const { machineState: _saved, ...rest } = configuration;
        this.target = { configuration: rest, source };
        this.body = undefined;
        await this.state.update(targetKey, this.target);
    }

    /** Asks the language server for the machine with its saved cards and media. */
    async describe(): Promise<void> {
        await this.serially(() => this.describeNow());
    }

    private async describeNow(): Promise<void> {
        const target = this.target;
        if (target === undefined) return;
        await this.ask("retrocore/machine/describe", { configuration: target.configuration, machineState: this.saved.get(target.configuration) });
    }

    /** Changes the machine as retro/hardware or retro/device would, and saves the result for its next launch. */
    async change(request: "hardware" | "device", args: Record<string, unknown>): Promise<void> {
        // The saved machine is read once the change before has saved its own.
        await this.serially(async () => {
            const target = this.target;
            if (target === undefined) return;
            await this.ask("retrocore/machine/change", {
                configuration: target.configuration, machineState: this.saved.get(target.configuration), request, arguments: args
            }, true);
        });
    }

    /** The catalog machine the off machine is, whose choices are its settings. */
    get machine(): Machine | undefined {
        const target = this.target;
        if (target === undefined) return undefined;
        return target.source.kind === "setup" ? machineById(target.source.setup.machineId) : catalogMachine(target.configuration);
    }

    /**
     * Changes one of the settings while the machine is off: in Start Machine's setup (which Start Last Machine then
     * starts), in the launch.json configuration, or in the configuration itself. The cards and media someone changed
     * stay on top of the new setting, where the whole saved machine would put back what the setting replaced.
     */
    async setSetting(option: string, value: string | number | boolean): Promise<void> {
        await this.serially(() => this.setSettingNow(option, value));
    }

    private async setSettingNow(option: string, value: string | number | boolean): Promise<void> {
        const target = this.target;
        const machine = this.machine;
        const choice = machine?.choices.find(candidate => candidate.option === option);
        if (target === undefined || machine === undefined || choice === undefined) {
            throw new Error(`${this.name ?? "The machine"} has no setting ${option}.`);
        }

        let next: OffTarget;
        if (target.source.kind === "setup") {
            const setup = withOption(machine, target.source.setup, option, value);
            next = { configuration: setupConfiguration(setup), source: { kind: "setup", setup } };
            await this.state.update(lastSetupKey, setup);
        } else {
            if (target.source.kind === "launch") await updateLaunch(target.source.name, choice, value);
            next = { configuration: withSetting(target.configuration, choice, value), source: target.source };
        }

        const saved = this.saved.get(target.configuration);
        if (saved !== undefined) {
            const base = await languageRequest<OffBody>("retrocore/machine/describe", { configuration: target.configuration });
            await this.saved.set(next.configuration, changesFrom(saved, base.configuration));
        }

        await this.selectNow(next);
    }

    /** Boots the machine as it came: Start Machine's setup, the launch.json configuration, or the configuration. */
    async boot(): Promise<boolean> {
        const target = this.target;
        if (target === undefined) return false;
        switch (target.source.kind) {
            case "setup":
                return await vscode.commands.executeCommand<boolean>("retrocore.startMachine", target.source.setup);
            case "launch":
                return await vscode.debug.startDebugging(folder(), target.source.name);
            default:
                return await vscode.debug.startDebugging(folder(), target.configuration as vscode.DebugConfiguration);
        }
    }

    /**
     * Switch Machine…: the favorites given, the last setup, the workspace's launch configurations, then the
     * catalog's machines; a favorite brings its saved machine.
     */
    async pick(favorites: (vscode.QuickPickItem & { target: OffTarget; machineState: unknown })[] = []):
        Promise<{ target: OffTarget; machineState?: unknown } | undefined> {
        type Item = vscode.QuickPickItem & { target?: OffTarget; machineState?: unknown };
        const items: Item[] = [];
        const setup = this.state.get<Setup>(lastSetupKey);
        if (favorites.length !== 0) items.push({ label: "Favorites", kind: vscode.QuickPickItemKind.Separator }, ...favorites);
        if (favorites.length !== 0 && isUsable(setup)) items.push({ label: "Recent", kind: vscode.QuickPickItemKind.Separator });
        if (isUsable(setup)) {
            items.push({ label: "$(history) " + describeSetup(setup), detail: "What Start Machine started last",
                target: { configuration: setupConfiguration(setup), source: { kind: "setup", setup } } });
        }
        const workspace = folder()?.uri.fsPath;
        const launches = launchConfigurations();
        if (launches.length !== 0) items.push({ label: "launch.json", kind: vscode.QuickPickItemKind.Separator });
        for (const entry of launches) {
            const name = String(entry.name);
            items.push({ label: name, description: String(entry.machine ?? ""),
                target: { configuration: resolveVariables(entry, workspace), source: { kind: "launch", name } } });
        }
        items.push({ label: "Machines", kind: vscode.QuickPickItemKind.Separator });
        for (const machine of machines) {
            const setup: Setup = { machineId: machine.id, kind: "machine", options: {} };
            items.push({ label: machine.label, detail: machine.detail,
                target: { configuration: setupConfiguration(setup), source: { kind: "setup", setup } } });
        }
        const current = this.name;
        for (const item of items) if (item.target?.configuration.name === current) item.description = "$(check) " + (item.description ?? "");
        const picked = await vscode.window.showQuickPick(items, { title: "Switch Machine", placeHolder: "Which machine to set up?" });
        return picked?.target === undefined ? undefined : { target: picked.target, machineState: picked.machineState };
    }

    private async ask(method: string, params: Record<string, unknown>, save = false): Promise<void> {
        const target = this.target;
        try {
            const body = await languageRequest<OffBody>(method, params);
            if (target !== this.target) return;
            this.body = body;
            this.error = undefined;
            if (save && target !== undefined) await this.saved.set(target.configuration, body.configuration);
            const problems = body.problems.join("\n");
            if (problems !== "" && problems !== this.shownProblems) {
                void vscode.window.showWarningMessage(`Retrocore: ${this.name ?? "the machine"} could not be fully set up: ${body.problems.join(" ")}`);
            }
            this.shownProblems = problems;
        } catch (error) {
            if (target !== this.target) return;
            if (save) throw error;
            this.body = undefined;
            this.error = error instanceof Error ? error.message : String(error);
        }
        this.changed.fire();
    }
}
