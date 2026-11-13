// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The Retro Devices view: the launched machine's installed hardware, slot by slot, with its floppy drives, tape
// drives and block storage under the hardware they sit on, their media and state, from the debug host's
// retro/devices request and event, and actions through retro/device.

import * as vscode from "vscode";
import * as path from "node:path";
import { cardsFor, group, type HardwareRow } from "./hardware";
import type { BasicPrograms, BasicSummary } from "./basic";

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

/** A row of the view: a piece of installed hardware, a device, or one line of a device's details. */
type Node = { hardware: HardwareRow; devices: Device[] } | { device: Device } | { detail: string; value: string; parent: string }
    | { basic: BasicSummary };

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

class DeviceTree implements vscode.TreeDataProvider<Node> {
    private readonly changed = new vscode.EventEmitter<Node | undefined>();
    readonly onDidChangeTreeData = this.changed.event;
    devices: Device[] = [];
    hardware: HardwareRow[] = [];
    basic: BasicSummary | undefined;

    show(body: Devices): void {
        this.devices = body.devices;
        this.hardware = body.hardware ?? [];
        this.changed.fire(undefined);
    }

    getChildren(node?: Node): Node[] {
        if (node === undefined) {
            const grouped = group(this.hardware, this.devices);
            return [
                ...this.basic === undefined ? [] : [{ basic: this.basic }],
                ...grouped.rows.map(({ row, devices }) => ({ hardware: row, devices })),
                ...grouped.loose.map(device => ({ device }))
            ];
        }
        if ("hardware" in node) return node.devices.map(device => ({ device }));
        if ("device" in node) return details(node.device).map(([detail, value]) => ({ detail, value, parent: node.device.id }));
        return [];
    }

    getTreeItem(node: Node): vscode.TreeItem {
        if ("basic" in node) {
            // The program in memory, opened in an editor where saving puts it back.
            const item = new vscode.TreeItem("BASIC program", vscode.TreeItemCollapsibleState.None);
            item.id = "basic";
            item.description = basicDescription(node.basic);
            item.tooltip = new vscode.MarkdownString(`**BASIC program**: the ${node.basic.displayName} program in the machine's memory. `
                + "Open it to read or edit it; saving puts it back in memory.");
            item.iconPath = new vscode.ThemeIcon("file-code");
            item.contextValue = "basicProgram";
            item.command = { command: "retrocore.basic.open", title: "Open BASIC Program" };
            return item;
        }
        if ("detail" in node) {
            const item = new vscode.TreeItem(node.detail, vscode.TreeItemCollapsibleState.None);
            item.description = node.value;
            item.tooltip = node.value;
            item.id = `${node.parent}/${node.detail}`;
            return item;
        }
        if ("hardware" in node) {
            // A slot or option is open when there is a drive on it, as the drives are what is used most.
            const row = node.hardware;
            const item = new vscode.TreeItem(row.name,
                node.devices.length > 0 ? vscode.TreeItemCollapsibleState.Expanded : vscode.TreeItemCollapsibleState.None);
            item.id = `hardware/${row.id}`;
            item.description = row.value;
            item.tooltip = new vscode.MarkdownString(`**${row.name}**: ${row.value.replace(/[\\`*_]/g, "\\$&")}\n\n`
                + row.description.replace(/[\\`*_]/g, "\\$&"));
            item.iconPath = new vscode.ThemeIcon(row.value === "empty" || row.value === "none" ? "circle-outline" : "circuit-board");
            item.contextValue = ["hardware", ...row.actions ?? []].join(" ");
            return item;
        }

        const device = node.device;
        const item = new vscode.TreeItem(device.name, vscode.TreeItemCollapsibleState.Collapsed);
        item.id = device.id;
        item.description = summary(device);
        item.iconPath = new vscode.ThemeIcon(
            device.kind === "tapeDrive" ? "record-keys" : device.kind === "blockStorage" ? "database" : "save",
            device.activity === "writing" ? new vscode.ThemeColor("charts.red")
                : device.activity === "reading" ? new vscode.ThemeColor("charts.green")
                : device.activity === "seeking" ? new vscode.ThemeColor("charts.yellow")
                : undefined);
        const tooltip = new vscode.MarkdownString(`**${device.name}**: ${device.description}\n\n`);
        for (const [detail, value] of details(device)) tooltip.appendMarkdown(`- ${detail}: ${value.replace(/[\\`*_]/g, "\\$&")}\n`);
        item.tooltip = tooltip;

        // Menus pick their actions by these words.
        const words = ["device", device.media ? "loaded" : "empty"];
        if (device.operations.includes("insert")) words.push("insert");
        if (device.operations.includes("record")) words.push("record");
        if (device.media && device.operations.includes("eject")) words.push("eject");
        if (device.media && device.operations.includes("writeProtect")) words.push(device.media.writeProtected ? "unprotect" : "protect");
        if (device.media && device.operations.includes("save")) words.push("save");
        if (device.media?.changed && device.operations.includes("save")) words.push("changed");
        item.contextValue = words.join(" ");
        return item;
    }
}

/** Registers the Retro Devices view and its actions. */
export function registerDevices(context: vscode.ExtensionContext, basic: BasicPrograms): void {
    const tree = new DeviceTree();
    const showBasic = (): void => {
        tree.basic = basic.summary(vscode.debug.activeDebugSession);
        tree.show({ devices: tree.devices, hardware: tree.hardware });
    };
    context.subscriptions.push(basic.onDidChange(session => {
        if (session.id === vscode.debug.activeDebugSession?.id || tree.basic !== undefined) showBasic();
    }));
    let pending: Devices | undefined;
    let timer: NodeJS.Timeout | undefined;

    // Running sends retro/devices as often as a head moves; the view redraws at most ten times a second.
    const show = (body: Devices): void => {
        pending = body;
        timer ??= setTimeout(() => {
            timer = undefined;
            if (pending) tree.show(pending);
        }, 100);
    };
    const refresh = async (session: vscode.DebugSession | undefined): Promise<void> => {
        tree.basic = basic.summary(session);
        if (session?.type !== "retrocore") { show({ devices: [] }); return; }
        try { show(await session.customRequest("retro/devices")); } catch { /* Not launched yet. */ }
    };

    context.subscriptions.push(vscode.window.registerTreeDataProvider("retrocore.devices", tree));
    context.subscriptions.push(vscode.debug.onDidReceiveDebugSessionCustomEvent(event => {
        if (event.event === "retro/devices" && event.session.id === vscode.debug.activeDebugSession?.id) show(event.body);
    }));
    context.subscriptions.push(vscode.debug.onDidChangeActiveDebugSession(session => void refresh(session)));
    context.subscriptions.push(vscode.debug.onDidTerminateDebugSession(() => void refresh(vscode.debug.activeDebugSession)));

    const act = async (node: Node | undefined, action: string, args: Record<string, unknown> = {}): Promise<void> => {
        const session = vscode.debug.activeDebugSession;
        if (session?.type !== "retrocore" || node === undefined || !("device" in node)) return;
        try {
            show(await session.customRequest("retro/device", { id: node.device.id, action, ...args }));
        } catch (error) {
            await vscode.window.showErrorMessage(`Retrocore: ${String(error)}`);
        }
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
    // Cards go in and come out while the machine runs, as nothing on the bus minds here.
    const change = async (node: Node | undefined, args: Record<string, unknown>): Promise<void> => {
        const session = vscode.debug.activeDebugSession;
        if (session?.type !== "retrocore" || node === undefined || !("hardware" in node)) return;
        try {
            show(await session.customRequest("retro/hardware", { id: node.hardware.id, ...args }));
        } catch (error) {
            await vscode.window.showErrorMessage(`Retrocore: ${String(error)}`);
        }
    };
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.hardware.addCard", async (node?: Node) => {
        if (node === undefined || !("hardware" in node)) return;
        const card = await vscode.window.showQuickPick(cardsFor(node.hardware.id), { title: `Add a card to ${node.hardware.name}` });
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
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.list", () => tree.devices));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.hardware", () => tree.hardware));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.basic", () =>
        tree.basic === undefined ? undefined : basicDescription(tree.basic)));
}
