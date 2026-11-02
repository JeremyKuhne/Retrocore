// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The BASIC program in a running machine, as a document: retrocore-basic://<session>/Program.<dialect>.bas reads the
// program through the debug host's retro/basic/program and saves it through retro/basic/write, which tokenizes it
// as the machine's ROM would. The host sends retro/basic/changed when the program in memory changes, so an open
// editor follows it, and asks what to do when it has unsaved edits.

import * as vscode from "vscode";

export const basicScheme = "retrocore-basic";
const machineScheme = "retrocore-basic-machine";

interface BasicProgram {
    dialect: string;
    displayName: string;
    text: string;
    version: string;
    running: boolean;
    error?: string | null;
}

interface BasicDiagnostic { line: number; severity: "error" | "warning"; message: string; }

interface BasicWrite { success: boolean; diagnostics: BasicDiagnostic[]; version: string; returnedToPrompt?: boolean; }

interface ShownProgram { version: string; mtime: number; size: number; }

/** What the Retro Devices row and the panel's BASIC button show of a session's program. */
export interface BasicSummary { displayName: string; lines: number; }

/** Each session's BASIC program in brief, for the machines whose BASIC the debugger edits. */
export interface BasicPrograms {
    /** The session's program, or none when the debugger has no editor for the machine's BASIC. */
    summary(session: vscode.DebugSession | undefined): BasicSummary | undefined;
    readonly onDidChange: vscode.Event<vscode.DebugSession>;
}

/** A program's lines, as LIST shows them: the non-blank ones. */
export function programLines(text: string): number {
    return text.split("\n").filter(line => line.trim().length !== 0).length;
}

const message = (error: unknown): string => error instanceof Error ? error.message : String(error);

/** The machine's program as a file: one per session, written back to memory on save. */
class BasicFileSystem implements vscode.FileSystemProvider {
    private readonly changes = new vscode.EventEmitter<vscode.FileChangeEvent[]>();
    readonly onDidChangeFile = this.changes.event;
    private readonly shown = new Map<string, ShownProgram>();
    private readonly asking = new Set<string>();
    // Saves in progress: the host reports the program it writes as changed before the save returns.
    private readonly writing = new Set<string>();
    private clock = Date.now();

    constructor(private readonly sessions: Map<string, vscode.DebugSession>, private readonly problems: vscode.DiagnosticCollection) {}

    session(uri: vscode.Uri): vscode.DebugSession {
        const session = this.sessions.get(uri.authority);
        if (session === undefined) throw vscode.FileSystemError.Unavailable(`The debug session for ${uri.path.slice(1)} has ended.`);
        return session;
    }

    watch(): vscode.Disposable { return new vscode.Disposable(() => undefined); }

    stat(uri: vscode.Uri): vscode.FileStat {
        if (!this.sessions.has(uri.authority)) throw vscode.FileSystemError.FileNotFound(uri);
        // The time changes only when the program does, through a save or the machine, as VS Code compares it to
        // detect a file changed since it was read.
        let shown = this.shown.get(uri.toString());
        if (shown === undefined) {
            shown = { version: "", mtime: ++this.clock, size: 0 };
            this.shown.set(uri.toString(), shown);
        }
        return { type: vscode.FileType.File, ctime: 0, mtime: shown.mtime, size: shown.size };
    }

    async readFile(uri: vscode.Uri): Promise<Uint8Array> {
        const program = await this.session(uri).customRequest("retro/basic/program") as BasicProgram;
        if (program.error) void vscode.window.showWarningMessage(`Retrocore: the machine's BASIC program cannot be read: ${program.error}`);
        const bytes = Buffer.from(program.text, "utf8");
        this.remember(uri, program.version, bytes.length, false);
        return bytes;
    }

    async writeFile(uri: vscode.Uri, content: Uint8Array): Promise<void> {
        let result: BasicWrite;
        this.writing.add(uri.toString());
        try {
            result = await this.session(uri).customRequest("retro/basic/write", { text: Buffer.from(content).toString("utf8") }) as BasicWrite;
        } finally {
            this.writing.delete(uri.toString());
        }
        this.report(uri, result.diagnostics);
        if (!result.success) {
            const first = result.diagnostics.find(diagnostic => diagnostic.severity === "error");
            throw new Error(`The program was not saved: ${first ? `line ${first.line + 1}: ${first.message}` : "it has errors"}`);
        }
        this.remember(uri, result.version, content.length, true);
    }

    /** The program in a session's machine changed: an editor without unsaved edits follows it, else it asks. */
    async machineChanged(session: vscode.DebugSession, version: string): Promise<void> {
        for (const [key, shown] of this.shown) {
            const uri = vscode.Uri.parse(key);
            if (uri.authority !== session.id || shown.version === version || this.writing.has(key)) continue;
            const document = vscode.workspace.textDocuments.find(open => open.uri.toString() === key);
            if (document === undefined || !document.isDirty) {
                this.refresh(uri, version);
                continue;
            }
            if (this.asking.has(key)) continue;
            this.asking.add(key);
            try {
                const keep = "Keep Mine", take = "Take the Machine's", compare = "Compare";
                const choice = await vscode.window.showWarningMessage(
                    "The BASIC program in the machine changed while you were editing it.", keep, take, compare);
                if (choice === take) {
                    this.refresh(uri, version);
                    await vscode.commands.executeCommand("workbench.action.files.revert", uri);
                } else {
                    // Saving overwrites the machine's program, without VS Code's own warning that the file is newer.
                    shown.version = version;
                    if (choice === compare) {
                        await vscode.commands.executeCommand("vscode.diff", uri.with({ scheme: machineScheme }), uri,
                            "BASIC program: the machine's ↔ yours");
                    }
                }
            } finally {
                this.asking.delete(key);
            }
        }
    }

    /**
     * The session ended, so its program has nowhere to be saved: an editor without edits closes, and one with edits
     * becomes an unsaved copy, with a message offering Save As, so nothing typed is lost.
     */
    async ended(session: vscode.DebugSession): Promise<void> {
        for (const key of [...this.shown.keys()]) {
            const uri = vscode.Uri.parse(key);
            if (uri.authority === session.id) { this.shown.delete(key); this.problems.delete(uri); }
        }

        const tabsOf = (uri: vscode.Uri): vscode.Tab[] => vscode.window.tabGroups.all.flatMap(group => group.tabs)
            .filter(tab => tab.input instanceof vscode.TabInputText && tab.input.uri.toString() === uri.toString());
        const documents = vscode.workspace.textDocuments.filter(document =>
            document.uri.scheme === basicScheme && document.uri.authority === session.id);
        let copies = 0;
        for (const document of documents) {
            const tabs = tabsOf(document.uri);
            if (!document.isDirty) {
                if (tabs.length !== 0) await vscode.window.tabGroups.close(tabs);
                continue;
            }

            const column = tabs[0]?.group.viewColumn;
            const text = document.getText();

            // The machine is gone, so reverting fails and the editor closes without asking to save.
            await vscode.window.showTextDocument(document, { viewColumn: column, preview: false });
            await vscode.commands.executeCommand("workbench.action.revertAndCloseActiveEditor");
            const copy = await vscode.workspace.openTextDocument({ language: document.languageId, content: text });
            await vscode.window.showTextDocument(copy, { viewColumn: column, preview: false });
            this.copies.push(copy);
            copies++;
        }

        if (copies !== 0) {
            const saveAs = "Save As…";
            void vscode.window.showInformationMessage(
                "Retrocore: the machine stopped, so your edits to its BASIC program are in an unsaved copy.", saveAs)
                .then(async choice => {
                    const copy = this.copies.at(-1);
                    if (choice !== saveAs || copy === undefined || copy.isClosed) return;
                    await vscode.window.showTextDocument(copy);
                    await vscode.commands.executeCommand("workbench.action.files.saveAs");
                });
        }
    }

    /** The unsaved copies made of edited programs whose sessions ended, newest last. */
    readonly copies: vscode.TextDocument[] = [];

    report(uri: vscode.Uri, diagnostics: BasicDiagnostic[]): void {
        this.problems.set(uri, diagnostics.map(diagnostic => new vscode.Diagnostic(
            new vscode.Range(diagnostic.line, 0, diagnostic.line, Number.MAX_SAFE_INTEGER),
            diagnostic.message,
            diagnostic.severity === "error" ? vscode.DiagnosticSeverity.Error : vscode.DiagnosticSeverity.Warning)));
    }

    readDirectory(): [string, vscode.FileType][] { return []; }
    createDirectory(uri: vscode.Uri): void { throw vscode.FileSystemError.NoPermissions(uri); }
    delete(uri: vscode.Uri): void { throw vscode.FileSystemError.NoPermissions(uri); }
    rename(uri: vscode.Uri): void { throw vscode.FileSystemError.NoPermissions(uri); }

    private refresh(uri: vscode.Uri, version: string): void {
        const shown = this.shown.get(uri.toString());
        if (shown !== undefined) { shown.version = version; shown.mtime = ++this.clock; }
        this.changes.fire([{ type: vscode.FileChangeType.Changed, uri }]);
    }

    private remember(uri: vscode.Uri, version: string, size: number, changed: boolean): void {
        const previous = this.shown.get(uri.toString());
        this.shown.set(uri.toString(), { version, size, mtime: changed || previous === undefined ? ++this.clock : previous.mtime });
    }
}

function activeSession(): vscode.DebugSession | undefined {
    const session = vscode.debug.activeDebugSession;
    if (session?.type === "retrocore") return session;
    void vscode.window.showWarningMessage("Start a Retrocore debug session first.");
    return undefined;
}

/** The session a command acts on: the BASIC editor's, else the active one. */
function commandSession(sessions: Map<string, vscode.DebugSession>, uri?: vscode.Uri): vscode.DebugSession | undefined {
    const editor = uri ?? vscode.window.activeTextEditor?.document.uri;
    if (editor?.scheme === basicScheme) {
        const session = sessions.get(editor.authority);
        if (session !== undefined) return session;
    }
    return activeSession();
}

/** Registers the BASIC program editor and its commands. */
export function registerBasic(context: vscode.ExtensionContext): BasicPrograms {
    const sessions = new Map<string, vscode.DebugSession>();
    for (const session of [vscode.debug.activeDebugSession]) {
        if (session?.type === "retrocore") sessions.set(session.id, session);
    }
    const problems = vscode.languages.createDiagnosticCollection("retrocore-basic");
    const files = new BasicFileSystem(sessions, problems);
    context.subscriptions.push(problems);
    context.subscriptions.push(vscode.workspace.registerFileSystemProvider(basicScheme, files, { isCaseSensitive: true }));
    context.subscriptions.push(vscode.workspace.registerTextDocumentContentProvider(machineScheme, {
        async provideTextDocumentContent(uri) {
            const session = sessions.get(uri.authority);
            if (session === undefined) return "";
            return (await session.customRequest("retro/basic/program") as BasicProgram).text;
        }
    }));
    // Each session's program in brief, kept as the host says it changes. A machine whose BASIC the debugger cannot
    // edit never says so, and its request fails, so it has none.
    const summaries = new Map<string, BasicSummary>();
    const summaryChanged = new vscode.EventEmitter<vscode.DebugSession>();
    context.subscriptions.push(summaryChanged);
    // The sessions launched with a BASIC file whose program editor has been opened, once each.
    const opened = new Set<string>();
    const summarize = async (session: vscode.DebugSession): Promise<void> => {
        let program: BasicProgram;
        try {
            program = await session.customRequest("retro/basic/program") as BasicProgram;
        } catch {
            return;
        }

        if (!sessions.has(session.id)) return;
        const summary = { displayName: program.displayName, lines: programLines(program.text) };
        const before = summaries.get(session.id);
        summaries.set(session.id, summary);
        if (before?.displayName !== summary.displayName || before.lines !== summary.lines) summaryChanged.fire(session);

        // A launch with a BASIC file opens the program's editor once the program is in memory.
        if (typeof session.configuration.basic === "string" && summary.lines !== 0 && !opened.has(session.id)) {
            opened.add(session.id);
            await openProgram(session, { preview: false, preserveFocus: true, viewColumn: vscode.ViewColumn.One });
        }
    };

    const openProgram = async (session: vscode.DebugSession, options?: vscode.TextDocumentShowOptions): Promise<vscode.Uri | undefined> => {
        sessions.set(session.id, session);
        try {
            const program = await session.customRequest("retro/basic/program") as BasicProgram;
            const uri = vscode.Uri.from({ scheme: basicScheme, authority: session.id, path: `/Program.${program.dialect}.bas` });
            await vscode.window.showTextDocument(await vscode.workspace.openTextDocument(uri), options);
            return uri;
        } catch (error) {
            void vscode.window.showErrorMessage(`Retrocore: ${message(error)}`);
            return undefined;
        }
    };

    context.subscriptions.push(vscode.debug.onDidStartDebugSession(session => {
        if (session.type !== "retrocore") return;
        sessions.set(session.id, session);
        // The BASIC thread's frames and breakpoints name the machine-program document by this session's URI.
        void Promise.resolve(session.customRequest("retro/basic/document", { base: `${basicScheme}://${session.id}/` }))
            .catch(() => undefined);
    }));
    context.subscriptions.push(vscode.debug.onDidTerminateDebugSession(session => {
        sessions.delete(session.id);
        opened.delete(session.id);
        if (summaries.delete(session.id)) summaryChanged.fire(session);
        void files.ended(session).then(undefined, error => console.warn(`retrocore: ${message(error)}`));
    }));
    context.subscriptions.push(vscode.debug.onDidReceiveDebugSessionCustomEvent(event => {
        if (event.event !== "retro/basic/changed") return;
        const body: unknown = event.body;
        if (typeof body === "object" && body !== null && "version" in body && typeof body.version === "string") {
            void files.machineChanged(event.session, body.version);
            void summarize(event.session);
        }
    }));

    // The display panel passes the column to open in, so the editor does not cover the machine's screen.
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.basic.open", async (column?: unknown): Promise<vscode.Uri | undefined> => {
        const session = activeSession();
        if (session === undefined) return undefined;
        return openProgram(session, typeof column === "number" ? { viewColumn: column } : undefined);
    }));

    // For the tests: the unsaved copies of edited programs whose sessions ended.
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.basic.endedCopies", () =>
        files.copies.filter(copy => !copy.isClosed).map(copy => copy.uri.toString())));

    // Import and export take a path when the test suite passes one, and ask otherwise.
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.basic.import", async (target?: unknown): Promise<BasicWrite | undefined> => {
        const session = commandSession(sessions, target instanceof vscode.Uri ? target : undefined);
        if (session === undefined) return undefined;
        const path = typeof target === "string" ? target : (await vscode.window.showOpenDialog({
            title: "Import a BASIC program into the machine",
            canSelectMany: false,
            filters: { "BASIC programs": ["bas", "txt", "cas", "bin"], "All files": ["*"] }
        }))?.[0]?.fsPath;
        if (path === undefined) return undefined;
        try {
            const result = await session.customRequest("retro/basic/import", { path }) as BasicWrite;
            if (!result.success) {
                const errors = result.diagnostics.filter(diagnostic => diagnostic.severity === "error").slice(0, 3)
                    .map(diagnostic => `line ${diagnostic.line + 1}: ${diagnostic.message}`);
                void vscode.window.showErrorMessage(`Retrocore: the program was not imported. ${errors.join("; ")}`);
            }
            return result;
        } catch (error) {
            void vscode.window.showErrorMessage(`Retrocore: ${message(error)}`);
            return undefined;
        }
    }));

    context.subscriptions.push(vscode.commands.registerCommand("retrocore.basic.export", async (target?: unknown, format?: string): Promise<string | undefined> => {
        const session = commandSession(sessions, target instanceof vscode.Uri ? target : undefined);
        if (session === undefined) return undefined;
        let path = typeof target === "string" ? target : undefined;
        try {
            if (path === undefined) {
                const program = await session.customRequest("retro/basic/program") as BasicProgram;
                const formats = [
                    { label: "Text listing", detail: "A .bas file, as LIST shows it", format: "text", name: `program.${program.dialect}.bas` },
                    {
                        label: "Tokenized program", detail: "The bytes as BASIC stores them",
                        format: "tokenized",
                        name: program.dialect === "applesoft" ? "PROGRAM#fc0801" : program.dialect === "integer" ? "PROGRAM#fa0000" : "program.bas"
                    },
                    ...program.dialect === "level2"
                        ? [{ label: "Model I tape", detail: "A .cas file, as CSAVE writes it", format: "tape", name: "program.cas" }]
                        : []
                ];
                const picked = await vscode.window.showQuickPick(formats, { title: "Export the machine's BASIC program as" });
                if (picked === undefined) return undefined;
                format = picked.format;
                const folder = vscode.workspace.workspaceFolders?.[0]?.uri;
                path = (await vscode.window.showSaveDialog({
                    title: `Export as ${picked.label.toLowerCase()}`,
                    defaultUri: folder ? vscode.Uri.joinPath(folder, picked.name) : undefined
                }))?.fsPath;
                if (path === undefined) return undefined;
            }
            await session.customRequest("retro/basic/export", { path, format });
            return path;
        } catch (error) {
            void vscode.window.showErrorMessage(`Retrocore: ${message(error)}`);
            return undefined;
        }
    }));

    return {
        summary: session => session === undefined ? undefined : summaries.get(session.id),
        onDidChange: summaryChanged.event
    };
}
