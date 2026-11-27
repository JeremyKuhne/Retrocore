// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Finds Retrocore.Debug.dll, which runs both the language server and the debug adapter. A workspace whose repository
// pins the retrocore tool in .config/dotnet-tools.json runs that tool once it is restored, so the editor builds what CI
// builds. Otherwise an installed extension uses the host packaged with it, so it works in any folder and stays on a
// known build. A self-hosted one (Extension Development Host or tests) uses the workspace's Release build first, or
// its repository's when a folder inside it is the workspace, so a rebuild shows at once.

import * as childProcess from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import * as vscode from "vscode";
import { chooseHost, findPin, packagesFolder, restoredHost, sameVersion, type HostChoice, type ToolPin } from "./pinnedTool";

const hostName = "Retrocore.Debug.dll";

/** The host the VSIX packages, in the extension's server folder. */
export function bundledHost(context: vscode.ExtensionContext): string | undefined {
    const candidate = path.join(context.extensionPath, "server", hostName);
    return fs.existsSync(candidate) ? candidate : undefined;
}

/**
 * The Release build in an open workspace folder, such as this repository's, or in a folder above one up to its
 * repository's root (the first with a .git; with none, up to the drive's), as when one of the repository's samples
 * is opened as the workspace. Each folder's own build comes before any folder's above it, and a worktree's root stops
 * the search at its own build.
 */
export function workspaceHost(): string | undefined {
    const build = (directory: string): string | undefined => {
        const candidate = path.join(directory, "artifacts", "AnyCPU", "Release", "Retrocore.Debug", "net11.0", hostName);
        return fs.existsSync(candidate) ? candidate : undefined;
    };
    const folders = (vscode.workspace.workspaceFolders ?? []).map(folder => folder.uri.fsPath);
    for (const folder of folders) {
        const own = build(folder);
        if (own !== undefined) return own;
    }
    for (const folder of folders) {
        for (let directory = folder; !fs.existsSync(path.join(directory, ".git")) && path.dirname(directory) !== directory;) {
            directory = path.dirname(directory);
            const above = build(directory);
            if (above !== undefined) return above;
        }
    }
    return undefined;
}

/**
 * The extension's own host, when no repository pins one: the packaged host, or in development the workspace's build
 * first.
 */
export function ownHost(context: vscode.ExtensionContext): string | undefined {
    return context.extensionMode === vscode.ExtensionMode.Production
        ? bundledHost(context) ?? workspaceHost()
        : workspaceHost() ?? bundledHost(context);
}

const versions = new Map<string, Promise<string | undefined>>();

/**
 * A host's version, as `retrocore --version` prints it; undefined when it cannot be run, as when its .NET runtime is
 * missing. Asked once per build of a host (its file's size and time) until a check succeeds, without blocking the
 * extension.
 */
export function hostVersion(host: string): Promise<string | undefined> {
    let key = host;
    try {
        const stat = fs.statSync(host);
        key = `${host}\u001f${stat.size}\u001f${stat.mtimeMs}`;
    } catch {
        return Promise.resolve(undefined);
    }
    let version = versions.get(key);
    if (version === undefined) {
        version = new Promise(resolve => {
            childProcess.execFile("dotnet", [host, "--version"], { encoding: "utf8", timeout: 20000 },
                (error, stdout) => resolve(error === null ? stdout.trim() || undefined : undefined));
        });
        versions.set(key, version);
        // A host that did not run is asked again next time, as its runtime may have been installed since.
        void version.then(found => { if (found === undefined) versions.delete(key); });
    }
    return version;
}

/**
 * The repository's pin of the retrocore tool for the workspace: that of the first workspace folder whose repository
 * pins one, at the folder or above it.
 */
export function workspacePin(): ToolPin | undefined {
    for (const folder of vscode.workspace.workspaceFolders ?? []) {
        const pin = findPin(folder.uri.fsPath);
        if (pin !== undefined) return pin;
    }
    return undefined;
}

/**
 * Chooses the host for the workspace when no launch configuration names one: the setting given, if any, then the
 * repository's pinned tool once it is restored and runs as the version pinned, and otherwise the extension's own host,
 * with a warning when its version differs (pinnedTool.ts). In development a workspace build of this repository comes
 * before the pin, so a rebuild shows at once.
 */
export async function chooseWorkspaceHost(context: vscode.ExtensionContext, configured?: string): Promise<HostChoice> {
    const own = ownHost(context);
    const pin = workspacePin();
    if (configured) return chooseHost({ configured, pin });
    const build = context.extensionMode === vscode.ExtensionMode.Production ? undefined : workspaceHost();
    if (build !== undefined) return { host: build, pin, pinned: false };
    if (pin === undefined) return { host: own, pinned: false };
    const found = restoredHost(pin.version);
    const restored = found !== undefined && sameVersion(await hostVersion(found), pin.version) ? found : undefined;
    const fallbackVersion = restored === undefined && own !== undefined ? await hostVersion(own) : undefined;
    return chooseHost({ pin, restored, unrunnable: found !== undefined && restored === undefined, fallback: own, fallbackVersion });
}

/** The host to run when no setting or launch configuration names one. */
export async function defaultHost(context: vscode.ExtensionContext): Promise<string | undefined> {
    return (await chooseWorkspaceHost(context)).host;
}

/**
 * Whether a host never changes while it runs and so needs no shadow copy: the packaged one, or a restored tool in the
 * NuGet packages folder.
 */
export function isBundled(context: vscode.ExtensionContext, host: string): boolean {
    const within = (folder: string): boolean => {
        const relative = path.relative(folder, host);
        return relative !== "" && !relative.startsWith("..") && !path.isAbsolute(relative);
    };
    return within(context.extensionPath) || within(packagesFolder());
}
