// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The machine the Machine and Drives views show while no Retrocore session runs: the last one started, or the one
// Switch Machine picked, powered off. The language server builds it (retrocore/machine/describe and change), and
// what is changed while it is off is its launch configuration's saved machine, which its next launch restores.

import * as vscode from "vscode";
import { keepResolved, resolveVariables } from "./favorite";
import { changesFrom, fitting } from "./hardware";
import type { Device } from "./drives";
import { languageRequest } from "./languageClient";
import { catalogMachine, isLevel1, launchConfiguration, machineById, machines, startsWithDisks, withSetting, type Machine, type MachineChoice } from "./machines";
import { activeTargetRead, withActiveTarget } from "./activeTarget";
import { withProjectMachine } from "./project";
import type { SavedMachines } from "./savedMachine";
import { crowdsCartridge, describeSetup, driveOptions, isUsable, refusal, setupConfiguration, setupFromConfiguration, startOrigin, withOption, type Setup } from "./startFlow";

/** Where an off machine came from, which decides how it boots. */
export type OffSource =
    | { kind: "setup"; setup: Setup }
    | { kind: "launch"; name: string; folder?: string }
    | { kind: "configuration"; folder?: string };

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
// The machine each recovery id's session started, so its kept disks can be shown when it is in neither launch.json
// nor the last setup, as a favorite another machine has followed is.
const recoveryTargetPrefix = "retrocore.recoveryTarget:";

export function folder(): vscode.WorkspaceFolder | undefined {
    return vscode.workspace.workspaceFolders?.[0];
}

/** The workspace's Retrocore launch configurations in launch.json. */
/** The workspace folder a launch came from, by its URI, or the first when it names none or that folder is gone. */
function folderOf(uri: string | undefined): vscode.WorkspaceFolder | undefined {
    return vscode.workspace.workspaceFolders?.find(candidate => candidate.uri.toString() === uri) ?? folder();
}

function launchConfigurations(workspace: vscode.WorkspaceFolder | undefined = folder()): Record<string, unknown>[] {
    const launch = vscode.workspace.getConfiguration("launch", workspace?.uri);
    return (launch.get<Record<string, unknown>[]>("configurations") ?? [])
        .filter(entry => entry.type === "retrocore" && entry.request === "launch" && typeof entry.name === "string");
}

/** Sets one choice in a launch.json configuration, keeping its variables as written. */
async function updateLaunch(name: string, choice: MachineChoice, value: string | number | boolean, at: string | undefined): Promise<void> {
    const workspace = folderOf(at);
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

    /**
     * The configuration's name. Its saved machine is kept under this name, with a project launch's target added
     * (project.ts savedName).
     */
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
        let source: OffSource = { kind: "configuration", folder: session.workspaceFolder?.uri.toString() };
        // Start Machine says it started it; otherwise a launch.json entry of its name, or a catalog machine's own.
        if (configuration[startOrigin] === "startMachine" && isUsable(setup) && setupConfiguration(setup).name === name) {
            source = { kind: "setup", setup };
        }
        // Its own folder's launch.json, as a multi-root workspace can have one in each.
        else if (typeof name === "string" && launchConfigurations(session.workspaceFolder ?? folder()).some(entry => entry.name === name)) {
            source = { kind: "launch", name, folder: (session.workspaceFolder ?? folder())?.uri.toString() };
        }
        else if (machine !== undefined && launchConfiguration(machine).name === name) {
            const setup = setupFromConfiguration(configuration);
            if (setup !== undefined) source = { kind: "setup", setup };
        }
        const { machineState: _saved, [startOrigin]: _origin, ...rest } = configuration;
        // This session's machine, kept as it is here: another may be shown by the time an update below finishes.
        const target: OffTarget = { configuration: rest, source };
        this.target = target;
        this.body = undefined;
        await this.state.update(targetKey, target);
        if (typeof rest.recoveryId === "string") await this.state.update(`${recoveryTargetPrefix}${rest.recoveryId}`, target);
    }

    /** Asks the language server for the machine with its saved cards and media. */
    async describe(): Promise<void> {
        await this.serially(() => this.describeNow());
    }

    /**
     * A launch.json machine as its entry is now, resolved, so an edit to launch.json shows and is what changes are
     * saved under; an entry that is gone keeps the last one seen.
     */
    private async reread(): Promise<void> {
        const target = this.target;
        if (target?.source.kind !== "launch") return;
        const name = target.source.name;
        const workspace = folderOf(target.source.folder);
        const entry = launchConfigurations(workspace).find(candidate => candidate.name === name);
        if (entry === undefined) return;
        // What only a launch resolves, such as ${file}, keeps the value the session it came from resolved it to.
        const { machineState: _saved, ...fresh } = resolveVariables(entry, workspace?.uri.fsPath);
        // The recovery id is launch.json's when it gives one; otherwise the one its launches are given, by its name.
        // A project launch's target gives its machine and the name its saved machine is kept under, as its session's.
        const configuration = withProjectMachine(keepResolved(fresh, target.configuration));
        if (JSON.stringify(configuration) === JSON.stringify(target.configuration)) return;
        this.target = { ...target, configuration };
        this.body = undefined;
        await this.state.update(targetKey, this.target);
    }

    private async describeNow(): Promise<void> {
        await this.reread();
        const target = this.target;
        if (target === undefined) return;
        await this.ask("retrocore/machine/describe", { configuration: this.withRecovery(target), machineState: this.saved.get(target.configuration) });
    }

    /**
     * Its configuration with the recovery id its launches use, so the language server shows and saves the disks its
     * last run kept.
     */
    private withRecovery(target: OffTarget): Record<string, unknown> {
        const recoveryId = this.saved.recoveryId(target.configuration, folderOf("folder" in target.source ? target.source.folder : undefined)?.uri.toString());
        return recoveryId === undefined ? target.configuration : { ...target.configuration, recoveryId };
    }

    /** The off machine's devices, as the language server last described them. */
    get devices(): Device[] {
        return (this.body?.devices ?? []) as Device[];
    }

    /**
     * Shows the machine whose journal has a recovery id, off, with the disks its last run kept: the one shown, or
     * the launch configuration or Start Machine setup it was made for. Says whether it could.
     */
    async showRecovery(recoveryId: string): Promise<boolean> {
        if (this.recoveryId !== recoveryId) {
            const owner = this.saved.recoveryOf(recoveryId);
            if (owner === undefined) return false;
            const workspace = folderOf(owner.folder);
            const entry = launchConfigurations(workspace).find(candidate => candidate.name === owner.name);
            const setup = this.state.get<Setup>(lastSetupKey);
            // What only a launch resolves, such as ${file}, keeps the value its session resolved it to.
            const started = this.state.get<OffTarget>(`${recoveryTargetPrefix}${recoveryId}`);
            if (entry !== undefined) {
                // A project launch's journal is its target's, whatever target the entry names now.
                const fresh = { ...resolveVariables(entry, workspace?.uri.fsPath), ...owner.target === undefined ? {} : { target: owner.target } };
                await this.select({ configuration: { ...withProjectMachine(keepResolved(fresh, started?.configuration ?? {})), recoveryId },
                    source: { kind: "launch", name: owner.name, folder: workspace?.uri.toString() } });
            } else if (isUsable(setup) && setupConfiguration(setup).name === owner.name) {
                await this.select({ configuration: { ...setupConfiguration(setup), recoveryId }, source: { kind: "setup", setup } });
            } else {
                // The machine as its session started it, as a favorite's is.
                if (started === undefined) return false;
                await this.select({ ...started, configuration: { ...started.configuration, recoveryId } });
            }
        } else {
            await this.describe();
        }
        return this.recoveryId === recoveryId;
    }

    /**
     * Whether the launch configuration or Start Machine setup a journal was made for still launches with its recovery
     * id, so its next launch puts the disks back: one given another id in launch.json since does not.
     */
    launchesWith(recoveryId: string): boolean {
        const owner = this.saved.recoveryOf(recoveryId);
        if (owner === undefined) return false;
        const workspace = folderOf(owner.folder);
        const entry = launchConfigurations(workspace).find(candidate => candidate.name === owner.name);
        if (entry !== undefined) {
            const fresh = { ...resolveVariables(entry, workspace?.uri.fsPath), ...owner.target === undefined ? {} : { target: owner.target } };
            return this.saved.recoveryId(fresh, workspace?.uri.toString()) === recoveryId;
        }
        const setup = this.state.get<Setup>(lastSetupKey);
        if (isUsable(setup) && setupConfiguration(setup).name === owner.name) {
            return this.saved.recoveryId(setupConfiguration(setup), folderOf(undefined)?.uri.toString()) === recoveryId;
        }
        // A machine launched from neither, as from a favorite: launched again as its session started it, it has
        // this id; and any launch of its name that gives no id of its own gets the id made for the name.
        return this.state.get(`${recoveryTargetPrefix}${recoveryId}`) !== undefined || owner.made;
    }

    /** The recovery id of the machine shown, whose journal keeps the disks its last run did not save. */
    get recoveryId(): string | undefined {
        const target = this.target;
        return target === undefined ? undefined : this.withRecovery(target).recoveryId as string | undefined;
    }

    /** Changes the machine as retro/hardware or retro/device would, and saves the result for its next launch. */
    async change(request: "hardware" | "device", args: Record<string, unknown>): Promise<void> {
        await this.request(request, args);
    }

    /**
     * Changes the machine as retro/hardware or retro/device would, saves the result for its next launch, and gives
     * the language server's body, with media's answer beside the devices when there is one. Given the machine it is
     * for (its recovery id, or its name), it is refused when another is shown by the time its turn comes.
     */
    async request(request: "hardware" | "device", args: Record<string, unknown>, shown?: string): Promise<OffBody & Record<string, unknown>> {
        // The saved machine is read once the change before has saved its own.
        return await this.serially(async () => {
            await this.reread();
            const target = this.target;
            if (target === undefined) throw new Error("No machine is set up.");
            if (shown !== undefined && (this.recoveryId ?? this.name) !== shown) {
                throw new Error("Another machine is shown now, so nothing was done.");
            }
            const body = await languageRequest<OffBody & Record<string, unknown>>("retrocore/machine/change", {
                configuration: this.withRecovery(target), machineState: this.saved.get(target.configuration), request, arguments: args
            });
            if (target === this.target) {
                this.body = body;
                this.error = undefined;
                await this.saved.set(target.configuration, body.configuration);
                this.showProblems(body);
                this.changed.fire();
            }
            return body;
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

    /**
     * Why the machine shown cannot take a setting, if it cannot: it has no such setting; its disks need their
     * controller, and the Model I's controller its Expansion Interface; a cartridge holds BASIC's slot; or Level I
     * cannot run what it starts with.
     */
    refusal(option: string, value: string | number | boolean): string | undefined {
        const target = this.target;
        const machine = this.machine;
        const choice = machine?.choices.find(candidate => candidate.option === option);
        if (target === undefined || machine === undefined || choice === undefined) return `${this.name ?? "The machine"} has no setting ${option}.`;
        if (driveOptions.has(option) && value === false && startsWithDisks(target.configuration)) {
            return `${this.name ?? "The machine"} starts with disks in its drives, so it keeps its ${choice.label.toLowerCase()}.`;
        }
        // A cartridge holds the left slot, where BASIC would go.
        if (crowdsCartridge(target.configuration, option, value)) {
            return `${this.name ?? "The machine"} starts with a cartridge in BASIC's slot, so BASIC stays out.`;
        }
        if (target.source.kind === "setup") return refusal(machine, target.source.setup, option, value);
        // A launch that runs a BASIC file needs Level II's BASIC.
        if (option === "rom" && typeof target.configuration.basic === "string" && isLevel1(withSetting(target.configuration, choice, value))) {
            return `${this.name ?? "The machine"} runs a BASIC file, which Level I cannot load.`;
        }
        return undefined;
    }

    private async setSettingNow(option: string, value: string | number | boolean): Promise<void> {
        await this.reread();
        const refused = this.refusal(option, value);
        if (refused !== undefined) throw new Error(refused);
        const target = this.target;
        const machine = this.machine;
        const choice = machine?.choices.find(candidate => candidate.option === option);
        if (target === undefined || machine === undefined || choice === undefined) throw new Error(`${this.name ?? "The machine"} has no setting ${option}.`);

        let next: OffTarget;
        if (target.source.kind === "setup") {
            const setup = withOption(machine, target.source.setup, option, value);
            next = { configuration: setupConfiguration(setup), source: { kind: "setup", setup } };
            await this.state.update(lastSetupKey, setup);
        } else {
            if (target.source.kind === "launch") await updateLaunch(target.source.name, choice, value, target.source.folder);
            next = { configuration: withSetting(target.configuration, choice, value), source: target.source };
        }

        // What the new machine has no drive for, such as the disks Level I has none for, is left out. It is described
        // with the changes, so the drives of cards added to it are there to keep theirs.
        const saved = this.saved.get(target.configuration);
        if (saved !== undefined) {
            const base = await languageRequest<OffBody>("retrocore/machine/describe", { configuration: target.configuration });
            const changes = changesFrom(saved, base.configuration);
            const fresh = await languageRequest<OffBody>("retrocore/machine/describe", { configuration: next.configuration, machineState: changes });
            await this.saved.set(next.configuration, fitting(changes, fresh.configuration));
        }

        await this.selectNow(next);
    }

    /** Boots the machine as it came: Start Machine's setup, the launch.json configuration, or the configuration. */
    async boot(): Promise<boolean> {
        // Changes sent before it are saved first, so the launch restores them and its start finds none in flight.
        await this.serially(async () => undefined);
        const target = this.target;
        if (target === undefined) return false;
        switch (target.source.kind) {
            case "setup":
                return await vscode.commands.executeCommand<boolean>("retrocore.startMachine", target.source.setup);
            case "launch":
                return await vscode.debug.startDebugging(folderOf(target.source.folder), target.source.name);
            default:
                return await vscode.debug.startDebugging(folderOf(target.source.folder), target.configuration as vscode.DebugConfiguration);
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
        // Each folder's launch.json, resolved against that folder, as a multi-root workspace has one in each; an
        // entry whose target is the active target's gets it once the workspace's projects are read.
        await activeTargetRead();
        const folders = vscode.workspace.workspaceFolders ?? [];
        for (const workspace of folders) {
            const launches = launchConfigurations(workspace);
            if (launches.length === 0) continue;
            items.push({ label: folders.length > 1 ? `launch.json: ${workspace.name}` : "launch.json", kind: vscode.QuickPickItemKind.Separator });
            for (const entry of launches) {
                const name = String(entry.name);
                const configuration = withProjectMachine(withActiveTarget(resolveVariables(entry, workspace.uri.fsPath)));
                items.push({ label: name, description: String(configuration.machine ?? ""),
                    target: { configuration, source: { kind: "launch", name, folder: workspace.uri.toString() } } });
            }
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

    /** Says what of the machine could not be set up, once for the same problems. */
    private showProblems(body: OffBody): void {
        const problems = body.problems.join("\n");
        if (problems !== "" && problems !== this.shownProblems) {
            void vscode.window.showWarningMessage(`Retrocore: ${this.name ?? "the machine"} could not be fully set up: ${body.problems.join(" ")}`);
        }
        this.shownProblems = problems;
    }

    private async ask(method: string, params: Record<string, unknown>, save = false): Promise<void> {
        const target = this.target;
        try {
            const body = await languageRequest<OffBody>(method, params);
            if (target !== this.target) return;
            this.body = body;
            this.error = undefined;
            if (save && target !== undefined) await this.saved.set(target.configuration, body.configuration);
            this.showProblems(body);
        } catch (error) {
            if (target !== this.target) return;
            if (save) throw error;
            this.body = undefined;
            this.error = error instanceof Error ? error.message : String(error);
        }
        this.changed.fire();
    }
}
