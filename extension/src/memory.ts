// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Memory views: Retrocore Memory, a custom editor for the vscode-debug-memory URIs VS Code gives memory references,
// which reads through the debug host's retro/memory/read and writes through writeMemory. The Open Memory command
// picks memory as the CPU maps it or one of the machine's banks, such as the IIe's auxiliary RAM, and an address
// in it, and the Variables and Watch views open an address from their context menus.

import * as vscode from "vscode";
import { randomBytes } from "node:crypto";
import { parseReference } from "./memoryModel";
import { memoryEditorHtml } from "./memoryView";

/** Memory as the CPU maps it, or a bank, as the debug host's retro/memoryBanks describes it. */
export interface MemoryBank {
    /** The bank's prefix in memory references, such as "aux"; null for memory as the CPU maps it. */
    name: string | null;
    label: string;
    memoryReference: string;
    readOnly: boolean;
    /** Where the memory map reads the bank now, such as "$0000-$01FF, $0400-$07FF", or "nowhere". */
    reads: string;
    /** Where it writes the bank now; null for a read-only bank. */
    writes: string | null;
}

/** Retrocore Memory's view type. */
export const memoryViewType = "retrocore.memory";

/** The URI VS Code's debug memory file system gives a memory reference, as its own View Binary Data opens it. */
export function memoryUri(session: vscode.DebugSession, memoryReference: string, name = "memory", range?: { from: number; to: number }): vscode.Uri {
    return vscode.Uri.from({
        scheme: "vscode-debug-memory",
        authority: session.id,
        path: `/${encodeURIComponent(memoryReference)}/${encodeURIComponent(name)}.bin`,
        query: range ? `?range=${range.from}:${range.to}` : undefined
    });
}

/** Opens a memory reference of a session in Retrocore Memory. */
export async function openMemory(session: vscode.DebugSession, memoryReference: string): Promise<void> {
    await vscode.commands.executeCommand("vscode.openWith", memoryUri(session, memoryReference, memoryReference.replace(":", "-")), memoryViewType);
}

function bankDetail(bank: MemoryBank): string {
    if (bank.name === null) return "$0000-$FFFF as the soft switches map it now";
    if (bank.readOnly) return `read-only · read at ${bank.reads}`;
    return `read at ${bank.reads} · written at ${bank.writes}`;
}

function message(error: unknown): string {
    return error instanceof Error ? error.message : String(error);
}

/** An open Retrocore Memory editor: the session, the reference its reads and writes go through, and its page. */
interface MemoryEditor {
    session: vscode.DebugSession;
    /** The start of the space, such as "0x0000" or "aux:0x0000", which memory events name. */
    reference: string;
    panel: vscode.WebviewPanel;
    ready: Promise<void>;
    tests: Map<number, (reply: { state?: unknown; error?: string }) => void>;
}

/** Where an address that memory reference names is, resolving an expression through the debugger. */
async function resolveReference(session: vscode.DebugSession, reference: string): Promise<{ bank: string | null; address: number }> {
    const parsed = parseReference(reference);
    if (parsed !== undefined) return parsed;
    const evaluated = await session.customRequest("evaluate", { expression: reference, context: "watch" }) as { memoryReference?: string };
    const resolved = evaluated.memoryReference === undefined ? undefined : parseReference(evaluated.memoryReference);
    if (resolved === undefined) throw new Error(`${reference} is not an address in the CPU's 64K.`);
    return resolved;
}

/** Where Go to's text points, in the editor's bank: an address, label or expression, or bare hex digits. */
async function goTo(session: vscode.DebugSession, bank: string | null, text: string): Promise<number> {
    const trimmed = text.trim();
    try {
        return (await resolveReference(session, bank === null ? trimmed : `${bank}:${trimmed}`)).address;
    } catch (error) {
        // Digits alone are hex, as in memory references, unless they name a label.
        if (/^[0-9A-Fa-f]{1,4}$/.test(trimmed)) return parseInt(trimmed, 16);
        throw error;
    }
}

const blankPage = (text: string) => `<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'"></head>
<body style="font-family:var(--vscode-font-family);color:var(--vscode-foreground);padding:12px">${text}</body></html>`;

/** Registers Retrocore Memory and the commands that open it. */
export function registerMemory(context: vscode.ExtensionContext): void {
    // Sessions by id, since a memory URI names its session and VS Code lists only the active one.
    const sessions = new Map<string, vscode.DebugSession>();
    const editors = new Set<MemoryEditor>();
    let lastEditor: MemoryEditor | undefined;
    context.subscriptions.push(vscode.debug.onDidStartDebugSession(session => sessions.set(session.id, session)));
    context.subscriptions.push(vscode.debug.onDidTerminateDebugSession(session => {
        sessions.delete(session.id);
        for (const editor of editors) {
            if (editor.session.id === session.id) void editor.panel.webview.postMessage({ type: "ended" });
        }
    }));

    // A memory event names the reference of a view whose bytes changed; that view reads them again.
    context.subscriptions.push(vscode.debug.registerDebugAdapterTrackerFactory("retrocore", {
        createDebugAdapterTracker(session) {
            sessions.set(session.id, session);
            return {
                onDidSendMessage(sent: unknown) {
                    if (typeof sent !== "object" || sent === null || !("event" in sent)) return;

                    // A stop is when changes are counted from, and when labels and the character set may change.
                    if (sent.event === "stopped") {
                        for (const editor of editors) {
                            if (editor.session.id === session.id) void editor.panel.webview.postMessage({ type: "stopped" });
                        }
                        return;
                    }

                    if (sent.event !== "memory" || !("body" in sent)) return;
                    const body: unknown = sent.body;
                    if (typeof body !== "object" || body === null || !("memoryReference" in body)) return;
                    for (const editor of editors) {
                        if (editor.session.id === session.id && editor.reference === body.memoryReference) {
                            void editor.panel.webview.postMessage({ type: "changed" });
                        }
                    }
                }
            };
        }
    }));

    const provider: vscode.CustomReadonlyEditorProvider = {
        openCustomDocument: uri => ({ uri, dispose: () => undefined }),
        async resolveCustomEditor(document, panel) {
            const uri = document.uri;
            const session = uri.scheme === "vscode-debug-memory" ? sessions.get(uri.authority) ?? (vscode.debug.activeDebugSession?.id === uri.authority ? vscode.debug.activeDebugSession : undefined) : undefined;
            if (session?.type !== "retrocore") {
                panel.webview.html = blankPage(uri.scheme === "vscode-debug-memory"
                    ? "Retrocore Memory shows memory while its Retrocore debug session runs; this one has ended."
                    : "Retrocore Memory shows the memory of a Retrocore debug session. Open this file in another editor.");
                return;
            }

            const reference = decodeURIComponent(uri.path.split("/").filter(part => part.length > 0)[0] ?? "");
            let start: { bank: string | null; address: number };
            let bank: MemoryBank | undefined;
            try {
                start = await resolveReference(session, reference);
                const { banks } = await session.customRequest("retro/memoryBanks") as { banks: MemoryBank[] };
                bank = banks.find(item => item.name === start.bank);
                if (bank === undefined) throw new Error(`The machine has no memory bank named ${start.bank}.`);
            } catch (error) {
                panel.webview.html = blankPage(`Retrocore: ${message(error)}`);
                return;
            }

            const base = start.bank === null ? "0x0000" : `${start.bank}:0x0000`;
            let ready!: () => void;
            const editor: MemoryEditor = {
                session, reference: base, panel, tests: new Map(),
                ready: new Promise<void>(resolve => { ready = resolve; })
            };
            editors.add(editor);
            lastEditor = editor;
            panel.onDidChangeViewState(() => { if (panel.active) lastEditor = editor; });
            panel.onDidDispose(() => {
                editors.delete(editor);
                if (lastEditor === editor) lastEditor = undefined;
            });
            panel.webview.options = { enableScripts: true };
            panel.webview.onDidReceiveMessage(async (received: { type: string; id?: number; [key: string]: unknown }) => {
                if (received.type === "ready") {
                    await panel.webview.postMessage({
                        type: "init",
                        address: start.address,
                        info: { bank: start.bank, label: bank.label, readOnly: bank.readOnly }
                    });
                    ready();
                    return;
                }
                if (received.type === "testDone") {
                    editor.tests.get(received.id ?? 0)?.(received as { state?: unknown; error?: string });
                    editor.tests.delete(received.id ?? 0);
                    return;
                }
                const reply = (result: unknown) => panel.webview.postMessage({ type: "reply", id: received.id, result });
                try {
                    switch (received.type) {
                        case "read":
                            await reply(await session.customRequest("retro/memory/read", { memoryReference: base, offset: received.offset, count: received.count }));
                            break;
                        case "labels":
                            await reply(await session.customRequest("retro/memory/labels", { memoryReference: base }));
                            break;
                        case "characters":
                            await reply(await session.customRequest("retro/memory/characters"));
                            break;
                        case "write":
                            await reply(await session.customRequest("writeMemory", {
                                memoryReference: base,
                                offset: received.offset,
                                data: Buffer.from(received.data as number[]).toString("base64")
                            }));
                            break;
                        case "goto":
                            await reply({ address: await goTo(session, start.bank, String(received.text)) });
                            break;
                        case "copy":
                            await vscode.env.clipboard.writeText(String(received.text));
                            await reply(null);
                            break;
                    }
                } catch (error) {
                    await panel.webview.postMessage({ type: "reply", id: received.id, error: message(error) });
                }
            });
            panel.webview.html = memoryEditorHtml(randomBytes(16).toString("hex"));
        }
    };
    context.subscriptions.push(vscode.window.registerCustomEditorProvider(memoryViewType, provider, {
        webviewOptions: { retainContextWhenHidden: true },
        supportsMultipleEditorsPerDocument: true
    }));

    context.subscriptions.push(vscode.commands.registerCommand("retrocore.memory.open", async () => {
        const session = vscode.debug.activeDebugSession;
        if (session?.type !== "retrocore") {
            void vscode.window.showWarningMessage("Start a Retrocore debug session first.");
            return;
        }

        const { banks } = await session.customRequest("retro/memoryBanks") as { banks: MemoryBank[] };
        const picked = banks.length === 1 ? { bank: banks[0] } : await vscode.window.showQuickPick(banks.map(bank => ({
            label: bank.name ?? "CPU",
            description: bank.label,
            detail: bankDetail(bank),
            bank
        })), { title: "Open memory", matchOnDescription: true });
        if (!picked) return;

        const start = picked.bank.memoryReference.replace(/^[a-z0-9]+:/i, "").replace(/^0x/i, "$");
        const address = await vscode.window.showInputBox({
            title: `Open ${picked.bank.label}`,
            prompt: "An address, label or expression, such as $0400 or TEXT_PAGE",
            value: start
        });
        if (address === undefined || address.trim().length === 0) return;

        // The debug host resolves the expression once, so the view opens at that address.
        const expression = picked.bank.name === null ? address : `${picked.bank.name}:${address}`;
        let memoryReference: string | undefined;
        try {
            memoryReference = (await session.customRequest("evaluate", { expression, context: "watch" }) as { memoryReference?: string }).memoryReference;
        } catch (error) {
            void vscode.window.showErrorMessage(`Retrocore: ${message(error)}`);
            return;
        }
        if (!memoryReference) {
            void vscode.window.showErrorMessage(`Retrocore: ${expression} is not an address in the CPU's 64K.`);
            return;
        }
        await openMemory(session, memoryReference);
    }));

    // The Variables and Watch views' context menus, on anything that holds an address.
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.memory.openVariable", async (item?: { sessionId?: string; variable?: { memoryReference?: string } }) => {
        const session = (item?.sessionId === undefined ? undefined : sessions.get(item.sessionId)) ?? vscode.debug.activeDebugSession;
        const memoryReference = item?.variable?.memoryReference;
        if (session?.type !== "retrocore" || memoryReference === undefined) return;
        await openMemory(session, memoryReference);
    }));

    // The test suite reads the banks through this command.
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.memory.banks", async () => {
        const session = vscode.debug.activeDebugSession;
        if (session?.type !== "retrocore") return [];
        return (await session.customRequest("retro/memoryBanks") as { banks: MemoryBank[] }).banks;
    }));

    // The test suite drives the last memory editor shown, as keys would, and reads where it stands.
    let nextTest = 1;
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.memory.test", async (actions: unknown[]) => {
        const editor = lastEditor;
        if (editor === undefined) throw new Error("No Retrocore Memory editor is open.");
        await editor.ready;
        const id = nextTest++;
        const reply = await new Promise<{ state?: unknown; error?: string }>(resolve => {
            editor.tests.set(id, resolve);
            void editor.panel.webview.postMessage({ type: "test", id, actions });
        });
        if (reply.error !== undefined) throw new Error(reply.error);
        return reply.state;
    }));
}
