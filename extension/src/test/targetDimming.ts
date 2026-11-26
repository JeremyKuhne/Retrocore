// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import * as path from "node:path";
import * as vscode from "vscode";

/**
 * The lines (1-based) a document's Unnecessary diagnostics cover: here, the lines its target's .if blocks leave out,
 * as hello.s has nothing else the server fades.
 */
function fadedLines(uri: vscode.Uri): number[] {
    return vscode.languages.getDiagnostics(uri)
        .filter(problem => problem.tags?.includes(vscode.DiagnosticTag.Unnecessary) === true)
        .flatMap(problem => {
            // A range ends at the start of the line after its last, which is not part of it.
            const last = problem.range.end.character === 0 ? problem.range.end.line - 1 : problem.range.end.line;
            return Array.from({ length: last - problem.range.start.line + 1 }, (_, index) => problem.range.start.line + index + 1);
        });
}

/** The lines (1-based) the extension shades, from the server's retrocore/inactiveRanges. */
async function shadedLines(uri: vscode.Uri): Promise<number[] | undefined> {
    const lines = await vscode.commands.executeCommand<number[] | undefined>("retrocore.inactiveLines", uri);
    return lines?.map(line => line + 1);
}

/** Waits for a document's shaded lines to be the wanted ones, up to a time. */
async function untilShaded(uri: vscode.Uri, wanted: number[], milliseconds = 30000): Promise<number[] | undefined> {
    for (const end = Date.now() + milliseconds; Date.now() < end; await new Promise(resolve => setTimeout(resolve, 200))) {
        if (JSON.stringify(await shadedLines(uri)) === JSON.stringify(wanted)) break;
    }
    return shadedLines(uri);
}

/** Waits for a document's faded lines to be the wanted ones, up to a time. */
async function untilFaded(uri: vscode.Uri, wanted: number[], milliseconds = 30000): Promise<number[]> {
    for (const end = Date.now() + milliseconds; Date.now() < end; await new Promise(resolve => setTimeout(resolve, 200))) {
        if (JSON.stringify(fadedLines(uri)) === JSON.stringify(wanted)) break;
    }
    return fadedLines(uri);
}

/**
 * The language server assembles a project's source for the active target the extension tells it: picking the target
 * that defines LOWERCASE moves the faded lines from that branch of the sample's .ifdef to the other.
 */
export async function testTargetDimming(workspace: vscode.WorkspaceFolder): Promise<void> {
    const project = path.join(workspace.uri.fsPath, "sample", "project");
    const file = path.join(project, "retrocore.json");
    const source = vscode.Uri.file(path.join(project, "src", "hello.s"));
    const lines = (await vscode.workspace.openTextDocument(source)).getText().split(/\r?\n/);
    // The .ifdef LOWERCASE block's two branches: its lowercase line, and the .else's capitals.
    const lowercase = lines.findIndex(line => line.includes("\"hello from a project\"")) + 1;
    const capitals = lines.findIndex(line => line.includes("\"HELLO FROM A PROJECT\"")) + 1;
    assert.ok(lowercase > 0 && capitals > 0, "the sample has both branches");
    await vscode.window.showTextDocument(source);
    // A .s in a project's folder opens as Retrocore assembly, which the language server analyzes.
    for (const end = Date.now() + 10000; Date.now() < end && vscode.window.activeTextEditor?.document.languageId !== "retrocore-asm";) {
        await new Promise(resolve => setTimeout(resolve, 100));
    }
    assert.equal(vscode.window.activeTextEditor?.document.languageId, "retrocore-asm", "the project's source is Retrocore assembly");

    assert.equal(await vscode.commands.executeCommand("retrocore.pickTarget", file, "apple2-iiplus"), "hello/apple2-iiplus");
    assert.deepEqual(await untilFaded(source, [lowercase]), [lowercase], "the II Plus leaves out the lowercase line");
    assert.deepEqual(await untilShaded(source, [lowercase]), [lowercase], "the extension shades the line the server says the II Plus leaves out");
    assert.equal(await vscode.commands.executeCommand("retrocore.pickTarget", file, "apple2-iie"), "hello/apple2-iie");
    assert.deepEqual(await untilFaded(source, [capitals]), [capitals], "the IIe, which defines LOWERCASE, leaves out the capitals");
    assert.deepEqual(await untilShaded(source, [capitals]), [capitals], "the shading moves with the target");
    await vscode.commands.executeCommand("workbench.action.closeActiveEditor");
    console.log("Isolated VS Code passed: the language server assembles a project's source for the active target, and its faded and shaded lines follow the target.");
}
