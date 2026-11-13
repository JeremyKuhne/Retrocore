// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as fs from "node:fs";
import * as path from "node:path";
import * as vscode from "vscode";
import { LanguageClient, LanguageClientOptions, ServerOptions, TransportKind } from "vscode-languageclient/node";
import { defaultHost, isBundled } from "./host";

let client: LanguageClient | undefined;

/** The Retrocore.Debug host: the setting, or the packaged host or the workspace's build (see host.ts). */
export function hostPath(context: vscode.ExtensionContext): string | undefined {
    const configured = vscode.workspace.getConfiguration("retrocore").get<string>("languageServer.host");
    return configured ? configured : defaultHost(context);
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

/** Starts the retrocore language server for retrocore-asm documents: diagnostics, definition, hover, completion and symbols. */
export async function startLanguageClient(context: vscode.ExtensionContext): Promise<void> {
    const settings = vscode.workspace.getConfiguration("retrocore");
    if (!settings.get<boolean>("languageServer.enabled", true)) return;
    const host = hostPath(context);
    if (host === undefined || !fs.existsSync(host)) {
        void vscode.window.showWarningMessage(
            "Retrocore: language features need Retrocore.Debug.dll. Reinstall the extension, build the repository, or set retrocore.languageServer.host.");
        return;
    }

    await startFrom(context, host);

    // Restart on the rebuilt host once a build has settled.
    let pending: NodeJS.Timeout | undefined;
    const watcher = vscode.workspace.createFileSystemWatcher(new vscode.RelativePattern(vscode.Uri.file(path.dirname(host)), path.basename(host)));
    const changed = (): void => {
        if (pending !== undefined) clearTimeout(pending);
        pending = setTimeout(() => {
            pending = undefined;
            void (async () => {
                await stopLanguageClient();
                if (fs.existsSync(host)) await startFrom(context, host);
            })();
        }, 2000);
    };
    context.subscriptions.push(watcher, watcher.onDidChange(changed), watcher.onDidCreate(changed),
        { dispose: () => { if (pending !== undefined) clearTimeout(pending); } });
}

async function startFrom(context: vscode.ExtensionContext, host: string): Promise<void> {
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
        documentSelector
    };
    const started = new LanguageClient("retrocore", "Retrocore Assembly", serverOptions, clientOptions);
    client = started;
    context.subscriptions.push({ dispose: () => { void started.stop().catch(() => undefined); } });
    await started.start();
}

/** The BASIC languages: one per dialect, and one whose pragma, file name or session decides. */
export const basicLanguages = ["retrocore-applesoft", "retrocore-level2", "retrocore-integer", "retrocore-apple1", "retrocore-business", "retrocore-level1", "retrocore-basic"];

/** Assembly documents must be files; BASIC also supports virtual documents. */
export const documentSelector = [
    ...["retrocore-asm", "retrocore-macro10"].map(language => ({ language, scheme: "file" })),
    ...basicLanguages.map(language => ({ language }))
];

/** Sends a request to the language server, or fails when it is not running. */
export async function languageRequest<T>(method: string, params: unknown): Promise<T> {
    if (client === undefined) throw new Error("The Retrocore language server is not running.");
    return await client.sendRequest<T>(method, params);
}

/** Stops the language server. */
export async function stopLanguageClient(): Promise<void> {
    const running = client;
    client = undefined;
    await running?.stop();
}
