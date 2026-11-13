// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The machines Retrocore can start, described once for the Run and Debug dropdown and Retrocore: Start Machine:
// each one's launch configuration, the files it runs, and the choices that set it up. Free of the vscode module, so
// the unit tests load it.

/** A value a choice can take: what it is called, a note, and the launch option's value. */
export interface ChoiceValue {
    label: string;
    detail?: string;
    value: string | number | boolean;
}

/** A setting of a machine the Start Machine command can ask about: a launch option and its values. */
export interface MachineChoice {
    /** The launch option it sets, such as monitor or slot0. */
    option: string;
    label: string;
    values: ChoiceValue[];
    /** The value used when nothing is chosen, as the debug host defaults it. */
    default: string | number | boolean;
}

/** A machine Retrocore can start. */
export interface Machine {
    /** A stable key for remembering what was started, such as apple2-iiplus. */
    id: string;
    /** The machine's name, as the dropdown and quick picks show it. */
    label: string;
    detail: string;
    /** The launch options that make it this machine. */
    configuration: Record<string, string>;
    /** The disk images it boots or mounts, as file extensions without the dot. */
    diskFormats: string[];
    /** The tapes it plays. */
    tapeFormats: string[];
    /** The BASIC dialects a basic launch runs on it. */
    basicDialects: string[];
    /** Whether a launch can put a program on a fresh DOS disk (dos). */
    dos: boolean;
    /** What the Start Machine command can set up, with its defaults. */
    choices: MachineChoice[];
}

const appleDisks = ["dsk", "do", "po", "woz", "d13"];

const sound: MachineChoice = {
    option: "sound",
    label: "Sound",
    values: [
        { label: "Speaker", value: "speaker" },
        { label: "Speaker and Mockingboard", detail: "Puts the Mockingboard in slot 4", value: "mockingboard" },
        { label: "Off", value: "off" }
    ],
    default: "speaker"
};

const ram: MachineChoice = {
    option: "ramKilobytes",
    label: "Memory",
    values: [{ label: "48 KB", value: 48 }, { label: "32 KB", value: 32 }, { label: "16 KB", value: 16 }],
    default: 48
};

const slot0 = (initial: string): MachineChoice => ({
    option: "slot0",
    label: "Slot 0",
    values: [
        { label: "Language card", detail: "16 KB of RAM at $D000-$FFFF, which DOS 3.3 loads the other BASIC into", value: "languageCard" },
        { label: "Firmware card", detail: "The other BASIC in ROM", value: "firmwareCard" },
        { label: "Empty", value: "empty" }
    ],
    default: initial
});

const lowercase: MachineChoice = {
    option: "lowercase",
    label: "Lowercase",
    values: [{ label: "Without the lowercase modification", value: false }, { label: "With the lowercase modification", value: true }],
    default: false
};

/** The machines, in the order the dropdown and Start Machine list them. */
export const machines: readonly Machine[] = [
    {
        id: "apple2-iie-enhanced",
        label: "Apple IIe (enhanced)",
        detail: "65C02, 128 KB, 80 columns and MouseText",
        configuration: { machine: "apple2", model: "iie-enhanced" },
        diskFormats: appleDisks,
        tapeFormats: [],
        basicDialects: ["applesoft"],
        dos: true,
        choices: [sound]
    },
    {
        id: "apple2-iie",
        label: "Apple IIe",
        detail: "6502, 128 KB and 80 columns",
        configuration: { machine: "apple2", model: "iie" },
        diskFormats: appleDisks,
        tapeFormats: [],
        basicDialects: ["applesoft"],
        dos: true,
        choices: [sound]
    },
    {
        id: "apple2-iiplus",
        label: "Apple II Plus",
        detail: "6502, AppleSoft and the Autostart Monitor, 48 KB and a language card",
        configuration: { machine: "apple2", model: "iiplus" },
        diskFormats: appleDisks,
        tapeFormats: [],
        basicDialects: ["applesoft"],
        dos: true,
        choices: [slot0("languageCard"), ram, sound]
    },
    {
        id: "apple2-ii",
        label: "Apple II",
        detail: "6502, Integer BASIC and the original Monitor, 48 KB",
        configuration: { machine: "apple2", model: "ii" },
        diskFormats: appleDisks,
        tapeFormats: [],
        basicDialects: ["integer"],
        dos: true,
        choices: [
            {
                option: "monitor",
                label: "Monitor",
                values: [
                    { label: "Original", detail: "Reset stops at the Monitor's * prompt", value: "original" },
                    { label: "Autostart", detail: "Boots a disk or starts BASIC", value: "autostart" }
                ],
                default: "original"
            },
            slot0("empty"),
            ram,
            {
                option: "boardRevision",
                label: "Board",
                values: [
                    { label: "Revision 1 and later", value: 1 },
                    { label: "Revision 0", detail: "Four hi-res colors", value: 0 }
                ],
                default: 1
            },
            {
                option: "programmersAid",
                label: "D0 socket",
                values: [
                    { label: "Empty", value: false },
                    { label: "Programmer's Aid #1", detail: "Hi-res graphics, renumber, tape verify and more", value: true }
                ],
                default: false
            },
            sound
        ]
    },
    {
        id: "apple3",
        label: "Apple III",
        detail: "6502A at 1 or 2 MHz, 256 KB and the built-in drive",
        configuration: { machine: "apple3" },
        diskFormats: ["dsk", "do", "po", "woz"],
        tapeFormats: [],
        basicDialects: [],
        dos: false,
        choices: [
            {
                option: "ramKilobytes",
                label: "Memory",
                values: [
                    { label: "256 KB", value: 256 },
                    { label: "128 KB", detail: "The first Apple III", value: 128 },
                    { label: "512 KB", detail: "With a third-party upgrade", value: 512 }
                ],
                default: 256
            }
        ]
    },
    {
        id: "trs80-model1-level2",
        label: "TRS-80 Model I (Level II)",
        detail: "Z80, Level II BASIC, 48 KB and the Expansion Interface",
        configuration: { machine: "trs80-model1" },
        diskFormats: ["dsk", "jv1", "jv3"],
        tapeFormats: ["cas"],
        basicDialects: ["level2"],
        dos: false,
        choices: [
            {
                option: "expansionInterface",
                label: "Expansion Interface",
                values: [
                    { label: "With the Expansion Interface", detail: "48 KB, the clock interrupt and disks", value: true },
                    { label: "Without it", detail: "16 KB, tapes only", value: false }
                ],
                default: true
            },
            lowercase
        ]
    },
    {
        id: "trs80-model1-level1",
        label: "TRS-80 Model I (Level I)",
        detail: "Z80, Level I BASIC and 4 KB",
        configuration: { machine: "trs80-model1", rom: "level1" },
        diskFormats: [],
        tapeFormats: ["cas"],
        basicDialects: [],
        dos: false,
        choices: [lowercase]
    }
];

/** Finds a machine by its id. */
export function machineById(id: string): Machine | undefined {
    return machines.find(machine => machine.id === id);
}

/**
 * A launch configuration that starts a machine as it is: booting, with the debug host packaged with the extension and
 * the SDK's ROMs unless the environment names dumps.
 */
export function launchConfiguration(machine: Machine, name = `${machine.label} (Retrocore)`): Record<string, unknown> {
    return { type: "retrocore", request: "launch", name, ...machine.configuration, stopOnEntry: false };
}
