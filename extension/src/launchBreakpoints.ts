// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as fs from "node:fs";
import * as vscode from "vscode";

/**
 * A launch configuration's breakpoint: a file and a 1-based line, a label in a file whose first instruction to stop at,
 * or a function breakpoint on a label or address; each with an optional condition, hit count and log message.
 */
interface LaunchBreakpoint {
    path?: unknown;
    line?: unknown;
    label?: unknown;
    function?: unknown;
    condition?: unknown;
    hitCondition?: unknown;
    logMessage?: unknown;
}

function text(value: unknown): string | undefined {
    return typeof value === "string" && value.trim().length !== 0 ? value : undefined;
}

/** Finds the line of a label's first instruction: the label's own line if code follows it, else the next code line. */
export function labelLine(text: string, label: string): number | undefined {
    const lines = text.split(/\r?\n/);
    const name = label.toUpperCase();
    const index = lines.findIndex(line => {
        const match = /^([A-Za-z_.@][\w.@$%]*):/.exec(line);
        return match !== null && match[1].toUpperCase() === name;
    });
    if (index < 0) return undefined;
    for (let line = index; line < lines.length; line++) {
        const code = (line === index ? lines[line].slice(lines[line].indexOf(":") + 1) : lines[line]).split(";")[0].trim();
        if (code.length === 0 || /^[A-Za-z_.@][\w.@$%]*:$/.test(code)) continue;
        return line;
    }
    return undefined;
}

/** Adds a launch configuration's "breakpoints" as ordinary editor breakpoints, once each, before the session starts. */
export function registerLaunchBreakpoints(context: vscode.ExtensionContext): void {
    context.subscriptions.push(vscode.debug.registerDebugConfigurationProvider("retrocore", {
        resolveDebugConfigurationWithSubstitutedVariables(_folder, configuration) {
            const wanted: unknown = configuration.breakpoints;
            if (!Array.isArray(wanted)) return configuration;
            const existing = vscode.debug.breakpoints.filter((item): item is vscode.SourceBreakpoint => item instanceof vscode.SourceBreakpoint);
            const functions = vscode.debug.breakpoints.filter((item): item is vscode.FunctionBreakpoint => item instanceof vscode.FunctionBreakpoint);
            const added: vscode.Breakpoint[] = [];
            for (const item of wanted as LaunchBreakpoint[]) {
                const condition = text(item?.condition);
                const hitCondition = text(item?.hitCondition);
                const logMessage = text(item?.logMessage);
                const name = text(item?.function);
                if (name !== undefined) {
                    if (!functions.some(breakpoint => breakpoint.functionName === name)) {
                        added.push(new vscode.FunctionBreakpoint(name, true, condition, hitCondition, logMessage));
                    }
                    continue;
                }
                if (typeof item?.path !== "string" || !fs.existsSync(item.path)) {
                    void vscode.window.showWarningMessage(`Retrocore: launch breakpoint file not found: ${String(item?.path)}`);
                    continue;
                }
                const line = typeof item.line === "number" ? item.line - 1
                    : typeof item.label === "string" ? labelLine(fs.readFileSync(item.path, "utf8"), item.label) : undefined;
                if (line === undefined) {
                    void vscode.window.showWarningMessage(`Retrocore: launch breakpoint ${String(item.label ?? item.line)} not found in ${item.path}`);
                    continue;
                }
                const uri = vscode.Uri.file(item.path);
                const present = existing.some(breakpoint =>
                    breakpoint.location.uri.fsPath.toLowerCase() === uri.fsPath.toLowerCase() && breakpoint.location.range.start.line === line);
                if (!present) {
                    added.push(new vscode.SourceBreakpoint(new vscode.Location(uri, new vscode.Position(line, 0)), true, condition, hitCondition, logMessage));
                }
            }
            if (added.length !== 0) vscode.debug.addBreakpoints(added);
            return configuration;
        }
    }));
}
