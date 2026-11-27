// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import * as childProcess from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import * as vscode from "vscode";
import { parseJsonc } from "../project";

/** The source's symbols, once the language server gives some, or none after a time. */
async function symbols(uri: vscode.Uri, milliseconds = 30000): Promise<string[]> {
    for (const end = Date.now() + milliseconds; ; await new Promise(resolve => setTimeout(resolve, 200))) {
        const found = await Promise.resolve(vscode.commands.executeCommand<vscode.DocumentSymbol[] | undefined>("vscode.executeDocumentSymbolProvider", uri))
            .catch(() => undefined);
        if ((found?.length ?? 0) > 0 || Date.now() > end) return (found ?? []).map(symbol => symbol.name);
    }
}

/**
 * Retrocore: Restart Language Server, as Restore Pinned Tool's restart does, replaces the server and keeps the first
 * start's registrations: the server answers again, twice over; Restore Pinned Tool in a repository that pins no tool
 * says so and changes nothing.
 */
async function testRestart(workspace: vscode.WorkspaceFolder): Promise<void> {
    const source = vscode.Uri.file(path.join(workspace.uri.fsPath, "src", "hello.s"));
    await vscode.window.showTextDocument(await vscode.workspace.openTextDocument(source));
    assert.ok((await symbols(source)).includes("START"), "the language server gives the source's symbols");
    for (let restart = 0; restart < 2; restart++) {
        assert.equal(await vscode.commands.executeCommand("retrocore.restartLanguageServer"), true, "a server runs after the restart");
        assert.ok((await symbols(source)).includes("START"), `the restarted language server gives the source's symbols (restart ${restart + 1})`);
    }
    assert.equal(await vscode.commands.executeCommand("retrocore.restoreTool"), false, "this repository pins no retrocore tool");
    console.log("Isolated VS Code passed: the language server restarts on the chosen host, twice, keeping its registrations, and Restore Pinned Tool finds no pin here.");
}

/**
 * Retrocore: New Project, given its answers, runs the host's `retrocore new` and writes the project: the targets for
 * the machines picked, the platform folders they use, and the repository's files, the tool pinned at the host's own
 * version. A name the host refuses writes nothing.
 */
export async function testNewProject(workspace: vscode.WorkspaceFolder): Promise<void> {
    await testRestart(workspace);
    const parent = fs.mkdtempSync(path.join(os.tmpdir(), "retrocore-new-project-"));
    try {
        const folder = await vscode.commands.executeCommand<string | undefined>("retrocore.newProject",
            { template: "6502", name: "greeting", machines: ["apple2", "bbc"], parent });
        assert.equal(folder, path.join(parent, "greeting"));

        const project = parseJsonc(fs.readFileSync(path.join(parent, "greeting", "retrocore.json"), "utf8")) as {
            name: string; targets: Record<string, { machine: string; environment: string }>;
        };
        assert.equal(project.name, "greeting");
        assert.deepEqual(Object.keys(project.targets), ["apple2-dos", "bbc-dfs"]);
        assert.equal(project.targets["bbc-dfs"].environment, "dfs");
        for (const file of ["src/main.s", "src/platform/apple2/console.s", "src/platform/dos33/exit.s", "src/platform/bbc/console.s",
            "src/platform/dfs/exit.s", "src/platform/bare/exit.s", ".gitignore", ".vscode/extensions.json", ".github/workflows/build.yml", "README.md"]) {
            assert.ok(fs.existsSync(path.join(parent, "greeting", file)), `New Project wrote ${file}`);
        }
        const tools = JSON.parse(fs.readFileSync(path.join(parent, "greeting", ".config", "dotnet-tools.json"), "utf8")) as {
            tools: { retrocore: { version: string } };
        };
        const host = path.join(workspace.uri.fsPath, "..", "..", "artifacts", "AnyCPU", "Release", "Retrocore.Debug", "net11.0", "Retrocore.Debug.dll");
        const version = childProcess.execFileSync("dotnet", [host, "--version"], { encoding: "utf8" }).trim();
        assert.equal(tools.tools.retrocore.version, version, "the tool is pinned at the version of the host that made it");
        assert.ok(!fs.existsSync(path.join(parent, "greeting", "src", "platform", "pet")), "no folder for a family not picked");

        // The host refuses hello for a DOS 3.3 target; New Project shows why and makes nothing.
        const refused = await vscode.commands.executeCommand<string | undefined>("retrocore.newProject",
            { template: "6502", name: "hello", machines: ["apple2"], parent });
        assert.equal(refused, undefined);
        assert.ok(!fs.existsSync(path.join(parent, "hello")), "a refused project writes nothing");
        console.log("Isolated VS Code passed: New Project runs retrocore new from the host's templates for the machines picked, and a refused name makes nothing.");
    } finally {
        fs.rmSync(parent, { recursive: true, force: true });
    }
}
