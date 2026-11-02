// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import * as vscode from "vscode";

async function until<T>(what: string, probe: () => Promise<T | undefined> | T | undefined, timeout = 30000): Promise<T> {
    const end = Date.now() + timeout;
    for (;;) {
        const value = await probe();
        if (value !== undefined) return value;
        if (Date.now() > end) throw new Error(`Timed out waiting for ${what}.`);
        await new Promise(resolve => setTimeout(resolve, 250));
    }
}

const hoverText = (hovers: vscode.Hover[]): string =>
    hovers.flatMap(hover => hover.contents).map(part => typeof part === "string" ? part : "value" in part ? part.value : "").join("\n");

const program = [
    "REM retrocore applesoft",
    "10 REM SETUP",
    "20 SCORE = 0: GOSUB 100",
    "30 IF SCORE > 5 THEN 10",
    "40 ON X GOTO 10,20,99",
    "50 PRINT SC",
    "99 REM ",
    "100 REM SCORING",
    "110 RETURN",
    ""
].join("\n");

/** Drives the BASIC language features: diagnostics, hover, navigation, completion, outline, dialects and renumbering. */
export async function testBasicLanguage(root: string): Promise<void> {
    const folder = path.join(root, "artifacts", "vscode-m1-tests", "basic-language");
    fs.rmSync(folder, { recursive: true, force: true });
    fs.mkdirSync(folder, { recursive: true });
    const file = path.join(folder, "program.applesoft.bas");
    fs.writeFileSync(file, program.replace("40 ON X GOTO 10,20,99", "40 ON X GOTO 10,20,98"));
    const document = await vscode.workspace.openTextDocument(file);
    await vscode.window.showTextDocument(document);
    assert.equal(document.languageId, "retrocore-applesoft");

    const problems = await until("BASIC diagnostics", () => {
        const found = vscode.languages.getDiagnostics(document.uri);
        return found.length >= 3 ? found : undefined;
    });
    assert.ok(problems.some(problem => problem.message === "There is no line 98." && problem.range.start.line === 4));
    assert.ok(problems.some(problem => problem.message.startsWith("BASIC reads SCORE as SC OR E")));

    const at = (line: number, text: string, offset = 0): vscode.Position =>
        new vscode.Position(line, document.lineAt(line).text.indexOf(text) + offset);
    const hover = async (position: vscode.Position): Promise<string> =>
        hoverText(await vscode.commands.executeCommand<vscode.Hover[]>("vscode.executeHoverProvider", document.uri, position));
    assert.match(await hover(at(2, "GOSUB")), /Calls the subroutine/);
    assert.match(await hover(at(2, "100")), /100 REM SCORING/);
    assert.match(await hover(at(5, "SC")), /\*\*SC\*\*: a numeric variable/);

    const definitions = await vscode.commands.executeCommand<vscode.Location[]>("vscode.executeDefinitionProvider", document.uri, at(2, "100"));
    assert.equal(definitions[0].range.start.line, 7);
    const references = await vscode.commands.executeCommand<vscode.Location[]>("vscode.executeReferenceProvider", document.uri, at(5, "SC"));
    assert.deepEqual(references.map(location => location.range.start.line), [2, 3, 5], "SCORE and SC are the variable SC");

    const lines = await vscode.commands.executeCommand<vscode.CompletionList>("vscode.executeCompletionItemProvider", document.uri, at(4, "10"));
    assert.ok(lines.items.some(item => item.label === "100"), "line numbers complete after GOTO");
    const words = await vscode.commands.executeCommand<vscode.CompletionList>(
        "vscode.executeCompletionItemProvider", document.uri, new vscode.Position(5, 3));
    assert.ok(words.items.some(item => item.label === "HPLOT"));

    const symbols = await vscode.commands.executeCommand<vscode.DocumentSymbol[]>("vscode.executeDocumentSymbolProvider", document.uri);
    assert.deepEqual(symbols.map(symbol => symbol.name), ["SETUP", "Line 99", "SCORING"]);
    assert.equal(symbols[2].kind, vscode.SymbolKind.Function, "GOSUB calls the SCORING section");
    assert.equal(symbols[2].detail, "GOSUB 100");

    // Renumbering follows every reference; a missing line is left alone.
    assert.equal(await vscode.commands.executeCommand("retrocore.basic.renumber", 1000, 10), true);
    assert.equal(document.lineAt(2).text, "1010 SCORE = 0: GOSUB 1060");
    assert.equal(document.lineAt(4).text, "1030 ON X GOTO 1000,1010,98");
    await vscode.commands.executeCommand("workbench.action.files.revert");

    // In a file with labels, a label's use goes to the label, and labels start sections of the outline.
    const labeled = path.join(folder, "labels.applesoft.bas");
    fs.writeFileSync(labeled, "loop:\n    PRINT \"HI\"\n    GOTO loop\n");
    const labels = await vscode.workspace.openTextDocument(labeled);
    await vscode.window.showTextDocument(labels);
    const use = new vscode.Position(2, labels.lineAt(2).text.indexOf("loop") + 1);
    const target = await until("the label's definition", async () => {
        const found = await vscode.commands.executeCommand<vscode.Location[]>("vscode.executeDefinitionProvider", labels.uri, use);
        return found.length > 0 ? found : undefined;
    });
    assert.equal(target[0].range.start.line, 0);
    const sections = await vscode.commands.executeCommand<vscode.DocumentSymbol[]>("vscode.executeDocumentSymbolProvider", labels.uri);
    assert.deepEqual(sections.map(symbol => symbol.name), ["loop"]);

    // A plain .bas takes its dialect from its pragma.
    const plain = path.join(folder, "plain.bas");
    fs.writeFileSync(plain, "' retrocore level2\n10 CLS\n");
    const level2 = await vscode.workspace.openTextDocument(plain);
    await until("the pragma's dialect", () => level2.languageId === "retrocore-level2" ? true : undefined);

    // A tape opens as its listing, and saving writes the tape again.
    const host = path.join(root, "artifacts", "AnyCPU", "Release", "Retrocore.Debug", "net10.0", "Retrocore.Debug.dll");
    const tape = path.join(folder, "game.cas");
    execFileSync("dotnet", [host, "--basic", "tokenize", plain, tape]);
    const listingUri = await vscode.commands.executeCommand<vscode.Uri>("retrocore.basic.openListing", vscode.Uri.file(tape));
    const listing = await vscode.workspace.openTextDocument(listingUri);
    assert.equal(listing.languageId, "retrocore-level2");
    assert.equal(listing.getText(), "10 CLS\n");
    const edit = new vscode.WorkspaceEdit();
    edit.insert(listing.uri, new vscode.Position(1, 0), "20 PRINT \"TAPE\"\n");
    await vscode.workspace.applyEdit(edit);
    assert.ok(await listing.save());
    assert.equal(execFileSync("dotnet", [host, "--basic", "list", tape], { encoding: "utf8" }), "10 CLS\n20 PRINT \"TAPE\"\n");

    // A CiderPress2 Integer BASIC file ($FA) opens as its listing; saving tokenizes through the II's ROM, the SDK's
    // build of it without dumps.
    const integer = path.join(folder, "HELLO#fa0000");
    fs.writeFileSync(integer, Buffer.from([
        0x10, 0x0A, 0x00, 0x61, 0x28, 0xC8, 0xC9, 0x29, 0x46, 0xC1, 0xB1, 0x12, 0xB2, 0x17, 0x00, 0x01,
        0x0B, 0x14, 0x00, 0x5D, 0xA0, 0xC8, 0xC5, 0xCC, 0xCC, 0xCF, 0x01
    ]));
    const integerUri = await vscode.commands.executeCommand<vscode.Uri>("retrocore.basic.openListing", vscode.Uri.file(integer));
    const integerListing = await vscode.workspace.openTextDocument(integerUri);
    assert.equal(integerListing.getText(), "10 PRINT \"HI\";A1+23\n20 REM HELLO\n");
    const more = new vscode.WorkspaceEdit();
    more.insert(integerListing.uri, new vscode.Position(2, 0), "30 END\n");
    await vscode.workspace.applyEdit(more);
    assert.ok(await integerListing.save());
    assert.deepEqual([...fs.readFileSync(integer).subarray(-5)], [0x05, 0x1E, 0x00, 0x51, 0x01], "30 END went in");

    // An Integer BASIC file: its own language, a line its grammar refuses, Integer BASIC's help, and a computed GOSUB
    // that is no missing label.
    const integerFile = path.join(folder, "program.integer.bas");
    fs.writeFileSync(integerFile, "10 T=100: GOSUB T\n20 PRINT (\n30 IF A#2 THEN PRINT A MOD 3\n100 RETURN\n");
    const integerDocument = await vscode.workspace.openTextDocument(integerFile);
    await vscode.window.showTextDocument(integerDocument);
    assert.equal(integerDocument.languageId, "retrocore-integer");
    const refused = await until("Integer BASIC's syntax error", () => {
        const found = vscode.languages.getDiagnostics(integerDocument.uri);
        return found.length >= 1 ? found : undefined;
    });
    assert.deepEqual(refused.map(problem => [problem.range.start.line, problem.message.startsWith("*** SYNTAX ERR")]), [[1, true]]);
    const integerHover = async (line: number, text: string): Promise<string> => hoverText(await vscode.commands.executeCommand<vscode.Hover[]>(
        "vscode.executeHoverProvider", integerDocument.uri, new vscode.Position(line, integerDocument.lineAt(line).text.indexOf(text))));
    assert.match(await integerHover(0, "GOSUB"), /expression/);
    assert.match(await integerHover(2, "MOD"), /remainder/);

    await vscode.commands.executeCommand("workbench.action.closeAllEditors");
    console.log("BASIC language passed: diagnostics, hover, definition, references, completion, outline, pragma dialects, renumbering, tape listings, Integer BASIC listings and Integer BASIC files.");
}
