// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The installed hardware the Retro Devices view lists: each built-in part, slot or option, from retro/devices.

/** A row of a machine's installed hardware, as the debug host's retro/devices describes it. */
export interface HardwareRow {
    id: string;
    name: string;
    value: string;
    description: string;
    devices: string[];
    /** What retro/hardware can do to the row: addCard for a free slot, removeCard for a card that can come out. */
    actions?: string[];
    /** The switches on it, such as a card's DIP switches, which retro/hardware's setSetting changes. */
    settings?: HardwareSetting[];
}

/** A switch on a piece of hardware, shown as a checkbox under its row. */
export interface HardwareSetting {
    id: string;
    label: string;
    value: boolean;
    description: string;
}

/** A card Add Card offers, the retro/hardware arguments that add it, and the slots it goes in, if not slots 1 to 7. */
export interface Card { label: string; detail: string; args: Record<string, unknown>; slots?: string[] }

/** The cards Add Card offers. */
export const cards: Card[] = [
    { label: "Disk II controller", detail: "16-sector: DOS 3.3 and ProDOS disks", args: { action: "addDiskII", sectors: 16 } },
    { label: "Disk II controller, 13-sector", detail: "DOS 3.2 and earlier disks", args: { action: "addDiskII", sectors: 13 } },
    {
        label: "Mockingboard", detail: "Two AY-3-8910 sound chips; Sound: speaker + Mockingboard plays them",
        args: { action: "addMockingboard" }, slots: ["slot4"]
    },
    {
        label: "Z80 SoftCard", detail: "Microsoft's Z80 card, for CP/M; one at a time",
        args: { action: "addSoftCard" }
    },
    {
        label: "Language card", detail: "16 KB of RAM at $D000-$FFFF, for slot 0 of a II or II Plus",
        args: { action: "addLanguageCard" }, slots: ["slot0"]
    },
    {
        label: "Firmware card", detail: "The other BASIC in ROM: AppleSoft on a II, Integer BASIC on a II Plus",
        args: { action: "addFirmwareCard" }, slots: ["slot0"]
    }
];

/** The cards a slot takes: slot 0 the language or firmware card, slots 1 to 7 the others. */
export function cardsFor(slot: string): Card[] {
    return cards.filter(card => card.slots === undefined ? slot !== "slot0" : card.slots.includes(slot));
}

/** The view's top level: the hardware rows, each with the devices on it, then any devices no row claims. */
export function group<T extends { id: string }>(hardware: HardwareRow[] | undefined, devices: T[]):
    { rows: { row: HardwareRow; devices: T[] }[]; loose: T[] } {
    const byId = new Map(devices.map(device => [device.id, device]));
    const claimed = new Set<string>();
    const rows = (hardware ?? []).map(row => ({
        row,
        devices: row.devices.flatMap(id => {
            const device = byId.get(id);
            if (device === undefined) return [];
            claimed.add(id);
            return [device];
        })
    }));
    return { rows, loose: devices.filter(device => !claimed.has(device.id)) };
}

/** The launch options that decide a machine's hardware and media. A change to any of them starts it afresh. */
export const hardwareOptions = [
    "machine", "model", "romDirectory", "rom", "revision", "ramKilobytes", "expansionInterface", "diskController",
    "lowercase", "characterGenerator", "doubler", "cassette", "disks", "diskImage", "dos", "dosYear", "diskSectors",
    "diskBootRom", "diskSequencerRom", "sequencerLayout", "mockingboard", "sound", "slot0", "monitor", "boardRevision",
    "firmwareCardRoms", "programmersAid", "softCard"
] as const;

/** A saved machine: the configuration from the debug host, and the hardware options it was saved under. */
export interface SavedMachine {
    fingerprint: string;
    configuration: unknown;
}

/** The hardware options a launch configuration gives, as one string to compare. */
export function fingerprint(configuration: Record<string, unknown>): string {
    return JSON.stringify(hardwareOptions.map(option => configuration[option] ?? null));
}

/**
 * The configuration to restore at a launch: the saved one when the launch's hardware options are the ones it was saved
 * under, otherwise none.
 */
export function restorable(saved: SavedMachine | undefined, configuration: Record<string, unknown>): unknown {
    return saved !== undefined && saved.fingerprint === fingerprint(configuration) ? saved.configuration : undefined;
}
