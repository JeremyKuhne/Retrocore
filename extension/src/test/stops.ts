// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as vscode from "vscode";
import * as path from "node:path";

/**
 * Waits until VS Code shows the source of the frame a session stopped in. VS Code opens that source after the stop,
 * in the active group, so an editor opened before it lands behind it, and a webview behind another tab never loads.
 */
export async function untilStopShown(session: vscode.DebugSession, milliseconds = 15000): Promise<void> {
    const deadline = Date.now() + milliseconds;
    const pause = () => new Promise(resolve => setTimeout(resolve, 100));
    let frame: vscode.DebugStackFrame | undefined;
    while (Date.now() < deadline) {
        const item = vscode.debug.activeStackItem;
        if (item instanceof vscode.DebugStackFrame && item.session.id === session.id) { frame = item; break; }
        await pause();
    }
    if (frame === undefined) throw new Error("VS Code did not focus the stopped frame.");
    const trace = await session.customRequest("stackTrace", { threadId: frame.threadId, levels: 1 });
    const top: { source?: { path?: string } | null } | undefined = trace.stackFrames?.[0];
    if (top === undefined) throw new Error("The stopped thread has no frames.");
    // A frame with no source line, such as one in unlabeled memory, opens no editor, so there is nothing to wait for.
    const source = top.source?.path;
    if (source === undefined) return;
    const key = (file: string) => process.platform === "win32" ? path.resolve(file).toLowerCase() : path.resolve(file);
    const shown = () => vscode.window.activeTextEditor !== undefined
        && key(vscode.window.activeTextEditor.document.uri.fsPath) === key(source);
    while (Date.now() < deadline && !shown()) await pause();
    if (!shown()) throw new Error(`VS Code did not show the stop's source, ${source}.`);
}
