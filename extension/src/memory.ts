// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Memory views: Retrocore Memory, a custom editor for retrocore-memory URIs, which name a session and a memory
// reference, and which reads through the debug host's retro/memory/read and writes through writeMemory. The Open Memory command
// picks memory as the CPU maps it or one of the machine's banks, such as the IIe's auxiliary RAM, and an address
// in it, and the Variables and Watch views open an address from their context menus. Bookmarks, names for addresses,
// are kept in the workspace's state for each launch configuration, since they record where someone was looking.

import * as vscode from "vscode";
import { randomBytes } from "node:crypto";
import { addressAt, bookmarkStore, breakpointAt, breakpointName, cpuWatches, hex, intelHex, parseIntelHex, parseReference, referenceIn, resolveIn, withBookmark, type MemoryBookmark } from "./memoryModel";
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

/** Opens a memory reference of a session in Retrocore Memory, in a column if given. */
export async function openMemory(session: vscode.DebugSession, memoryReference: string, viewColumn?: vscode.ViewColumn): Promise<void> {
    await vscode.commands.executeCommand("vscode.openWith", memoryUri(session, memoryReference), memoryViewType,
        viewColumn === undefined ? undefined : { viewColumn, preserveFocus: true });
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
// Saves a range the page sends its bytes for, in the form the file's extension asks: Intel HEX for .hex and .ihx,
// native assembly from the debugger for .asm and .s, and the bytes as they are for anything else.
async function saveRange(session: vscode.DebugSession, base: string, received: { [key: string]: unknown }): Promise<unknown> {
    const offset = Number(received.offset), data = received.data as number[];
    const span = `${hex(offset, 4)}-${hex(offset + data.length - 1, 4)}`;
    const folder = vscode.workspace.workspaceFolders?.[0]?.uri;
    const chosen = await vscode.window.showSaveDialog({
        title: `Save $${span} (${data.length} bytes)`,
        defaultUri: folder === undefined ? undefined : vscode.Uri.joinPath(folder, `memory-${span}.bin`),
        filters: { "Binary": ["bin"], "Intel HEX": ["hex", "ihx"], "Native assembly": ["asm", "s"], "All files": ["*"] },
        saveLabel: "Save"
    });
    if (chosen === undefined) return { cancelled: true };
    const extension = chosen.path.slice(chosen.path.lastIndexOf(".") + 1).toLowerCase();
    let contents: Uint8Array, form: string, exact: boolean | undefined;
    if (extension === "hex" || extension === "ihx") {
        contents = Buffer.from(intelHex(data, offset), "latin1");
        form = "Intel HEX";
    } else if (extension === "asm" || extension === "s") {
        const exported = await session.customRequest("retro/memory/export", { memoryReference: base, address: offset, count: data.length, starts: received.starts }) as { source: string; exact: boolean };
        contents = Buffer.from(exported.source, "utf8");
        form = "assembly";
        exact = exported.exact;
    } else {
        contents = Uint8Array.from(data);
        form = "bytes";
    }
    await vscode.workspace.fs.writeFile(chosen, contents);
    return { path: vscode.workspace.asRelativePath(chosen), form, exact };
}

// Reads a file to load into memory: Intel HEX, by its .hex or .ihx extension, as the runs of bytes it gives
// addresses, or any other file's bytes as they are, which the page writes at the cursor.
async function loadFile(): Promise<unknown> {
    const folder = vscode.workspace.workspaceFolders?.[0]?.uri;
    const chosen = await vscode.window.showOpenDialog({
        title: "Load into memory",
        defaultUri: folder,
        canSelectMany: false,
        filters: { "Binary or Intel HEX": ["bin", "hex", "ihx"], "All files": ["*"] },
        openLabel: "Load"
    });
    if (chosen === undefined || chosen.length === 0) return { cancelled: true };
    const bytes = await vscode.workspace.fs.readFile(chosen[0]);
    const name = vscode.workspace.asRelativePath(chosen[0]);
    const extension = chosen[0].path.slice(chosen[0].path.lastIndexOf(".") + 1).toLowerCase();
    if (extension === "hex" || extension === "ihx") {
        const runs = parseIntelHex(Buffer.from(bytes).toString("latin1"));
        if (typeof runs === "string") throw new Error(`${name}: ${runs}`);
        return { name, runs };
    }
    if (bytes.length > 0x10000) throw new Error(`${name} is ${bytes.length} bytes, more than the 64K memory holds.`);
    return { name, data: Array.from(bytes) };
}

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
    /** Points the editor at the session again when VS Code restarts it, which keeps its id. */
    rebind: (session: vscode.DebugSession) => void;
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

/**
 * The workspace state key bookmarks are kept under: pairs of a launch configuration's name and its bookmarks, a list
 * rather than an object so that any name, such as constructor or __proto__, is only a name.
 */
const bookmarksKey = "retrocore.memory.bookmarks";

/** Where a bookmark is, as the page writes addresses: $0400, or aux:$0400 in a bank. */
function bookmarkWhere(bookmark: MemoryBookmark): string {
    return `${bookmark.bank === null ? "" : `${bookmark.bank}:`}$${hex(bookmark.address, 4)}`;
}

const blankPage = (text: string) => `<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'"></head>
<body style="font-family:var(--vscode-font-family);color:var(--vscode-foreground);padding:12px">${text}</body></html>`;

/** The requests whose responses change where breakpoints stop, after which the listings show them again. */
const breakpointCommands = new Set(["setBreakpoints", "setFunctionBreakpoints", "setInstructionBreakpoints"]);

/**
 * Toggles a breakpoint at an address of a view's bank from the listing's gutter: takes away the function breakpoint
 * it set there and any other the debugger says stops there (ids), or, with none, sets one. Returns what it did.
 */
async function toggleBreakpoint(session: vscode.DebugSession, bank: string | null, address: number, ids: number[]): Promise<string> {
    const found: vscode.Breakpoint[] = [];
    for (const breakpoint of vscode.debug.breakpoints) {
        if (breakpoint instanceof vscode.FunctionBreakpoint && breakpointAt(breakpoint.functionName, bank, address)) {
            found.push(breakpoint);
            continue;
        }
        if (ids.length === 0) continue;
        const known = await session.getDebugProtocolBreakpoint(breakpoint);
        if (known !== undefined && "id" in known && typeof known.id === "number" && ids.includes(known.id)) found.push(breakpoint);
    }

    const name = breakpointName(bank, address);
    if (found.length > 0) {
        vscode.debug.removeBreakpoints(found);
        return `Took the breakpoint at ${name} away.`;
    }

    // One VS Code has no breakpoint for, as the Disassembly view's are, is taken away where it was set.
    if (ids.length > 0) throw new Error(`The breakpoint at ${name} was set in the Disassembly view; take it away there.`);
    vscode.debug.addBreakpoints([new vscode.FunctionBreakpoint(name)]);
    return `Breakpoint at ${name}.`;
}

/** Registers Retrocore Memory and the commands that open it. */
export function registerMemory(context: vscode.ExtensionContext): void {
    // Sessions by id, since a memory URI names its session and VS Code lists only the active one.
    const sessions = new Map<string, vscode.DebugSession>();
    const subscriptionSessions = new Set<string>();
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
    // The bookmarks of a session's launch configuration, and of one space of them as a page shows them.
    const bookmarks = (session: vscode.DebugSession): MemoryBookmark[] =>
        bookmarkStore(context.workspaceState.get<unknown>(bookmarksKey)).get(session.configuration.name) ?? [];
    const bookmarksIn = (session: vscode.DebugSession, reference: string) =>
        bookmarks(session).filter(item => bankBase(item.bank) === reference).map(item => ({ name: item.name, address: item.address }));
    // Keeps a launch configuration's bookmarks and shows them in every editor of its sessions.
    const keepBookmarks = async (session: vscode.DebugSession, list: MemoryBookmark[]): Promise<void> => {
        const all = bookmarkStore(context.workspaceState.get<unknown>(bookmarksKey));
        if (list.length === 0) all.delete(session.configuration.name);
        else all.set(session.configuration.name, list);
        await context.workspaceState.update(bookmarksKey, [...all]);
        for (const editor of editors) {
            if (editor.session.configuration.name === session.configuration.name) {
                void editor.panel.webview.postMessage({ type: "bookmarks", bookmarks: bookmarksIn(editor.session, editor.reference) });
            }
        }
    };
    context.subscriptions.push(vscode.debug.onDidStartDebugSession(session => sessions.set(session.id, session)));

    // A session's editors close when it ends, as their memory is gone. VS Code restarts a session by ending it with
    // restart set and starting it again with the same id, so a restart's editors stay, and read the new machine once
    // the debugger has its configuration.
    const restarting = new Set<string>();
    const restarted = new Set<string>();
    context.subscriptions.push(vscode.debug.onDidTerminateDebugSession(session => {
        sessions.delete(session.id);
        subscriptionSessions.delete(session.id);
        for (const editor of editors) {
            if (editor.session.id === session.id) void editor.panel.webview.postMessage({ type: "ended" });
        }
        if (restarting.delete(session.id)) {
            restarted.add(session.id);
            return;
        }
        restarted.delete(session.id);
        const tabs = vscode.window.tabGroups.all.flatMap(group => group.tabs).filter(tab =>
            tab.input instanceof vscode.TabInputCustom && tab.input.uri.scheme === memoryScheme && tab.input.uri.authority === session.id);
        if (tabs.length > 0) void vscode.window.tabGroups.close(tabs, true);
    }));

    // A memory event names the reference of a view whose bytes changed; that view reads them again.
    context.subscriptions.push(vscode.debug.registerDebugAdapterTrackerFactory("retrocore", {
        createDebugAdapterTracker(session) {
            sessions.set(session.id, session);
            return {
                onWillReceiveMessage(received: unknown) {
                    // VS Code asks the debugger to end the session with restart set when it restarts it.
                    if (typeof received !== "object" || received === null || !("command" in received)) return;
                    if (received.command !== "disconnect" && received.command !== "terminate") return;
                    const restart = "arguments" in received && typeof received.arguments === "object" && received.arguments !== null
                        && "restart" in received.arguments && received.arguments.restart === true;
                    if (restart) restarting.add(session.id);
                    else restarting.delete(session.id);
                },
                onDidSendMessage(sent: unknown) {
                    if (typeof sent !== "object" || sent === null) return;
                    if ("command" in sent && sent.command === "initialize" && "body" in sent
                        && typeof sent.body === "object" && sent.body !== null
                        && "supportsRetrocoreMemorySubscriptions" in sent.body
                        && sent.body.supportsRetrocoreMemorySubscriptions === true) {
                        subscriptionSessions.add(session.id);
                    }

                    // A restarted session is ready for its editors once the debugger has its configuration.
                    if ("command" in sent && sent.command === "configurationDone" && restarted.delete(session.id)) {
                        for (const editor of editors) {
                            if (editor.session.id !== session.id) continue;
                            editor.rebind(session);
                            void editor.panel.webview.postMessage({ type: "restarted" });
                        }
                        return;
                    }

                    // Breakpoints set anywhere, from a source's gutter, the Breakpoints view, the Disassembly view or
                    // a listing's, show in the listings once the debugger has them.
                    if ("command" in sent && typeof sent.command === "string" && breakpointCommands.has(sent.command)) {
                        for (const editor of editors) {
                            if (editor.session.id === session.id) void editor.panel.webview.postMessage({ type: "breakpoints" });
                        }
                        return;
                    }

                    if (!("event" in sent)) return;

                    // The debugger moves or binds breakpoints itself too, as when a module loads.
                    if (sent.event === "breakpoint") {
                        for (const editor of editors) {
                            if (editor.session.id === session.id) void editor.panel.webview.postMessage({ type: "breakpoints" });
                        }
                        return;
                    }

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
            const found = uri.scheme === memoryScheme ? sessions.get(uri.authority) ?? (vscode.debug.activeDebugSession?.id === uri.authority ? vscode.debug.activeDebugSession : undefined) : undefined;
            if (found?.type !== "retrocore") {
                // A tab whose session is gone, as VS Code restores after a reload or in a new window, closes: its
                // memory is gone with the machine.
                panel.webview.html = blankPage("Retrocore Memory shows memory while its Retrocore debug session runs; this one has ended.");
                const tabs = vscode.window.tabGroups.all.flatMap(group => group.tabs).filter(tab =>
                    tab.input instanceof vscode.TabInputCustom && tab.input.uri.toString() === uri.toString());
                if (tabs.length > 0) void vscode.window.tabGroups.close(tabs, true);
                return;
            }
            // A restart keeps the session's id but can give a new session object, which rebind points the editor at.
            let session: vscode.DebugSession = found;

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
            const subscriber = subscriptionSessions.has(session.id) ? randomBytes(16).toString("hex") : undefined;
            let disposed = false;
            let ready!: () => void;
            const editor: MemoryEditor = {
                session, reference: base, panel, tests: new Map(),
                rebind: restartedSession => {
                    session = restartedSession;
                    editor.session = restartedSession;
                },
                ready: new Promise<void>(resolve => { ready = resolve; })
            };
            editors.add(editor);
            lastEditor = editor;
            panel.onDidChangeViewState(() => { if (panel.active) lastEditor = editor; });
            panel.onDidDispose(() => {
                disposed = true;
                editors.delete(editor);
                if (lastEditor === editor) lastEditor = undefined;
                if (subscriber !== undefined && sessions.has(session.id)) {
                    void session.customRequest("retro/memory/unsubscribe", { subscriber })
                        .then(undefined, error => vscode.window.showErrorMessage(`Retrocore: ${message(error)}`));
                }
            });
            const icons = vscode.Uri.joinPath(context.extensionUri, "media", "codicons");
            panel.webview.options = { enableScripts: true, localResourceRoots: [icons] };
            panel.webview.onDidReceiveMessage(async (received: { type: string; id?: number; [key: string]: unknown }) => {
                if (received.type === "ready") {
                    await panel.webview.postMessage({
                        type: "init",
                        address: start.address,
                        info: { bank: start.bank, label: bank.label, readOnly: bank.readOnly, bigEndian: bank.bigEndian === true },
                        bookmarks: bookmarksIn(session, base)
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
                            await reply(await session.customRequest("retro/memory/read", { memoryReference: base, offset: received.offset, count: received.count, subscriber }));
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
                                })),
                                // Every space, this editor's among them, for the toolbar's space list.
                                spaces: banks.map(item => ({
                                    name: item.name,
                                    label: item.name === null ? item.label : `${item.label} (${item.name})`
                                }))
                            });
                            break;
                        }
                        case "switch": {
                            // Another space in this editor's place: it opens at the cursor's address, and this closes.
                            const name = received.bank === null ? null : String(received.bank);
                            await reply(null);
                            if (name === start.bank) break;
                            const column = panel.viewColumn;
                            await openMemory(session, `${name === null ? "" : `${name}:`}0x${hex(Number(received.address), 4)}`, column);
                            const own = vscode.window.tabGroups.all.flatMap(group => group.tabs).filter(tab =>
                                tab.input instanceof vscode.TabInputCustom && tab.input.uri.toString() === document.uri.toString()
                                && tab.group.viewColumn === column);
                            if (own.length > 0) await vscode.window.tabGroups.close(own, true);
                            break;
                        }
                        case "readOther": {
                            // Only a bank the machine has, as the page lists them.
                            const reference = String(received.reference);
                            const { banks } = await session.customRequest("retro/memoryBanks") as { banks: MemoryBank[] };
                            if (!banks.some(item => bankBase(item.name) === reference)) throw new Error(`The machine has no memory bank at ${reference} now.`);
                            if (disposed) break;
                            await reply(await session.customRequest("retro/memory/read", { memoryReference: reference, offset: received.offset, count: received.count, subscriber }));
                            break;
                        }
                        case "labels":
                            await reply(await session.customRequest("retro/memory/labels", { memoryReference: base }));
                            break;
                        case "map":
                            await reply(await session.customRequest("retro/memory/map", { memoryReference: base }));
                            break;
                        case "inspect":
                            await reply(await session.customRequest("retro/memory/inspect", {
                                memoryReference: base,
                                address: received.address,
                                starts: received.starts
                            }));
                            break;
                        case "listing":
                            await reply(await session.customRequest("retro/memory/listing", {
                                memoryReference: base,
                                address: received.address,
                                count: received.count,
                                starts: received.starts
                            }));
                            break;
                        case "find":
                            // An instruction such as STA $C0??, which the debugger decodes.
                            await reply(await session.customRequest("retro/memory/find", {
                                memoryReference: base,
                                pattern: received.pattern,
                                from: received.from,
                                backward: received.backward
                            }));
                            break;
                        case "breakpoint": {
                            // What stops at the address is asked again, not taken from the page's listing, which may
                            // be from before a breakpoint moved; a start there makes a line begin at it.
                            const address = Number(received.address);
                            const now = await session.customRequest("retro/memory/listing", {
                                memoryReference: base,
                                address,
                                count: 1,
                                starts: [address]
                            }) as { lines?: { address: number; breakpoints: number[] | null }[] };
                            const line = (now.lines ?? []).find(item => item.address === address);
                            await reply({ status: await toggleBreakpoint(session, start.bank, address, line?.breakpoints ?? []) });
                            break;
                        }
                        case "starts":
                            // The Decode from here starts a mark leaves.
                            await reply(await session.customRequest("retro/memory/starts", {
                                memoryReference: base,
                                address: received.address,
                                count: received.count,
                                starts: received.starts,
                                keep: received.keep
                            }));
                            break;
                        case "mark": {
                            // Mark as code or data, or a name or comment, which asks for its text, kept in the hints file.
                            const args: Record<string, unknown> = { memoryReference: base, address: received.address, count: received.count };
                            if (received.kind !== undefined) {
                                args.kind = received.kind;
                            } else {
                                const naming = received.what === "name";
                                // What the hints file has now, whatever the page has listed.
                                const note = await session.customRequest("retro/memory/note", { memoryReference: base, address: received.address }) as { name: string | null; comment: string | null };
                                const text = await vscode.window.showInputBox({
                                    title: (naming ? "Name " : "Comment on ") + "$" + Number(received.address).toString(16).toUpperCase().padStart(4, "0"),
                                    prompt: naming ? "A label for this address; empty takes the name away." : "A comment for this address; empty takes it away.",
                                    value: (naming ? note.name : note.comment) ?? ""
                                });
                                if (text === undefined) {
                                    await reply({ cancelled: true });
                                    break;
                                }
                                args[naming ? "name" : "comment"] = text;
                            }
                            type Marked = { needsFile?: boolean; path?: string; address?: number; count?: number };
                            let marked = await session.customRequest("retro/memory/mark", args) as Marked;
                            if (marked.needsFile) {
                                // A launch with no program or source to keep marks beside asks where, once.
                                const chosen = await vscode.window.showSaveDialog({
                                    title: "Keep marks, names and comments in",
                                    filters: { "Hints": ["json"] },
                                    saveLabel: "Keep here"
                                });
                                if (chosen === undefined) {
                                    await reply({ cancelled: true });
                                    break;
                                }
                                marked = await session.customRequest("retro/memory/mark", { ...args, hints: chosen.fsPath }) as Marked;
                            }
                            await reply(marked);
                            // Other editors on the same space show the same labels and listing.
                            others(editor, { type: "marked", kind: received.kind, address: marked.address, count: marked.count });
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
                        case "numbers":
                            // A number's bytes as the BASIC's floats, which Find looks for.
                            await reply(await session.customRequest("retro/memory/numbers", { memoryReference: base, value: received.value }));
                            break;
                        case "assemble": {
                            // An instruction to type over the line at an address, checked as it is typed: its bytes
                            // and what they decode to, or why it does not assemble.
                            const address = Number(received.address);
                            const at = bookmarkWhere({ name: "", bank: start.bank, address });
                            const assemble = (line: string) => session.customRequest("retro/memory/assemble", { memoryReference: base, address, line });
                            const line = await vscode.window.showInputBox({
                                title: `Assemble at ${at}`,
                                prompt: "An instruction in the CPU's syntax, with the session's labels, such as LDA KBD or JSR COUT.",
                                value: typeof received.text === "string" ? received.text : "",
                                validateInput: async value => {
                                    if (value.trim().length === 0) return null;
                                    try {
                                        const result = await assemble(value);
                                        const shown = (result.bytes as number[]).map(byte => byte.toString(16).toUpperCase().padStart(2, "0")).join(" ");
                                        return { message: `${shown}${result.text ? `: ${result.text}` : ""}`, severity: vscode.InputBoxValidationSeverity.Info };
                                    } catch (error) {
                                        return error instanceof Error ? error.message : String(error);
                                    }
                                }
                            });
                            if (line === undefined || line.trim().length === 0) {
                                await reply({ cancelled: true });
                                break;
                            }
                            await reply({ ...(await assemble(line)), line: line.trim() });
                            break;
                        }
                        case "confirm": {
                            // A question the page asks before it writes, with its answers; null when dismissed.
                            const actions = Array.isArray(received.actions) ? received.actions.map(String) : [];
                            const choice = await vscode.window.showWarningMessage(String(received.message), { modal: true }, ...actions);
                            await reply({ choice: choice ?? null });
                            break;
                        }
                        case "bookmark": {
                            // Names the address, renames its bookmark, or with an empty name removes it.
                            const address = Number(received.address);
                            const here = bookmarks(session).find(item => item.bank === start.bank && item.address === address);
                            const at = bookmarkWhere({ name: "", bank: start.bank, address });
                            const name = await vscode.window.showInputBox({
                                title: `Bookmark ${at}`,
                                prompt: here === undefined ? "A name for this bookmark." : "A new name for this bookmark; empty removes it.",
                                value: here?.name ?? (typeof received.name === "string" ? received.name : at)
                            });
                            if (name === undefined || (here === undefined && name.trim().length === 0)) {
                                await reply({ cancelled: true });
                                break;
                            }
                            await keepBookmarks(session, withBookmark(bookmarks(session), start.bank, address, name));
                            await reply({ bookmarks: bookmarksIn(session, base) });
                            break;
                        }
                        case "bookmarks": {
                            // A quick pick of the launch configuration's bookmarks, each with a button to remove it.
                            if (bookmarks(session).length === 0) {
                                await reply({ none: true });
                                break;
                            }
                            type Item = vscode.QuickPickItem & { bookmark: MemoryBookmark };
                            const remove: vscode.QuickInputButton = { iconPath: new vscode.ThemeIcon("trash"), tooltip: "Remove this bookmark" };
                            const items = (): Item[] => bookmarks(session).map(bookmark => ({
                                label: bookmark.name, description: bookmarkWhere(bookmark), buttons: [remove], bookmark
                            }));
                            const pick = vscode.window.createQuickPick<Item>();
                            pick.title = "Go to a bookmark";
                            pick.placeholder = "A bookmark's name or address";
                            pick.matchOnDescription = true;
                            pick.items = items();
                            const chosen = await new Promise<MemoryBookmark | undefined>(resolve => {
                                pick.onDidTriggerItemButton(async event => {
                                    const gone = event.item.bookmark;
                                    await keepBookmarks(session, withBookmark(bookmarks(session), gone.bank, gone.address, ""));
                                    pick.items = items();
                                    if (pick.items.length === 0) pick.hide();
                                });
                                pick.onDidAccept(() => {
                                    resolve(pick.selectedItems[0]?.bookmark);
                                    pick.hide();
                                });
                                pick.onDidHide(() => resolve(undefined));
                                pick.show();
                            });
                            pick.dispose();
                            if (chosen === undefined || bankBase(chosen.bank) === base) {
                                await reply({ bookmarks: bookmarksIn(session, base), address: chosen?.address, name: chosen?.name });
                                break;
                            }
                            // A bookmark in another space: an editor showing that space goes there, else one opens.
                            await reply({ bookmarks: bookmarksIn(session, base) });
                            const showing = [...editors].find(item => item.session.id === session.id && item.reference === bankBase(chosen.bank));
                            if (showing !== undefined) {
                                showing.panel.reveal();
                                await showing.panel.webview.postMessage({ type: "goto", address: chosen.address });
                            } else {
                                await openMemory(session, `${chosen.bank === null ? "" : `${chosen.bank}:`}0x${hex(chosen.address, 4)}`);
                            }
                            break;
                        }
                        case "copy":
                            await vscode.env.clipboard.writeText(String(received.text));
                            await reply(null);
                            break;
                        case "paste":
                            await reply({ text: await vscode.env.clipboard.readText() });
                            break;
                        case "input": {
                            // A value for the page to write, such as a word from the inspector or a fill's pattern.
                            const text = await vscode.window.showInputBox({
                                title: String(received.title),
                                prompt: typeof received.prompt === "string" ? received.prompt : undefined,
                                value: typeof received.value === "string" ? received.value : ""
                            });
                            await reply(text === undefined ? { cancelled: true } : { text });
                            break;
                        }
                        case "pick": {
                            // One of the page's choices, such as Copy as's forms.
                            const items = (received.items as { label: string; detail?: string }[]).map((item, index) => ({ label: item.label, detail: item.detail, index }));
                            const picked = await vscode.window.showQuickPick(items, { title: String(received.title) });
                            await reply(picked === undefined ? { cancelled: true } : { index: picked.index });
                            break;
                        }
                        case "save":
                            await reply(await saveRange(session, base, received));
                            break;
                        case "load":
                            await reply(await loadFile());
                            break;
                    }
                } catch (error) {
                    await panel.webview.postMessage({ type: "reply", id: received.id, error: message(error) });
                }
            });
            panel.webview.html = memoryEditorHtml(randomBytes(16).toString("hex"), {
                cspSource: panel.webview.cspSource,
                codicons: panel.webview.asWebviewUri(vscode.Uri.joinPath(icons, "codicon.css")).toString()
            });
        }
    };
    context.subscriptions.push(vscode.window.registerCustomEditorProvider(memoryViewType, provider, {
        webviewOptions: { retainContextWhenHidden: true },
        supportsMultipleEditorsPerDocument: true
    }));

    // Tabs VS Code restored from before this window's extension host started, even ones not shown yet, belong to
    // sessions that have ended with it.
    const stale = vscode.window.tabGroups.all.flatMap(group => group.tabs).filter(tab =>
        tab.input instanceof vscode.TabInputCustom && tab.input.uri.scheme === memoryScheme && !sessions.has(tab.input.uri.authority));
    if (stale.length > 0) void vscode.window.tabGroups.close(stale, true);

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
