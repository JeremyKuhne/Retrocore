// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as vscode from "vscode";
import { basicLanguages, documentSelector } from "../languageClient";

async function until<T>(what: string, probe: () => Promise<T | undefined> | T | undefined, timeout = 30000): Promise<T> {
    const end = Date.now() + timeout;
    for (;;) {
        const value = await probe();
        if (value !== undefined) return value;
        if (Date.now() > end) throw new Error(`Timed out waiting for ${what}.`);
        await new Promise(resolve => setTimeout(resolve, 250));
    }
}

const text = (hover: vscode.Hover): string =>
    hover.contents.map(part => typeof part === "string" ? part : "value" in part ? part.value : "").join("\n");

/** Drives the retrocore language server through VS Code's own provider commands. */
export async function testLanguageServer(root: string): Promise<void> {
    for (const languageId of ["retrocore-asm", "retrocore-macro10", ...basicLanguages]) {
        for (const scheme of ["file", "chat-editing-text-model", "chat-editing-snapshot-text-model", "retrocore-basic", "retrocore-basic-file", "untitled"]) {
            const document = { uri: vscode.Uri.from({ scheme, path: "/main.asm" }), languageId } as vscode.TextDocument;
            assert.equal(vscode.languages.match(documentSelector, document) > 0,
                scheme === "file" || basicLanguages.includes(languageId), `${languageId} in ${scheme}`);
        }
    }

    const folder = path.join(root, "artifacts", "vscode-m1-tests", "language-server");
    fs.mkdirSync(folder, { recursive: true });
    fs.writeFileSync(path.join(folder, "equates.retrocore.asm"),
        "; Keyboard data, bit 7 set when a key is waiting.\nKBD = $C000\n\n.macro show value\n    lda #value\n.endmacro\n");
    const mainPath = path.join(folder, "main.retrocore.asm");
    fs.writeFileSync(mainPath, ".include \"equates.retrocore.asm\"\n.org $6000\n;; Waits for a key; see <KBD>.\n;; Out:   A = the key, negative = a key is waiting\n;; Keeps: X, Y\nstart:\n    lda KBD\n    bpl start\n    show 1\n    jmp missing\n;; Documents nothing.\n\n");
    const document = await vscode.workspace.openTextDocument(vscode.Uri.file(mainPath));
    await vscode.window.showTextDocument(document);

    const diagnostics = await until("diagnostics", () => {
        const found = vscode.languages.getDiagnostics(document.uri);
        return found.length > 0 ? found : undefined;
    });
    assert.equal(diagnostics[0].range.start.line, 9, "The unresolved name is reported on its line.");
    assert.match(diagnostics[0].message, /missing/);
    const misplaced = await until("documentation diagnostics", () =>
        vscode.languages.getDiagnostics(document.uri).find(diagnostic => diagnostic.range.start.line === 10));
    assert.match(misplaced.message, /directly above the definition/);

    const kbd = new vscode.Position(6, document.lineAt(6).text.indexOf("KBD") + 1);
    const hovers = await until("hover", async () => {
        const found = await vscode.commands.executeCommand<vscode.Hover[]>("vscode.executeHoverProvider", document.uri, kbd);
        return found.length > 0 ? found : undefined;
    });
    assert.match(text(hovers[0]), /Keyboard data/, "Hover shows the comment above the definition.");

    // A ;; comment renders its sections and links.
    const startHover = await vscode.commands.executeCommand<vscode.Hover[]>(
        "vscode.executeHoverProvider", document.uri, new vscode.Position(7, 9));
    assert.match(text(startHover[0]), /Waits for a key; see \[`KBD`\]\(file:/);
    assert.match(text(startHover[0]), /\*\*Keeps\*\*: `X`, `Y`/);

    // A flag's word in a ;; comment shows the CPU's letter for it and what it means.
    const flag = await vscode.commands.executeCommand<vscode.Hover[]>(
        "vscode.executeHoverProvider", document.uri, new vscode.Position(3, document.lineAt(3).text.indexOf("negative") + 2));
    assert.match(text(flag[0]), /^\*\*negative \(N\) flag\*\*: Set when a result's bit 7 is 1/);

    const lda = await vscode.commands.executeCommand<vscode.Hover[]>(
        "vscode.executeHoverProvider", document.uri, new vscode.Position(6, 5));
    assert.match(text(lda[0]), /Loads A from memory/);

    const definitions = await vscode.commands.executeCommand<vscode.Location[]>("vscode.executeDefinitionProvider", document.uri, kbd);
    assert.equal(path.basename(definitions[0].uri.fsPath), "equates.retrocore.asm");
    assert.equal(definitions[0].range.start.line, 1);

    // Find All References: the definition in the include, the code that uses it and the documentation link.
    const references = await vscode.commands.executeCommand<vscode.Location[]>("vscode.executeReferenceProvider", document.uri, kbd);
    assert.deepEqual(references.map(location => `${path.basename(location.uri.fsPath)}:${location.range.start.line}`).sort(),
        ["equates.retrocore.asm:1", "main.retrocore.asm:2", "main.retrocore.asm:6"]);
    const startReferences = await vscode.commands.executeCommand<vscode.Location[]>(
        "vscode.executeReferenceProvider", document.uri, new vscode.Position(7, 9));
    assert.deepEqual(startReferences.map(location => location.range.start.line).sort(), [5, 7], "start: its label and the branch to it.");

    const operand = await vscode.commands.executeCommand<vscode.CompletionList>(
        "vscode.executeCompletionItemProvider", document.uri, new vscode.Position(7, 8));
    assert.ok(operand.items.some(item => item.label === "KBD"), "Operands complete the assembly's names.");
    const documented = operand.items.find(item => item.label === "start");
    assert.match(typeof documented?.documentation === "string" ? documented.documentation : documented?.documentation?.value ?? "",
        /Waits for a key/, "Completion carries the summary.");
    const operation = await vscode.commands.executeCommand<vscode.CompletionList>(
        "vscode.executeCompletionItemProvider", document.uri, new vscode.Position(8, 4));
    assert.ok(operation.items.some(item => item.label === "lda"), "Operations complete mnemonics.");
    assert.ok(operation.items.some(item => item.label === "show"), "Operations complete macros.");

    // The server may still be indexing the SDK, so wait for the outline as for the other results.
    const symbols = await until("document symbols", async () => {
        const found = await vscode.commands.executeCommand<vscode.DocumentSymbol[] | undefined>(
            "vscode.executeDocumentSymbolProvider", document.uri);
        return found?.some(symbol => symbol.name === "start") ? found : undefined;
    });
    assert.ok(symbols.length > 0);

    // A file's outline is right the first time it is asked for: VS Code keeps the symbols it gets as a file opens
    // until the file changes, so the server waits for the file's first assembly rather than answering empty.
    const outlinePath = path.join(folder, `outline-${Date.now()}.retrocore.asm`);
    fs.writeFileSync(outlinePath, ".org $6000\nfirst:\n    rts\nsecond:\n    rts\n");
    const outline = await vscode.workspace.openTextDocument(vscode.Uri.file(outlinePath));
    await vscode.window.showTextDocument(outline);
    const firstSymbols = await vscode.commands.executeCommand<vscode.DocumentSymbol[] | undefined>(
        "vscode.executeDocumentSymbolProvider", outline.uri);
    assert.deepEqual(firstSymbols?.map(symbol => symbol.name), ["first", "second"], "The first outline has the file's labels.");
    await vscode.commands.executeCommand("workbench.action.closeActiveEditor");
    fs.rmSync(outlinePath, { force: true });

    // The SDK's ROM sources beside the host are indexed for workspace search.
    const cout = await until("workspace symbols", async () => {
        const found = await vscode.commands.executeCommand<vscode.SymbolInformation[]>("vscode.executeWorkspaceSymbolProvider", "COUT");
        return found.some(symbol => symbol.name === "COUT") ? found : undefined;
    });
    assert.equal(path.basename(cout.find(symbol => symbol.name === "COUT")?.location.uri.fsPath ?? ""), "Monitor.asm");

    // MACRO-10 sources are a language of their own, for their own icon, and the server serves them as assembly.
    const overlayPath = path.join(root, "src", "Retrocore.Machines.Apple2", "Roms", "AppleSoft", "applesoft.mac");
    const overlay = await vscode.workspace.openTextDocument(vscode.Uri.file(overlayPath));
    assert.equal(overlay.languageId, "retrocore-macro10");
    await vscode.window.showTextDocument(overlay);
    const overlaySymbols = await until("MACRO-10 symbols", async () => {
        const found = await vscode.commands.executeCommand<vscode.DocumentSymbol[] | undefined>(
            "vscode.executeDocumentSymbolProvider", overlay.uri);
        return found !== undefined && found.length > 0 ? found : undefined;
    });
    assert.ok(overlaySymbols.length > 0, "The server outlines a MACRO-10 source.");
    await vscode.commands.executeCommand("workbench.action.closeActiveEditor");
}
