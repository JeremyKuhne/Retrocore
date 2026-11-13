// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The Retrocore activity bar's views. Machine: the launched machine, whether it runs, its installed hardware slot by
// slot, and its BASIC program. Drives: its floppy drives, tape drives and block storage under the controllers they sit
// on, with their media and state. Both from the debug host's retro/devices request and event, with actions through
// retro/device and retro/hardware.

import * as vscode from "vscode";
import * as path from "node:path";
import { cardsFor, group, type HardwareRow } from "./hardware";
import type { BasicPrograms, BasicSummary } from "./basic";
import { catalogMachine, settingValue, type MachineChoice } from "./machines";
import { OffMachine, type OffTarget } from "./offMachine";
import type { SavedMachines } from "./savedMachine";

/** A device as the debug host's retro/devices describes it. */
export interface Device {
    id: string;
    kind: "floppyDrive" | "tapeDrive" | "blockStorage";
    name: string;
    description: string;
    controller: string;
    formats: string[];
    operations: ("insert" | "eject" | "record" | "writeProtect" | "save")[];
    tracks: number;
    sides: number;
    media: { label: string; format: string; writeProtected: boolean; changed: boolean } | null;
    activity: "idle" | "seeking" | "reading" | "writing";
    head?: { motor: boolean; selected: boolean; track: number; side: number; sector: number | null };
    transport?: { motor: boolean; mode: "stopped" | "playing" | "recording"; position: number; length: number };
    blocks?: { count: number; last: number | null };
}

/** The retro/devices body. */
interface Devices { devices: Device[]; hardware?: HardwareRow[] }

/**
 * A row of the Machine or Drives view: the machine itself, its settings and each setting, a piece of its installed
 * hardware, a controller its drives are listed under, a device, one line of a device's details, or the BASIC program
 * in memory.
 */
type Node = { machine: HardwareRow | undefined } | { switcher: true } | { settings: MachineChoice[] } | { setting: MachineChoice }
    | { hardware: HardwareRow; devices: Device[] }
    | { controller: HardwareRow; devices: Device[] } | { device: Device } | { detail: string; value: string; parent: string }
    | { basic: BasicSummary };

/** The machines whose screens the media folder draws, by the launch's machine option. */
const screens: Record<string, string> = { apple2: "apple2", apple3: "apple2", apple1: "apple1", "trs80-model1": "trs80-model1", coco: "coco" };

/** The icons of the Machine view's rows, by hardware id, when the row is not a slot. */
const hardwareIcons: Record<string, string> = {
    cpu: "chip", rom: "file-binary", memory: "server", video: "device-desktop", builtIn: "plug", gamePort: "game",
    cassette: "record-keys", auxiliary: "extensions"
};

/** Escapes Markdown in a value shown in a tooltip. */
const escape = (text: string): string => text.replace(/[\\`*_]/g, "\\$&");

/** The BASIC program row's summary, such as AppleSoft · 12 lines. */
export function basicDescription(summary: BasicSummary): string {
    return `${summary.displayName} · ${summary.lines === 0 ? "no program" : summary.lines === 1 ? "1 line" : `${summary.lines} lines`}`;
}

/** The one-line summary after a device's name: its media, where it is and what it is doing. */
export function summary(device: Device): string {
    const parts: string[] = [device.media ? path.basename(device.media.label) || device.media.format : "empty"];
    if (device.head) {
        const track = Number.isInteger(device.head.track) ? String(device.head.track) : device.head.track.toFixed(2);
        parts.push(`track ${track}` + (device.sides > 1 ? ` side ${device.head.side}` : "")
            + (device.head.sector !== null ? ` sector ${device.head.sector}` : ""));
    }
    if (device.transport && device.media) parts.push(`${device.transport.position.toLocaleString()} of ${device.transport.length.toLocaleString()} bytes`);
    if (device.blocks?.last !== null && device.blocks?.last !== undefined) parts.push(`block ${device.blocks.last}`);
    if (device.media?.writeProtected) parts.push("read-only");
    if (device.media?.changed) parts.push("changed");
    if (device.activity !== "idle") parts.push(device.activity);
    else if (device.head?.motor || device.transport?.motor) parts.push("motor on");
    return parts.join(" · ");
}

/** The detail rows under a device. */
export function details(device: Device): [string, string][] {
    const rows: [string, string][] = [
        ["Media", device.media ? `${device.media.label} (${device.media.format})` : "none"],
        ["Activity", device.activity]
    ];
    if (device.media) {
        rows.push(["Write protected", device.media.writeProtected ? "yes" : "no"]);
        rows.push(["Changed", device.media.changed ? "yes, not saved to the image" : "no"]);
    }
    if (device.head) {
        rows.push(["Motor", device.head.motor ? "on" : "off"]);
        rows.push(["Selected", device.head.selected ? "yes" : "no"]);
        rows.push(["Track", String(device.head.track)]);
        if (device.sides > 1) rows.push(["Side", String(device.head.side)]);
        if (device.head.sector !== null) rows.push(["Sector", String(device.head.sector)]);
    }
    if (device.transport) {
        rows.push(["Motor", device.transport.motor ? "on" : "off"]);
        rows.push(["Mode", device.transport.mode]);
        rows.push(["Position", `${device.transport.position.toLocaleString()} of ${device.transport.length.toLocaleString()} bytes`]);
    }
    if (device.blocks) {
        rows.push(["Blocks", device.blocks.count.toLocaleString()]);
        rows.push(["Last block", device.blocks.last === null ? "none yet" : String(device.blocks.last)]);
    }
    rows.push(["Device", device.description]);
    rows.push(["Controller", device.controller]);
    if (device.tracks > 0) rows.push(["Geometry", `${device.tracks} tracks, ${device.sides} side${device.sides === 1 ? "" : "s"}`]);
    if (device.formats.length > 0) rows.push(["Formats", device.formats.map(format => `.${format}`).join(", ")]);
    return rows;
}

/**
 * What the Machine and Drives views show: the active Retrocore session's machine, hardware, devices and BASIC program,
 * or with no session the off machine's.
 */
class MachineState {
    private readonly changed = new vscode.EventEmitter<void>();
    readonly onDidChange = this.changed.event;
    devices: Device[] = [];
    hardware: HardwareRow[] = [];
    basic: BasicSummary | undefined;
    /** The active session, when it is a Retrocore one. */
    session: vscode.DebugSession | undefined;
    /** With no session, the off machine's launch configuration, while it has a description to show. */
    off: Record<string, unknown> | undefined;
    /** The ids of the sessions stopped in the debugger. */
    readonly paused = new Set<string>();

    show(body: Devices): void {
        this.devices = body.devices;
        this.hardware = body.hardware ?? [];
        this.changed.fire();
    }

    redraw(): void {
        this.changed.fire();
    }
}

/** The tooltip of a hardware row: what is there, and what it does. */
function hardwareTooltip(row: HardwareRow): vscode.MarkdownString {
    return new vscode.MarkdownString(`**${escape(row.name)}**: ${escape(row.value)}\n\n${escape(row.description)}`);
}

/** Whether a hardware row has nothing in it, such as an empty slot. */
const isEmpty = (row: HardwareRow): boolean => row.value === "empty" || row.value === "none";

/** The Machine view: the machine, with its installed hardware under it, then the BASIC program in its memory. */
class MachineTree implements vscode.TreeDataProvider<Node> {
    private readonly changed = new vscode.EventEmitter<Node | undefined>();
    readonly onDidChangeTreeData = this.changed.event;

    constructor(private readonly state: MachineState, private readonly extension: vscode.Uri) {
        state.onDidChange(() => this.changed.fire(undefined));
    }

    getChildren(node?: Node): Node[] {
        if (node === undefined) {
            if (this.state.session === undefined && this.state.off === undefined) return [];
            return [
                { machine: this.state.hardware.find(row => row.id === "model") },
                ...this.state.basic === undefined ? [] : [{ basic: this.state.basic }],
                // While off, another machine is a click away rather than a title-bar icon shown only on hover.
                ...this.state.session === undefined ? [{ switcher: true as const }] : []
            ];
        }
        if ("machine" in node) {
            const choices = catalogMachine(this.configuration())?.choices ?? [];
            return [
                ...choices.length === 0 ? [] : [{ settings: choices }],
                ...group(this.state.hardware, this.state.devices).rows
                    .filter(({ row }) => row.id !== "model")
                    .map(({ row, devices }) => ({ hardware: row, devices }))
            ];
        }
        if ("settings" in node) return node.settings.map(setting => ({ setting }));
        return [];
    }

    // The configuration the machine shown was launched with, or will be.
    private configuration(): Record<string, unknown> {
        return (this.state.session?.configuration as Record<string, unknown> | undefined) ?? this.state.off ?? {};
    }

    // Revealing a row, as bringing the views back does, needs its parent: the machine for a piece of hardware.
    getParent(node: Node): Node | undefined {
        if ("setting" in node) return { settings: catalogMachine(this.configuration())?.choices ?? [] };
        return "hardware" in node || "settings" in node ? { machine: this.state.hardware.find(row => row.id === "model") } : undefined;
    }

    getTreeItem(node: Node): vscode.TreeItem {
        if ("machine" in node) return this.machineItem(node.machine);
        if ("basic" in node) return basicItem(node.basic);
        if ("settings" in node) return this.settingsItem();
        if ("setting" in node) return this.settingItem(node.setting);
        if ("switcher" in node) {
            const item = new vscode.TreeItem("Switch to Another Machine…", vscode.TreeItemCollapsibleState.None);
            item.id = "switch";
            item.iconPath = new vscode.ThemeIcon("arrow-swap");
            item.tooltip = "Pick a launch configuration or a machine to set up, off, and start from here.";
            item.command = { command: "retrocore.machine.switch", title: "Switch Machine" };
            return item;
        }
        if (!("hardware" in node)) return new vscode.TreeItem("");

        const row = node.hardware;
        const item = new vscode.TreeItem(row.name, vscode.TreeItemCollapsibleState.None);
        item.id = `hardware/${row.id}`;
        // A row with drives says how many; the Drives view lists them.
        const drives = node.devices.length;
        item.description = drives === 0 || isEmpty(row) ? row.value : `${row.value} · ${drives} drive${drives === 1 ? "" : "s"}`;
        item.tooltip = hardwareTooltip(row);
        item.iconPath = new vscode.ThemeIcon(isEmpty(row) ? "circle-outline" : hardwareIcons[row.id] ?? "circuit-board",
            isEmpty(row) ? new vscode.ThemeColor("disabledForeground") : undefined);
        item.contextValue = ["hardware", ...row.actions ?? []].join(" ");
        return item;
    }

    // The settings: the launch options the catalog offers for the machine, changed while it is off.
    private settingsItem(): vscode.TreeItem {
        const off = this.state.session === undefined;
        const item = new vscode.TreeItem("Settings",
            off ? vscode.TreeItemCollapsibleState.Expanded : vscode.TreeItemCollapsibleState.Collapsed);
        item.id = "settings";
        item.iconPath = new vscode.ThemeIcon("settings-gear");
        item.description = off ? "" : "fixed while it runs";
        item.tooltip = off
            ? "What the machine is built with. A change keeps the cards and media you added, where they still fit."
            : "What the machine was built with. Stop it to change them.";
        return item;
    }

    // One setting: its value, and while off a click to pick another.
    private settingItem(choice: MachineChoice): vscode.TreeItem {
        const value = settingValue(choice, this.configuration());
        const chosen = choice.values.find(candidate => candidate.value === value);
        const item = new vscode.TreeItem(choice.label, vscode.TreeItemCollapsibleState.None);
        item.id = `setting/${choice.option}`;
        item.description = chosen?.label ?? String(value);
        const standard = choice.values.find(candidate => candidate.value === choice.default)?.label ?? String(choice.default);
        const tooltip = new vscode.MarkdownString(`**${escape(choice.label)}**: ${escape(chosen?.label ?? String(value))}`);
        if (chosen?.detail !== undefined) tooltip.appendMarkdown(`\n\n${escape(chosen.detail)}`);
        tooltip.appendMarkdown(`\n\nThe launch option \`${choice.option}\`; ${escape(standard)} by default.`);
        if (this.state.session !== undefined) tooltip.appendMarkdown(" Stop the machine to change it.");
        item.tooltip = tooltip;
        if (this.state.session === undefined) {
            item.contextValue = "setting off";
            item.command = { command: "retrocore.machine.setting", title: "Change Setting", arguments: [choice.option] };
        } else {
            item.contextValue = "setting";
        }
        return item;
    }

    // The machine heads the view, its screen lit while it runs and dark while it is stopped in the debugger or off.
    private machineItem(model: HardwareRow | undefined): vscode.TreeItem {
        const session = this.state.session;
        const off = session === undefined ? this.state.off : undefined;
        const configuration = session?.configuration ?? off ?? {};
        const name = String(configuration.name ?? "Machine");
        const paused = session !== undefined && this.state.paused.has(session.id);
        const status = off !== undefined ? "off" : paused ? "paused" : "running";
        const item = new vscode.TreeItem(model?.name ?? name, vscode.TreeItemCollapsibleState.Expanded);
        item.id = "machine";
        item.description = [model?.value, status].filter(part => part !== undefined).join(" · ");
        const screen = status !== "running" ? "crt-off" : screens[String(configuration.machine ?? "apple2")] ?? "apple2";
        item.iconPath = {
            light: vscode.Uri.joinPath(this.extension, "media", `${screen}-light.svg`),
            dark: vscode.Uri.joinPath(this.extension, "media", `${screen}-dark.svg`)
        };
        const tooltip = new vscode.MarkdownString(model === undefined ? "" : `**${escape(model.name)}**: ${escape(model.value)}\n\n${escape(model.description)}\n\n`);
        tooltip.appendMarkdown(off !== undefined
            ? `*${escape(name)}*, off. Cards and media changed now are there when it starts.`
            : `Launched by *${escape(name)}*, ${paused ? "stopped in the debugger" : "running"}.`);
        item.tooltip = tooltip;
        item.contextValue = off !== undefined ? "machine off" : "machine";
        return item;
    }
}

/** The BASIC program row: the program in memory, opened in an editor where saving puts it back. */
function basicItem(summary: BasicSummary): vscode.TreeItem {
    const item = new vscode.TreeItem("BASIC program", vscode.TreeItemCollapsibleState.None);
    item.id = "basic";
    item.description = basicDescription(summary);
    item.tooltip = new vscode.MarkdownString(`**BASIC program**: the ${summary.displayName} program in the machine's memory. `
        + "Open it to read or edit it; saving puts it back in memory.");
    item.iconPath = new vscode.ThemeIcon("file-code");
    item.contextValue = "basicProgram";
    item.command = { command: "retrocore.basic.open", title: "Open BASIC Program" };
    return item;
}

/** The Drives view: each controller with drives on it, its drives under it, and each drive's details under that. */
class DriveTree implements vscode.TreeDataProvider<Node> {
    private readonly changed = new vscode.EventEmitter<Node | undefined>();
    readonly onDidChangeTreeData = this.changed.event;

    constructor(private readonly state: MachineState) {
        state.onDidChange(() => this.changed.fire(undefined));
    }

    getChildren(node?: Node): Node[] {
        if (node === undefined) {
            if (this.state.session === undefined && this.state.off === undefined) return [];
            const grouped = group(this.state.hardware, this.state.devices);
            return [
                ...grouped.rows.filter(({ devices }) => devices.length > 0).map(({ row, devices }) => ({ controller: row, devices })),
                ...grouped.loose.map(device => ({ device }))
            ];
        }
        if ("controller" in node) return node.devices.map(device => ({ device }));
        if ("device" in node) return details(node.device).map(([detail, value]) => ({ detail, value, parent: node.device.id }));
        return [];
    }

    getTreeItem(node: Node): vscode.TreeItem {
        if ("detail" in node) {
            const item = new vscode.TreeItem(node.detail, vscode.TreeItemCollapsibleState.None);
            item.description = node.value;
            item.tooltip = node.value;
            item.id = `${node.parent}/${node.detail}`;
            return item;
        }
        if ("controller" in node) {
            const row = node.controller;
            const item = new vscode.TreeItem(row.name, vscode.TreeItemCollapsibleState.Expanded);
            item.id = `controller/${row.id}`;
            item.description = row.value;
            item.tooltip = hardwareTooltip(row);
            item.iconPath = new vscode.ThemeIcon(hardwareIcons[row.id] ?? "circuit-board");
            item.contextValue = "controller";
            return item;
        }
        if (!("device" in node)) return new vscode.TreeItem("");

        const device = node.device;
        const item = new vscode.TreeItem(device.name, vscode.TreeItemCollapsibleState.Collapsed);
        item.id = device.id;
        item.description = summary(device);
        item.iconPath = new vscode.ThemeIcon(
            device.kind === "tapeDrive" ? "record-keys" : device.kind === "blockStorage" ? "database" : "save",
            device.activity === "writing" ? new vscode.ThemeColor("charts.red")
                : device.activity === "reading" ? new vscode.ThemeColor("charts.green")
                : device.activity === "seeking" ? new vscode.ThemeColor("charts.yellow")
                : device.media === null ? new vscode.ThemeColor("disabledForeground")
                : undefined);
        const tooltip = new vscode.MarkdownString(`**${escape(device.name)}**: ${escape(device.description)}\n\n`);
        for (const [detail, value] of details(device)) tooltip.appendMarkdown(`- ${detail}: ${escape(value)}\n`);
        item.tooltip = tooltip;

        // Menus pick their actions by these words. While the machine is off, a tape cannot record and nothing has
        // changed a disk to save.
        const running = this.state.session !== undefined;
        const words = ["device", device.media ? "loaded" : "empty"];
        if (device.operations.includes("insert")) words.push("insert");
        if (running && device.operations.includes("record")) words.push("record");
        if (device.media && device.operations.includes("eject")) words.push("eject");
        if (device.media && device.operations.includes("writeProtect")) words.push(device.media.writeProtected ? "unprotect" : "protect");
        if (running && device.media && device.operations.includes("save")) words.push("save");
        if (running && device.media?.changed && device.operations.includes("save")) words.push("changed");
        item.contextValue = words.join(" ");
        return item;
    }
}

/** The requests that set a stopped machine running again. */
const resumes = new Set(["continue", "next", "stepIn", "stepOut", "stepBack", "reverseContinue", "goto"]);

/** Registers the Retrocore activity bar's Machine and Drives views and their actions. */
export function registerDevices(context: vscode.ExtensionContext, basic: BasicPrograms, saved: SavedMachines): void {
    const tree = new MachineState();
    const off = new OffMachine(context.workspaceState, saved);
    const showBasic = (): void => {
        tree.basic = basic.summary(vscode.debug.activeDebugSession);
        tree.show({ devices: tree.devices, hardware: tree.hardware });
    };
    context.subscriptions.push(basic.onDidChange(session => {
        if (session.id === vscode.debug.activeDebugSession?.id || tree.basic !== undefined) showBasic();
    }));
    let pending: Devices | undefined;
    let timer: NodeJS.Timeout | undefined;

    // Running sends retro/devices as often as a head moves; the views redraw at most ten times a second.
    const show = (body: Devices): void => {
        pending = body;
        timer ??= setTimeout(() => {
            timer = undefined;
            if (pending) tree.show(pending);
        }, 100);
    };
    // With no Retrocore session the views show the off machine, which the language server describes when they come
    // into sight, so a closed sidebar builds nothing.
    let stale = true;
    const refresh = async (session: vscode.DebugSession | undefined): Promise<void> => {
        tree.basic = basic.summary(session);
        if (session?.type === "retrocore") {
            tree.session = session;
            tree.off = undefined;
            void vscode.commands.executeCommand("setContext", "retrocore.machineOff", false);
            machineView.message = undefined;
            try { show(await session.customRequest("retro/devices")); } catch { /* Not launched yet. */ }
            return;
        }
        tree.session = undefined;
        stale = true;
        showOff();
        if (showing()) await describeOff();
    };
    const showOff = (): void => {
        if (tree.session !== undefined) return;
        tree.off = off.body === undefined ? undefined : off.target?.configuration;
        void vscode.commands.executeCommand("setContext", "retrocore.machineOff", tree.off !== undefined);
        machineView.message = off.error === undefined ? undefined : `${off.name ?? "The machine"} could not be set up: ${off.error}`;
        show((off.body as Devices | undefined) ?? { devices: [] });
    };
    const describeOff = async (): Promise<void> => {
        stale = false;
        await off.describe();
    };
    context.subscriptions.push(off.onDidChange(showOff));

    const machineView = vscode.window.createTreeView("retrocore.machine", { treeDataProvider: new MachineTree(tree, context.extensionUri) });
    const drivesView = vscode.window.createTreeView("retrocore.drives", { treeDataProvider: new DriveTree(tree) });
    context.subscriptions.push(machineView, drivesView);

    // VS Code opens Run and Debug as a session starts and when it breaks (its debug.openDebug setting). When that
    // takes the sidebar from the Retrocore views, they come back, without taking the keyboard from the display panel
    // or the editor. A session start or break and the views going out of sight within a moment of each other, in
    // either order, is VS Code's doing rather than a click on another view.
    const moment = 1500;
    let hiddenAt = Number.NEGATIVE_INFINITY;
    let debugAt = Number.NEGATIVE_INFINITY;
    const showing = (): boolean => machineView.visible || drivesView.visible;
    const bringBack = (): void => {
        hiddenAt = debugAt = Number.NEGATIVE_INFINITY;
        const model = tree.hardware.find(row => row.id === "model");
        machineView.reveal({ machine: model }, { select: false, focus: false }).then(undefined,
            () => vscode.commands.executeCommand("workbench.view.extension.retrocore"));
    };
    const debugMoved = (): void => {
        debugAt = Date.now();
        if (!showing() && debugAt - hiddenAt < moment) bringBack();
    };
    const hidden = (): void => {
        if (showing()) return;
        hiddenAt = Date.now();
        if (hiddenAt - debugAt < moment) bringBack();
    };
    context.subscriptions.push(machineView.onDidChangeVisibility(hidden), drivesView.onDidChangeVisibility(hidden));
    const seen = (): void => {
        if (showing() && stale && tree.session === undefined) void describeOff();
    };
    context.subscriptions.push(machineView.onDidChangeVisibility(seen), drivesView.onDidChangeVisibility(seen));
    context.subscriptions.push(vscode.debug.onDidStartDebugSession(session => {
        if (session.type !== "retrocore") return;
        debugMoved();
        // Once this session ends, the views show its machine, off.
        void off.started(session);
    }));
    context.subscriptions.push(saved.onDidReset(() => {
        if (tree.session !== undefined) return;
        stale = true;
        seen();
    }));
    // The Drives view's badge counts the disks changed in the machine and not yet saved to their images.
    context.subscriptions.push(tree.onDidChange(() => {
        const changed = tree.devices.filter(device => device.media?.changed && device.operations.includes("save")).length;
        drivesView.badge = changed === 0 ? undefined
            : { value: changed, tooltip: `${changed} disk${changed === 1 ? "" : "s"} changed and not saved to ${changed === 1 ? "its image" : "their images"}` };
    }));
    // The machine row shows whether the machine runs or is stopped in the debugger.
    context.subscriptions.push(vscode.debug.registerDebugAdapterTrackerFactory("retrocore", {
        createDebugAdapterTracker(session) {
            const set = (paused: boolean): void => {
                if (paused) debugMoved();
                if (paused === tree.paused.has(session.id)) return;
                if (paused) tree.paused.add(session.id); else tree.paused.delete(session.id);
                if (session.id === tree.session?.id) tree.redraw();
            };
            return {
                onWillReceiveMessage(message: { command?: string }) { if (message.command !== undefined && resumes.has(message.command)) set(false); },
                onDidSendMessage(message: { event?: string }) {
                    if (message.event === "stopped") set(true);
                    else if (message.event === "continued") set(false);
                },
                onExit() { tree.paused.delete(session.id); }
            };
        }
    }));
    context.subscriptions.push(vscode.debug.onDidReceiveDebugSessionCustomEvent(event => {
        if (event.event === "retro/devices" && event.session.id === vscode.debug.activeDebugSession?.id) show(event.body);
    }));
    context.subscriptions.push(vscode.debug.onDidChangeActiveDebugSession(session => void refresh(session)));
    // As a session ends VS Code can still give it as the active one; it is not, so the views show its machine off.
    context.subscriptions.push(vscode.debug.onDidTerminateDebugSession(ended => {
        const active = vscode.debug.activeDebugSession;
        void refresh(active?.id === ended.id ? undefined : active);
    }));

    // A change goes to the running machine as retro/hardware or retro/device, or to the off machine, whose saved
    // machine its next launch restores.
    const send = async (request: "hardware" | "device", args: Record<string, unknown>): Promise<void> => {
        const session = vscode.debug.activeDebugSession;
        try {
            if (session?.type === "retrocore") show(await session.customRequest(`retro/${request}`, args));
            else if (tree.off !== undefined) await off.change(request, args);
        } catch (error) {
            void vscode.window.showErrorMessage(`Retrocore: ${error instanceof Error ? error.message : String(error)}`);
        }
    };
    const act = async (node: Node | undefined, action: string, args: Record<string, unknown> = {}): Promise<void> => {
        if (node !== undefined && "device" in node) await send("device", { id: node.device.id, action, ...args });
    };
    const filters = (device: Device): Record<string, string[]> => ({ [`${device.name} images`]: device.formats });

    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.insert", async (node?: Node) => {
        if (node === undefined || !("device" in node)) return;
        const file = (await vscode.window.showOpenDialog({ title: `Insert in ${node.device.name}`, canSelectMany: false, filters: filters(node.device) }))?.[0];
        if (file) await act(node, "insert", { path: file.fsPath });
    }));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.record", async (node?: Node) => {
        if (node === undefined || !("device" in node)) return;
        const file = await vscode.window.showSaveDialog({ title: `Record from ${node.device.name} to`, filters: filters(node.device) });
        if (file) await act(node, "record", { path: file.fsPath });
    }));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.eject", (node?: Node) => act(node, "eject")));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.protect",
        (node?: Node) => act(node, "writeProtect", { writeProtected: true })));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.unprotect",
        (node?: Node) => act(node, "writeProtect", { writeProtected: false })));
    // Saving over the disk's own image replaces the file it was loaded from, so it asks first.
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.save", async (node?: Node) => {
        if (node === undefined || !("device" in node) || !node.device.media) return;
        const save = "Save";
        const answer = await vscode.window.showWarningMessage(
            `Replace ${node.device.media.label} with the disk in ${node.device.name}?`, { modal: true }, save);
        if (answer === save) await act(node, "save");
    }));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.saveAs", async (node?: Node) => {
        if (node === undefined || !("device" in node) || !node.device.media) return;
        const file = await vscode.window.showSaveDialog({
            title: `Save the disk in ${node.device.name} as`,
            defaultUri: vscode.Uri.file(node.device.media.label),
            filters: { "Disk images": node.device.formats.filter(format => ["woz", "dsk", "do", "po"].includes(format)) }
        });
        if (file) await act(node, "save", { path: file.fsPath });
    }));
    // Cards go in and come out while the machine runs, as nothing on the bus minds here, and while it is off.
    const change = async (node: Node | undefined, args: Record<string, unknown>): Promise<void> => {
        if (node !== undefined && "hardware" in node) await send("hardware", { id: node.hardware.id, ...args });
    };
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.hardware.addCard", async (node?: Node) => {
        if (node === undefined || !("hardware" in node)) return;
        const machine = (tree.session?.configuration ?? tree.off)?.machine as string | undefined;
        const card = await vscode.window.showQuickPick(cardsFor(node.hardware.id, machine),
            { title: `Add a card to ${node.hardware.name}` });
        if (card) await change(node, card.args);
    }));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.hardware.removeCard", async (node?: Node) => {
        if (node === undefined || !("hardware" in node)) return;
        // Taking out a card with disks in it ejects them, so it asks first.
        if (node.devices.some(device => device.media !== null)) {
            const remove = "Remove Card";
            const answer = await vscode.window.showWarningMessage(
                `Remove the ${node.hardware.value} from ${node.hardware.name}? Its disks are ejected.`, { modal: true }, remove);
            if (answer !== remove) return;
        }
        await change(node, { action: "removeCard" });
    }));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.refresh", () => refresh(vscode.debug.activeDebugSession)));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.machine.boot", () => off.boot()));
    // Switch Machine… picks the off machine, or takes it given, as the tests and favorites do.
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.machine.switch", async (given?: OffTarget) => {
        const target = given ?? await off.pick();
        if (target === undefined) return;
        stale = false;
        await off.select(target);
    }));
    // A setting's row: pick its value while the machine is off, or take it given, as the tests do.
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.machine.setting",
        async (option: string, given?: string | number | boolean) => {
            // The note is not awaited: it settles only when dismissed.
            if (tree.session !== undefined || tree.off === undefined) {
                void vscode.window.showInformationMessage("Retrocore: stop the machine to change its settings.");
                return;
            }
            const choice = off.machine?.choices.find(candidate => candidate.option === option);
            if (choice === undefined) return;
            const current = settingValue(choice, tree.off);
            const value = given ?? (await vscode.window.showQuickPick(
                choice.values.map(candidate => ({
                    label: candidate.label,
                    detail: candidate.detail,
                    description: candidate.value === choice.default ? "default" : undefined,
                    picked: candidate.value === current,
                    value: candidate.value
                })),
                { title: `${off.name ?? "Machine"}: ${choice.label}`, placeHolder: "Applies when it starts; cards and disks you added stay" }))?.value;
            if (value === undefined || value === current) return;
            try {
                await off.setSetting(option, value);
            } catch (error) {
                void vscode.window.showErrorMessage(`Retrocore: ${error instanceof Error ? error.message : String(error)}`);
            }
        }));
    // A change without a view's row, for the tests: as retro/hardware or retro/device takes it.
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.machine.change",
        (request: "hardware" | "device", args: Record<string, unknown>) => send(request, args)));
    // The off machine's configuration name, for the tests; undefined while a session runs or before it is described.
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.machine.off", () => tree.off?.name));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.list", () => tree.devices));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.hardware", () => tree.hardware));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.basic", () =>
        tree.basic === undefined ? undefined : basicDescription(tree.basic)));
    void refresh(vscode.debug.activeDebugSession);
}
