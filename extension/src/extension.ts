// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as vscode from "vscode";
import * as path from "node:path";
import { randomBytes } from "node:crypto";
import { shadowCopy, startLanguageClient, stopLanguageClient } from "./languageClient";
import { defaultHost, isBundled } from "./host";
import { registerLaunchBreakpoints } from "./launchBreakpoints";
import { registerDevices } from "./devices";
import { registerSavedMachines } from "./savedMachine";
import { registerMachineMenu } from "./machineMenu";
import { registerStartMachine } from "./startMachine";
import { registerBreakpoints } from "./breakpoints";
import { registerMemory } from "./memory";
import { registerBasic } from "./basic";
import { registerBasicLanguage } from "./basicLanguage";
import { webviewHtml } from "./display";
import { PictureCache } from "./pictures";

export function activate(context: vscode.ExtensionContext): void {
    void startLanguageClient(context);
    registerLaunchBreakpoints(context);
    const basic = registerBasic(context);
    registerDevices(context, basic);
    registerSavedMachines(context);
    registerMachineMenu(context);
    registerStartMachine(context);
    registerBreakpoints(context);
    registerMemory(context);
    registerBasicLanguage(context);
    let panel: vscode.WebviewPanel | undefined;
    // Which screen the panel's tab icon shows, so a run of frames does not set it again each time.
    let panelScreen: string | undefined;
    let displaySession: vscode.DebugSession | undefined;
    // The session the panel last showed, once it has ended: Restart starts its launch again.
    let endedSession: { name: string; configuration: vscode.DebugConfiguration; folder: vscode.WorkspaceFolder | undefined } | undefined;
    // Whether the panel's BASIC button shows, as it was last told.
    let panelBasic: boolean | undefined;
    const showBasicButton = (): void => {
        const available = displaySession !== undefined && basic.summary(displaySession) !== undefined;
        if (panel === undefined || panelBasic === available) return;
        panelBasic = available;
        void panel.webview.postMessage({ basic: available }).then(undefined, showError);
    };
    context.subscriptions.push(basic.onDidChange(showBasicButton));
    const pictures = new PictureCache();
    let cycleLines: CycleLine[] = [];
    let callLines: CycleLine[] = [];
    const cycleDecorations = new Map<number, vscode.TextEditorDecorationType>();
    // A JSR line's latest call goes after the line's text, where it moves nothing, and carries the hover.
    const callDecoration = vscode.window.createTextEditorDecorationType({
        after: { color: new vscode.ThemeColor("editorCodeLens.foreground"), margin: "0 0 0 2em" }
    });
    context.subscriptions.push(callDecoration, { dispose: () => {
        for (const decoration of cycleDecorations.values()) decoration.dispose();
    } });
    const annotate = (): void => {
        const counts = new Set(cycleLines.map(line => line.cycles));
        for (const [count, decoration] of cycleDecorations) {
            if (!counts.has(count)) { decoration.dispose(); cycleDecorations.delete(count); }
        }
        for (const count of counts) {
            if (!cycleDecorations.has(count)) {
                const label = count > 999 ? "999+" : String(count);
                cycleDecorations.set(count, vscode.window.createTextEditorDecorationType({
                    gutterIconPath: vscode.Uri.parse("data:image/svg+xml;base64," + Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><text x="8" y="12" text-anchor="middle" fill="#888888" font-family="monospace" font-size="${label.length > 2 ? 6 : 10}">${label}</text></svg>`).toString("base64")),
                    gutterIconSize: "contain"
                }));
            }
        }
        for (const editor of vscode.window.visibleTextEditors) {
            for (const [count, decoration] of cycleDecorations) {
                editor.setDecorations(decoration, cycleLines
                .filter(line => line.cycles === count && line.path.toLowerCase() === editor.document.uri.fsPath.toLowerCase() && line.line <= editor.document.lineCount)
                // Only the gutter shows the count: text inserted in the line would shift the source, and VS Code
                // attaches a decoration's hover to line text, never to its gutter icon.
                .map((line): vscode.DecorationOptions => ({ range: new vscode.Range(line.line - 1, 0, line.line - 1, 0) })));
            }
            editor.setDecorations(callDecoration, callLines
                .filter(line => line.path.toLowerCase() === editor.document.uri.fsPath.toLowerCase() && line.line <= editor.document.lineCount)
                .map((line): vscode.DecorationOptions => {
                    const end = editor.document.lineAt(line.line - 1).range.end;
                    return {
                        range: new vscode.Range(end, end),
                        hoverMessage: `The last call from this line took ${line.cycles.toLocaleString()} cycles, counting the JSR, `
                            + "the subroutine with any calls it made, and its return.",
                        renderOptions: { after: { contentText: `⤷ ${line.cycles.toLocaleString()}c` } }
                    };
                }));
        }
    };
    const showError = (error: unknown) => vscode.window.showErrorMessage(`Retrocore: ${String(error)}`);
    // Restart starts the ended session's launch again. Its configuration is the one VS Code resolved, so the machine
    // it saved is dropped: resolving again restores the one saved since.
    const restart = async (): Promise<boolean> => {
        if (endedSession === undefined) return false;
        const { machineState: _saved, ...configuration } = endedSession.configuration;
        return vscode.debug.startDebugging(endedSession.folder, configuration as vscode.DebugConfiguration);
    };
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.display.restart", restart));
    // For the tests: the name of the ended session the panel offers to restart, if it does.
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.display.ended", () =>
        panel !== undefined && displaySession === undefined ? endedSession?.name : undefined));
    context.subscriptions.push(vscode.window.onDidChangeVisibleTextEditors(annotate));
    context.subscriptions.push(vscode.debug.onDidTerminateDebugSession(session => {
        if (displaySession?.id === session.id) {
            displaySession = undefined;
            endedSession = { name: session.name, configuration: session.configuration, folder: session.workspaceFolder };
            if (panel !== undefined) {
                panel.iconPath = machineIcon(context.extensionUri, "off");
                panelScreen = "off";
                panelBasic = false;
                if (vscode.workspace.getConfiguration("retrocore").get<string>("display.onSessionEnd") === "close") {
                    panel.dispose();
                } else {
                    void panel.webview.postMessage({ ended: { name: session.name } }).then(undefined, showError);
                }
            }
            cycleLines = [];
            callLines = [];
            annotate();
        }
    }));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.clearCycles", async () => {
        const session = vscode.debug.activeDebugSession;
        if (session?.type !== "retrocore") { await showError("No active Retrocore debug session."); return; }
        try {
            await session.customRequest("retro/cycles", { clear: true });
            cycleLines = [];
            callLines = [];
            annotate();
        } catch (error) { await showError(error); }
    }));
    // Model I media: each command sends retro/media to the active session.
    const media = async (args: Record<string, unknown>): Promise<void> => {
        const session = vscode.debug.activeDebugSession;
        if (session?.type !== "retrocore") { await showError("No active Retrocore debug session."); return; }
        try { await session.customRequest("retro/media", args); } catch (error) { await showError(error); }
    };
    const pickDrive = async (): Promise<number | undefined> => {
        const drive = await vscode.window.showQuickPick(["0", "1", "2", "3"], { title: "Drive" });
        return drive === undefined ? undefined : Number(drive);
    };
    const openFile = async (title: string, filters: Record<string, string[]>): Promise<string | undefined> =>
        (await vscode.window.showOpenDialog({ title, canSelectMany: false, filters }))?.[0]?.fsPath;
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.insertCassette", async () => {
        const path = await openFile("Insert cassette", { "Cassette images": ["cas"] });
        if (path !== undefined) await media({ device: "cassette", action: "insert", path });
    }));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.recordCassette", async () => {
        const path = (await vscode.window.showSaveDialog({ title: "Record cassette to", filters: { "Cassette images": ["cas"] } }))?.fsPath;
        if (path !== undefined) await media({ device: "cassette", action: "record", path });
    }));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.ejectCassette", () => media({ device: "cassette", action: "eject" })));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.insertDisk", async () => {
        const drive = await pickDrive();
        if (drive === undefined) return;
        const path = await openFile(`Insert disk in drive ${drive}`, { "Disk images": ["dsk", "jv1", "jv3"] });
        if (path !== undefined) await media({ device: "disk", action: "insert", drive, path });
    }));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.ejectDisk", async () => {
        const drive = await pickDrive();
        if (drive !== undefined) await media({ device: "disk", action: "eject", drive });
    }));
    context.subscriptions.push(vscode.debug.registerDebugAdapterDescriptorFactory("retrocore", {
        createDebugAdapterDescriptor(session) {
            const host: unknown = session.configuration.debugHost;
            const filename = typeof host === "string" ? host : defaultHost(context);
            if (filename === undefined) {
                throw new Error("Retrocore: no debug host. Reinstall the extension, build the repository, or set debugHost.");
            }
            // Like the language server, a built adapter runs from a copy so the host can be rebuilt during a session;
            // its SDK sources stay the original's, so breakpoints set in them bind.
            let adapter = filename;
            try {
                if (!isBundled(context, filename)) adapter = shadowCopy(filename, context.globalStorageUri.fsPath, "debug-adapter");
            } catch (error) {
                console.warn(`retrocore: running the debug adapter in place: ${String(error)}`);
            }
            return new vscode.DebugAdapterExecutable("dotnet", [adapter, "--sdk-roms", path.join(path.dirname(filename), "Sdk", "Roms")]);
        }
    }));
    context.subscriptions.push(vscode.debug.registerDebugAdapterTrackerFactory("retrocore", {
        createDebugAdapterTracker(session) {
            return {
                onDidSendMessage(message: unknown) {
                    if (typeof message !== "object" || message === null || !("event" in message) || !("body" in message)) {
                        return;
                    }
                    if (message.event === "retro/cycles") {
                        if (typeof message.body !== "object" || message.body === null || !("lines" in message.body) || !Array.isArray(message.body.lines) || !message.body.lines.every(isCycleLine)) {
                            void showError("Invalid source-cycle event from the debug host.");
                            return;
                        }
                        cycleLines = message.body.lines;
                        const calls: unknown = "calls" in message.body ? message.body.calls : [];
                        callLines = Array.isArray(calls) && calls.every(isCycleLine) ? calls : [];
                        annotate();
                        return;
                    }
                    if (message.event === "retro/audio") {
                        // Sound while running, played by the panel; without a panel there is nothing to hear it.
                        if (panel !== undefined && isAudio(message.body)) {
                            void panel.webview.postMessage({ audio: message.body }).then(undefined, showError);
                        }
                        return;
                    }
                    if (message.event !== "retro/frame") return;
                    if (displaySession !== session) pictures.reset();
                    displaySession = session;
                    endedSession = undefined;
                    const machine = typeof message.body === "object" && message.body !== null && "machine" in message.body ? message.body.machine : undefined;
                    const model = typeof message.body === "object" && message.body !== null && "model" in message.body && typeof message.body.model === "string" ? message.body.model : undefined;
                    const title = machine === "trs80-model1" ? "TRS-80 Model I" : model ?? "Apple IIe";
                    // The screen glows in the machine's phosphor while it runs, and goes dark when it stops.
                    const running = typeof message.body === "object" && message.body !== null && "running" in message.body && message.body.running === true;
                    const screen = running ? (machine === "trs80-model1" ? "trs80-model1" : "apple2") : "off";
                    const icon = machineIcon(context.extensionUri, screen);
                    if (panel !== undefined && panel.title !== title) panel.title = title;
                    if (panel !== undefined && panelScreen !== screen) {
                        panel.iconPath = icon;
                        panelScreen = screen;
                        panelScreen = screen;
                    }
                    const newPanel = panel === undefined;
                    if (panel === undefined) {
                        // The page is kept while another editor covers it, as the BASIC program's editor can: else
                        // VS Code reloads it on return, without its picture, sound, BASIC button or Machine off.
                        panel = vscode.window.createWebviewPanel("retrocore", title, vscode.ViewColumn.Beside,
                            { enableScripts: true, retainContextWhenHidden: true });
                        panel.iconPath = icon;
                        context.subscriptions.push(panel);
                        const nonce = randomBytes(16).toString("hex");
                        panel.webview.html = webviewHtml(nonce);
                        panel.onDidDispose(() => { panel = undefined; panelBasic = undefined; }, undefined, context.subscriptions);
                        panel.webview.onDidReceiveMessage((input: unknown) => {
                            if (typeof input === "object" && input !== null && "code" in input && typeof input.code === "number" && Number.isInteger(input.code) && input.code >= 0 && input.code < 128) {
                                if (displaySession !== undefined) {
                                    void displaySession.customRequest("retro/key", { code: input.code }).then(undefined, showError);
                                }
                            } else if (typeof input === "object" && input !== null && "button" in input && typeof input.button === "number"
                                && Number.isInteger(input.button) && input.button >= 0 && input.button <= 1
                                && "pressed" in input && typeof input.pressed === "boolean") {
                                if (displaySession !== undefined) {
                                    void displaySession.customRequest("apple2/button", { button: input.button, pressed: input.pressed }).then(undefined, showError);
                                }
                            } else if (typeof input === "object" && input !== null && "mouse" in input
                                && typeof input.mouse === "object" && input.mouse !== null) {
                                // The mouse card's movement and button, from the display's locked pointer.
                                const mouse = input.mouse as Record<string, unknown>;
                                const args: Record<string, unknown> = {};
                                for (const axis of ["dx", "dy"]) {
                                    const value = mouse[axis];
                                    if (typeof value === "number" && Number.isInteger(value) && Math.abs(value) <= 4096) args[axis] = value;
                                }
                                if (typeof mouse.pressed === "boolean") args.pressed = mouse.pressed;
                                if (displaySession !== undefined && Object.keys(args).length !== 0) {
                                    void displaySession.customRequest("apple2/mouse", args).then(undefined, showError);
                                }
                            } else if (typeof input === "object" && input !== null && "command" in input && input.command === "screen"
                                && "screen" in input && (input.screen === "color" || input.screen === "white" || input.screen === "green" || input.screen === "amber")) {
                                if (displaySession !== undefined) {
                                    void displaySession.customRequest("apple2/screen", { screen: input.screen }).then(undefined, showError);
                                }
                            } else if (typeof input === "object" && input !== null && "command" in input && input.command === "reset") {
                                if (displaySession !== undefined) {
                                    void displaySession.customRequest("retro/reset").then(undefined, showError);
                                }
                            } else if (typeof input === "object" && input !== null && "command" in input && input.command === "sound"
                                && "mode" in input && (input.mode === "off" || input.mode === "speaker" || input.mode === "mockingboard")) {
                                if (displaySession !== undefined) {
                                    void displaySession.customRequest("apple2/sound", { mode: input.mode }).then(undefined, showError);
                                }
                            } else if (typeof input === "object" && input !== null && "command" in input && input.command === "fastDisk"
                                && "enabled" in input && typeof input.enabled === "boolean") {
                                if (displaySession !== undefined) {
                                    void displaySession.customRequest("apple2/fastDisk", { enabled: input.enabled }).then(undefined, showError);
                                }
                            } else if (typeof input === "object" && input !== null && "command" in input && input.command === "speed"
                                && "speed" in input && (input.speed === "max" || input.speed === 1 || input.speed === 2 || input.speed === 4 || input.speed === 8)) {
                                if (displaySession !== undefined) {
                                    void displaySession.customRequest("retro/speed", { speed: input.speed }).then(undefined, showError);
                                }
                            } else if (typeof input === "object" && input !== null && "command" in input && input.command === "restart") {
                                void restart().then(undefined, showError);
                            } else if (typeof input === "object" && input !== null && "command" in input && input.command === "startMachine") {
                                void vscode.commands.executeCommand("retrocore.startMachine").then(undefined, showError);
                            } else if (typeof input === "object" && input !== null && "command" in input && input.command === "close") {
                                panel?.dispose();
                            } else if (typeof input === "object" && input !== null && "command" in input && input.command === "basic") {
                                if (displaySession !== undefined) {
                                    const column = panel?.viewColumn === vscode.ViewColumn.One ? vscode.ViewColumn.Two : vscode.ViewColumn.One;
                                    void vscode.commands.executeCommand("retrocore.basic.open", column).then(undefined, showError);
                                }
                            } else if (typeof input === "object" && input !== null && "error" in input && typeof input.error === "string") {
                                void showError(input.error);
                            }
                        }, undefined, context.subscriptions);
                    }
                    void panel.webview.postMessage(pictures.frame(message.body, newPanel)).then(undefined, showError);
                    showBasicButton();
                },
                onError(error) { void showError(error); }
            };
        }
    }));
}

interface CycleLine { path: string; line: number; cycles: number; }

/**
 * The display panel's tab icon: a CRT monitor framed in the theme's tab text color, whose screen glows in the
 * machine's phosphor while it runs (green for the IIe, white for the Model I) and is dark (off) when it stops.
 */
function machineIcon(extension: vscode.Uri, screen: "apple2" | "trs80-model1" | "off"): { light: vscode.Uri; dark: vscode.Uri } {
    const name = screen === "off" ? "crt-off" : screen;
    return {
        light: vscode.Uri.joinPath(extension, "media", `${name}-light.svg`),
        dark: vscode.Uri.joinPath(extension, "media", `${name}-dark.svg`)
    };
}

/** A chunk of sound from the debug host: base64 16-bit PCM at a rate, mono or interleaved stereo. */
interface AudioChunk { rate: number; channels: number; samples: string; }

function isAudio(value: unknown): value is AudioChunk {
    return typeof value === "object" && value !== null
        && "rate" in value && typeof value.rate === "number" && value.rate > 0
        && "channels" in value && (value.channels === 1 || value.channels === 2)
        && "samples" in value && typeof value.samples === "string";
}

function isCycleLine(value: unknown): value is CycleLine {
    return typeof value === "object" && value !== null
        && "path" in value && typeof value.path === "string"
        && "line" in value && typeof value.line === "number" && Number.isInteger(value.line) && value.line > 0
        && "cycles" in value && typeof value.cycles === "number" && Number.isSafeInteger(value.cycles) && value.cycles >= 0;
}

export function deactivate(): Promise<void> {
    return stopLanguageClient();
}
