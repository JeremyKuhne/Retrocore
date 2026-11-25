// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The Retrocore activity bar's views. Machine: the launched machine, whether it runs, its installed hardware slot by
// slot, its memory and banks, and its BASIC program. Drives: its floppy drives, tape drives and block storage under the controllers they sit
// on, with their media and state. Both from the debug host's retro/devices request and event, with actions through
// retro/device and retro/hardware.

import * as vscode from "vscode";
import * as path from "node:path";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { mkdirSync, writeFileSync } from "node:fs";
import { cardsFor, group, type HardwareRow, type HardwareSetting } from "./hardware";
import type { BasicPrograms, BasicSummary } from "./basic";
import { catalogMachine, settingValue, type MachineChoice } from "./machines";
import { favoriteChoices, type Favorites } from "./favorites";
import type { OffMachine, OffTarget } from "./offMachine";
import type { SavedMachines } from "./savedMachine";
import { bankDetail, type MemoryBank } from "./memory";
import { languageRequest } from "./languageClient";
import {
    changeWords, conflictQuestion, contextWords, discardedMessage, iconName, iconSvg, keptSummary, leaveQuestion,
    lockState, lossless, lossyQuestion, mark, readOnlyQuestion, revertedMessage, savedMessage, stoppedMessage, summary,
    tooltipLines, unsavedDisks, crashedMessage, discardKept, discardKeptQuestion, letGoQuestion, saveAllKept, type Device, type Differences, type KeptDisk, type Question
} from "./drives";

/** What retro/device and retro/hardware say back about media, beside the devices, to a client that speaks it. */
interface MediaAnswer {
    outcome?: "saved" | "changed" | "conflict" | "losses" | "readOnly" | "reverted" | "discarded" | "undone" | "inserted" | "differences";
    undo?: string | null;
    ejected?: string;
    differences?: Differences | null;
    device?: string;
    label?: string;
    medium?: string;
    generation?: number;
    format?: string;
    losses?: string[];
    notes?: string[];
    backup?: string;
    reason?: "noImage" | "format" | "file" | "access";
    path?: string;
    baseline?: { length: number; written: string; sha256: string } | null;
    current?: { length: number; written: string; sha256: string } | null;
}

/** Where a change goes: a running session's machine, or the off machine the language server builds. */
interface Target {
    /** Sends retro/hardware or retro/device, or its off machine's change, and gives the devices with media's answer. */
    request(request: "hardware" | "device", args: Record<string, unknown>): Promise<Devices & MediaAnswer>;
    /** Whether a question about it still stands: it is still the machine the views show. */
    still(): boolean;
    /** Shows its devices, as an answer brings them. */
    show(body: Devices): void;
    /** Its devices as last read, which may not be the ones the views show. */
    devices(): Device[];
    /** Whether a disk it lets go can be put back with Undo: a running machine's can, an off one's cannot. */
    undoes: boolean;
}

/** The retro/devices body. */
interface Devices {
    devices: Device[];
    hardware?: HardwareRow[];
    /** Whether the session keeps its changed disks in its recovery journal, for the next launch. */
    recovery?: boolean;
}

/**
 * A row of the Machine or Drives view: the machine itself, its settings and each setting, a piece of its installed
 * hardware and the switches on it, a controller its drives are listed under, a device, one line of a device's details,
 * or the BASIC program in memory.
 */
type Node = { machine: HardwareRow | undefined } | { switcher: true } | { settings: MachineChoice[] } | { setting: MachineChoice }
    | { hardware: HardwareRow; devices: Device[] } | { switch: HardwareSetting; row: HardwareRow }
    | { controller: HardwareRow; devices: Device[] } | { device: Device } | { detail: string; value: string; parent: string }
    | { kept: KeptDisk; device: Device }
    | { basic: BasicSummary } | { memory: MemoryBank[] } | { bank: MemoryBank };

/** The machines whose screens the media folder draws, by the launch's machine option. */
// As the display panel picks them: the Model III, 4 and the Altair's terminal glow white like the Model I, and the
// Model II and the Kaypro II green like the IIe.
const screens: Record<string, string> = {
    apple2: "apple2", apple3: "apple2", apple1: "apple1", coco: "coco", "trs80-model1": "trs80-model1",
    "trs80-model3": "trs80-model1", "trs80-model4": "trs80-model1", altair: "trs80-model1", "trs80-model2": "apple2",
    pet: "trs80-model1",
    kaypro2: "apple2",
    bbc: "coco",
    atari800: "coco"
};

/** What a device holds, as its questions name it: a tape or a disk (block storage's volumes are disks too). */
export function mediumOf(device: Device): "tape" | "disk" {
    return device.kind === "tapeDrive" ? "tape" : "disk";
}

/**
 * The files a device's Insert offers: its formats, and on a PET a .prg too, which goes in as the tape SAVE writes.
 */
export function insertFormats(device: Device, machine: unknown): string[] {
    return machine === "pet" && device.kind === "tapeDrive" && !device.formats.includes("prg") ? [...device.formats, "prg"] : device.formats;
}

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

/** The detail rows under a device. */
export function details(device: Device): [string, string][] {
    const rows: [string, string][] = [
        ["Media", device.media ? `${device.media.label} (${device.media.format})` : "none"],
        ["Activity", device.activity]
    ];
    if (device.media) {
        rows.push(["Lock", lockState(device.media).toLowerCase()]);
        if (device.operations.includes("save")) rows.push(["Changed", device.media.changed ? "yes, not saved to the image" : "no"]);
        const source = device.media.source;
        if (source?.stale) rows.push(["Image", source.current === null ? "deleted since it was read" : "changed on disk since it was read"]);
        else if (source?.readOnly === "file") rows.push(["Image", "a read-only file"]);
        else if (source?.readOnly === "format") rows.push(["Image", `${device.media.format}, which can only be read`]);
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
    /** The running machine's memory as the CPU maps it and its banks, from retro/memoryBanks; empty while off. */
    banks: MemoryBank[] = [];
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

    constructor(private readonly state: MachineState, private readonly extension: vscode.Uri, private readonly favorites: Favorites) {
        state.onDidChange(() => this.changed.fire(undefined));
    }

    getChildren(node?: Node): Node[] {
        if (node === undefined) {
            if (this.state.session === undefined && this.state.off === undefined) return [];
            return [
                { machine: this.state.hardware.find(row => row.id === "model") },
                // While it runs, its memory opens in Retrocore Memory from here.
                ...this.state.session === undefined || this.state.banks.length === 0 ? [] : [{ memory: this.state.banks }],
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
        if ("hardware" in node) return (node.hardware.settings ?? []).map(setting => ({ switch: setting, row: node.hardware }));
        if ("memory" in node && node.memory.length > 1) return node.memory.map(bank => ({ bank }));
        return [];
    }

    // The configuration the machine shown was launched with, or will be.
    private configuration(): Record<string, unknown> {
        return (this.state.session?.configuration as Record<string, unknown> | undefined) ?? this.state.off ?? {};
    }

    // Revealing a row, as bringing the views back does, needs its parent: the machine for a piece of hardware.
    getParent(node: Node): Node | undefined {
        if ("setting" in node) return { settings: catalogMachine(this.configuration())?.choices ?? [] };
        if ("switch" in node) return { hardware: node.row, devices: [] };
        if ("bank" in node) return { memory: this.state.banks };
        return "hardware" in node || "settings" in node ? { machine: this.state.hardware.find(row => row.id === "model") } : undefined;
    }

    getTreeItem(node: Node): vscode.TreeItem {
        if ("machine" in node) return this.machineItem(node.machine);
        if ("basic" in node) return basicItem(node.basic);
        if ("memory" in node) return memoryItem(node.memory);
        if ("bank" in node) return bankItem(node.bank);
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
        if ("switch" in node) return switchItem(node.switch, node.row);
        if (!("hardware" in node)) return new vscode.TreeItem("");

        // A row with switches opens to them.
        const row = node.hardware;
        const item = new vscode.TreeItem(row.name,
            (row.settings?.length ?? 0) > 0 ? vscode.TreeItemCollapsibleState.Collapsed : vscode.TreeItemCollapsibleState.None);
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

        // The heart beside it: empty when it is not a favorite, filled when it is one as saved, broken when it has
        // changed since.
        const mark = this.favorites.mark();
        const favorite = mark.kept === undefined ? "" : escape(mark.kept.favorite.name);
        tooltip.appendMarkdown(mark.state === "none"
            ? "\n\nNot in your favorites: the empty heart saves it, with its settings, cards and disks."
            : mark.state === "saved"
                ? `\n\nSaved in your favorites as *${favorite}*.`
                : `\n\nSaved in your favorites as *${favorite}*, but ${(mark.differences ?? []).join(", ")} changed since: the broken heart updates it.`);
        item.tooltip = tooltip;
        item.contextValue = [off !== undefined ? "machine off" : "machine", `heart-${mark.state}`].join(" ");
        return item;
    }
}

/** A switch on a card, as a checkbox: ticking it sets it at once, running or off. */
function switchItem(setting: HardwareSetting, row: HardwareRow): vscode.TreeItem {
    const item = new vscode.TreeItem(setting.label, vscode.TreeItemCollapsibleState.None);
    item.id = `hardware/${row.id}/${setting.id}`;
    item.description = setting.value ? "on" : "off";
    item.tooltip = new vscode.MarkdownString(`**${escape(setting.label)}**: ${escape(setting.description)}`);
    item.checkboxState = setting.value ? vscode.TreeItemCheckboxState.Checked : vscode.TreeItemCheckboxState.Unchecked;
    item.contextValue = "hardwareSetting";
    return item;
}

/**
 * The Memory row: with banks, they are listed under it, each opened with a click; without, a click on it opens the
 * CPU's 64K.
 */
function memoryItem(banks: MemoryBank[]): vscode.TreeItem {
    const single = banks.length === 1;
    const item = new vscode.TreeItem("Memory", single ? vscode.TreeItemCollapsibleState.None : vscode.TreeItemCollapsibleState.Collapsed);
    item.id = "memory";
    item.iconPath = new vscode.ThemeIcon("file-binary");
    item.description = single ? "$0000-$FFFF" : `the CPU's 64K and ${banks.length - 1} bank${banks.length === 2 ? "" : "s"}`;
    item.tooltip = new vscode.MarkdownString(single
        ? "**Memory**: the CPU's 64K. Open it in Retrocore Memory to read, edit, search and freeze bytes."
        : "**Memory**: the CPU's 64K as it maps it now, and each bank of RAM and ROM, mapped or not. Open one in "
            + "Retrocore Memory to read, edit, search and freeze bytes.");
    item.contextValue = "memory";
    if (single) item.command = { command: "retrocore.memory.openReference", title: "Open in Retrocore Memory", arguments: [banks[0].memoryReference] };
    return item;
}

/** A bank under the Memory row, or the CPU's 64K: where the memory map reads and writes it now. */
function bankItem(bank: MemoryBank): vscode.TreeItem {
    const item = new vscode.TreeItem(bank.name === null ? "CPU" : bank.label, vscode.TreeItemCollapsibleState.None);
    item.id = `memory/${bank.name ?? "cpu"}`;
    item.iconPath = new vscode.ThemeIcon(bank.name === null ? "chip" : bank.readOnly ? "lock" : "server");
    item.description = bankDetail(bank);
    const prefix = bank.name === null ? "" : `\n\nAddresses in it take the prefix \`${bank.name}:\`, as in \`${bank.name}:$0400\`.`;
    item.tooltip = new vscode.MarkdownString(`**${escape(bank.label)}**: ${escape(bankDetail(bank))}${prefix}`);
    item.contextValue = "memoryBank";
    item.command = { command: "retrocore.memory.openReference", title: "Open in Retrocore Memory", arguments: [bank.memoryReference] };
    return item;
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

    constructor(private readonly state: MachineState, private readonly icons: (name: string) => { light: vscode.Uri; dark: vscode.Uri },
        private readonly changes: (device: Device) => Promise<string | undefined>) {
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
        // The disks the machine ejected come first under their drive, then its details.
        if ("device" in node) {
            return [
                ...(node.device.ejected ?? []).map(kept => ({ kept, device: node.device })),
                ...details(node.device).map(([detail, value]) => ({ detail, value, parent: node.device.id }))
            ];
        }
        return [];
    }

    // A changed disk's tooltip says what changed, which the host works out only when the pointer is on the row; VS Code
    // asks for it here only for a row whose tooltip was left undefined.
    async resolveTreeItem(item: vscode.TreeItem, node: Node): Promise<vscode.TreeItem> {
        if (!("device" in node) || item.tooltip !== undefined) return item;
        item.tooltip = driveTooltip(node.device, await this.changes(node.device));
        return item;
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
        if ("kept" in node) return keptItem(node.kept, node.device);
        if (!("device" in node)) return new vscode.TreeItem("");

        // The drive's own picture with its lock as a badge, in the colour of what it is doing; the mark at the row's
        // end, from the drive decorations, says whether the disk changed and whether its image did.
        const device = node.device;
        const item = new vscode.TreeItem(device.name, (device.ejected?.length ?? 0) > 0
            ? vscode.TreeItemCollapsibleState.Expanded
            : vscode.TreeItemCollapsibleState.Collapsed);
        item.id = device.id;
        item.description = summary(device);
        item.iconPath = this.icons(iconName(device));
        item.resourceUri = driveUri(device);
        if (!device.media?.changed || this.state.session === undefined) item.tooltip = driveTooltip(device);
        item.contextValue = contextWords(device, this.state.session !== undefined).join(" ");
        return item;
    }
}

/** A drive's tooltip: its name and kind, then the disk, its image, the lock and the head; with what changed, once known. */
function driveTooltip(device: Device, changes?: string): vscode.MarkdownString {
    const tooltip = new vscode.MarkdownString(`**${escape(device.name)}**: ${escape(device.description)}\n\n`);
    tooltip.appendMarkdown(tooltipLines(device, new Date(), changes).map(line => escape(line)).join("  \n"));
    return tooltip;
}

/** A disk the machine ejected, under its drive: what it is and when it left, with its save, put back and let go. */
function keptItem(kept: KeptDisk, device: Device): vscode.TreeItem {
    const item = new vscode.TreeItem("Ejected", vscode.TreeItemCollapsibleState.None);
    item.id = `${device.id}/ejected/${kept.id}`;
    item.description = keptSummary(kept);
    item.iconPath = new vscode.ThemeIcon("debug-step-out");
    item.resourceUri = vscode.Uri.from({ scheme: driveScheme, path: `/${device.id}/${kept.id}`, query: kept.changed ? "changed" : "" });
    item.tooltip = new vscode.MarkdownString(`**${escape(path.basename(kept.label))}** (${escape(kept.format)}), ejected from `
        + `${escape(device.name)} by the machine with changes not saved.\n\nSave it, put it back in the drive, or let it go.`);
    item.contextValue = "ejectedDisk";
    return item;
}

/** The scheme of the drives' rows, which the drive decorations mark. */
const driveScheme = "retrocore-drive";

/** A drive row's resource, whose query is the mark it gets: changed, stale, conflict or none. */
const driveUri = (device: Device): vscode.Uri => vscode.Uri.from({ scheme: driveScheme, path: `/${device.id}`, query: mark(device) ?? "" });

/** The marks at the end of the drive rows, as Git marks a changed file: ● changed, ⚠ an image changed on disk. */
class DriveDecorations implements vscode.FileDecorationProvider {
    provideFileDecoration(uri: vscode.Uri): vscode.FileDecoration | undefined {
        if (uri.scheme !== driveScheme) return undefined;
        switch (uri.query) {
            case "changed":
                return { badge: "●", tooltip: "Changed, not saved to its image", color: new vscode.ThemeColor("gitDecoration.modifiedResourceForeground") };
            case "stale":
                return { badge: "⚠", tooltip: "Its image changed on disk", color: new vscode.ThemeColor("list.warningForeground") };
            case "conflict":
                return { badge: "⚠", tooltip: "Changed, and its image changed on disk too", color: new vscode.ThemeColor("list.warningForeground") };
            case "behind":
                return { badge: "⚠", tooltip: "Changed, and its recovery copy is behind", color: new vscode.ThemeColor("list.warningForeground") };
            default:
                return undefined;
        }
    }
}

/**
 * The drives' icons, written once to the extension's storage, as a tree row's icon must be a file: each name's light
 * and dark SVGs, under a name that changes with the drawing so a new one is not taken from the cache.
 */
function driveIcons(storage: vscode.Uri): (name: string) => { light: vscode.Uri; dark: vscode.Uri } {
    const folder = vscode.Uri.joinPath(storage, "drive-icons");
    const written = new Map<string, { light: vscode.Uri; dark: vscode.Uri }>();
    return name => {
        const known = written.get(name);
        if (known !== undefined) return known;
        const uris = { light: icon(folder, name, false), dark: icon(folder, name, true) };
        written.set(name, uris);
        return uris;
    };
}

/** Writes one icon, if it is not there already, and gives its file. */
function icon(folder: vscode.Uri, name: string, dark: boolean): vscode.Uri {
    const svg = iconSvg(name, dark);
    const file = vscode.Uri.joinPath(folder, `${name}-${dark ? "dark" : "light"}-${createHash("sha256").update(svg).digest("hex").slice(0, 8)}.svg`);
    try {
        mkdirSync(folder.fsPath, { recursive: true });
        writeFileSync(file.fsPath, svg, { flag: "wx" });
    } catch { /* Written already, or by another window. */ }
    return file;
}

/** The requests that set a stopped machine running again. */
const resumes = new Set(["continue", "next", "stepIn", "stepOut", "stepBack", "reverseContinue", "goto"]);

/** Registers the Retrocore activity bar's Machine and Drives views and their actions. */
export function registerDevices(context: vscode.ExtensionContext, basic: BasicPrograms, saved: SavedMachines, off: OffMachine, favorites: Favorites): void {
    const tree = new MachineState();
    const showBasic = (): void => {
        tree.basic = basic.summary(vscode.debug.activeDebugSession);
        tree.show({ devices: tree.devices, hardware: tree.hardware });
    };
    context.subscriptions.push(basic.onDidChange(session => {
        if (session.id === vscode.debug.activeDebugSession?.id || tree.basic !== undefined) showBasic();
    }));
    let pending: Devices | undefined;
    let timer: NodeJS.Timeout | undefined;
    // Each session's devices as it last sent them, shown or not, so one that stops in the background can say what it
    // took with it.
    const sessionDevices = new Map<string, Devices>();

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
            // Another session's banks are not this one's.
            if (tree.session?.id !== session.id) tree.banks = [];
            tree.session = session;
            tree.off = undefined;
            void vscode.commands.executeCommand("setContext", "retrocore.machineOff", false);
            machineView.message = undefined;
            try {
                const body = await session.customRequest("retro/devices") as Devices;
                sessionDevices.set(session.id, body);
                show(body);
            } catch { /* Not launched yet. */ }
            await readBanks(session);
            return;
        }
        tree.session = undefined;
        tree.banks = [];
        stale = true;
        showOff();
        if (showing()) await describeOff();
    };
    // The Memory rows say where the memory map has each bank, which the soft switches change as the machine runs:
    // they are read again at each stop.
    // A reply for a session no longer shown, as when another becomes active while it is read, is dropped.
    const readBanks = async (session: vscode.DebugSession): Promise<void> => {
        let banks: MemoryBank[];
        try {
            banks = (await session.customRequest("retro/memoryBanks") as { banks: MemoryBank[] }).banks;
        } catch {
            // Not launched yet; the first stop reads them.
            banks = [];
        }
        if (session.id !== tree.session?.id) return;
        tree.banks = banks;
        tree.redraw();
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
    // A favorite saved, updated or removed changes the heart.
    context.subscriptions.push(favorites.onDidChange(() => tree.redraw()));

    const machineView = vscode.window.createTreeView("retrocore.machine", { treeDataProvider: new MachineTree(tree, context.extensionUri, favorites) });
    const drives = new DriveTree(tree, driveIcons(context.globalStorageUri), device => changesOf(device));
    const drivesView = vscode.window.createTreeView("retrocore.drives", { treeDataProvider: drives });
    context.subscriptions.push(machineView, drivesView, vscode.window.registerFileDecorationProvider(new DriveDecorations()));

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
    // An edit to launch.json may be the off machine's own entry, which it reads again when next described.
    context.subscriptions.push(vscode.workspace.onDidChangeConfiguration(event => {
        if (tree.session !== undefined || off.target?.source.kind !== "launch" || !event.affectsConfiguration("launch")) return;
        stale = true;
        seen();
    }));
    context.subscriptions.push(saved.onDidReset(() => {
        if (tree.session !== undefined) return;
        stale = true;
        seen();
    }));
    // The Drives view's badge counts the disks changed in the machine and not yet saved to their images.
    context.subscriptions.push(tree.onDidChange(() => {
        const changed = tree.devices.filter(device => device.media?.changed && device.operations.includes("save")).length
            + tree.devices.reduce((count, device) => count + (device.ejected ?? []).filter(kept => kept.changed).length, 0);
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
                onDidSendMessage(message: { event?: string; body?: { areas?: string[] } }) {
                    if (message.event === "stopped") {
                        set(true);
                        if (session.id === tree.session?.id) void readBanks(session);
                    }
                    // A card put in or taken out while stopped, such as a SoftCard, adds or removes a bank.
                    else if (message.event === "invalidated" && message.body?.areas?.includes("all")) {
                        if (session.id === tree.session?.id) void readBanks(session);
                    }
                    else if (message.event === "continued") set(false);
                },
                onExit() { tree.paused.delete(session.id); }
            };
        }
    }));
    context.subscriptions.push(vscode.debug.onDidReceiveDebugSessionCustomEvent(event => {
        if (event.event !== "retro/devices") return;
        sessionDevices.set(event.session.id, event.body as Devices);
        if (event.session.id === vscode.debug.activeDebugSession?.id) show(event.body);
    }));
    context.subscriptions.push(vscode.debug.onDidChangeActiveDebugSession(session => void refresh(session)));
    // As a session ends VS Code can still give it as the active one; it is not, so the views show its machine off.
    context.subscriptions.push(vscode.debug.onDidTerminateDebugSession(ended => {
        // A session that ends with disks not saved says so, shown or in the background: kept in its recovery journal
        // for its next launch, or, for a session that keeps none, gone.
        const last = sessionDevices.get(ended.id);
        sessionDevices.delete(ended.id);
        const { kept, lost } = unsavedDisks(last?.devices ?? (ended.id === tree.session?.id ? tree.devices : []), last?.recovery === true);
        const machine = String(ended.configuration.name ?? "The machine");
        const recoveryId = typeof ended.configuration.recoveryId === "string" ? ended.configuration.recoveryId : undefined;
        if (kept.length + lost.length > 0) {
            const message = stoppedMessage(machine, kept, lost);
            // The kept disks are the off machine's now: saved there, shown in its Drives view, or let go.
            const buttons = kept.length !== 0 && recoveryId !== undefined ? ["Save All", "Review", "Discard"] : [];
            void (lost.length === 0 ? vscode.window.showInformationMessage(message, ...buttons) : vscode.window.showWarningMessage(message, ...buttons))
                .then(choice => recoveryId === undefined ? undefined : onKeptDisks(choice, recoveryId, machine, ended.id));
        }
        const active = vscode.debug.activeDebugSession;
        void refresh(active?.id === ended.id ? undefined : active);
    }));

    // What a person chose for a machine's kept disks, from its stop notice or its crash notice. Save All saves each
    // through the off machine, asking only as Save does; Review shows them in the Drives view; Discard asks once, as
    // nothing can put them back. It asks about the disks the journal keeps now, as the machine may have run again
    // since the notice, and asks again if it keeps others by the time the answer comes.
    const onKeptDisks = async (choice: string | undefined, recoveryId: string, machine: string, ended?: string): Promise<void> => {
        if (choice === undefined) return;
        if (choice === "Discard") {
            try {
                const outcome = await discardKept(
                    async () => (await languageRequest<{ journals: { disks: string[]; revision: string }[] }>(
                        "retrocore/recovery/list", { id: recoveryId })).journals[0],
                    async disks => await ask(discardKeptQuestion(machine, disks)) === "Discard",
                    async revision => await languageRequest<{ outcome?: string }>("retrocore/recovery/resolve",
                        { id: recoveryId, action: "discard", revision }));
                if (outcome === "kept") return;
                if (outcome === "none") void vscode.window.showInformationMessage(`Retrocore: ${machine} keeps no disks to discard now, or is running.`);
            } catch (error) {
                void vscode.window.showErrorMessage(`Retrocore: ${error instanceof Error ? error.message : String(error)}`);
            }
            if (off.recoveryId === recoveryId) await off.describe();
            return;
        }
        if (!await off.showRecovery(recoveryId)) {
            void vscode.window.showInformationMessage(`Retrocore: start ${machine} to see the disks it kept.`);
            return;
        }
        // The views show a running session's machine; the stopped one's disks are shown once none runs, and Save All
        // saves them meanwhile. The session that just ended can still be given as the active one; it is not running.
        const active = vscode.debug.activeDebugSession;
        const running = active?.type === "retrocore" && active.id !== ended ? active : undefined;
        if (choice !== "Save All") {
            if (running === undefined) {
                await vscode.commands.executeCommand("retrocore.drives.focus");
                return;
            }
            const now = await vscode.window.showInformationMessage(
                `Retrocore: the Drives view shows ${running.name} while it runs, and ${machine}'s kept disks once it stops.`, "Save All");
            if (now !== "Save All") return;
        } else if (running === undefined) {
            await vscode.commands.executeCommand("retrocore.drives.focus");
        }
        // Only the machine whose disks these are: another chosen meanwhile has its own.
        const on = offTarget(true, recoveryId);
        await saveAllKept(off.devices, on.still,
            async (id, ejected) => await sendTo(on, "device", ejected === undefined ? { id, action: "save" } : { id, action: "save", ejected }));
    };

    // A session that did not stop cleanly, found as the extension starts, offers the disks its journal kept: Recover
    // keeps them for the machine's next launch, Review shows them too, and Discard lets them go. A journal of another
    // workspace's machine is that workspace's to offer.
    const offerRecovery = async (): Promise<void> => {
        let journals: { id: string; name?: string | null; kept?: string | null; disks: string[] }[] | undefined;
        // The language server may still be starting, so a failed look is tried again a few times before giving up
        // until the next start; nothing is marked, so the journals are offered then.
        for (let tries = 0; journals === undefined; tries++) {
            try {
                journals = (await languageRequest<{ journals: NonNullable<typeof journals> }>("retrocore/recovery/list", {})).journals;
            } catch {
                if (tries === 4) return;
                await new Promise(resolve => setTimeout(resolve, 3000));
            }
        }
        for (const journal of journals) {
            const owner = saved.recoveryOf(journal.id);
            if (owner === undefined) continue;
            const machine = journal.name ?? owner.name;
            void vscode.window.showWarningMessage(crashedMessage(machine, journal.disks, journal.kept ?? undefined), "Recover", "Review", "Discard")
                .then(async choice => {
                    if (choice === undefined) return;
                    // A machine that launches with another recovery id now would never put these disks back, so they
                    // stay offered rather than being marked recovered; Discard still lets them go.
                    if (choice !== "Discard" && !off.launchesWith(journal.id)) {
                        void vscode.window.showWarningMessage(`Retrocore: ${machine} now launches with another recovery id, `
                            + "so its next launch cannot put these disks back. They stay offered; Discard lets them go.");
                        return;
                    }
                    // Review marks the disks recovered only once they can be shown, so they are offered again if not.
                    if (choice === "Review" && !await off.showRecovery(journal.id)) {
                        void vscode.window.showInformationMessage(`Retrocore: start ${machine} to see the disks it kept.`);
                        return;
                    }
                    if (choice !== "Discard") {
                        try {
                            await languageRequest("retrocore/recovery/resolve", { id: journal.id, action: "recover" });
                        } catch (error) {
                            void vscode.window.showErrorMessage(`Retrocore: ${error instanceof Error ? error.message : String(error)}`);
                            return;
                        }
                    }
                    if (choice === "Recover") {
                        void vscode.window.showInformationMessage(`Retrocore: ${machine}'s next launch puts back the disks it kept, still changed.`);
                        return;
                    }
                    await onKeptDisks(choice, journal.id, machine);
                });
        }
    };
    // The language server starts with the extension; its answer comes once it is up.
    setTimeout(() => void offerRecovery(), 2000);

    // A change goes to the running machine as retro/hardware or retro/device, or to the off machine, whose saved
    // machine its next launch restores.
    const send = async (request: "hardware" | "device", args: Record<string, unknown>): Promise<boolean> => {
        const on = targetNow();
        return on !== undefined && await sendTo(on, request, args);
    };
    // A running session's machine as a target for changes.
    const onSession = (session: vscode.DebugSession): Target => ({
        request: async (request, args) => await session.customRequest(`retro/${request}`, args) as Devices & MediaAnswer,
        still: () => still(session),
        show,
        devices: () => sessionDevices.get(session.id)?.devices ?? (tree.session?.id === session.id ? tree.devices : []),
        undoes: true
    });
    // The off machine as a target: a question about it stands while no session runs and it is still the one shown,
    // or, for a stopped machine's kept disks saved from its notice, while it is still the one shown. Its views follow
    // its own changes, so an answer's devices need no showing.
    const offTarget = (alongside = false, machine?: string): Target => {
        const shown = machine ?? off.recoveryId ?? off.name;
        return {
            request: async (request, args) => await off.request(request, args, shown) as unknown as Devices & MediaAnswer,
            still: () => (alongside || vscode.debug.activeDebugSession?.type !== "retrocore") && (off.recoveryId ?? off.name) === shown,
            show: () => undefined,
            devices: () => off.devices,
            undoes: false
        };
    };
    // The machine the views show: the active session's, or the off one.
    const targetNow = (): Target | undefined => {
        const session = vscode.debug.activeDebugSession;
        if (session?.type === "retrocore") return onSession(session);
        return tree.off !== undefined ? offTarget() : undefined;
    };
    // A change to one machine, with its answers; an error is shown. Says whether it went through.
    const sendTo = async (on: Target, request: "hardware" | "device", args: Record<string, unknown>): Promise<boolean> => {
        try {
            return await answer(on, request, args);
        } catch (error) {
            void vscode.window.showErrorMessage(`Retrocore: ${error instanceof Error ? error.message : String(error)}`);
            return false;
        }
    };
    // Whether a question about a session's machine still stands: the views follow the active session, so one that
    // stopped being active while a question was open has its answer dropped rather than sent to another machine.
    const still = (session: vscode.DebugSession): boolean => vscode.debug.activeDebugSession?.id === session.id;
    // Asks a question a save raises, modally, and gives the button chosen.
    const ask = (question: Question): Thenable<string | undefined> =>
        vscode.window.showWarningMessage(question.message, { modal: true, detail: question.detail }, ...question.buttons);
    // Sends a change to the running machine and answers what media says back, as the media persistence plan's "saving
    // in each state" has it: a save that asks nothing says so in the status bar; a lossy format offers the format that
    // holds it all or saves anyway; a changed image is overwritten or the disk saved as a new one; a read-only file is
    // made writable or the disk saved as a new one; a changed disk that would leave its drive is saved or let go. Says
    // whether the change went through. Each answer goes back for the disk it was about (its mount's generation, or the
    // mount in discards), so a disk that went in while a question was open is never saved or let go by it.
    const answer = async (on: Target, request: "hardware" | "device", args: Record<string, unknown>): Promise<boolean> => {
        let current: Record<string, unknown> = { ...args, supportsRetrocoreMedia: 1 };
        // The image each changed disk asked about came from, to name it when it is let go.
        const labels = new Map<string, string>();
        for (;;) {
            if (!on.still()) return false;
            const body = await on.request(request, current);
            if (!on.still()) return body.outcome === undefined || body.outcome === "saved";
            on.show(body);
            const id = body.device ?? "";
            const generation = body.generation;
            const device = body.devices?.find(candidate => candidate.id === id) ?? on.devices().find(candidate => candidate.id === id);
            const name = device?.name ?? id;
            const medium = device === undefined ? "disk" : mediumOf(device);
            // The file the save was for: the one chosen in Save As, or the disk's own image.
            const target = typeof current.path === "string" ? current.path : device?.media?.source?.path ?? device?.media?.label;
            const file = target ? path.basename(target) : "its image";
            switch (body.outcome) {
                case undefined:
                    return true;
                case "saved": {
                    const said = [...body.notes ?? [], ...body.losses ?? []];
                    if (said.length !== 0) void vscode.window.showInformationMessage(`Retrocore: saved the ${medium} in ${name} to ${file}. ${said.join(" ")}`);
                    else vscode.window.setStatusBarMessage(savedMessage(file, name, body.backup !== undefined), 5000);
                    return true;
                }
                case "changed": {
                    // Save goes through the same checks as the Save button; Discard lets the disk go with Undo.
                    const label = body.label ? path.basename(body.label) : "its image";
                    // What changed is the mounted disk's, so an ejected one's question says none.
                    const changes = body.ejected === undefined ? changeWords(await differencesOf(on, id)) : undefined;
                    const choice = await ask(leaveQuestion(label, name, leaving(current, name), changes));
                    // A disk the machine ejected, which a card's removal would take, is named by its ejected id.
                    const ejected = body.ejected === undefined ? {} : { ejected: body.ejected };
                    if (choice === "Discard") {
                        const discards = Array.isArray(current.discards) ? current.discards : [];
                        current = { ...current, discards: [...discards, { device: id, generation, ...ejected }] };
                        labels.set(id, label);
                    } else if (choice === "Save As...") {
                        if (!await saveAsNew(on, id, generation, ejected)) return false;
                    } else if (choice !== "Save" || !await answer(on, "device", { id, action: "save", generation, ...ejected })) return false;
                    continue;
                }
                case "conflict": {
                    // An image changed on disk since the disk was read can also be read again in its place.
                    const own = body.baseline && body.current && current.ejected === undefined && typeof current.path !== "string"
                        && device?.operations.includes("insert") === true;
                    const question = conflictQuestion(body.path ? path.basename(body.path) : file, name, body.baseline, body.current);
                    const choice = await ask(own ? { ...question, buttons: [...question.buttons, "Revert to Image"] } : question);
                    if (choice !== undefined && choice === question.buttons[0]) {
                        current = { ...current, overwrite: { sha256: body.current?.sha256 ?? null }, generation };
                        continue;
                    }
                    if (choice === "Revert to Image") return revert(on, id, generation);
                    return choice === "Save As..." && await saveAsNew(on, id, generation, current);
                }
                case "losses": {
                    // The format that holds it all, unless that is the one that cannot.
                    const keeps = lossless(device);
                    const offered = keeps === undefined || keeps === body.format?.toLowerCase() ? undefined : keeps;
                    const choice = await ask(lossyQuestion(file, name, body.format ?? "The format", body.losses ?? [], offered));
                    if (choice === "Save Anyway") {
                        current = { ...current, acceptLosses: true, generation };
                        continue;
                    }
                    return offered !== undefined && choice === `Save as ${offered.toUpperCase()}...` && await saveAsNew(on, id, generation, current, offered);
                }
                case "readOnly": {
                    const choice = await ask(readOnlyQuestion(target ? path.basename(target) : undefined, name, device?.media?.format, body.reason));
                    // The host makes the file writable as it saves, for this mount and only over the revision the
                    // save may replace, so an answer left open while the disk or file changed alters nothing.
                    if (choice === "Make Writable and Save") {
                        current = { ...current, makeWritable: true, generation };
                        continue;
                    }
                    return choice === "Save As..." && await saveAsNew(on, id, generation, current);
                }
                // A disk let go of, or replaced by Undo or Insert Again while changed, can be put back.
                case "discarded":
                case "undone":
                case "inserted":
                    if (body.undo) offerUndo(on, id, body.undo, discardedMessage(name, labels.get(id) ?? file));
                    return true;
                default:
                    return true;
            }
        }
    };
    // What would take a changed disk out, as its question says it.
    const leaving = (args: Record<string, unknown>, name: string): string =>
        args.action === "insert" ? `inserting another disk in ${name}`
            : args.action === "undo" ? `putting back the disk ${name} had`
            : args.action === "insertAgain" ? `putting the ejected disk back in ${name}`
            : args.action === "removeCard" ? `removing the card ${name} is on`
            : `ejecting it from ${name}`;
    // What a drive's disk changed against its image, which the host works out on request; undefined when it cannot.
    const differencesOf = async (on: Target, id: string): Promise<Differences | undefined> => {
        try {
            const body = await on.request("device", { id, action: "differences", supportsRetrocoreMedia: 1 });
            return body.differences ?? undefined;
        } catch {
            return undefined;
        }
    };
    const changesOf = async (device: Device): Promise<string | undefined> => {
        const on = targetNow();
        return on === undefined ? undefined : changeWords(await differencesOf(on, device.id));
    };
    // A notification with Undo, which puts back the disk it is about, by the id the host kept it under: a later revert
    // or discard keeps another, and the host refuses this one rather than put back a different disk.
    const offerUndo = (on: Target, id: string, medium: string, message: string): void => {
        void vscode.window.showInformationMessage(message, "Undo").then(async choice => {
            if (choice !== "Undo" || !on.still()) return;
            await sendTo(on, "device", { id, action: "undo", medium });
        });
    };
    // Revert to Image reads the image as it is now in place of the disk, without asking: Undo puts the disk back.
    const revert = async (on: Target, id: string, generation?: number): Promise<boolean> => {
        const device = on.devices().find(candidate => candidate.id === id);
        const file = path.basename(device?.media?.source?.path ?? device?.media?.label ?? "its image");
        const differences = device?.media?.changed ? await differencesOf(on, id) : undefined;
        // Off, nothing puts the changes back, so they are let go only when the person says so.
        if (!on.undoes && device?.media?.changed && await ask(letGoQuestion(device.name, "revert", file)) !== "Revert") return false;
        try {
            if (!on.still()) return false;
            const body = await on.request("device", { id, action: "revert", generation, supportsRetrocoreMedia: 1 });
            // Another session that became active meanwhile keeps its own rows.
            if (!on.still()) return true;
            on.show(body);
            const name = device?.name ?? id;
            if (body.undo) offerUndo(on, id, body.undo, revertedMessage(name, file, differences));
            else vscode.window.setStatusBarMessage(`$(discard) Reverted ${name} to ${file}`, 5000);
            return true;
        } catch (error) {
            void vscode.window.showErrorMessage(`Retrocore: ${error instanceof Error ? error.message : String(error)}`);
            return false;
        }
    };
    const act = async (node: Node | undefined, action: string, args: Record<string, unknown> = {}): Promise<void> => {
        if (node !== undefined && "device" in node) await send("device", { id: node.device.id, action, ...args });
    };
    const filters = (device: Device): Record<string, string[]> => ({ [`${device.name} images`]: device.formats });

    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.insert", async (node?: Node) => {
        if (node === undefined || !("device" in node)) return;
        const formats = insertFormats(node.device, (tree.session?.configuration ?? tree.off)?.machine);
        const file = (await vscode.window.showOpenDialog({
            title: `Insert in ${node.device.name}`, canSelectMany: false, filters: { [`${node.device.name} images`]: formats }
        }))?.[0];
        if (file) await act(node, "insert", { path: file.fsPath });
    }));
    // A Datasette's keys, pressed on the tape in it. RECORD with none in it puts in a blank tape, which is saved later
    // with Save As, as a changed disk is.
    for (const key of ["play", "stop", "rewind"]) {
        context.subscriptions.push(vscode.commands.registerCommand(`retrocore.device.${key}`, (node?: Node) => act(node, key)));
    }
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.recordKey", (node?: Node) => act(node, "record")));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.record", async (node?: Node) => {
        if (node === undefined || !("device" in node)) return;
        const file = await vscode.window.showSaveDialog({ title: `Record from ${node.device.name} to`, filters: filters(node.device) });
        if (file) await act(node, "record", { path: file.fsPath });
    }));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.eject", (node?: Node) => act(node, "eject")));
    // The lock: Lock and Unlock in the menu, and the row's toggle, which shows the lock as it is.
    const lock = (node?: Node): Promise<void> => act(node, "writeProtect", { writeProtected: true });
    const unlock = (node?: Node): Promise<void> => act(node, "writeProtect", { writeProtected: false });
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.protect", lock));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.unprotect", unlock));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.locked", unlock));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.unlocked", lock));
    // Save writes the disk's own image at once, and asks only when something is off: a lossy format, an image changed
    // on disk, or a read-only file. The row's button for a changed image says it will ask.
    const save = (node?: Node): Promise<void> => act(node, "save");
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.save", save));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.saveStale", save));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.revert", async (node?: Node) => {
        const on = targetNow();
        if (node !== undefined && "device" in node && on !== undefined) await revert(on, node.device.id, node.device.media?.generation);
    }));
    // A disk the machine ejected: saved, put back in its drive, or let go with Undo.
    const onKept = async (node: Node | undefined, action: string): Promise<void> => {
        const on = targetNow();
        if (node === undefined || !("kept" in node) || on === undefined) return;
        if (action === "discard" && !on.undoes && node.kept.changed
            && await ask(letGoQuestion(node.device.name, "discard", node.kept.label)) !== "Discard") return;
        if (!on.still()) return;
        await sendTo(on, "device", { id: node.device.id, action, ejected: node.kept.id });
    };
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.ejectedSave", (node?: Node) => onKept(node, "save")));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.ejectedInsert", (node?: Node) => onKept(node, "insertAgain")));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.ejectedDiscard", (node?: Node) => onKept(node, "discard")));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.ejectedSaveAs", async (node?: Node) => {
        const on = targetNow();
        if (node !== undefined && "kept" in node && on !== undefined) await saveAs(on, node.device, undefined, undefined, node.kept);
    }));
    // Save As asks where, and saves the disk there, in the machine of the session it was asked for; says whether it
    // was saved. The person chose the file as it was then, so the save may replace that revision and no later one.
    // An answer's Save As carries the mount it was about, so a disk that went in since is not the one saved.
    // A format given, as a lossy save's offer of the format that holds it all, names the file with its extension.
    // A disk the machine ejected is saved as itself, named by its id among the drive's ejected disks.
    const saveAs = async (on: Target | undefined, device: Device, generation?: number, format?: string,
        kept?: KeptDisk): Promise<boolean> => {
        if (!device.media && kept === undefined) return false;
        const own = kept?.label ?? device.media?.source?.path ?? device.media?.label ?? "";
        const file = await vscode.window.showSaveDialog({
            title: kept === undefined ? `Save the ${mediumOf(device)} in ${device.name} as` : `Save the disk ejected from ${device.name} as`,
            defaultUri: vscode.Uri.file(format === undefined ? own : path.join(path.dirname(own), `${path.parse(own).name}.${format}`)),
            filters: { [mediumOf(device) === "tape" ? "Tape images" : "Disk images"]: device.saveFormats ?? [] }
        });
        if (file === undefined || (on !== undefined && !on.still())) return false;
        const chosen = await readFile(file.fsPath).then(bytes => createHash("sha256").update(bytes).digest("hex"), () => undefined);
        const args: Record<string, unknown> = kept !== undefined
            ? { id: device.id, action: "save", path: file.fsPath, ejected: kept.id }
            : { id: device.id, action: "save", path: file.fsPath, generation: generation ?? device.media?.generation };
        const saving = chosen === undefined ? args : { ...args, overwrite: { sha256: chosen } };
        return on === undefined ? send("device", saving) : sendTo(on, "device", saving);
    };
    // An answer's Save As: for the disk the question was about, in its drive or ejected from it.
    const saveAsNew = async (on: Target, id: string, generation: number | undefined, args: Record<string, unknown>,
        format?: string): Promise<boolean> => {
        const device = on.still() ? on.devices().find(candidate => candidate.id === id) : undefined;
        const kept = typeof args.ejected === "string" ? device?.ejected?.find(candidate => candidate.id === args.ejected) : undefined;
        // An ejected disk no longer kept, put back or let go meanwhile, is not saved as the disk in the drive instead.
        if (typeof args.ejected === "string" && kept === undefined) {
            void vscode.window.showWarningMessage("Retrocore: that ejected disk was put back or let go, so it was not saved.");
            return false;
        }
        return device !== undefined && await saveAs(on, device, generation, format, kept);
    };
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.saveAs", async (node?: Node) => {
        if (node !== undefined && "device" in node) await saveAs(targetNow(), node.device);
    }));
    // Cards go in and come out while the machine runs, as nothing on the bus minds here, and while it is off.
    const change = async (node: Node | undefined, args: Record<string, unknown>): Promise<void> => {
        if (node !== undefined && "hardware" in node) await send("hardware", { id: node.hardware.id, ...args });
    };
    // A switch on a card, such as the SoftCard's address translation, is a checkbox: ticking it sets it at once.
    context.subscriptions.push(machineView.onDidChangeCheckboxState(async event => {
        for (const [node, state] of event.items) {
            if (!("switch" in node)) continue;
            await change({ hardware: node.row, devices: [] }, {
                action: "setSetting", setting: node.switch.id, value: state === vscode.TreeItemCheckboxState.Checked
            });
        }
    }));
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
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.machine.switch", async (given?: unknown) => {
        // The machine row's button passes its row; only the tests give a machine.
        const target = typeof given === "object" && given !== null && "configuration" in given && "source" in given ? given as OffTarget : undefined;
        const picked = target === undefined ? await off.pick(favoriteChoices()) : { target };
        if (picked === undefined) return;
        stale = false;
        await off.select(picked.target, picked.machineState);
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
    // The drive rows as the Drives view draws them, for the tests: each drive's name, summary, menu words, icon file,
    // the mark at its end and its tooltip.
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.driveRows", () => Promise.all(
        drives.getChildren().flatMap(node => "controller" in node ? drives.getChildren(node) : [node])
            .filter(node => "device" in node)
            .map(async node => {
                // As hovering would, a tooltip left for hover is worked out.
                const item = await drives.resolveTreeItem(drives.getTreeItem(node), node);
                const icon = item.iconPath as { light: vscode.Uri } | undefined;
                return {
                    id: item.id, label: item.label, description: item.description, contextValue: item.contextValue,
                    icon: icon?.light.fsPath, mark: item.resourceUri?.query ?? "",
                    tooltip: item.tooltip instanceof vscode.MarkdownString ? item.tooltip.value : item.tooltip
                };
            }))));
    // The Memory rows' labels, descriptions and the references they open, for the tests.
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.machine.memoryRows", () => {
        const provider = new MachineTree(tree, context.extensionUri, favorites);
        const memory = provider.getChildren().find(node => "memory" in node);
        if (memory === undefined) return [];
        return [memory, ...provider.getChildren(memory)].map(node => {
            const item = provider.getTreeItem(node);
            return { label: item.label, description: item.description, opens: item.command?.arguments?.[0] };
        });
    }));
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.device.basic", () =>
        tree.basic === undefined ? undefined : basicDescription(tree.basic)));
    void refresh(vscode.debug.activeDebugSession);
}
