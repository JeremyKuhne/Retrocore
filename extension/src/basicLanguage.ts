// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// BASIC files in the workspace: which dialect each is, renumbering, and tokenized programs and Model I tapes opened
// as listings through retrocore-basic-file://, which the language server lists and tokenizes back on save.

import * as vscode from "vscode";
import { basicLanguages, languageRequest } from "./languageClient";

const listingScheme = "retrocore-basic-file";
const dialects: Record<string, string> = {
    applesoft: "retrocore-applesoft", level2: "retrocore-level2", level1: "retrocore-level1", integer: "retrocore-integer",
    business: "retrocore-business"
};

interface Diagnostic { line: number; severity: "error" | "warning"; message: string; start: number; end: number; }

const message = (error: unknown): string => error instanceof Error ? error.message : String(error);

/** The dialect a document's first line names, as REM retrocore applesoft or ' retrocore level2. */
export function pragmaOf(document: vscode.TextDocument): string | undefined {
    for (let line = 0; line < Math.min(document.lineCount, 20); line++) {
        const text = document.lineAt(line).text;
        if (text.trim().length === 0) continue;
        return /^\s*(?:\d+\s*)?(?:REM|')\s*retrocore\s+(\S+)/i.exec(text)?.[1]?.toLowerCase();
    }
    return undefined;
}

/** The BASIC of the machine being debugged, if any. */
function sessionDialect(): string | undefined {
    const session = vscode.debug.activeDebugSession;
    if (session?.type !== "retrocore") return undefined;
    if (session.configuration.machine === "apple2" || session.configuration.machine === "apple2e") {
        return session.configuration.model === "ii" ? "integer" : "applesoft";
    }

    if (session.configuration.machine === "apple3") return "business";
    if (session.configuration.machine === "trs80-model1") return session.configuration.rom === "level1" ? "level1" : "level2";
    return undefined;
}

/** The language a BASIC document should have: its pragma's, else for a plain .bas the setting's or the session's. */
function wanted(document: vscode.TextDocument): string | undefined {
    const pragma = pragmaOf(document);
    if (pragma !== undefined) return dialects[pragma];
    if (document.languageId !== "retrocore-basic") return undefined;
    const setting = vscode.workspace.getConfiguration("retrocore").get<string>("basic.dialect", "");
    return dialects[setting || sessionDialect() || ""];
}

async function choose(document: vscode.TextDocument): Promise<void> {
    if (!basicLanguages.includes(document.languageId)) return;
    const language = wanted(document);
    if (language !== undefined && language !== document.languageId) await vscode.languages.setTextDocumentLanguage(document, language);
}

/** A tokenized file or tape as a listing: the original file, read and written through the language server. */
class ListingFileSystem implements vscode.FileSystemProvider {
    private readonly changes = new vscode.EventEmitter<vscode.FileChangeEvent[]>();
    readonly onDidChangeFile = this.changes.event;

    constructor(private readonly problems: vscode.DiagnosticCollection) {}

    static uri(file: vscode.Uri, dialect: string): vscode.Uri {
        return vscode.Uri.from({ scheme: listingScheme, path: `${file.path}.${dialect}.bas` });
    }

    static original(uri: vscode.Uri): { file: vscode.Uri; dialect: string } {
        const match = /^(.*)\.(\w+)\.bas$/.exec(uri.path);
        if (match === null) throw vscode.FileSystemError.FileNotFound(uri);
        return { file: vscode.Uri.file(vscode.Uri.from({ scheme: "file", path: match[1] }).fsPath), dialect: match[2] };
    }

    watch(uri: vscode.Uri): vscode.Disposable {
        const { file } = ListingFileSystem.original(uri);
        const watcher = vscode.workspace.createFileSystemWatcher(new vscode.RelativePattern(vscode.Uri.joinPath(file, ".."), file.path.split("/").pop() ?? ""));
        watcher.onDidChange(() => this.changes.fire([{ type: vscode.FileChangeType.Changed, uri }]));
        return watcher;
    }

    async stat(uri: vscode.Uri): Promise<vscode.FileStat> {
        const stat = await vscode.workspace.fs.stat(ListingFileSystem.original(uri).file);
        return { type: vscode.FileType.File, ctime: stat.ctime, mtime: stat.mtime, size: stat.size };
    }

    async readFile(uri: vscode.Uri): Promise<Uint8Array> {
        const { file, dialect } = ListingFileSystem.original(uri);
        const listing = await languageRequest<{ text: string }>("retrocore/basic/list", { path: file.fsPath, dialect });
        return Buffer.from(listing.text, "utf8");
    }

    async writeFile(uri: vscode.Uri, content: Uint8Array): Promise<void> {
        const { file, dialect } = ListingFileSystem.original(uri);
        const result = await languageRequest<{ success: boolean; diagnostics: Diagnostic[] }>("retrocore/basic/store",
            { path: file.fsPath, dialect, text: Buffer.from(content).toString("utf8") });
        this.problems.set(uri, result.diagnostics.map(diagnostic => new vscode.Diagnostic(
            new vscode.Range(diagnostic.line, diagnostic.start, diagnostic.line, diagnostic.end < 0 ? Number.MAX_SAFE_INTEGER : diagnostic.end),
            diagnostic.message,
            diagnostic.severity === "error" ? vscode.DiagnosticSeverity.Error : vscode.DiagnosticSeverity.Warning)));
        if (!result.success) throw new Error("The program has errors, so the file was not written.");
    }

    readDirectory(): [string, vscode.FileType][] { return []; }
    createDirectory(uri: vscode.Uri): void { throw vscode.FileSystemError.NoPermissions(uri); }
    delete(uri: vscode.Uri): void { throw vscode.FileSystemError.NoPermissions(uri); }
    rename(uri: vscode.Uri): void { throw vscode.FileSystemError.NoPermissions(uri); }
}

/** The dialect a tokenized file's name gives: a tape is Level II, a CiderPress2 $FC name AppleSoft, $FA Integer BASIC. */
function dialectOfFile(file: vscode.Uri): string | undefined {
    const name = file.path.split("/").pop() ?? "";
    if (/\.cas$/i.test(name)) return "level2";
    if (/#fc/i.test(name)) return "applesoft";
    if (/#fa/i.test(name)) return "integer";
    return undefined;
}

/** Registers BASIC dialect selection, Renumber and Open as BASIC Listing. */
export function registerBasicLanguage(context: vscode.ExtensionContext): void {
    const problems = vscode.languages.createDiagnosticCollection("retrocore-basic-listing");
    context.subscriptions.push(problems);
    context.subscriptions.push(vscode.workspace.registerFileSystemProvider(listingScheme, new ListingFileSystem(problems), { isCaseSensitive: true }));
    for (const document of vscode.workspace.textDocuments) void choose(document);
    context.subscriptions.push(vscode.workspace.onDidOpenTextDocument(document => void choose(document)));
    context.subscriptions.push(vscode.workspace.onDidChangeTextDocument(event => {
        // Only the first lines hold a pragma.
        if (event.contentChanges.some(change => change.range.start.line < 20)) void choose(event.document);
    }));

    context.subscriptions.push(vscode.commands.registerCommand("retrocore.basic.renumber", async (start?: number, step?: number): Promise<boolean> => {
        const editor = vscode.window.activeTextEditor;
        if (editor === undefined || !basicLanguages.includes(editor.document.languageId)) {
            void vscode.window.showWarningMessage("Open a BASIC program to renumber.");
            return false;
        }
        const ask = async (prompt: string): Promise<number | undefined> => {
            const text = await vscode.window.showInputBox({
                title: "Renumber BASIC program", prompt, value: "10",
                validateInput: value => /^\d+$/.test(value) && Number(value) > 0 ? undefined : "Enter a whole number above 0."
            });
            return text === undefined ? undefined : Number(text);
        };
        start ??= await ask("The first line's new number");
        if (start === undefined) return false;
        step ??= await ask("How far apart the lines are");
        if (step === undefined) return false;
        try {
            const document = editor.document;
            const result = await languageRequest<{ text: string | null; diagnostics: Diagnostic[] }>("retrocore/basic/renumber",
                { text: document.getText(), start, step, languageId: document.languageId, path: document.uri.path });
            if (result.text === null) {
                void vscode.window.showErrorMessage(`Retrocore: ${result.diagnostics[0]?.message ?? "the program cannot be renumbered."}`);
                return false;
            }
            const edit = new vscode.WorkspaceEdit();
            edit.replace(document.uri, new vscode.Range(0, 0, document.lineCount, 0), result.text);
            await vscode.workspace.applyEdit(edit);
            const missing = result.diagnostics.filter(diagnostic => diagnostic.severity === "warning").length;
            if (missing > 0) void vscode.window.showWarningMessage(`Retrocore: ${missing} references name lines that do not exist; they are unchanged.`);
            return true;
        } catch (error) {
            void vscode.window.showErrorMessage(`Retrocore: ${message(error)}`);
            return false;
        }
    }));

    context.subscriptions.push(vscode.commands.registerCommand("retrocore.basic.openListing", async (target?: vscode.Uri, dialect?: string): Promise<vscode.Uri | undefined> => {
        const file = target ?? (await vscode.window.showOpenDialog({ title: "Open a tokenized BASIC program or tape", canSelectMany: false }))?.[0];
        if (file === undefined) return undefined;
        dialect ??= dialectOfFile(file) ?? (await vscode.window.showQuickPick(
            [
                { label: "AppleSoft", dialect: "applesoft" },
                { label: "Integer BASIC", dialect: "integer", detail: "Saving tokenizes through the Apple II's ROM (RETROCORE_II_ROMS)" },
                { label: "Business BASIC", dialect: "business" },
                { label: "Level II BASIC", dialect: "level2" }
            ],
            { title: "Which BASIC is this program?" }))?.dialect;
        if (dialect === undefined) return undefined;
        const uri = ListingFileSystem.uri(file, dialect);
        try {
            await vscode.window.showTextDocument(await vscode.workspace.openTextDocument(uri));
            return uri;
        } catch (error) {
            void vscode.window.showErrorMessage(`Retrocore: ${message(error)}`);
            return undefined;
        }
    }));
}
