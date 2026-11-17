// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The Favorites view: the machines kept in the retrocore.favorites setting, in user settings (in every workspace) and
// the workspace's (shared through git). Clicking one sets it up off in the Machine and Drives views; its play button
// starts it. favorite.ts has the favorite itself.

import * as vscode from "vscode";
import { differences, expanded, favoriteFrom, favoriteSetup, isFavorite, local, portable, resolveVariables, type Favorite } from "./favorite";
import { machineById } from "./machines";
import { folder, type OffMachine, type OffTarget } from "./offMachine";
import type { SavedMachines } from "./savedMachine";
import { describeSetup, setupConfiguration, setupFromConfiguration, setupName, type Setup } from "./startFlow";

/** Where a favorite is kept: user settings, or the workspace's. */
export type Scope = "user" | "workspace";

/** A favorite where it is kept. */
export interface Kept { favorite: Favorite; scope: Scope }

type Node = { scope: Scope } | Kept;

/**
 * Whether the machine the Machine view shows is a favorite: not one, saved and matching, or saved and changed since,
 * with what differs.
 */
export interface FavoriteMark {
    state: "none" | "saved" | "changed";
    kept?: Kept;
    differences?: string[];
}

/** The favorites, as the Machine view's heart asks after them. */
export interface Favorites {
    mark(): FavoriteMark;
    readonly onDidChange: vscode.Event<void>;
}

// Which favorite each launch configuration was saved as, by its name, so its heart follows it once saved.
const linksKey = "retrocore.favoriteLinks";


const section = "retrocore";
const key = "favorites";
const target = (scope: Scope): vscode.ConfigurationTarget =>
    scope === "user" ? vscode.ConfigurationTarget.Global : vscode.ConfigurationTarget.Workspace;
const scopeName = (scope: Scope): string => scope === "user" ? "user settings" : "the workspace's settings";
const workspacePath = (): string | undefined => folder()?.uri.fsPath;

/** The favorites in each scope, as the setting has them. */
export function readFavorites(): Record<Scope, Favorite[]> {
    const inspected = vscode.workspace.getConfiguration(section).inspect<unknown[]>(key);
    const usable = (values: unknown[] | undefined): Favorite[] => (Array.isArray(values) ? values : []).filter(isFavorite);
    return { user: usable(inspected?.globalValue), workspace: usable(inspected?.workspaceValue) };
}

async function writeFavorites(scope: Scope, favorites: Favorite[]): Promise<void> {
    await vscode.workspace.getConfiguration(section).update(key, favorites, target(scope));
}

/** The setup and saved machine that load or start a favorite, its paths resolved. */
export function favoriteTarget(favorite: Favorite): { target: OffTarget; machineState: unknown } {
    const resolved = resolveVariables(favorite, workspacePath());
    const setup = favoriteSetup(resolved);
    // One with no saved machine restores nothing over its launch, so loading it drops edits made to it since.
    return { target: { configuration: setupConfiguration(setup), source: { kind: "setup", setup } }, machineState: resolved.machineState ?? {} };
}

/** Each favorite as Switch Machine and Start Machine list it. */
export function favoriteChoices(): { label: string; description?: string; detail?: string; target: OffTarget; machineState: unknown; setup: Setup }[] {
    const kept = readFavorites();
    return [...kept.workspace, ...kept.user].map(favorite => {
        const { target: off, machineState } = favoriteTarget(favorite);
        return {
            label: "$(star-full) " + favorite.name,
            description: favorite.description,
            detail: describeSetup({ ...favoriteSetup(favorite), name: undefined }),
            target: off,
            machineState,
            setup: (off.source as { setup: Setup }).setup
        };
    });
}

/** A favorite's hover: its description, machine, settings, what it runs, and its cards and media. */
function tooltip(kept: Kept): vscode.MarkdownString {
    const { favorite, scope } = kept;
    const escape = (text: string): string => text.replace(/[\\`*_[\]<>]/g, "\\$&");
    const text = new vscode.MarkdownString(`**${escape(favorite.name)}**`);
    if (favorite.description !== undefined) text.appendMarkdown(`\n\n${escape(favorite.description)}`);
    text.appendMarkdown(`\n\n${escape(describeSetup({ ...favoriteSetup(favorite), name: undefined }))}`);
    const state = favorite.machineState as { cards?: Record<string, unknown>; media?: Record<string, { path?: string } | null> } | undefined;
    const cards = Object.entries(state?.cards ?? {}).filter(([, card]) => card !== "empty");
    if (cards.length !== 0) text.appendMarkdown(`\n\nCards: ${cards.map(([slot, card]) => `${escape(String(card))} in slot ${slot}`).join(", ")}`);
    const media = Object.entries(state?.media ?? {}).filter(([, entry]) => entry?.path !== undefined);
    for (const [drive, entry] of media) text.appendMarkdown(`\n\n- ${escape(drive)}: ${escape(String(entry?.path))}`);
    text.appendMarkdown(`\n\nIn ${scopeName(scope)}.`);
    return text;
}

class FavoritesTree implements vscode.TreeDataProvider<Node> {
    private readonly changed = new vscode.EventEmitter<Node | undefined>();
    readonly onDidChangeTreeData = this.changed.event;

    constructor(private readonly mark: () => FavoriteMark) {}

    refresh(): void {
        this.changed.fire(undefined);
    }

    getChildren(node?: Node): Node[] {
        const kept = readFavorites();
        const all = (scope: Scope): Kept[] => kept[scope].map(favorite => ({ favorite, scope }));
        if (node === undefined) {
            // Grouped only when both have some.
            if (kept.user.length !== 0 && kept.workspace.length !== 0) return [{ scope: "workspace" }, { scope: "user" }];
            return [...all("workspace"), ...all("user")];
        }
        return "favorite" in node ? [] : all(node.scope);
    }

    // Revealing a favorite, as the Machine view's filled heart does, needs its group when there are groups.
    getParent(node: Node): Node | undefined {
        if (!("favorite" in node)) return undefined;
        const kept = readFavorites();
        return kept.user.length !== 0 && kept.workspace.length !== 0 ? { scope: node.scope } : undefined;
    }

    getTreeItem(node: Node): vscode.TreeItem {
        if (!("favorite" in node)) {
            const item = new vscode.TreeItem(node.scope === "user" ? "User" : "Workspace", vscode.TreeItemCollapsibleState.Expanded);
            item.id = `scope/${node.scope}`;
            item.tooltip = node.scope === "user" ? "In your user settings: in every workspace." : "In the workspace's settings: shared with the project.";
            return item;
        }

        const { favorite, scope } = node;
        const item = new vscode.TreeItem(favorite.name, vscode.TreeItemCollapsibleState.None);
        item.id = `favorite/${scope}/${favorite.name}`;
        const mark = this.mark();
        const shown = mark.kept?.favorite.name === favorite.name && mark.kept.scope === scope
            ? (vscode.debug.activeDebugSession?.type === "retrocore" ? "running" : "set up") + (mark.state === "changed" ? ", changed" : "")
            : undefined;
        item.description = [favorite.description ?? machineById(favorite.machine)?.label, shown].filter(part => part !== undefined).join(" · ");
        item.tooltip = tooltip(node);
        item.iconPath = new vscode.ThemeIcon(shown === undefined ? "star-empty" : "star-full");
        item.contextValue = `favorite ${scope}`;
        item.command = { command: "retrocore.favorite.load", title: "Set Up This Machine", arguments: [node] };
        return item;
    }
}

/** Registers the Favorites view and its actions, and gives the Machine view's heart what it asks. */
export function registerFavorites(context: vscode.ExtensionContext, off: OffMachine, saved: SavedMachines): Favorites {
    const changed = new vscode.EventEmitter<void>();
    context.subscriptions.push(changed);
    const tree = new FavoritesTree(() => mark());
    const view = vscode.window.createTreeView("retrocore.favorites", { treeDataProvider: tree });
    context.subscriptions.push(view);
    const refresh = (): void => {
        tree.refresh();
        changed.fire();
    };
    context.subscriptions.push(vscode.workspace.onDidChangeConfiguration(event => {
        if (event.affectsConfiguration(`${section}.${key}`)) refresh();
    }));
    context.subscriptions.push(off.onDidChange(() => tree.refresh()));
    context.subscriptions.push(vscode.debug.onDidChangeActiveDebugSession(() => tree.refresh()));
    context.subscriptions.push(vscode.debug.onDidReceiveDebugSessionCustomEvent(event => {
        if (event.event === "retro/devices") tree.refresh();
    }));
    const links = (): Record<string, string> => context.workspaceState.get<Record<string, string>>(linksKey) ?? {};
    const link = async (from: string, to: string | undefined): Promise<void> => {
        const all = { ...links() };
        if (to === undefined) delete all[from];
        else all[from] = to;
        await context.workspaceState.update(linksKey, all);
    };

    const error = (message: string): void => { void vscode.window.showErrorMessage(`Retrocore: ${message}`); };
    // A favorite given by its view's row, or by name, as the tests and Start Machine give it.
    const find = (given: Kept | { name: string; scope?: Scope } | string | undefined): Kept | undefined => {
        if (given === undefined) return undefined;
        const name = typeof given === "string" ? given : "favorite" in given ? given.favorite.name : given.name;
        const scope = typeof given === "string" ? undefined : "favorite" in given ? given.scope : given.scope;
        const kept = readFavorites();
        for (const where of scope === undefined ? ["workspace", "user"] as Scope[] : [scope]) {
            const favorite = kept[where].find(candidate => candidate.name === name);
            if (favorite !== undefined) return { favorite, scope: where };
        }
        return undefined;
    };
    const replace = async (scope: Scope, name: string, favorite: Favorite | undefined): Promise<void> => {
        const list = readFavorites()[scope].filter(candidate => candidate.name !== name);
        await writeFavorites(scope, favorite === undefined ? list : [...list, favorite].sort((a, b) => a.name.localeCompare(b.name)));
    };
    // A name is one favorite across user and workspace settings: it names the favorite's launch configuration and
    // saved machine, so loading it, its heart and Start Machine always find the one meant.
    const unique = (except?: string) => (name: string): string | undefined => {
        if (name.trim() === "") return "A favorite needs a name.";
        const kept = readFavorites();
        return [...kept.user, ...kept.workspace].some(candidate => candidate.name === name.trim() && candidate.name !== except)
            ? `There is already a favorite named ${name.trim()}.` : undefined;
    };

    // What the Machine view shows, as a favorite: the running session's machine, or the off one.
    const current = (): { setup: Setup; machineState: unknown } | undefined => {
        const session = vscode.debug.activeDebugSession;
        if (session?.type === "retrocore") {
            const configuration = session.configuration as Record<string, unknown>;
            const setup = off.name === session.name && off.target?.source.kind === "setup" ? off.target.source.setup : setupFromConfiguration(configuration);
            return setup === undefined ? undefined : { setup, machineState: saved.get(configuration) };
        }
        const shown = off.target;
        if (shown === undefined) return undefined;
        const setup = shown.source.kind === "setup" ? shown.source.setup : setupFromConfiguration(shown.configuration);
        // As described, every card and drive; the saved machine can be only what differs from the launch's own.
        return setup === undefined ? undefined : { setup, machineState: off.body?.configuration ?? saved.get(shown.configuration) };
    };
    // The shown machine as a favorite in a scope: in the workspace's settings, paths inside it as ${workspaceFolder}.
    const capture = (name: string, description: string | undefined, scope: Scope, quiet = false): Favorite | undefined => {
        const machine = current();
        if (machine === undefined) {
            if (!quiet) error("there is no machine to keep: set one up or start one first. Machines Retrocore's catalog lacks cannot be kept.");
            return undefined;
        }
        const favorite = favoriteFrom(machine.setup, name, description, machine.machineState);
        return scope === "workspace" ? portable(favorite, workspacePath()) : favorite;
    };

    // The name of the machine the Machine view shows: the running session's, or the off one's.
    const shownName = (): string | undefined => {
        const session = vscode.debug.activeDebugSession;
        return session?.type === "retrocore" ? session.name : off.name;
    };
    // The favorite the shown machine is: one of its name, as a loaded favorite is, or the one it was saved as.
    const linked = (): Kept | undefined => {
        const name = shownName();
        return name === undefined ? undefined : find(name) ?? find(links()[name]);
    };
    const mark = (): FavoriteMark => {
        const kept = linked();
        if (kept === undefined) return { state: "none" };
        const now = capture(kept.favorite.name, kept.favorite.description, kept.scope, true);
        const found = now === undefined ? [] : differences(expanded(kept.favorite, workspacePath()), expanded(now, workspacePath()));
        return found.length === 0 ? { state: "saved", kept } : { state: "changed", kept, differences: found };
    };

    // A name for the shown machine as a favorite: its own, or its machine and file, numbered if it is taken.
    const suggestedName = (setup: Setup): string => {
        const machine = machineById(setup.machineId);
        const base = setup.name ?? (machine === undefined ? "Machine" : setupName(machine, { ...setup, name: undefined }).replace(/ \(Retrocore\)$/, ""));
        let name = base;
        for (let count = 2; unique()(name) !== undefined; count++) name = `${base} ${count}`;
        return name;
    };

    const load = async (given?: Kept | { name: string; scope?: Scope } | string): Promise<boolean> => {
        const kept = find(given);
        if (kept === undefined) return false;
        const { target: off2, machineState } = favoriteTarget(kept.favorite);
        await off.select(off2, machineState);
        return true;
    };
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.favorite.load", load));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.favorite.start", async (given?: Kept | { name: string; scope?: Scope } | string) => {
        if (!await load(given)) return false;
        return await off.boot();
    }));

    // The empty heart: saves the shown machine at once under a name of its own, to rename or describe after.
    // The heart passes its row first and the welcome link nothing; only the tests give a name and description.
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.favorite.add", async (given?: unknown, said?: unknown) => {
        const name = typeof given === "string" ? given : undefined;
        const description = typeof said === "string" ? said : undefined;
        const setup = current()?.setup;
        const from = shownName();
        if (setup === undefined || from === undefined) {
            error("there is no machine to keep: set one up or start one first. Machines Retrocore's catalog lacks cannot be kept.");
            return false;
        }
        const chosen = name?.trim() ?? suggestedName(setup);
        if (unique()(chosen) !== undefined) return false;
        const favorite = capture(chosen, description, "user");
        if (favorite === undefined) return false;
        await link(from, chosen);
        await replace("user", favorite.name, favorite);
        if (name === undefined) {
            const rename = "Rename…";
            const describe = "Add Description…";
            void vscode.window.showInformationMessage(`Retrocore: saved ${chosen} to your favorites.`, rename, describe).then(answer => {
                const kept = { name: chosen, scope: "user" as Scope };
                if (answer === rename) void vscode.commands.executeCommand("retrocore.favorite.rename", kept);
                if (answer === describe) void vscode.commands.executeCommand("retrocore.favorite.editDescription", kept);
            });
        }
        return true;
    }));

    // The broken heart: the favorite takes the shown machine as it is now.
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.favorite.updateShown", async () => {
        const kept = linked();
        if (kept === undefined) return false;
        const favorite = capture(kept.favorite.name, kept.favorite.description, kept.scope);
        if (favorite === undefined) return false;
        await replace(kept.scope, kept.favorite.name, favorite);
        void vscode.window.showInformationMessage(`Retrocore: updated ${kept.favorite.name} to the machine as it is now.`);
        return true;
    }));

    // The filled heart: shows the favorite in the Favorites view.
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.favorite.showShown", async () => {
        const kept = linked();
        if (kept === undefined) return;
        await view.reveal(kept, { select: true, focus: true });
    }));

    context.subscriptions.push(vscode.commands.registerCommand("retrocore.favorite.update", async (given?: Kept) => {
        const kept = find(given);
        if (kept === undefined) return false;
        const replace2 = "Update";
        const answer = await vscode.window.showWarningMessage(
            `Replace ${kept.favorite.name} with the machine the Machine view shows?`, { modal: true }, replace2);
        if (answer !== replace2) return false;
        const favorite = capture(kept.favorite.name, kept.favorite.description, kept.scope);
        if (favorite === undefined) return false;
        await replace(kept.scope, kept.favorite.name, favorite);
        return true;
    }));

    context.subscriptions.push(vscode.commands.registerCommand("retrocore.favorite.editDescription", async (given?: Kept, text?: unknown) => {
        // A menu passes the selected rows second; only the tests give the description.
        const description = typeof text === "string" ? text : undefined;
        const kept = find(given);
        if (kept === undefined) return false;
        const said = description ?? await vscode.window.showInputBox({
            title: `Describe ${kept.favorite.name}`, prompt: "Empty for none", value: kept.favorite.description ?? ""
        });
        if (said === undefined) return false;
        const favorite: Favorite = { ...kept.favorite, description: said.trim() === "" ? undefined : said.trim() };
        if (favorite.description === undefined) delete favorite.description;
        await replace(kept.scope, kept.favorite.name, favorite);
        return true;
    }));

    context.subscriptions.push(vscode.commands.registerCommand("retrocore.favorite.rename", async (given?: Kept, text?: unknown) => {
        const name = typeof text === "string" ? text : undefined;
        const kept = find(given);
        if (kept === undefined) return false;
        const check = unique(kept.favorite.name);
        const chosen = name ?? await vscode.window.showInputBox({ title: `Rename ${kept.favorite.name}`, value: kept.favorite.name, validateInput: check });
        if (chosen === undefined || chosen.trim() === kept.favorite.name || check(chosen) !== undefined) return false;
        await replace(kept.scope, kept.favorite.name, undefined);
        await replace(kept.scope, chosen.trim(), { ...kept.favorite, name: chosen.trim() });
        // Machines saved as it follow it to its new name, as does one loaded from it, which still has the old name.
        for (const [from, to] of Object.entries(links())) if (to === kept.favorite.name) await link(from, chosen.trim());
        await link(kept.favorite.name, chosen.trim());
        refresh();
        return true;
    }));

    const move = async (given: Kept | undefined, to: Scope): Promise<boolean> => {
        const kept = find(given);
        if (kept === undefined || kept.scope === to) return false;
        if (to === "workspace" && folder() === undefined) {
            error("open a folder to share a favorite with its workspace.");
            return false;
        }
        if (readFavorites()[to].some(candidate => candidate.name === kept.favorite.name)) {
            error(`${scopeName(to)} already have a favorite named ${kept.favorite.name}; rename one first.`);
            return false;
        }
        // Shared, its workspace paths travel as ${workspaceFolder}; in user settings they are this workspace's again.
        const moved = to === "workspace" ? portable(kept.favorite, workspacePath()) : local(kept.favorite, workspacePath());
        await replace(to, kept.favorite.name, moved);
        await replace(kept.scope, kept.favorite.name, undefined);
        return true;
    };
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.favorite.share", (given?: Kept) => move(given, "workspace")));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.favorite.moveToUser", (given?: Kept) => move(given, "user")));

    context.subscriptions.push(vscode.commands.registerCommand("retrocore.favorite.remove", async (given?: Kept, confirmed?: boolean) => {
        const kept = find(given);
        if (kept === undefined) return false;
        const remove = "Remove";
        if (confirmed !== true) {
            const answer = await vscode.window.showWarningMessage(
                `Remove ${kept.favorite.name} from ${scopeName(kept.scope)}?`, { modal: true }, remove);
            if (answer !== remove) return false;
        }
        await replace(kept.scope, kept.favorite.name, undefined);
        return true;
    }));

    // The favorites in each scope, and the shown machine's heart, for the tests.
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.favorite.list", () => readFavorites()));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.favorite.mark", () => {
        const found = mark();
        return { state: found.state, name: found.kept?.favorite.name, differences: found.differences };
    }));

    return { mark, onDidChange: changed.event };
}
