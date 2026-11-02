// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Breakpoint hit counts, which VS Code's Breakpoints view does not show: a quick pick of every breakpoint with its
// hits, and a reset, from the debug host's retro/breakpoints request.

import * as vscode from "vscode";

/** A breakpoint as the debug host's retro/breakpoints describes it. */
export interface BreakpointHits {
    id: number;
    kind: "breakpoint" | "function breakpoint" | "instruction breakpoint" | "data breakpoint";
    location: string;
    path: string | null;
    line: number | null;
    address: string | null;
    verified: boolean;
    hits: number;
    condition: string | null;
    hitCondition: string | null;
    logMessage: string | null;
    message: string | null;
}

/** The detail line of a breakpoint's quick pick item: its hits and what decides whether it stops. */
export function hitDetail(breakpoint: BreakpointHits): string {
    const parts = [breakpoint.hits === 1 ? "hit once" : `hit ${breakpoint.hits} times`];
    if (breakpoint.condition) parts.push(`when ${breakpoint.condition}`);
    if (breakpoint.hitCondition) parts.push(`hit count ${breakpoint.hitCondition}`);
    if (breakpoint.logMessage) parts.push(`logs "${breakpoint.logMessage}"`);
    if (!breakpoint.verified && breakpoint.message) parts.push(breakpoint.message);
    return parts.join(" · ");
}

function retroSession(): vscode.DebugSession | undefined {
    const session = vscode.debug.activeDebugSession;
    if (session?.type === "retrocore") return session;
    void vscode.window.showWarningMessage("Start a Retrocore debug session first.");
    return undefined;
}

/** Registers the hit count commands. */
export function registerBreakpoints(context: vscode.ExtensionContext): void {
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.breakpoints.showHits", async () => {
        const session = retroSession();
        if (!session) return;
        const body = await session.customRequest("retro/breakpoints") as { breakpoints: BreakpointHits[] };
        if (body.breakpoints.length === 0) {
            void vscode.window.showInformationMessage("No breakpoints are set.");
            return;
        }
        const picked = await vscode.window.showQuickPick(body.breakpoints.map(breakpoint => ({
            label: breakpoint.location,
            description: breakpoint.kind,
            detail: hitDetail(breakpoint),
            breakpoint
        })), { title: "Breakpoint hit counts", matchOnDescription: true, matchOnDetail: true });
        if (picked?.breakpoint.path && picked.breakpoint.line) {
            const position = new vscode.Position(picked.breakpoint.line - 1, 0);
            await vscode.window.showTextDocument(vscode.Uri.file(picked.breakpoint.path), { selection: new vscode.Range(position, position) });
        }
    }));

    context.subscriptions.push(vscode.commands.registerCommand("retrocore.breakpoints.resetHits", async () => {
        const session = retroSession();
        if (session) await session.customRequest("retro/breakpoints", { reset: true });
    }));

    // The test suite reads the hit counts through this command.
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.breakpoints.list", async () => {
        const session = vscode.debug.activeDebugSession;
        if (session?.type !== "retrocore") return [];
        return (await session.customRequest("retro/breakpoints") as { breakpoints: BreakpointHits[] }).breakpoints;
    }));
}
