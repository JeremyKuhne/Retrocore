// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as vscode from "vscode";

interface Program { text: string; running: boolean; dialect: string; }

async function until<T>(what: string, probe: () => Promise<T | undefined> | T | undefined, timeout = 20000): Promise<T> {
    const end = Date.now() + timeout;
    for (;;) {
        const value = await probe();
        if (value !== undefined) return value;
        if (Date.now() > end) throw new Error(`Timed out waiting for ${what}.`);
        await new Promise(resolve => setTimeout(resolve, 200));
    }
}

async function type(session: vscode.DebugSession, text: string): Promise<void> {
    for (const character of text) await session.customRequest("retro/key", { code: character.charCodeAt(0) });
}

async function replace(document: vscode.TextDocument, text: string): Promise<void> {
    const edit = new vscode.WorkspaceEdit();
    edit.replace(document.uri, new vscode.Range(0, 0, document.lineCount, 0), text);
    assert.ok(await vscode.workspace.applyEdit(edit));
}

/** Drives the BASIC program editor on a running Level II machine at its prompt. */
export async function testBasicEditor(session: vscode.DebugSession, root: string): Promise<void> {
    const program = async (): Promise<Program> => await session.customRequest("retro/basic/program") as Program;
    const holds = (text: string) => async () => (await program()).text === text ? true : undefined;

    // Lines typed on the machine are in the editor it opens.
    await type(session, "10 PRINT \"HI\"\r20 GOTO 10\r");
    await until("the typed program", holds("10 PRINT \"HI\"\n20 GOTO 10\n"));
    const uri = await vscode.commands.executeCommand<vscode.Uri>("retrocore.basic.open");
    assert.equal(uri.scheme, "retrocore-basic");
    assert.equal(path.posix.basename(uri.path), "Program.level2.bas");
    const document = await vscode.workspace.openTextDocument(uri);
    assert.equal(document.getText(), "10 PRINT \"HI\"\n20 GOTO 10\n");

    // Saving tokenizes the text into memory.
    await replace(document, "10 PRINT \"BYE\"\n20 END\n");
    assert.ok(await document.save());
    assert.equal((await program()).text, "10 PRINT \"BYE\"\n20 END\n");

    // A line typed on the machine shows in the editor, which has no unsaved edits.
    await type(session, "30 REM X\r");
    await until("the editor to follow the machine", () => document.getText().includes("30 REM X") ? true : undefined);
    assert.equal(document.isDirty, false);

    // Text that does not compile is not saved, and its problems are listed.
    await replace(document, "10 CLS\n20 GOTO nowhere\n");
    assert.equal(await document.save(), false);
    const problems = vscode.languages.getDiagnostics(uri);
    assert.equal(problems.length, 1);
    assert.equal(problems[0].range.start.line, 1);
    assert.equal((await program()).text, "10 PRINT \"BYE\"\n20 END\n30 REM X\n");

    // Saving while a program runs brings BASIC back to its prompt with the new program.
    await replace(document, "10 GOTO 10\n");
    assert.ok(await document.save());
    await type(session, "RUN\r");
    await until("the program to run", async () => (await program()).running ? true : undefined);
    await replace(document, "10 PRINT \"OK\"\n");
    assert.ok(await document.save());
    const after = await program();
    assert.equal(after.running, false);
    assert.equal(after.text, "10 PRINT \"OK\"\n");
    await type(session, "RUN\r");
    await until("the new program's output", async () => {
        const display = await session.customRequest("retro/display") as { rows: string[] };
        return display.rows.some(row => row.startsWith("OK")) ? true : undefined;
    });

    // Export as text, a tokenized file and a tape, and import each back.
    const folder = path.join(root, "artifacts", "vscode-m1-tests", "basic");
    fs.mkdirSync(folder, { recursive: true });
    const text = path.join(folder, "exported.bas");
    assert.equal(await vscode.commands.executeCommand("retrocore.basic.export", text), text);
    assert.equal(fs.readFileSync(text, "utf8"), "' retrocore level2\n10 PRINT \"OK\"\n");
    const tape = path.join(folder, "exported.cas");
    await vscode.commands.executeCommand("retrocore.basic.export", tape);
    const tokenized = path.join(folder, "exported.bin");
    await vscode.commands.executeCommand("retrocore.basic.export", tokenized);
    assert.deepEqual([...fs.readFileSync(tokenized)].slice(4), [0xB2, 0x20, 0x22, 0x4F, 0x4B, 0x22, 0, 0, 0]);

    const imported = path.join(folder, "imported.level2.bas");
    fs.writeFileSync(imported, "10 CLS\n20 PRINT \"IMPORTED\"\n");
    assert.equal((await vscode.commands.executeCommand<{ success: boolean }>("retrocore.basic.import", imported)).success, true);
    await until("the import in the editor", () => document.getText().includes("IMPORTED") ? true : undefined);
    for (const file of [tape, tokenized]) {
        assert.equal((await vscode.commands.executeCommand<{ success: boolean }>("retrocore.basic.import", file)).success, true);
        await until(`the import of ${path.basename(file)}`, holds("10 PRINT \"OK\"\n"));
    }

    await vscode.commands.executeCommand("workbench.action.closeAllEditors");
}
