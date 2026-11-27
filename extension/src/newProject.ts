// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Retrocore: New Project. It asks for a template, the machines to build for, a name and a folder, then runs the host's
// `retrocore new`, so it writes exactly what the command line does from the same templates, and opens the folder.
// Given its answers as an argument, as the editor tests do, it asks nothing, and opens the folder only when they say to.

import * as childProcess from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import * as vscode from "vscode";
import { defaultHost } from "./host";

/** A template as `retrocore new --list --json` gives it. */
interface Template {
    name: string;
    description: string;
    cpu: string;
    families: { name: string; machine: string; environment: string; target: string; machines: string[] }[];
}

/** What New Project needs, given instead of asked. */
export interface NewProjectAnswers {
    template: string;
    name: string;
    machines?: string[];
    /** The folder the project's folder is made in. */
    parent: string;
    /** Whether to open the project's folder; false by default when answers are given. */
    open?: boolean;
}

// The project names the host takes: letters, digits, '-', '_' and '.', but not '.' or '..'.
const namePattern = /^[A-Za-z0-9._-]+$/;

function run(host: string, args: string[]): Promise<{ code: number; stdout: string; stderr: string; failure: string }> {
    return new Promise(resolve => {
        childProcess.execFile("dotnet", [host, ...args], { encoding: "utf8", timeout: 60000 }, (error, stdout, stderr) => {
            const code = error === null ? 0 : typeof error.code === "number" ? error.code : 1;
            resolve({ code, stdout, stderr, failure: error?.message ?? "" });
        });
    });
}

/** Runs New Project, asking for whatever `answers` does not give. Returns the project's folder, or undefined. */
export async function newProject(context: vscode.ExtensionContext, answers?: NewProjectAnswers): Promise<string | undefined> {
    const host = await defaultHost(context);
    if (host === undefined) {
        void vscode.window.showErrorMessage("Retrocore: no host to make the project with. Reinstall the extension or build the repository.");
        return undefined;
    }

    let template = answers?.template;
    let machines = answers?.machines;
    if (answers === undefined) {
        const listed = await run(host, ["new", "--list", "--json"]);
        if (listed.code !== 0) {
            void vscode.window.showErrorMessage(`Retrocore: the host could not list its templates: ${listed.stderr.trim() || listed.failure}`);
            return undefined;
        }
        let templates: Template[];
        try {
            templates = (JSON.parse(listed.stdout) as { templates: Template[] }).templates;
        } catch (error) {
            void vscode.window.showErrorMessage(`Retrocore: the host's list of templates could not be read: ${String(error)}`);
            return undefined;
        }
        if (!Array.isArray(templates) || templates.length === 0) {
            void vscode.window.showErrorMessage("Retrocore: the host has no project templates.");
            return undefined;
        }
        const chosen = templates.length === 1
            ? templates[0]
            : (await vscode.window.showQuickPick(
                templates.map(item => ({ label: item.name, description: item.description, template: item })),
                { title: "New Retrocore Project", placeHolder: "The CPU family to write for" }))?.template;
        if (chosen === undefined) return undefined;
        template = chosen.name;

        // Each family's own machine is ticked; its other machines follow it, unticked, for targets of their own.
        type Item = vscode.QuickPickItem & { machine: string };
        const items: Item[] = [];
        for (const family of chosen.families) {
            items.push({ label: family.name, kind: vscode.QuickPickItemKind.Separator, machine: "" });
            items.push({ label: family.target, description: `${family.machine}, ${family.environment}`, picked: true, machine: family.name });
            for (const machine of family.machines.filter(id => id !== family.machine)) {
                items.push({ label: machine, description: family.environment, picked: false, machine });
            }
        }
        const picked = await vscode.window.showQuickPick(items, {
            title: `New ${chosen.cpu} Project`,
            placeHolder: "The machines to build for: each becomes a target in its usual environment",
            canPickMany: true
        });
        if (picked === undefined || picked.length === 0) return undefined;
        machines = picked.map(item => item.machine);
    }

    const name = answers?.name ?? await vscode.window.showInputBox({
        title: "New Retrocore Project",
        prompt: "The project's name, which names its folder and its programs",
        validateInput: value => namePattern.test(value) && value !== "." && value !== ".."
            ? undefined
            : "Use letters, digits, '-', '_' and '.'."
    });
    if (name === undefined || template === undefined) return undefined;

    let parent = answers?.parent;
    if (parent === undefined) {
        const folders = await vscode.window.showOpenDialog({
            canSelectFiles: false,
            canSelectFolders: true,
            canSelectMany: false,
            openLabel: "Make the project here",
            title: `The folder to make ${name}/ in`
        });
        parent = folders?.[0]?.fsPath;
    }
    if (parent === undefined) return undefined;

    const folder = path.join(parent, name);
    const args = ["new", template, name, "--output", folder];
    if (machines !== undefined && machines.length !== 0) args.push("--machines", machines.join(","));
    const made = await run(host, args);
    if (made.code !== 0 || !fs.existsSync(path.join(folder, "retrocore.json"))) {
        const said = made.code !== 0 ? made.stderr.trim() || made.stdout.trim() || made.failure : "";
        void vscode.window.showErrorMessage(`Retrocore: ${said || "the project could not be made."}`);
        return undefined;
    }

    if (answers?.open ?? answers === undefined) {
        const choice = await vscode.window.showInformationMessage(
            `Made ${name} in ${folder}. Its README says how to build it; F5 debugs the target picked in the status bar.`,
            "Open", "Open in New Window");
        if (choice !== undefined) {
            await vscode.commands.executeCommand("vscode.openFolder", vscode.Uri.file(folder), { forceNewWindow: choice === "Open in New Window" });
        }
    }
    return folder;
}
