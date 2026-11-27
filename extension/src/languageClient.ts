// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as fs from "node:fs";
import * as path from "node:path";
import * as vscode from "vscode";
import { LanguageClient, LanguageClientOptions, ServerOptions, TransportKind } from "vscode-languageclient/node";
import { defaultHost, isBundled } from "./host";
import type { ActiveTargets } from "./activeTarget";
import { activeTargetParams } from "./project";

let client: LanguageClient | undefined;
// The current client's start, which requests wait for.
let starting: Promise<void> | undefined;
const stopped = new vscode.EventEmitter<void>();
const startedEvent = new vscode.EventEmitter<void>();

/** Fires when the language server is stopped, as it is before a restart, so what it reported can be cleared. */
export const onDidStopLanguageClient = stopped.event;

/**
 * Fires when a language server has started and been sent the active target, after a restart as well as the first
 * time, so it can be asked again.
 */
export const onDidStartLanguageClient = startedEvent.event;

/** The Retrocore.Debug host: the setting, or the repository's pinned tool, the packaged host or the workspace's build (see host.ts). */
export async function hostPath(context: vscode.ExtensionContext): Promise<string | undefined> {
    const configured = vscode.workspace.getConfiguration("retrocore").get<string>("languageServer.host");
    return configured ? configured : await defaultHost(context);
}

// Stops the running server and starts it again on the host given, or the one chosen now, with the registrations its
// first start made; true when a server runs after it.
let restartOn: ((host?: string) => Promise<boolean>) | undefined;

// Every restart, the rebuild watcher's included, waits for the one before it, so no two start servers at once.
let restarts: Promise<unknown> = Promise.resolve();

function queued<T>(work: () => Promise<T>): Promise<T> {
    const next = restarts.then(work, work);
    restarts = next.catch(() => undefined);
    return next;
}

/**
 * Restarts the language server on the host chosen now, as after the pinned tool is restored: the first start's
 * watchers, listeners and commands are kept, and only the server is replaced; it starts it if the extension never
 * found a host to start it on. Restarts run one after another, after the first start.
 * @returns Whether a language server runs after it: false when there is no host, or the server did not start.
 */
export function restartLanguageClient(context: vscode.ExtensionContext, targets?: ActiveTargets): Promise<boolean> {
    return queued(async () => {
        if (restartOn !== undefined) return await restartOn();
        await startLanguageClient(context, targets);
        return client?.isRunning() ?? false;
    });
}

/**
 * Copies the host's directory into extension storage and returns the copy's DLL. The server runs from the copy,
 * so building the debug host (for instance a debug launch's preLaunchTask) can overwrite the original while it runs.
 */
export function shadowCopy(host: string, storage: string, folder = "language-server"): string {
    // A library can rebuild without the host DLL changing, so the newest DLL names the copy.
    const directory = path.dirname(host);
    const stamp = Math.max(...fs.readdirSync(directory).filter(name => name.endsWith(".dll"))
        .map(name => fs.statSync(path.join(directory, name)).mtimeMs)).toFixed(0);
    const root = path.join(storage, folder);
    const target = path.join(root, stamp);
    if (!fs.existsSync(path.join(target, path.basename(host)))) {
        const staging = `${target}.${process.pid}.tmp`;
        fs.rmSync(staging, { recursive: true, force: true });
        fs.cpSync(directory, staging, { recursive: true });
        try {
            fs.renameSync(staging, target);
        } catch {
            // Another window made the same copy first.
            fs.rmSync(staging, { recursive: true, force: true });
        }
    }
    for (const entry of fs.readdirSync(root)) {
        // Older copies may still be in use by other windows; those stay until a later start.
        if (entry === stamp || entry.endsWith(".tmp")) continue;
        // A running copy keeps its DLL locked, so deleting that first leaves a copy in use whole.
        const old = path.join(root, entry);
        try {
            fs.rmSync(path.join(old, path.basename(host)), { force: true });
            fs.rmSync(old, { recursive: true, force: true });
        } catch {
            // In use; a later start removes it.
        }
    }
    return path.join(target, path.basename(host));
}

/**
 * Starts the retrocore language server for retrocore-asm documents: diagnostics, definition, hover, completion and
 * symbols. It tells the server the active target, for assembling a project's sources with it.
 */
export async function startLanguageClient(context: vscode.ExtensionContext, targets?: ActiveTargets): Promise<void> {
    const settings = vscode.workspace.getConfiguration("retrocore");
    if (!settings.get<boolean>("languageServer.enabled", true)) return;
    context.subscriptions.push(stopped, startedEvent);
    const host = await hostPath(context);
    if (restartOn !== undefined) return;
    if (host === undefined || !fs.existsSync(host)) {
        void vscode.window.showWarningMessage(
            "Retrocore: language features need Retrocore.Debug.dll. Reinstall the extension, build the repository, restore the pinned tool, or set retrocore.languageServer.host.");
        return;
    }

    const configurations = vscode.workspace.createFileSystemWatcher("**/*.cfg");
    // A project file's changes reach the server too, for its project support (phase 2) to analyze the sources again.
    const projects = vscode.workspace.createFileSystemWatcher("**/retrocore.json");
    // A Pascal file changed on disk, such as an include no editor has open, changes the programs that read it.
    const pascal = vscode.workspace.createFileSystemWatcher("**/*.{text,TEXT,Text,pas,PAS,Pas,pascal,PASCAL,Pascal}");
    const isConfiguration = (document: vscode.TextDocument): boolean =>
        document.uri.scheme === "file" && path.extname(document.uri.fsPath).toLowerCase() === ".cfg";
    const notify = (method: string, params: object): void => {
        const running = client;
        if (running === undefined) return;
        void (async () => {
            await starting;
            if (client === running) await running.sendNotification(method, params);
        })().catch(error => console.error(`retrocore: configuration synchronization failed: ${String(error)}`));
    };
    const opened = (document: vscode.TextDocument): void => {
        if (isConfiguration(document)) notify("textDocument/didOpen", {
            textDocument: { uri: document.uri.toString(), languageId: document.languageId, version: document.version, text: document.getText() }
        });
    };
    const wordsFor = (uri?: vscode.Uri): string[] => {
        const values = vscode.workspace.getConfiguration("retrocore.lint", uri).inspect<string[]>("unlinkedNameWords");
        return [...new Set([...(values?.globalValue ?? []), ...(values?.workspaceValue ?? []),
            ...(values?.workspaceFolderValue ?? [])])];
    };
    const updateWords = (): void => notify("retrocore/unlinkedNameWords", {
        words: wordsFor(),
        folders: (vscode.workspace.workspaceFolders ?? []).map(folder => ({
            uri: folder.uri.toString(), words: wordsFor(folder.uri)
        }))
    });
    const updateTarget = (): void => notify("retrocore/activeTarget", activeTargetParams(targets?.active));
    if (targets !== undefined) context.subscriptions.push(targets.onDidChange(updateTarget));
    context.subscriptions.push(configurations, projects, pascal, vscode.workspace.onDidOpenTextDocument(opened),
        vscode.workspace.onDidChangeTextDocument(event => {
            if (isConfiguration(event.document)) notify("textDocument/didChange", {
                textDocument: { uri: event.document.uri.toString(), version: event.document.version },
                contentChanges: [{ text: event.document.getText() }]
            });
        }),
        vscode.workspace.onDidCloseTextDocument(document => {
            if (isConfiguration(document)) notify("textDocument/didClose", { textDocument: { uri: document.uri.toString() } });
        }),
        vscode.workspace.onDidChangeConfiguration(event => {
            if (event.affectsConfiguration("retrocore.lint.unlinkedNameWords")) updateWords();
        }),
        vscode.workspace.onDidChangeWorkspaceFolders(updateWords),
        vscode.commands.registerCommand("retrocore.lint.addUnlinkedNameWord", addUnlinkedNameWord));

    let current = host;
    const start = async (from: string = current): Promise<void> => {
        current = from;
        await startFrom(context, from, [configurations, projects, pascal]);
        updateWords();
        updateTarget();
        for (const document of vscode.workspace.textDocuments) opened(document);
        // After the target, so what is asked now is answered for it.
        startedEvent.fire();
    };
    // Set before the first start, so a restart after one that failed replaces the server rather than registering again.
    // A server that does not start is reported, and the restart says so; the host it was to run is kept, so a rebuild
    // of the first start's host revives it only if that was the one.
    const notStarted = (on: string, error: unknown): void => {
        void vscode.window.showWarningMessage(`Retrocore: the language server did not start on ${on}: ${String(error)}`);
    };
    restartOn = async (given?: string) => {
        await stopLanguageClient();
        if (!vscode.workspace.getConfiguration("retrocore").get<boolean>("languageServer.enabled", true)) return false;
        let next: string | undefined = given;
        try {
            next ??= await hostPath(context);
            if (next === undefined || !fs.existsSync(next)) {
                void vscode.window.showWarningMessage(
                    "Retrocore: language features need Retrocore.Debug.dll. Reinstall the extension, build the repository, restore the pinned tool, or set retrocore.languageServer.host.");
                return false;
            }
            await start(next);
        } catch (error) {
            notStarted(next ?? "the host chosen", error);
            return false;
        }
        return client?.isRunning() ?? false;
    };

    // Restart on the rebuilt host once a build has settled, while it is the host the server runs: a server moved to
    // another host, such as the restored pinned tool, stays there. The watcher is made before the first start, so a
    // rebuild recovers from a first start that failed.
    let pending: NodeJS.Timeout | undefined;
    const watcher = vscode.workspace.createFileSystemWatcher(new vscode.RelativePattern(vscode.Uri.file(path.dirname(host)), path.basename(host)));
    const changed = (): void => {
        if (pending !== undefined) clearTimeout(pending);
        pending = setTimeout(() => {
            pending = undefined;
            if (current !== host || !fs.existsSync(host)) return;
            queued(async () => await restartOn?.(host))
                .catch(error => console.error(`retrocore: the language server did not restart: ${String(error)}`));
        }, 2000);
    };
    context.subscriptions.push(watcher, watcher.onDidChange(changed), watcher.onDidCreate(changed),
        { dispose: () => { if (pending !== undefined) clearTimeout(pending); } });
    try {
        await start();
    } catch (error) {
        notStarted(host, error);
    }
}

/** Adds a word to the user's or the workspace's unlinked-name dictionary: the server's quick fix for the lint. */
async function addUnlinkedNameWord(word?: unknown, scope?: unknown): Promise<boolean> {
    if (typeof word !== "string" || word.length === 0) return false;
    const workspace = scope === "workspace";
    if (workspace && vscode.workspace.workspaceFolders === undefined) {
        void vscode.window.showWarningMessage("Retrocore: open a folder or workspace to add words to its dictionary.");
        return false;
    }
    const settings = vscode.workspace.getConfiguration("retrocore.lint");
    const values = settings.inspect<string[]>("unlinkedNameWords");
    const current = (workspace ? values?.workspaceValue : values?.globalValue) ?? [];
    if (current.includes(word)) return true;
    await settings.update("unlinkedNameWords", [...current, word],
        workspace ? vscode.ConfigurationTarget.Workspace : vscode.ConfigurationTarget.Global);
    return true;
}

async function startFrom(context: vscode.ExtensionContext, host: string, watchers: vscode.FileSystemWatcher[]): Promise<void> {
    let server = host;
    try {
        // The packaged host never changes while it runs; a build can, so it runs from a copy.
        if (!isBundled(context, host)) server = shadowCopy(host, context.globalStorageUri.fsPath);
    } catch (error) {
        // Running in place still works; it only blocks rebuilding the host while the server runs.
        console.warn(`retrocore: running the language server in place: ${String(error)}`);
    }

    const serverOptions: ServerOptions = {
        command: "dotnet",
        // The SDK sources are indexed from the original host's directory, not the copy, so navigation opens them there.
        args: [server, "--language-server", "--sdk-roms", path.join(path.dirname(host), "Sdk", "Roms")],
        transport: TransportKind.stdio
    };
    const clientOptions: LanguageClientOptions = {
        documentSelector,
        synchronize: { fileEvents: watchers }
    };
    const started = new LanguageClient("retrocore", "Retrocore Assembly", serverOptions, clientOptions);
    client = started;
    context.subscriptions.push({ dispose: () => { void started.stop().catch(() => undefined); } });
    starting = started.start();
    await starting;
}

/** The BASIC languages: one per dialect, and one whose pragma, file name or session decides. */
export const basicLanguages = ["retrocore-applesoft", "retrocore-level2", "retrocore-integer", "retrocore-apple1", "retrocore-business",
    "retrocore-level1", "retrocore-colorbasic", "retrocore-mbasic", "retrocore-model100",
    "retrocore-petbasic", "retrocore-bbcbasic", "retrocore-atari", "retrocore-basic"];

/** Assembly and Pascal documents must be files, read with the files they include; BASIC also supports virtual documents. */
export const documentSelector = [
    ...["retrocore-asm", "retrocore-macro10", "retrocore-pascal"].map(language => ({ language, scheme: "file" })),
    ...basicLanguages.map(language => ({ language }))
];

/** Sends a request to the language server once it has started, or fails when it is not running. */
export async function languageRequest<T>(method: string, params: unknown): Promise<T> {
    const running = client;
    if (running === undefined) throw new Error("The Retrocore language server is not running.");
    await starting;
    return await running.sendRequest<T>(method, params);
}

/** Stops the language server; one that never started, or is still starting, is let go as it is. */
export async function stopLanguageClient(): Promise<void> {
    const running = client;
    client = undefined;
    if (running !== undefined) stopped.fire();
    try {
        await running?.stop();
    } catch (error) {
        // vscode-languageclient keeps no hold on a server whose start failed, so its process may still run.
        console.warn(`retrocore: the language server could not be stopped, and its process may still run: ${String(error)}`);
    }
}
