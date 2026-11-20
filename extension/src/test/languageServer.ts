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
    // The Apple III's boot ROM has a COUT too.
    const homes = cout.filter(symbol => symbol.name === "COUT").map(symbol => path.basename(symbol.location.uri.fsPath));
    assert.ok(homes.includes("Monitor.asm"), homes.join(", "));

    await until("AppleSoft symbols", async () => {
        const found = await vscode.commands.executeCommand<vscode.SymbolInformation[]>("vscode.executeWorkspaceSymbolProvider", "INVERS");
        return found.some(symbol => symbol.name === "INVERS" && path.basename(symbol.location.uri.fsPath) === "applesoft.mac")
            ? found : undefined;
    });

    // A companion linker configuration supplies the included procedure's address and documentation.
    const configured = path.join(folder, "configured");
    fs.mkdirSync(configured, { recursive: true });
    const configuredRoot = path.join(configured, "system.asm");
    const configuredBios = path.join(configured, "Bios.asm");
    fs.writeFileSync(configuredRoot, ".section HIGH\n.include \"Bios.asm\"\n    jsr InverseCapitalsOn\n");
    fs.writeFileSync(path.join(configured, "system.cfg"),
        "MEMORY { HIGH: start = $FE00, size = $0200, file = %O; }\nSEGMENTS { HIGH: load = HIGH, type = ro; }\n");
    fs.writeFileSync(configuredBios, ";; Shows capitals inverse.\n.proc InverseCapitalsOn\n    rts\n.endproc\n");
    const bios = await vscode.workspace.openTextDocument(vscode.Uri.file(configuredBios));
    await vscode.window.showTextDocument(bios);
    const procedure = new vscode.Position(1, bios.lineAt(1).text.indexOf("InverseCapitalsOn") + 1);
    const procedureHover = await until("configured procedure hover", async () => {
        const found = await vscode.commands.executeCommand<vscode.Hover[]>("vscode.executeHoverProvider", bios.uri, procedure);
        return found.find(item => text(item).includes("(label) InverseCapitalsOn = $FE00"));
    });
    assert.match(text(procedureHover), /Shows capitals inverse/);
    const procedureDefinitions = await vscode.commands.executeCommand<vscode.Location[]>("vscode.executeDefinitionProvider", bios.uri, procedure);
    assert.equal(procedureDefinitions[0].uri.fsPath, configuredBios);
    assert.equal(procedureDefinitions[0].range.start.line, 1);
    assert.equal(procedureDefinitions[0].range.start.character, 6);
    assert.equal(procedureDefinitions[0].range.end.character, 6 + "InverseCapitalsOn".length);

    // An assembly with errors still finds its procedure; an unrelated native name cannot resolve to INVERS.
    const broken = path.join(folder, "broken");
    fs.mkdirSync(broken, { recursive: true });
    const brokenRoot = path.join(broken, "system.asm");
    const brokenBios = path.join(broken, "Bios.asm");
    fs.writeFileSync(brokenRoot, ".org $6000\n.include \"Bios.asm\"\n    jsr InverseCapitalsMissing\n");
    fs.writeFileSync(brokenBios, ";; Shows capitals inverse.\n.proc InverseCapitalsOn\n    rts\n.endproc\n");
    const brokenDocument = await vscode.workspace.openTextDocument(vscode.Uri.file(brokenRoot));
    await vscode.window.showTextDocument(brokenDocument);
    await until("broken assembly diagnostics", () => {
        const found = vscode.languages.getDiagnostics(brokenDocument.uri);
        return found.some(diagnostic => diagnostic.message.includes("InverseCapitalsMissing")) ? found : undefined;
    });
    const missing = new vscode.Position(2, brokenDocument.lineAt(2).text.indexOf("InverseCapitalsMissing") + 1);
    const missingDefinitions = await vscode.commands.executeCommand<vscode.Location[]>("vscode.executeDefinitionProvider", brokenDocument.uri, missing);
    assert.deepEqual(missingDefinitions, [], "A native name must not resolve to the SDK's six-character INVERS.");

    const brokenBiosDocument = await vscode.workspace.openTextDocument(vscode.Uri.file(brokenBios));
    await vscode.window.showTextDocument(brokenBiosDocument);
    const brokenProcedure = new vscode.Position(1, brokenBiosDocument.lineAt(1).text.indexOf("InverseCapitalsOn") + 1);
    const brokenHover = await until("procedure hover after an error", async () => {
        const found = await vscode.commands.executeCommand<vscode.Hover[]>("vscode.executeHoverProvider", brokenBiosDocument.uri, brokenProcedure);
        return found.find(item => text(item).includes("(label) InverseCapitalsOn"));
    });
    assert.match(text(brokenHover), /Shows capitals inverse/);
    const brokenDefinitions = await vscode.commands.executeCommand<vscode.Location[]>(
        "vscode.executeDefinitionProvider", brokenBiosDocument.uri, brokenProcedure);
    assert.equal(brokenDefinitions[0].uri.fsPath, brokenBios);
    assert.equal(brokenDefinitions[0].range.start.character, 6);

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
