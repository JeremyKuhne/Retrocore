// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// What the extension says about the repository's pinned retrocore tool. At activation, when the pin is not restored or
// does not run and another version runs instead, a warning that names it, with a Restore button. Retrocore: Restore
// Pinned Tool, the button's command, runs `dotnet tool restore` where the manifest is and restarts the language server
// on the host chosen then; a debug launch chooses its host at each launch. A retrocore.languageServer.host setting
// governs the language server alone, and a launch's debugHost that launch alone, so the warning is about the
// debugger then. In development a build of this repository runs before the pin, and there is no warning.

import * as childProcess from "node:child_process";
import * as vscode from "vscode";
import { chooseWorkspaceHost, workspacePin } from "./host";
import { restoredHost } from "./pinnedTool";

function configuredHost(): string | undefined {
    return vscode.workspace.getConfiguration("retrocore").get<string>("languageServer.host") || undefined;
}

/** Registers the restore command, and warns at activation when the pinned tool cannot run. */
export function registerToolStatus(context: vscode.ExtensionContext, restartLanguageServer: () => Promise<boolean>): void {
    const restore = async (): Promise<boolean> => {
        const pin = workspacePin();
        if (pin === undefined) {
            void vscode.window.showInformationMessage("Retrocore: this workspace's repository pins no retrocore tool.");
            return false;
        }
        const result = await vscode.window.withProgress(
            { location: vscode.ProgressLocation.Notification, title: `Restoring retrocore ${pin.version}` },
            () => new Promise<{ ok: boolean; output: string }>(resolve => {
                childProcess.execFile("dotnet", ["tool", "restore"], { cwd: pin.folder, encoding: "utf8", timeout: 300000 },
                    (error, stdout, stderr) => resolve({ ok: error === null, output: `${stdout}${stderr}`.trim() || String(error) }));
            }));
        if (!result.ok) {
            void vscode.window.showErrorMessage(`Retrocore: dotnet tool restore failed in ${pin.folder}: ${result.output}`);
            return false;
        }
        if (restoredHost(pin.version) === undefined) {
            void vscode.window.showWarningMessage(`Retrocore: retrocore ${pin.version} was restored, but its host is not in the NuGet packages folder Retrocore looks in.`);
            return false;
        }
        // The restart also stops a server left running after the language server was turned off.
        const enabled = vscode.workspace.getConfiguration("retrocore").get<boolean>("languageServer.enabled", true);
        if (!await restartLanguageServer() && enabled) return false;
        const debuggerChoice = await chooseWorkspaceHost(context);
        if (debuggerChoice.warning !== undefined) {
            void vscode.window.showWarningMessage(`Retrocore: ${debuggerChoice.warning}`);
            return false;
        }
        const configured = configuredHost();
        const debugging = debuggerChoice.pinned
            ? "debugging uses it from the next launch"
            : "debugging uses a build of this repository, which comes first in development";
        const server = !enabled
            ? "the language server is off"
            : configured === undefined
                ? debuggerChoice.pinned ? "the language server runs it" : "the language server runs the same host as debugging"
                : `the language server runs ${configured}, which retrocore.languageServer.host names`;
        void vscode.window.showInformationMessage(`Retrocore: retrocore ${pin.version} is restored; ${server}, and ${debugging}.`);
        return true;
    };
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.restoreTool", () =>
        restore().catch(error => {
            void vscode.window.showErrorMessage(`Retrocore: the pinned tool could not be restored: ${String(error)}`);
            return false;
        })));

    // The debugger's host: the language server's too, unless the setting names that one.
    void chooseWorkspaceHost(context).then(choice => {
        if (choice.warning === undefined) return;
        const enabled = vscode.workspace.getConfiguration("retrocore").get<boolean>("languageServer.enabled", true);
        const which = configuredHost() === undefined || !enabled
            ? ""
            : " (for debugging; the language server runs the host retrocore.languageServer.host names)";
        void vscode.window.showWarningMessage(`Retrocore: ${choice.warning}${which}`, "Restore", "Not now").then(answer => {
            if (answer === "Restore") void vscode.commands.executeCommand("retrocore.restoreTool");
        });
    }, error => console.warn(`retrocore: the pinned tool could not be checked: ${String(error)}`));
}
