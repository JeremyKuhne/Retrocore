// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// A Retrocore project's sources are Retrocore assembly. *.s and *.inc are not claimed in general, as ca65 and the GNU
// assembler use them too (see the README's "Select the assembly language"), but one in a folder with a project's
// retrocore.json, or below it, is the project's: it opens as retrocore-asm, so the language server analyzes it for the
// active target. Only a document no other language claims (plain text) is changed.

import * as path from "node:path";
import * as vscode from "vscode";
import { activeTargetRead, type ActiveTargets } from "./activeTarget";
import { inProject } from "./project";

/** The extensions of the sources a project's folder gives the assembly language. */
const sourceExtensions = new Set([".s", ".inc"]);

/** Opens a project's plain-text .s and .inc sources as Retrocore assembly, now and as they open. */
export function registerProjectLanguage(context: vscode.ExtensionContext, targets: ActiveTargets): void {
    const claim = (document: vscode.TextDocument): void => {
        if (document.uri.scheme !== "file" || document.languageId !== "plaintext"
            || !sourceExtensions.has(path.extname(document.uri.fsPath).toLowerCase())) return;
        const folders = [...new Set(targets.targets.map(target => path.dirname(target.file)))];
        if (inProject(document.uri.fsPath, folders)) {
            void vscode.languages.setTextDocumentLanguage(document, "retrocore-asm").then(undefined, error =>
                console.warn(`retrocore: could not open ${document.uri.fsPath} as Retrocore assembly: ${String(error)}`));
        }
    };
    const claimOpen = (): void => { for (const document of vscode.workspace.textDocuments) claim(document); };
    context.subscriptions.push(vscode.workspace.onDidOpenTextDocument(claim), targets.onDidChange(claimOpen));
    void activeTargetRead().then(claimOpen);
}
