// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as vscode from "vscode";
import type { ActiveTargets } from "./activeTarget";
import { languageRequest, onDidStartLanguageClient, onDidStopLanguageClient } from "./languageClient";

/** The server's answer to retrocore/inactiveRanges: whole lines, each range ending at the start of the line after it. */
interface InactiveRangesResult {
    ranges: { start: { line: number; character: number }; end: { line: number; character: number } }[] | null;
}

/** The lines (0-based) each document's assembly leaves out, as the server last answered for it. */
const inactive = new Map<string, number[]>();

/**
 * The lines, 0-based, that the last answer for a document left out, or undefined before it has one or after the
 * server stopped: a .if block's other branch, for the target the source is assembled for. An empty list means the
 * answer left out none, or that no analysis covers the document, as for a file no project target assembles, or none
 * has yet.
 */
export function inactiveLines(uri: vscode.Uri): number[] | undefined {
    return inactive.get(uri.toString());
}

/** The lines a range covers: from its start line to the line before its end, which it ends at the start of. */
export function rangeLines(range: { start: { line: number }; end: { line: number; character: number } }): number[] {
    const last = range.end.character === 0 ? range.end.line - 1 : range.end.line;
    return Array.from({ length: Math.max(0, last - range.start.line + 1) }, (_, index) => range.start.line + index);
}

/**
 * Shades the lines a Retrocore assembly source's .if blocks leave out, from the language server's
 * retrocore/inactiveRanges, with the themable color retrocore.inactiveCodeBackground across the whole line, and marks
 * them in the overview ruler with retrocore.inactiveCodeOverviewRuler. The server also fades those lines' text, with
 * Unnecessary hints. A document is asked again each time the server publishes its diagnostics, which follow each
 * analysis, and when the active target changes; when the server can't answer, as it stops, the shading goes with its
 * fading. `retrocore.inactiveCode.shade` turns the shading off.
 */
export function registerInactiveRanges(context: vscode.ExtensionContext, targets?: ActiveTargets): void {
    const decoration = vscode.window.createTextEditorDecorationType({
        isWholeLine: true,
        backgroundColor: new vscode.ThemeColor("retrocore.inactiveCodeBackground"),
        overviewRulerColor: new vscode.ThemeColor("retrocore.inactiveCodeOverviewRuler"),
        overviewRulerLane: vscode.OverviewRulerLane.Left
    });

    const enabled = (): boolean => vscode.workspace.getConfiguration("retrocore").get<boolean>("inactiveCode.shade", true);
    const isAssembly = (document: vscode.TextDocument): boolean =>
        document.languageId === "retrocore-asm" && document.uri.scheme === "file";

    const paint = (uri: vscode.Uri): void => {
        const shown = enabled() ? inactive.get(uri.toString()) ?? [] : [];
        for (const editor of vscode.window.visibleTextEditors) {
            if (editor.document.uri.toString() !== uri.toString()) continue;
            editor.setDecorations(decoration, shown
                .filter(line => line < editor.document.lineCount)
                .map(line => editor.document.lineAt(line).range));
        }
    };

    // The newest request for each document wins; an older answer that arrives after it is dropped.
    const asked = new Map<string, number>();
    let requests = 0;
    const ask = (document: vscode.TextDocument): void => {
        if (!isAssembly(document)) return;
        const key = document.uri.toString();
        const request = ++requests;
        asked.set(key, request);
        void (async () => {
            try {
                const result = await languageRequest<InactiveRangesResult>("retrocore/inactiveRanges", { textDocument: { uri: key } });
                if (asked.get(key) !== request) return;
                // No analysis covers the document, or none has yet; one that does publishes diagnostics, which asks again.
                inactive.set(key, result.ranges === null ? [] : result.ranges.flatMap(rangeLines));
            } catch {
                // No server, or it stopped, which clears its fading too: the shading goes until the next answer.
                if (asked.get(key) !== request) return;
                inactive.delete(key);
            }
            paint(document.uri);
        })();
    };

    const askVisible = (): void => {
        const seen = new Set<string>();
        for (const editor of vscode.window.visibleTextEditors) {
            if (seen.has(editor.document.uri.toString())) continue;
            seen.add(editor.document.uri.toString());
            ask(editor.document);
        }
    };

    context.subscriptions.push(decoration,
        vscode.languages.onDidChangeDiagnostics(event => {
            const changed = new Set(event.uris.map(uri => uri.toString()));
            for (const document of vscode.workspace.textDocuments) {
                if (changed.has(document.uri.toString())) ask(document);
            }
        }),
        vscode.window.onDidChangeVisibleTextEditors(editors => {
            const seen = new Set<string>();
            for (const editor of editors) {
                const key = editor.document.uri.toString();
                if (seen.has(key)) continue;
                seen.add(key);
                if (inactive.has(key)) paint(editor.document.uri);
                else ask(editor.document);
            }
        }),
        vscode.workspace.onDidCloseTextDocument(document => {
            inactive.delete(document.uri.toString());
            asked.delete(document.uri.toString());
        }),
        // A stopped server's fading is gone, so its shading goes too; a started one is asked for what it shades.
        onDidStartLanguageClient(() => askVisible()),
        onDidStopLanguageClient(() => {
            const shaded = [...inactive.keys()];
            inactive.clear();
            asked.clear();
            for (const key of shaded) paint(vscode.Uri.parse(key));
        }),
        vscode.workspace.onDidChangeConfiguration(event => {
            if (!event.affectsConfiguration("retrocore.inactiveCode.shade")) return;
            for (const editor of vscode.window.visibleTextEditors) paint(editor.document.uri);
        }),
        // For tests and other extensions; not in the command palette.
        vscode.commands.registerCommand("retrocore.inactiveLines", (uri?: unknown): number[] | undefined => {
            const target = uri instanceof vscode.Uri ? uri : typeof uri === "string" ? vscode.Uri.parse(uri) : vscode.window.activeTextEditor?.document.uri;
            return target === undefined ? undefined : inactiveLines(target);
        }));

    // The server reanalyzes after the target changes. Asking now usually reaches it after the target, which the
    // language client sends first; either way the new analysis publishes diagnostics, which asks again.
    if (targets !== undefined) context.subscriptions.push(targets.onDidChange(askVisible));
    askVisible();
}
