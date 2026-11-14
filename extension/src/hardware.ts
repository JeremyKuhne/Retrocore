// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The installed hardware the Machine view lists: each built-in part, slot or option, from retro/devices.

/** A row of a machine's installed hardware, as the debug host's retro/devices describes it. */
export interface HardwareRow {
    id: string;
    name: string;
    value: string;
    description: string;
    devices: string[];
    /** What retro/hardware can do to the row: addCard for a free slot, removeCard for a card that can come out. */
    actions?: string[];
}

/**
 * A card Add Card offers, the retro/hardware arguments that add it, the slots it goes in, if not any but slot 0, and the
 * machines that take it, if not only the Apple II.
 */
export interface Card { label: string; detail: string; args: Record<string, unknown>; slots?: string[]; machines?: string[] }

/** The cards Add Card offers. */
export const cards: Card[] = [
    { label: "Disk II controller", detail: "16-sector: DOS 3.3 and ProDOS disks", args: { action: "addDiskII", sectors: 16 } },
    { label: "Disk II controller, 13-sector", detail: "DOS 3.2 and earlier disks", args: { action: "addDiskII", sectors: 13 } },
    {
        label: "Mockingboard", detail: "Two AY-3-8910 sound chips; Sound: speaker + Mockingboard plays them",
        args: { action: "addMockingboard" }, slots: ["slot4"]
    },
    {
        label: "Mouse card", detail: "An AppleMouse II-compatible mouse; click the display to move it, Escape to let go",
        args: { action: "addMouse" }
    },
    {
        label: "ProFile interface card", detail: "Apple's ProFile hard disk; insert a .po or .hdv image",
        args: { action: "addProFile" }, machines: ["apple2", "apple3"]
    },
    {
        label: "3.5 disk controller", detail: "Two SuperDrives: 400K and 800K Apple disks, 720K and 1.44 MB MFM disks",
        args: { action: "addDisk35" }
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

/** The cards a machine's slot takes: on the Apple II, slot 0 the language or firmware card, slots 1 to 7 the others. */
export function cardsFor(slot: string, machine = "apple2"): Card[] {
    return cards.filter(card => (card.machines ?? ["apple2"]).includes(machine)
        && (card.slots === undefined ? slot !== "slot0" : card.slots.includes(slot)));
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
    "diskBootRom", "diskSequencerRom", "sequencerLayout", "mockingboard", "mouse", "proFiles", "disk35", "disk35Images",
    "sound", "slot0", "monitor", "boardRevision", "firmwareCardRoms", "programmersAid"
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

/**
 * What of a saved machine differs from the machine its launch gives by itself (base, as retrocore/machine/describe
 * answers with no saved machine): the cards and media someone changed. Saved alone, they go on top of whatever a
 * change of setting makes the launch give, where the whole saved machine would put back what the setting replaced.
 */
export function changesFrom(saved: unknown, base: unknown): Record<string, Record<string, unknown>> {
    const changes: Record<string, Record<string, unknown>> = {};
    for (const section of ["cards", "media"]) {
        const ours = (saved as Record<string, unknown> | undefined)?.[section];
        if (typeof ours !== "object" || ours === null) continue;
        const theirs = ((base as Record<string, unknown> | undefined)?.[section] ?? {}) as Record<string, unknown>;
        changes[section] = Object.fromEntries(Object.entries(ours as Record<string, unknown>)
            .filter(([key, value]) => JSON.stringify(value) !== JSON.stringify(theirs[key])));
    }
    return changes;
}
