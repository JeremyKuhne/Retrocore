// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Memory views: Retrocore Memory, a custom editor for retrocore-memory URIs, which name a session and a memory
// reference, and which reads through the debug host's retro/memory/read and writes through writeMemory. The Open Memory command
// picks memory as the CPU maps it or one of the machine's banks, such as the IIe's auxiliary RAM, and an address
// in it, and the Variables and Watch views open an address from their context menus.

import * as vscode from "vscode";
import { randomBytes } from "node:crypto";
import { addressAt, cpuWatches, hex, parseReference, referenceIn, resolveIn } from "./memoryModel";
import { memoryEditorHtml } from "./memoryView";

/** Memory as the CPU maps it, or a bank, as the debug host's retro/memoryBanks describes it. */
/** A bank's reference from $0000, which a memory view reads its bytes by: 0x0000 for the CPU's memory. */
function bankBase(name: string | null): string {
    return name === null ? "0x0000" : `${name}:0x0000`;
}

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
    /** Whether it is a coprocessor's address space, such as the SoftCard's Z80's. */
    coprocessor?: boolean;
    /** Whether its CPU keeps a word's high byte first, as the 6809 does. */
    bigEndian?: boolean;
}

/** Retrocore Memory's view type. */
export const memoryViewType = "retrocore.memory";

/**
 * The scheme of Retrocore Memory's URIs. Nothing reads them as files: the editor takes the session and memory
 * reference from them, and the bytes come from the debugger. Its own scheme keeps the editor off real files.
 */
export const memoryScheme = "retrocore-memory";

/** The tab title of a memory reference, such as Memory $3C00 or Memory aux:$0400. */
export function memoryTitle(memoryReference: string): string {
    return `Memory ${memoryReference.replace(/0x([0-9a-f]+)$/i, (_, digits: string) => `$${digits.toUpperCase().padStart(4, "0")}`)}`;
}

/** The URI Retrocore Memory opens a memory reference of a session at: the reference, then the tab's title. */
export function memoryUri(session: vscode.DebugSession, memoryReference: string): vscode.Uri {
    return vscode.Uri.from({
        scheme: memoryScheme,
        authority: session.id,
        path: `/${memoryReference}/${memoryTitle(memoryReference)}`
    });
}

/** Opens a memory reference of a session in Retrocore Memory. */
export async function openMemory(session: vscode.DebugSession, memoryReference: string): Promise<void> {
    await vscode.commands.executeCommand("vscode.openWith", memoryUri(session, memoryReference), memoryViewType);
}

export function bankDetail(bank: MemoryBank): string {
    if (bank.name === null) return "$0000-$FFFF as the CPU maps it now";
    const reads = bank.reads === "nowhere" ? undefined : bank.reads;
    const writes = bank.writes === null || bank.writes === "nowhere" ? undefined : bank.writes;
    if (bank.readOnly) return reads === undefined ? "read-only · not mapped now" : `read-only · at ${reads}`;
    if (reads === undefined && writes === undefined) return "not mapped now";
    if (reads === writes) return `at ${reads}`;
    return `${reads === undefined ? "not read" : `read at ${reads}`} · ${writes === undefined ? "not written" : `written at ${writes}`}`;
}

function message(error: unknown): string {
    return error instanceof Error ? error.message : String(error);
}

/** The session's focused stack frame, if one is. */
function focusedFrame(session: vscode.DebugSession): number | undefined {
    const focused = vscode.debug.activeStackItem;
    return focused instanceof vscode.DebugStackFrame && focused.session.id === session.id ? focused.frameId : undefined;
}

/** The memory reference an expression evaluates to in a frame, by default the CPU's, such as a label, an address or HL. */
async function evaluateIn(session: vscode.DebugSession, expression: string, frameId?: number): Promise<string | undefined> {
    return (await session.customRequest("evaluate", { expression, frameId, context: addressContext }) as { memoryReference?: string }).memoryReference;
}

/** The memory reference an expression evaluates to in the focused frame, else in the CPU's; see referenceIn. */
async function evaluateAddress(session: vscode.DebugSession, expression: string): Promise<string | undefined> {
    return await referenceIn((text, frameId) => evaluateIn(session, text, frameId), expression, focusedFrame(session));
}

/** What VS Code passes a Variables or Watch view command: the session, the variable's container and the variable. */
interface OpenVariableItem {
    sessionId?: string;
    container?: { variablesReference?: number };
    variable?: { name?: string; evaluateName?: string; memoryReference?: string };
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

/**
 * The evaluate context Retrocore Memory resolves addresses with. The debugger leaves memory references out of watch
 * and hover results, where VS Code would show its Hex Editor icon, but gives them for this one.
 */
const addressContext = "retrocore";

/** Where an address that memory reference names is, resolving an expression through the debugger. */
async function resolveReference(session: vscode.DebugSession, reference: string): Promise<{ bank: string | null; address: number }> {
    const parsed = parseReference(reference);
    if (parsed !== undefined) return parsed;
    const evaluated = await evaluateAddress(session, reference);
    const resolved = evaluated === undefined ? undefined : parseReference(evaluated);
    if (resolved === undefined) throw new Error(`${reference} is not an address in the CPU's 64K.`);
    return resolved;
}

/**
 * Where an address, label or expression points in a bank, as the focused frame reads it; see resolveIn. A memory
 * reference, such as 0x0400 or 0400, needs no evaluating.
 */
async function addressIn(session: vscode.DebugSession, bank: string | null, text: string): Promise<number> {
    // The bank's own name may lead, as in aux:$0400 in the aux editor.
    if (bank !== null && text.toLowerCase().startsWith(`${bank.toLowerCase()}:`)) text = text.slice(bank.length + 1).trim();
    const parsed = parseReference(bank === null ? text : `${bank}:${text}`);
    if (parsed !== undefined && parsed.bank === bank) return parsed.address;
    const address = await resolveIn((expression, frameId) => evaluateIn(session, expression, frameId), bank, text, focusedFrame(session));
    if (address === undefined) throw new Error(`${text} is not an address in ${bank === null ? "the CPU's 64K" : bank}.`);
    return address;
}

/** Where Go to's text points, in the editor's bank: an address, label or expression, or bare hex digits. */
async function goTo(session: vscode.DebugSession, bank: string | null, text: string): Promise<number> {
    const trimmed = text.trim();
    try {
        return await addressIn(session, bank, trimmed);
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
    // Posts a message to the other editors showing the same session's same space as an editor.
    const others = (editor: MemoryEditor, body: Record<string, unknown>): void => {
        for (const other of editors) {
            if (other !== editor && other.session.id === editor.session.id && other.reference === editor.reference) {
                void other.panel.webview.postMessage(body);
            }
        }
    };
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

                    // While stopped, a card put in or taken out, a reset or BASIC's prompt changes what memory holds,
                    // and may change the labels, the characters and the banks frozen bytes are in. A write, which
                    // invalidates only the variables, tells the views through memory events.
                    if (sent.event === "invalidated") {
                        const areas = "body" in sent && typeof sent.body === "object" && sent.body !== null && "areas" in sent.body ? sent.body.areas : undefined;
                        if (!Array.isArray(areas) || !areas.includes("all")) return;
                        for (const editor of editors) {
                            if (editor.session.id === session.id) void editor.panel.webview.postMessage({ type: "invalidated" });
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
            const session = uri.scheme === memoryScheme ? sessions.get(uri.authority) ?? (vscode.debug.activeDebugSession?.id === uri.authority ? vscode.debug.activeDebugSession : undefined) : undefined;
            if (session?.type !== "retrocore") {
                panel.webview.html = blankPage("Retrocore Memory shows memory while its Retrocore debug session runs; this one has ended.");
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

            const base = bankBase(start.bank);
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
                        info: { bank: start.bank, label: bank.label, readOnly: bank.readOnly, bigEndian: bank.bigEndian === true }
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
                        case "banks": {
                            // The other banks this editor's bytes can be compared with, read now, as a card can go in.
                            // Each is read from $0000, as this editor's own is, so its bytes line up by address; the
                            // machine's references, such as bank1:0xD000, start where the bank does.
                            const { banks } = await session.customRequest("retro/memoryBanks") as { banks: MemoryBank[] };
                            await reply({
                                banks: banks.filter(item => item.name !== start.bank).map(item => ({
                                    memoryReference: bankBase(item.name),
                                    label: item.name === null ? item.label : `${item.label} (${item.name})`
                                }))
                            });
                            break;
                        }
                        case "readOther": {
                            // Only a bank the machine has, as the page lists them.
                            const reference = String(received.reference);
                            const { banks } = await session.customRequest("retro/memoryBanks") as { banks: MemoryBank[] };
                            if (!banks.some(item => bankBase(item.name) === reference)) throw new Error(`The machine has no memory bank at ${reference} now.`);
                            await reply(await session.customRequest("retro/memory/read", { memoryReference: reference, offset: received.offset, count: received.count }));
                            break;
                        }
                        case "labels":
                            await reply(await session.customRequest("retro/memory/labels", { memoryReference: base }));
                            break;
                        case "listing":
                            await reply(await session.customRequest("retro/memory/listing", {
                                memoryReference: base,
                                address: received.address,
                                count: received.count,
                                starts: received.starts
                            }));
                            break;
                        case "mark": {
                            // Mark as code or data, or a name or comment, which asks for its text, kept in the hints file.
                            const args: Record<string, unknown> = { memoryReference: base, address: received.address, count: received.count };
                            if (received.kind !== undefined) {
                                args.kind = received.kind;
                            } else {
                                const naming = received.what === "name";
                                const text = await vscode.window.showInputBox({
                                    title: (naming ? "Name " : "Comment on ") + "$" + Number(received.address).toString(16).toUpperCase().padStart(4, "0"),
                                    prompt: naming ? "A label for this address; empty takes the name away." : "A comment for this address; empty takes it away.",
                                    value: String(received.value ?? "")
                                });
                                if (text === undefined) {
                                    await reply({ cancelled: true });
                                    break;
                                }
                                args[naming ? "name" : "comment"] = text;
                            }
                            await reply(await session.customRequest("retro/memory/mark", args));
                            break;
                        }
                        case "open": {
                            // A listing line's source, beside the editor, at its line.
                            const line = Math.max(0, Number(received.line) - 1);
                            await vscode.window.showTextDocument(vscode.Uri.file(String(received.path)), {
                                viewColumn: vscode.ViewColumn.Beside,
                                selection: new vscode.Range(line, 0, line, 0)
                            });
                            await reply(null);
                            break;
                        }
                        case "characters":
                            await reply(await session.customRequest("retro/memory/characters"));
                            break;
                        case "freeze": {
                            const result = await session.customRequest("retro/memory/freeze", { memoryReference: base, freeze: received.freeze, thaw: received.thaw }) as { frozen: unknown };
                            await reply(result);
                            // Other editors on the same space show the same frozen bytes.
                            others(editor, { type: "frozen", frozen: result.frozen });
                            break;
                        }
                        case "watch": {
                            // The CPU's view watches cpu:$0400 on a machine with a coprocessor; see cpuWatches. The
                            // banks are read now, as a SoftCard can go in after the editor opens.
                            let expressions = received.expressions as string[];
                            if (start.bank === null) {
                                const { banks } = await session.customRequest("retro/memoryBanks") as { banks: MemoryBank[] };
                                expressions = cpuWatches(expressions, banks.some(item => item.coprocessor === true));
                            }
                            // VS Code's own Add to Watch, which takes a variable's evaluate name; there is no API for it.
                            for (const expression of expressions) {
                                await vscode.commands.executeCommand("debug.addToWatchExpressions", { variable: { evaluateName: expression } });
                            }
                            await reply({ expressions });
                            break;
                        }
                        case "write":
                            await reply(await session.customRequest("writeMemory", {
                                memoryReference: base,
                                offset: received.offset,
                                data: Buffer.from(received.data as number[]).toString("base64")
                            }));
                            // The debugger tells no view of the writer's reference, which other editors on the same
                            // space share, so they read again here.
                            others(editor, { type: "changed" });
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

        // The debug host resolves the expression once, in the focused frame, so the view opens at that address. One
        // that names a bank, such as aux:$0400, opens that bank whichever was picked.
        const typed = /^\s*([A-Za-z][A-Za-z0-9]*)\s*:(.*)$/.exec(address);
        // cpu: names the CPU's memory, which the list has as the bank with no name.
        const prefix = typed?.[1].toLowerCase();
        const named = prefix === undefined ? undefined : banks.find(bank => (bank.name?.toLowerCase() ?? "cpu") === prefix);
        const name = named === undefined ? picked.bank.name : named.name;
        let at: number;
        try {
            at = await addressIn(session, name, (named === undefined || typed === null ? address : typed[2]).trim());
        } catch (error) {
            void vscode.window.showErrorMessage(`Retrocore: ${message(error)}`);
            return;
        }
        await openMemory(session, `${name === null ? "" : `${name}:`}0x${hex(at, 4)}`);
    }));

    // The Variables and Watch views' icon and context menus, on anything that holds an address.
    // The Variables view offers it on variables the debugger marks as holding an address; the Watch view, which has
    // no such mark, on every expression, so one that holds no address says so. The debugger sends neither with its
    // memory reference, which would bring VS Code's Hex Editor icon, so it is asked for here: a variable's by its
    // container and name, an expression's by evaluating it in the focused frame.
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.memory.openVariable", async (item?: OpenVariableItem) => {
        const session = (item?.sessionId === undefined ? undefined : sessions.get(item.sessionId)) ?? vscode.debug.activeDebugSession;
        if (session?.type !== "retrocore") return;
        const variable = item?.variable;
        let memoryReference = variable?.memoryReference;
        try {
            if (memoryReference === undefined && variable?.name !== undefined && item?.container?.variablesReference) {
                memoryReference = (await session.customRequest("retro/memory/variable", {
                    variablesReference: item.container.variablesReference,
                    name: variable.name
                }) as { memoryReference: string }).memoryReference;
            } else if (memoryReference === undefined && variable?.evaluateName !== undefined) {
                memoryReference = await evaluateAddress(session, variable.evaluateName);
            }
        } catch {
            memoryReference = undefined;
        }

        if (memoryReference === undefined) {
            const name = variable?.evaluateName ?? variable?.name ?? "This";
            void vscode.window.showInformationMessage(`${name} does not hold an address to open in Retrocore Memory.`);
            return;
        }
        await openMemory(session, memoryReference);
    }));

    // The Machine view's Memory rows: memory as the CPU maps it, or a bank, from its start.
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.memory.openReference", async (memoryReference?: string) => {
        const session = vscode.debug.activeDebugSession;
        if (session?.type !== "retrocore" || memoryReference === undefined) return;
        await openMemory(session, memoryReference);
    }));

    // An assembly editor's context menu while debugging: the selection, or the label or address under the cursor.
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.memory.openAtCursor", async () => {
        const session = vscode.debug.activeDebugSession;
        const editor = vscode.window.activeTextEditor;
        if (session?.type !== "retrocore" || editor === undefined) return;
        const selection = editor.selection;
        const expression = selection.isEmpty
            ? addressAt(editor.document.lineAt(selection.active.line).text, selection.active.character)
            : editor.document.getText(selection).trim();
        if (expression === undefined || expression.length === 0) {
            void vscode.window.showInformationMessage("Retrocore: put the cursor on a label or address to open in Retrocore Memory.");
            return;
        }

        let memoryReference: string | undefined;
        try {
            memoryReference = await evaluateAddress(session, expression);
        } catch {
            memoryReference = undefined;
        }
        if (memoryReference === undefined) {
            void vscode.window.showInformationMessage(`Retrocore: ${expression} is not a label or address in the CPU's 64K.`);
            return;
        }
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
