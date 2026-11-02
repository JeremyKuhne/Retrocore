// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import * as path from "node:path";
import * as vscode from "vscode";

export async function testAssemblyLanguage(root: string): Promise<void> {
    const language = "retrocore-asm";
    assert.ok((await vscode.languages.getLanguages()).includes(language));
    const extension = vscode.extensions.getExtension("retrocore.retrocore");
    assert.ok(extension, "The development extension must be registered.");
    const firmware = await vscode.workspace.openTextDocument(
        vscode.Uri.file(path.join(root, "src", "Retrocore.Machines.Apple2", "Roms", "Slot7.rom.asm")));
    assert.equal(firmware.languageId, language, "Native ROM sources should be recognized automatically.");
    // Every .asm and .mac is claimed, such as the SDK's sources beside the debug host, which a launch without sdkRoms
    // steps into.
    const sdk = path.join(root, "artifacts", "AnyCPU", "Release", "Retrocore.Debug", "net10.0", "Sdk", "Roms");
    const monitor = await vscode.workspace.openTextDocument(vscode.Uri.file(path.join(sdk, "System", "Monitor.asm")));
    assert.equal(monitor.languageId, language, "Any .asm file should be recognized.");
    const appleSoft = await vscode.workspace.openTextDocument(vscode.Uri.file(path.join(sdk, "AppleSoft", "applesoft.mac")));
    assert.equal(appleSoft.languageId, "retrocore-macro10");
    await vscode.window.showTextDocument(firmware);
    assert.equal(vscode.debug.activeDebugSession, undefined, "Highlighting must work without a debug session.");
    const manifest = extension.packageJSON;
    assert.ok(manifest.contributes.debuggers[0].languages.includes(language));
    assert.equal(manifest.contributes.grammars.find((item: { language: string }) => item.language === language)?.scopeName, "source.retrocore");

    const tagged = await vscode.workspace.openTextDocument(vscode.Uri.parse("untitled:Highlighting.retrocore.asm"));
    assert.equal(tagged.languageId, language, "Explicitly tagged assembly should be recognized automatically.");
    const sample = await vscode.workspace.openTextDocument(vscode.Uri.file(path.join(root, "sample", "iie", "main.s")));
    assert.notEqual(sample.languageId, language, "Do not silently reassign other dialects' .s sources.");

    const document = await vscode.workspace.openTextDocument({
        language,
        content: "Entry: LDA ($42,X)\nByte_\u00E9 = $10\nLDA A\n.word Outer::Value, @loop, ::Root, :++\n"
    });
    const editor = await vscode.window.showTextDocument(document);
    const symbol = document.getWordRangeAtPosition(new vscode.Position(1, 3));
    assert.ok(symbol);
    assert.equal(document.getText(symbol), "Byte_\u00E9");
    for (const name of ["Outer::Value", "@loop", "::Root", ":++"]) {
        const range = document.getWordRangeAtPosition(new vscode.Position(3, document.lineAt(3).text.indexOf(name) + 1));
        assert.ok(range);
        assert.equal(document.getText(range), name);
    }
    editor.selection = new vscode.Selection(2, 0, 2, 0);
    await vscode.commands.executeCommand("editor.action.commentLine");
    assert.match(document.lineAt(2).text, /^\s*;\s*LDA A$/);
    await vscode.commands.executeCommand("editor.action.commentLine");
    assert.equal(document.lineAt(2).text, "LDA A");
    const parenthesis = document.lineAt(0).text.indexOf("(");
    editor.selection = new vscode.Selection(0, parenthesis, 0, parenthesis);
    await vscode.commands.executeCommand("editor.action.jumpToBracket");
    const close = document.lineAt(0).text.indexOf(")");
    assert.equal(editor.selection.active.line, 0);
    assert.ok(editor.selection.active.character >= close && editor.selection.active.character <= close + 1,
        "Parentheses should participate in VS Code bracket navigation.");
    assert.equal(vscode.debug.activeDebugSession, undefined, "Editing support must not start a debug session.");
    console.log("Native assembly language passed: automatic detection, no debug session, word selection, comments and bracket navigation.");
}
