// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The active target: the project target F5 debugs in a workspace with no launch.json, and the one
// ${command:retrocore.activeTarget} names in a launch configuration. It shows in the status bar, which picks it from
// the targets of the workspace's retrocore.json files, and is kept in workspace state.

import * as path from "node:path";
import * as vscode from "vscode";
import { machineById } from "./machines";
import { isRootFile, loadTargets, projectFileName, projectLaunch, qualifiedName, type ProjectTarget } from "./project";

// The workspace state the active target is kept in: its project's file and its name.
const stateKey = "retrocore.activeTarget";

// Folders a project file is never looked for in: packages, build output and version control.
const excluded = "**/{node_modules,artifacts,obj,.git}/**";

// The active target as last read, for what resolves ${command:retrocore.activeTarget} itself, such as the off
// machine reading launch.json; none until the workspace's projects are read, or without any.
let current: ProjectTarget | undefined;
// The read of the workspace's projects in progress, or the last one.
let lastRead: Promise<void> = Promise.resolve();

/** Waits for the workspace's projects to be read, so activeTargetName gives the active target. */
export function activeTargetRead(): Promise<void> {
    return lastRead.catch(() => undefined);
}

/** The active target's name as retrocore.activeTarget gives it (project/target), if the workspace has one. */
export function activeTargetName(): string | undefined {
    return current === undefined ? undefined : qualifiedName(current);
}

const activeTargetVariable = "${command:retrocore.activeTarget}";

/**
 * A launch configuration with ${command:retrocore.activeTarget} in its target replaced by the active target, as VS
 * Code's launch substitutes it, so what reads launch.json without launching gets the target the launch would.
 */
export function withActiveTarget<T extends Record<string, unknown>>(configuration: T): T {
    const name = activeTargetName();
    if (name === undefined || typeof configuration.target !== "string" || !configuration.target.includes(activeTargetVariable)) {
        return configuration;
    }
    return { ...configuration, target: configuration.target.replaceAll(activeTargetVariable, name) };
}

/** The workspace's project targets and the one chosen. */
export interface ActiveTargets {
    /** The active target: the one chosen, while the workspace still has it, else the first; none without projects. */
    readonly active: ProjectTarget | undefined;
    /** Every target of the workspace's projects, in their files' order. */
    readonly targets: readonly ProjectTarget[];
    /** Fires when the active target, or what its project gives it, changes. */
    readonly onDidChange: vscode.Event<ProjectTarget | undefined>;
    /** Reads the workspace's project files again. */
    refresh(): Promise<void>;
}

/** Finds the workspace's projects, shows the active target and registers the commands that name and pick it. */
export function registerActiveTarget(context: vscode.ExtensionContext): ActiveTargets {
    const changed = new vscode.EventEmitter<ProjectTarget | undefined>();
    const item = vscode.window.createStatusBarItem("retrocore.activeTarget", vscode.StatusBarAlignment.Left, 100);
    item.name = "Retrocore Target";
    item.command = "retrocore.pickTarget";
    context.subscriptions.push(changed, item);

    let targets: ProjectTarget[] = [];
    let shown = "";
    const chosen = (): { file: string; target: string } | undefined => context.workspaceState.get(stateKey);
    const same = (a: string, b: string): boolean =>
        process.platform === "win32" ? path.resolve(a).toLowerCase() === path.resolve(b).toLowerCase() : path.resolve(a) === path.resolve(b);
    const active = (): ProjectTarget | undefined => {
        const choice = chosen();
        return targets.find(target => choice !== undefined && same(target.file, choice.file) && target.name === choice.target) ?? targets[0];
    };
    const show = (): void => {
        const target = active();
        const text = target === undefined ? "" : JSON.stringify([target.file, target.project, target.name, target.definition]);
        if (target === undefined) {
            item.hide();
        } else {
            const machine = machineById(target.machine);
            item.text = `$(target) ${target.project} · ${target.name}`;
            item.tooltip = new vscode.MarkdownString(`**Retrocore target:** ${target.project} · ${target.name}`
                + `${machine === undefined ? "" : `, on the ${machine.label}`}\n\n`
                + "F5 with no launch.json builds and debugs it, as does a launch whose target is "
                + "`${command:retrocore.activeTarget}` when the launch's "
                + "project is this target's retrocore.json or a root file that lists it. "
                + `Click to pick another of the workspace's targets.\n\n\`${target.file.replaceAll("`", "'")}\``);
            item.show();
        }
        if (text !== shown) {
            shown = text;
            changed.fire(target);
        }
    };

    let reading: Promise<void> | undefined;
    const refresh = async (): Promise<void> => {
        let files: string[];
        try {
            files = (await vscode.workspace.findFiles(`**/${projectFileName}`, excluded)).map(uri => uri.fsPath)
                .sort((a, b) => a.localeCompare(b));
        } catch (error) {
            // The targets stay as they were; the next change to a project file looks again.
            console.warn(`retrocore: could not look for ${projectFileName} files: ${String(error)}`);
            return;
        }
        const found: ProjectTarget[] = [];
        // A root file's projects are found as files of their own too, and are listed once, under their own file.
        for (const file of files) {
            if (isRootFile(file)) continue;
            try {
                found.push(...loadTargets(file));
            } catch {
                // A file the extension cannot read gives no targets; a launch of it says why.
            }
        }
        for (const file of files.filter(isRootFile)) {
            try {
                for (const target of loadTargets(file)) {
                    if (!found.some(other => same(other.file, target.file) && other.name === target.name)) found.push(target);
                }
            } catch {
                // As above.
            }
        }
        targets = found;
        current = active();
        show();
    };
    const queue = (): Promise<void> => {
        const next = (reading ?? Promise.resolve()).then(refresh, refresh);
        reading = next;
        lastRead = next;
        return next;
    };

    const watcher = vscode.workspace.createFileSystemWatcher(`**/${projectFileName}`);
    context.subscriptions.push(watcher, watcher.onDidChange(() => void queue()), watcher.onDidCreate(() => void queue()),
        watcher.onDidDelete(() => void queue()), vscode.workspace.onDidChangeWorkspaceFolders(() => void queue()));
    void queue();

    // Names the active target for ${command:retrocore.activeTarget}: as project/target, which picks it whether the
    // launch's project is its own file or a root file that lists it.
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.activeTarget", async () => {
        await reading;
        const target = active();
        if (target === undefined) {
            void vscode.window.showErrorMessage(`Retrocore: the workspace has no ${projectFileName} with a target to debug.`);
            return undefined;
        }
        return qualifiedName(target);
    }));

    // Picks the active target from the workspace's, grouped by project; or takes one given, as the tests do, by its
    // project's file and name.
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.pickTarget", async (file?: string, name?: string) => {
        await queue();
        let picked: ProjectTarget | undefined;
        if (typeof file === "string" && typeof name === "string") {
            picked = targets.find(target => same(target.file, file) && target.name === name);
            if (picked === undefined) throw new Error(`There is no target ${name} in ${file}.`);
        } else {
            picked = await pick(targets, active());
        }
        if (picked === undefined) return undefined;
        await context.workspaceState.update(stateKey, { file: picked.file, target: picked.name });
        current = active();
        show();
        return qualifiedName(picked);
    }));

    // F5 with no launch.json sends an empty configuration: in a workspace with a project, that debugs the active
    // target. VS Code asks the providers of the debugger it guesses from the editor, and those registered for every
    // type, so both take it; the first fills it in and the other sees a configuration of its own.
    const provider: vscode.DebugConfigurationProvider = {
        async resolveDebugConfiguration(_folder, configuration) {
            // VS Code may have set the type it guessed; a configuration with a request or a name is someone's own.
            const empty = (configuration.type === undefined || configuration.type === "retrocore")
                && configuration.request === undefined && configuration.name === undefined;
            if (!empty) return configuration;
            await reading;
            const target = active();
            return target === undefined ? configuration : { ...configuration, ...projectLaunch(target) };
        }
    };
    context.subscriptions.push(vscode.debug.registerDebugConfigurationProvider("retrocore", provider),
        vscode.debug.registerDebugConfigurationProvider("*", provider));

    // For the tests: what the status bar shows, which they cannot read from VS Code.
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.activeTarget.statusBar", async () => {
        await reading;
        return { text: item.text, command: item.command, visible: active() !== undefined };
    }));

    return {
        get active() { return active(); },
        get targets() { return targets; },
        onDidChange: changed.event,
        refresh: queue
    };
}

/** Shows the workspace's targets, one group per project when there are several, the active one checked. */
async function pick(targets: readonly ProjectTarget[], chosen: ProjectTarget | undefined): Promise<ProjectTarget | undefined> {
    if (targets.length === 0) {
        void vscode.window.showInformationMessage(`Retrocore: the workspace has no ${projectFileName} with targets.`);
        return undefined;
    }
    type Item = vscode.QuickPickItem & { target?: ProjectTarget };
    const files = [...new Set(targets.map(target => target.file))];
    const items: Item[] = [];
    for (const file of files) {
        const own = targets.filter(target => target.file === file);
        if (files.length > 1) {
            items.push({ label: `${own[0].project} · ${vscode.workspace.asRelativePath(path.dirname(file))}`, kind: vscode.QuickPickItemKind.Separator });
        }
        for (const target of own) {
            const machine = machineById(target.machine);
            const environment = typeof target.definition.environment === "string" ? target.definition.environment : "bare";
            items.push({
                label: `${target === chosen ? "$(check)" : "$(blank)"} ${target.name}`,
                description: machine?.label ?? target.machine,
                detail: `${environment === "bare" ? "On the bare machine" : `In ${environment}`}${machine === undefined ? "" : `: ${machine.detail}`}`,
                target
            });
        }
    }
    const picked = await vscode.window.showQuickPick(items, {
        title: "Retrocore: Pick Target",
        placeHolder: "Which target does F5 build and debug?",
        matchOnDescription: true
    });
    return picked?.target;
}
