// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The machine the Machine and Drives views show while no Retrocore session runs: the last one started, or the one
// Switch Machine picked, powered off. The language server builds it (retrocore/machine/describe and change), and
// what is changed while it is off is its launch configuration's saved machine, which its next launch restores.

import * as os from "node:os";
import * as vscode from "vscode";
import { languageRequest } from "./languageClient";
import { launchConfiguration, machines } from "./machines";
import type { SavedMachines } from "./savedMachine";
import { describeSetup, isUsable, setupConfiguration, type Setup } from "./startFlow";

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

function folder(): vscode.WorkspaceFolder | undefined {
    return vscode.workspace.workspaceFolders?.[0];
}

/**
 * Substitutes the variables a launch configuration in launch.json uses, as VS Code does when it starts one:
 * ${workspaceFolder}, ${workspaceFolderBasename}, ${userHome} and ${env:NAME}. Anything else is left as it is.
 */
export function resolveVariables<T>(value: T, workspace: string | undefined, env: NodeJS.ProcessEnv = process.env): T {
    if (typeof value === "string") {
        return value.replace(/\$\{([^}]+)\}/g, (whole, name: string) => {
            if (name === "workspaceFolder" && workspace !== undefined) return workspace;
            if (name === "workspaceFolderBasename" && workspace !== undefined) return workspace.split(/[\\/]/).pop() ?? whole;
            if (name === "userHome") return os.homedir();
            if (name.startsWith("env:")) return env[name.slice(4)] ?? "";
            return whole;
        }) as T;
    }
    if (Array.isArray(value)) return value.map(item => resolveVariables(item, workspace, env)) as T;
    if (typeof value === "object" && value !== null) {
        return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, resolveVariables(item, workspace, env)])) as T;
    }
    return value;
}

/** The workspace's Retrocore launch configurations in launch.json. */
function launchConfigurations(): Record<string, unknown>[] {
    const launch = vscode.workspace.getConfiguration("launch", folder()?.uri);
    return (launch.get<Record<string, unknown>[]>("configurations") ?? [])
        .filter(entry => entry.type === "retrocore" && entry.request === "launch" && typeof entry.name === "string");
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

    /** Makes a machine the off one, and describes it. */
    async select(target: OffTarget): Promise<void> {
        const { machineState: _saved, ...configuration } = target.configuration;
        this.target = { ...target, configuration };
        this.body = undefined;
        await this.state.update(targetKey, this.target);
        await this.describe();
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
        let source: OffSource = { kind: "configuration" };
        if (isUsable(setup) && setupConfiguration(setup).name === name) source = { kind: "setup", setup };
        else if (typeof name === "string" && launchConfigurations().some(entry => entry.name === name)) source = { kind: "launch", name };
        const { machineState: _saved, ...rest } = configuration;
        this.target = { configuration: rest, source };
        this.body = undefined;
        await this.state.update(targetKey, this.target);
    }

    /** Asks the language server for the machine with its saved cards and media. */
    async describe(): Promise<void> {
        const target = this.target;
        if (target === undefined) return;
        await this.ask("retrocore/machine/describe", { configuration: target.configuration, machineState: this.saved.get(target.configuration) });
    }

    /** Changes the machine as retro/hardware or retro/device would, and saves the result for its next launch. */
    async change(request: "hardware" | "device", args: Record<string, unknown>): Promise<void> {
        const target = this.target;
        if (target === undefined) return;
        await this.ask("retrocore/machine/change", {
            configuration: target.configuration, machineState: this.saved.get(target.configuration), request, arguments: args
        }, true);
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

    /** Switch Machine…: the last setup, the workspace's launch configurations, then the catalog's machines. */
    async pick(): Promise<OffTarget | undefined> {
        type Item = vscode.QuickPickItem & { target?: OffTarget };
        const items: Item[] = [];
        const setup = this.state.get<Setup>(lastSetupKey);
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
            items.push({ label: machine.label, detail: machine.detail,
                target: { configuration: launchConfiguration(machine), source: { kind: "configuration" } } });
        }
        const current = this.name;
        for (const item of items) if (item.target?.configuration.name === current) item.description = "$(check) " + (item.description ?? "");
        return (await vscode.window.showQuickPick(items, { title: "Switch Machine", placeHolder: "Which machine to set up?" }))?.target;
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
