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
    /** The disk a basic launch boots for its BASIC, as the open dialog asks for it; none when BASIC is in ROM. */
    basicDisk?: string;
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

const model4Ram: MachineChoice = {
    option: "ramKilobytes",
    label: "Memory",
    values: [{ label: "128 KB", value: 128 }, { label: "64 KB", value: 64 }],
    default: 128
};

const model2Ram: MachineChoice = {
    option: "ramKilobytes",
    label: "Memory",
    values: [
        { label: "64 KB", value: 64 },
        { label: "128 KB", value: 128 },
        { label: "256 KB", value: 256 },
        { label: "512 KB", value: 512 },
        { label: "32 KB", value: 32 }
    ],
    default: 64
};

const model2Disks = ["imd", "dmk", "jv3", "dsk"];

const cocoSound: MachineChoice = {
    option: "sound",
    label: "Sound",
    values: [
        { label: "On", detail: "The DAC, cassette and single-bit sound through the TV", value: "speaker" },
        { label: "Off", value: "off" }
    ],
    default: "speaker"
};

const cocoDisk: MachineChoice = {
    option: "diskController",
    label: "Disk controller",
    values: [
        { label: "None", detail: "Tapes and ROM packs", value: false },
        { label: "Disk controller", detail: "Disk Extended Color BASIC and four drives", value: true }
    ],
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
        basicDialects: ["business"],
        basicDisk: "The Business BASIC disk",
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
        diskFormats: ["dsk", "jv1", "jv3", "dmk", "imd"],
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
    },
    // The Model III family and the Model II run the SDK's builds of their ROMs, or dumps from romDirectory (or
    // RETROCORE_TRS80_ROMS). The Model III's and Model 4's BASIC is Level II's.
    {
        id: "trs80-model3",
        label: "TRS-80 Model III",
        detail: "Z80 at 2 MHz, the Model III ROM, 48 KB and the FD1793",
        configuration: { machine: "trs80-model3", model: "3" },
        diskFormats: ["dsk", "jv1", "jv3", "dmk", "imd"],
        tapeFormats: ["cas"],
        basicDialects: ["level2"],
        dos: false,
        choices: [
            {
                option: "ramKilobytes",
                label: "Memory",
                values: [{ label: "48 KB", value: 48 }, { label: "32 KB", value: 32 }, { label: "16 KB", value: 16 }],
                default: 48
            }
        ]
    },
    {
        id: "trs80-model4",
        label: "TRS-80 Model 4",
        detail: "Z80 at 4 MHz, the Model III ROM, 128 KB, 80x24 and the FD1793",
        configuration: { machine: "trs80-model3", model: "4" },
        diskFormats: ["dsk", "jv1", "jv3", "dmk", "imd"],
        tapeFormats: ["cas"],
        basicDialects: ["level2"],
        dos: false,
        choices: [model4Ram]
    },
    {
        id: "trs80-model4p",
        label: "TRS-80 Model 4P",
        detail: "Z80 at 4 MHz, the 4P's boot ROM, 128 KB, 80x24 and the FD1793",
        configuration: { machine: "trs80-model3", model: "4p" },
        diskFormats: ["dsk", "jv1", "jv3", "dmk", "imd"],
        tapeFormats: [],
        basicDialects: [],
        dos: false,
        choices: [model4Ram]
    },
    {
        id: "trs80-model2",
        label: "TRS-80 Model II",
        detail: "Z80 at 4 MHz, 64 KB, 80x24 and 8-inch disks",
        configuration: { machine: "trs80-model2", model: "2" },
        diskFormats: model2Disks,
        tapeFormats: [],
        basicDialects: [],
        dos: false,
        choices: [model2Ram]
    },
    {
        id: "trs80-model12",
        label: "TRS-80 Model 12",
        detail: "The Model II's successor: Z80 at 4 MHz, 80x24 and 8-inch disks",
        configuration: { machine: "trs80-model2", model: "12" },
        diskFormats: model2Disks,
        tapeFormats: [],
        basicDialects: [],
        dos: false,
        choices: [model2Ram]
    },
    {
        id: "trs80-model16",
        label: "TRS-80 Model 16 (Z80 side)",
        detail: "The Model 16, 16B or Tandy 6000 running Model II software; the 68000 board is not emulated",
        configuration: { machine: "trs80-model2", model: "16" },
        diskFormats: model2Disks,
        tapeFormats: [],
        basicDialects: [],
        dos: false,
        choices: [model2Ram]
    },
    {
        id: "apple1",
        label: "Apple-1",
        detail: "6502, the Woz Monitor, 4 KB plus 4 KB at $E000, and the cassette interface",
        configuration: { machine: "apple1" },
        diskFormats: [],
        tapeFormats: ["wav"],
        basicDialects: ["apple1"],
        dos: false,
        choices: [
            {
                option: "ramKilobytes",
                label: "Memory",
                values: [{ label: "4 KB", value: 4 }, { label: "8 KB", value: 8 }],
                default: 4
            },
            {
                option: "highRam",
                label: "$E000 bank",
                values: [
                    { label: "4 KB at $E000", detail: "Where BASIC loads and runs", value: true },
                    { label: "Empty", value: false }
                ],
                default: true
            },
            {
                option: "cassetteInterface",
                label: "Cassette interface",
                values: [
                    { label: "The Apple Cassette Interface", detail: "Started from the Monitor with C100R", value: true },
                    { label: "Empty slot", value: false }
                ],
                default: true
            }
        ]
    },
    // Without dumps, every Color Computer builds its ROMs from the SDK's sources: Color, Extended and Disk BASIC, and
    // the CoCo 3's ROM.
    {
        id: "coco1",
        label: "TRS-80 Color Computer",
        detail: "6809, Extended Color BASIC 1.1 and 16 KB",
        configuration: { machine: "coco", model: "coco1" },
        diskFormats: ["dsk"],
        tapeFormats: ["cas"],
        basicDialects: ["colorbasic"],
        dos: false,
        choices: [
            {
                option: "ramKilobytes",
                label: "Memory",
                values: [
                    { label: "16 KB", value: 16 },
                    { label: "32 KB", value: 32 },
                    { label: "64 KB", value: 64 },
                    { label: "4 KB", detail: "Color BASIC alone", value: 4 }
                ],
                default: 16
            },
            cocoDisk,
            cocoSound
        ]
    },
    {
        id: "coco2",
        label: "TRS-80 Color Computer 2",
        detail: "6809, Extended Color BASIC 1.1 and 64 KB",
        configuration: { machine: "coco", model: "coco2" },
        diskFormats: ["dsk"],
        tapeFormats: ["cas"],
        basicDialects: ["colorbasic"],
        dos: false,
        choices: [
            {
                option: "lowercase",
                label: "Video chip",
                values: [
                    { label: "MC6847", detail: "Uppercase, lowercase shown inverse", value: false },
                    { label: "MC6847T1", detail: "True lowercase, as on the CoCo 2B", value: true }
                ],
                default: false
            },
            cocoDisk,
            cocoSound
        ]
    },
    {
        id: "coco3",
        label: "TRS-80 Color Computer 3",
        detail: "6809, Extended Color BASIC 2.0, the GIME and 128 KB",
        configuration: { machine: "coco", model: "coco3" },
        diskFormats: ["dsk"],
        tapeFormats: ["cas"],
        basicDialects: [],
        dos: false,
        choices: [
            {
                option: "ramKilobytes",
                label: "Memory",
                values: [
                    { label: "128 KB", value: 128 },
                    { label: "512 KB", value: 512 }
                ],
                default: 128
            },
            {
                option: "monitor",
                label: "Monitor",
                values: [
                    { label: "Composite", detail: "A TV or composite monitor", value: "composite" },
                    { label: "RGB", detail: "The CM-8 RGB monitor", value: "rgb" }
                ],
                default: "composite"
            },
            cocoDisk,
            cocoSound
        ]
    },
    // The Altair has no ROM: it starts in empty RAM, and a launched source or program runs on its terminal.
    {
        id: "altair",
        label: "MITS Altair 8800",
        detail: "8080, a terminal on the 88-2SIO or 88-SIO, the 88-ACR cassette and 64 KB",
        configuration: { machine: "altair" },
        diskFormats: [],
        tapeFormats: ["tap"],
        basicDialects: [],
        dos: false,
        choices: [
            {
                option: "ramKilobytes",
                label: "Memory",
                values: [
                    { label: "64 KB", value: 64 },
                    { label: "48 KB", value: 48 },
                    { label: "32 KB", value: 32 },
                    { label: "16 KB", value: 16 },
                    { label: "4 KB", detail: "As the first Altairs shipped", value: 4 }
                ],
                default: 64
            },
            {
                option: "console",
                label: "Terminal",
                values: [
                    { label: "On the 88-2SIO", detail: "Ports $10 and $11; 4.0 BASICs with the switches down", value: "2sio" },
                    { label: "On the 88-SIO", detail: "Ports $00 and $01; 4K BASIC 3.2 with the switches down", value: "sio" }
                ],
                default: "2sio"
            },
            {
                option: "upperCase",
                label: "Caps lock",
                values: [
                    { label: "Off", value: false },
                    { label: "On", detail: "Letters type as capitals, as Altair BASIC needs", value: true }
                ],
                default: false
            }
        ]
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
