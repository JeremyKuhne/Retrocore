// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Finds Retrocore.Debug.dll, which runs both the language server and the debug adapter. An installed extension uses
// the host packaged with it, so it works in any folder and stays on a known build. A self-hosted one (Extension
// Development Host or tests) uses the workspace's Release build first, so a rebuild shows at once.

import * as fs from "node:fs";
import * as path from "node:path";
import * as vscode from "vscode";

const hostName = "Retrocore.Debug.dll";

/** The host the VSIX packages, in the extension's server folder. */
export function bundledHost(context: vscode.ExtensionContext): string | undefined {
    const candidate = path.join(context.extensionPath, "server", hostName);
    return fs.existsSync(candidate) ? candidate : undefined;
}

/** The Release build in an open workspace folder, such as this repository's. */
export function workspaceHost(): string | undefined {
    for (const folder of vscode.workspace.workspaceFolders ?? []) {
        const candidate = path.join(folder.uri.fsPath, "artifacts", "AnyCPU", "Release", "Retrocore.Debug", "net10.0", hostName);
        if (fs.existsSync(candidate)) return candidate;
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
