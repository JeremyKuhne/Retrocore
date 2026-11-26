// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Finds Retrocore.Debug.dll, which runs both the language server and the debug adapter. An installed extension uses
// the host packaged with it, so it works in any folder and stays on a known build. A self-hosted one (Extension
// Development Host or tests) uses the workspace's Release build first, or its repository's when a folder inside it
// is the workspace, so a rebuild shows at once.

import * as fs from "node:fs";
import * as path from "node:path";
import * as vscode from "vscode";

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

/** The host to run when no setting or launch configuration names one. */
export function defaultHost(context: vscode.ExtensionContext): string | undefined {
    return context.extensionMode === vscode.ExtensionMode.Production
        ? bundledHost(context) ?? workspaceHost()
        : workspaceHost() ?? bundledHost(context);
}

/** Whether a host is the packaged one, which never changes while it runs and so needs no shadow copy. */
export function isBundled(context: vscode.ExtensionContext, host: string): boolean {
    const relative = path.relative(context.extensionPath, host);
    return !relative.startsWith("..") && !path.isAbsolute(relative);
}
