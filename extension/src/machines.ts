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
    /**
     * The launch options the value stands for, when it is more than its option set to it, as the Model I's Level II
     * 1.2 is rom level2 and revision 1.2.
     */
    launch?: Record<string, string>;
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
    /** The launch option a tape it starts with goes in; cassette unless it says. */
    tapeOption?: string;
    /** The programs a program launch loads, as file extensions without the dot; bin unless it says. */
    programFormats?: string[];
    /** The BASIC dialects a basic launch runs on it. */
    basicDialects: string[];
    /** The disk a basic launch boots for its BASIC, as the open dialog asks for it; none when BASIC is in ROM. */
    basicDisk?: string;
    /** The executables it boots from a disk built for them (executable), such as the Atari's .xex; none by default. */
    executableFormats?: string[];
    /** The cartridge images it plugs in (cartridge), in place of its BASIC; none by default. */
    cartridgeFormats?: string[];
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

// The Model I's and the Model III's ROM, Level I or Level II BASIC, which their rom launch option picks: Level I
// reads only 250 baud tapes and has no disks, and Level II only 500 baud ones. The Model I's Level II also has its
// revision, 1.3 unless the revision option says 1.2.
const model1Rom: MachineChoice = {
    option: "rom",
    label: "ROM",
    values: [
        { label: "Level II BASIC 1.3", detail: "500 baud tapes, and disks with the Expansion Interface", value: "level2" },
        { label: "Level II BASIC 1.2", detail: "The earlier Level II ROM", value: "level2-1.2", launch: { rom: "level2", revision: "1.2" } },
        { label: "Level I BASIC", detail: "4K of Tiny BASIC: 250 baud tapes and no disks", value: "level1" }
    ],
    default: "level2"
};

const model3Rom: MachineChoice = {
    option: "rom",
    label: "ROM",
    values: [
        { label: "Model III ROM", detail: "Level II BASIC: 500 and 1500 baud tapes, and disks", value: "level2" },
        { label: "Level I BASIC", detail: "The Model III's Level I: 250 baud tapes and no disks", value: "level1" }
    ],
    default: "level2"
};

// The Model I's RAM: 4 or 16 KB in the keyboard unit, and up to 48 KB with the Expansion Interface, which choosing
// more than 16 KB brings. Left out, it is 48 KB with the interface, else 16 KB, or 4 KB for Level I.
const model1Ram = (initial: number): MachineChoice => ({
    option: "ramKilobytes",
    label: "Memory",
    values: [
        { label: "48 KB", detail: "With the Expansion Interface", value: 48 },
        { label: "32 KB", detail: "With the Expansion Interface", value: 32 },
        { label: "16 KB", detail: "The most the keyboard unit holds", value: 16 },
        { label: "4 KB", detail: "As the first Level I machines came", value: 4 }
    ],
    default: initial
});

const model1Expansion = (initial: boolean): MachineChoice => ({
    option: "expansionInterface",
    label: "Expansion Interface",
    values: [
        { label: "With the Expansion Interface", detail: "Memory over 16 KB, the clock interrupt and disks", value: true },
        { label: "Without it", detail: "16 KB at most, and tapes only", value: false }
    ],
    default: initial
});

const model3Ram: MachineChoice = {
    option: "ramKilobytes",
    label: "Memory",
    values: [{ label: "48 KB", value: 48 }, { label: "32 KB", value: 32 }, { label: "16 KB", value: 16 }],
    default: 48
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

const bbcSound: MachineChoice = {
    option: "sound",
    label: "Sound",
    values: [
        { label: "On", detail: "The SN76489 through the internal speaker", value: "speaker" },
        { label: "Off", value: "off" }
    ],
    default: "speaker"
};

const petRam: MachineChoice = {
    option: "ramKilobytes",
    label: "Memory",
    values: [
        { label: "8 KB", value: 8 },
        { label: "4 KB", value: 4 },
        { label: "16 KB", value: 16 },
        { label: "32 KB", value: 32 }
    ],
    default: 8
};

const petSound: MachineChoice = {
    option: "sound",
    label: "Sound",
    values: [
        { label: "Speaker", detail: "The VIA's CB2, as a speaker on the user port plays it", value: "speaker" },
        { label: "Off", value: "off" }
    ],
    default: "speaker"
};

// The 4000 series came with 32K, or 16K as the 4016.
const pet4032Ram: MachineChoice = {
    option: "ramKilobytes",
    label: "Memory",
    values: [
        { label: "32 KB", detail: "The 4032", value: 32 },
        { label: "16 KB", detail: "The 4016", value: 16 },
        { label: "8 KB", value: 8 }
    ],
    default: 32
};

const petSnow: MachineChoice = {
    option: "snow",
    label: "Snow",
    values: [
        { label: "Snow", detail: "Video RAM touched while a line is drawn shows as snow, as on the 2001's board", value: true },
        { label: "No snow", value: false }
    ],
    default: true
};

// The 2001 with BASIC 2 launches without snow unless snow is asked for, so its choice starts off.
const petSnowOff: MachineChoice = { ...petSnow, default: false };
// The Atari 400's and 800's choices: Atari BASIC's revision in the left slot, the video standard (PAL brings the
// PAL OS), how the disk drives are emulated, and sound.
const atariChoices: MachineChoice[] = [
    {
        option: "basicCartridge",
        label: "BASIC",
        values: [
            { label: "Atari BASIC rev. C", value: "c" },
            { label: "Atari BASIC rev. B", value: "b" },
            { label: "Atari BASIC rev. A", detail: "The first, as the 400 and 800 shipped with", value: "a" },
            { label: "None", detail: "The left slot is empty, and the OS starts in the memo pad or boots a disk", value: "none" }
        ],
        default: "c"
    },
    {
        option: "video",
        label: "Video",
        values: [
            { label: "NTSC", detail: "60 Hz, with OS rev. B", value: "ntsc" },
            { label: "PAL", detail: "50 Hz, with the PAL OS", value: "pal" }
        ],
        default: "ntsc"
    },
    {
        option: "diskDrive",
        label: "Disk drives",
        values: [
            { label: "Atari 810", detail: "The 810's own 6507 and firmware, at the hardware level", value: "atari810" },
            { label: "SIO", detail: "Drives that answer the serial bus's commands, without the 810's firmware", value: "sio" }
        ],
        default: "atari810"
    },
    {
        option: "sound",
        label: "Sound",
        values: [
            { label: "On", detail: "POKEY's four channels through the TV", value: "speaker" },
            { label: "Off", value: "off" }
        ],
        default: "speaker"
    }
];

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
    // The Model I and the Model III each have an entry for each Level, which Start Machine lists; their ROM setting
    // moves a machine between the two.
    {
        id: "trs80-model1-level2",
        label: "TRS-80 Model I (Level II)",
        detail: "Z80, Level II BASIC, 48 KB and the Expansion Interface",
        configuration: { machine: "trs80-model1" },
        diskFormats: ["dsk", "jv1", "jv3", "dmk", "imd"],
        tapeFormats: ["cas"],
        basicDialects: ["level2"],
        dos: false,
        choices: [model1Rom, model1Ram(48), model1Expansion(true), lowercase]
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
        choices: [model1Rom, model1Ram(4), model1Expansion(false), lowercase]
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
        choices: [model3Rom, model3Ram]
    },
    {
        id: "trs80-model3-level1",
        label: "TRS-80 Model III (Level I)",
        detail: "Z80 at 2 MHz, the Model III's Level I BASIC and 250 baud tapes",
        configuration: { machine: "trs80-model3", model: "3", rom: "level1" },
        diskFormats: [],
        tapeFormats: ["cas"],
        basicDialects: [],
        dos: false,
        choices: [model3Rom, model3Ram]
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
    // Without dumps, the PETs build BASIC, the screen editor and the kernal from the SDK's sources. A tape starts in
    // the built-in Datasette, cassette #1, with PLAY down; a .prg goes in as the tape SAVE writes.
    {
        id: "pet2001-basic2",
        label: "Commodore PET 2001 (BASIC 2)",
        detail: "6502, BASIC 2 (the 2001-N's ROMs), 8 KB and the built-in Datasette",
        configuration: { machine: "pet", model: "pet2001-basic2" },
        diskFormats: [],
        tapeFormats: ["tap", "wav", "prg"],
        tapeOption: "cassette1",
        programFormats: ["prg", "bin"],
        basicDialects: ["petbasic"],
        dos: false,
        choices: [petRam, petSound, petSnowOff]
    },
    {
        id: "pet2001",
        label: "Commodore PET 2001",
        detail: "6502, BASIC 1, 8 KB, the chiclet keyboard and the built-in Datasette",
        configuration: { machine: "pet", model: "pet2001" },
        diskFormats: [],
        tapeFormats: ["tap", "wav", "prg"],
        tapeOption: "cassette1",
        programFormats: ["prg", "bin"],
        basicDialects: ["petbasic"],
        dos: false,
        choices: [petRam, petSound, petSnow]
    },
    // BASIC 4's PETs come with a 4040 dual drive as device 8, when its ROMs are found; a disk goes in its drive 0.
    {
        id: "pet4032",
        label: "Commodore PET 4032",
        detail: "6502, BASIC 4 with its disk commands, 32 KB, the graphics keyboard and a 4040 disk drive",
        configuration: { machine: "pet", model: "pet4032" },
        diskFormats: ["d64", "g64"],
        tapeFormats: ["tap", "wav", "prg"],
        tapeOption: "cassette1",
        programFormats: ["prg", "bin"],
        basicDialects: ["petbasic"],
        dos: false,
        choices: [pet4032Ram, petSound]
    },
    {
        id: "pet4032-business",
        label: "Commodore PET 4032 (business keyboard)",
        detail: "6502, BASIC 4 with its disk commands, 32 KB, the business keyboard and a 4040 disk drive",
        configuration: { machine: "pet", model: "pet4032-business" },
        diskFormats: ["d64", "g64"],
        tapeFormats: ["tap", "wav", "prg"],
        tapeOption: "cassette1",
        programFormats: ["prg", "bin"],
        basicDialects: ["petbasic"],
        dos: false,
        choices: [pet4032Ram, petSound]
    },
    // Without dumps, the BBC Micro builds its ROMs from the SDK's sources: MOS 1.20, BASIC II, DNFS 1.20 and the
    // SAA5050's characters.
    {
        id: "bbcb",
        label: "BBC Micro Model B",
        detail: "6502 at 2 MHz, MOS 1.20, BASIC II, DNFS 1.20 and 32 KB",
        configuration: { machine: "bbc", model: "bbcb" },
        diskFormats: ["ssd", "dsd"],
        tapeFormats: ["uef"],
        basicDialects: ["bbcbasic"],
        dos: false,
        choices: [
            {
                option: "diskInterface",
                label: "Disk interface",
                values: [
                    { label: "Intel 8271", detail: "Acorn DFS and two drives", value: true },
                    { label: "None", detail: "Tapes only, with PAGE at &E00", value: false }
                ],
                default: true
            },
            bbcSound
        ]
    },
    {
        id: "bbca",
        label: "BBC Micro Model A",
        detail: "6502 at 2 MHz, MOS 1.20, BASIC II and 16 KB",
        configuration: { machine: "bbc", model: "bbca" },
        diskFormats: [],
        tapeFormats: ["uef"],
        basicDialects: ["bbcbasic"],
        dos: false,
        choices: [bbcSound]
    },
    // Without dumps, the Atari 400 and 800 build their ROMs from the SDK's sources: the OS, the floating point package,
    // Atari BASIC and the 810's firmware.
    {
        id: "atari800",
        label: "Atari 800",
        detail: "6502 at 1.79 MHz, OS rev. B, Atari BASIC rev. C and 48 KB",
        configuration: { machine: "atari800", model: "atari800" },
        diskFormats: ["atr", "xfd"],
        tapeFormats: ["cas"],
        basicDialects: ["atari"],
        executableFormats: ["xex"],
        cartridgeFormats: ["rom", "car"],
        dos: false,
        choices: atariChoices
    },
    {
        id: "atari400",
        label: "Atari 400",
        detail: "6502 at 1.79 MHz, OS rev. B, Atari BASIC rev. C and 16 KB",
        configuration: { machine: "atari800", model: "atari400" },
        diskFormats: ["atr", "xfd"],
        tapeFormats: ["cas"],
        basicDialects: ["atari"],
        executableFormats: ["xex"],
        cartridgeFormats: ["rom", "car"],
        dos: false,
        choices: atariChoices
    },
    // The Altair has no ROM: it starts in empty RAM, and a launched source or program runs on its terminal.
    {
        id: "altair",
        label: "MITS Altair 8800",
        detail: "8080, a terminal on the 88-2SIO or 88-SIO, the 88-ACR cassette, 88-DCDD 8-inch disks and 64 KB",
        configuration: { machine: "altair" },
        // A disk boots through DBL, which a launch with disks fits.
        diskFormats: ["dsk"],
        // A tape alone cannot start an Altair, which needs a bootstrap keyed in to read it, so tapes go in through
        // Retro Devices or a launch's cassette option instead.
        tapeFormats: [],
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
            },
            {
                option: "diskController",
                label: "Disk controller",
                values: [
                    { label: "None", value: false },
                    { label: "88-DCDD", detail: "Four 8-inch drives, with DBL at $FF00 to boot drive 0", value: true }
                ],
                default: false
            }
        ]
    },
    // The Kaypro II boots CP/M 2.2 from drive A, with its monitor ROM a dump from romDirectory (or
    // RETROCORE_KAYPRO_ROMS) or the SDK's build.
    {
        id: "kaypro2",
        label: "Kaypro II",
        detail: "Z80 at 2.5 MHz, 64 KB, 80x24 and two drives, running CP/M 2.2",
        configuration: { machine: "kaypro2" },
        diskFormats: ["img", "dsk", "imd", "dmk"],
        tapeFormats: [],
        basicDialects: ["mbasic"],
        // CP/M boots from drive A and the launch types MBASIC at its prompt, so the disk must have both.
        basicDisk: "A CP/M system disk with MBASIC.COM",
        dos: false,
        choices: []
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

// The models a launch option names, as the debug host reads them, by machine: an alias, or none for its default.
const models: Record<string, Record<string, string>> = {
    apple2: { "": "iie-enhanced", enhanced: "iie-enhanced", original: "iie" },
    coco: { "": "coco2" },
    pet: { "": "pet2001-basic2" },
    bbc: { "": "bbcb" },
    atari800: { "": "atari800" },
    "trs80-model3": { "": "3", III: "3", model3: "3", model4: "4", "4P": "4p", model4p: "4p" },
    "trs80-model2": { "": "2", II: "2", model2: "2", model12: "12", "16b": "16", "6000": "16", model16: "16" }
};

// The machine names the debug host takes for another: the Model 4 is the Model III's machine, a 4 unless it says.
const machineAliases: Record<string, { machine: string; model: string }> = {
    apple2e: { machine: "apple2", model: "" },
    "trs80-model4": { machine: "trs80-model3", model: "4" }
};

/**
 * The catalog machine a launch configuration starts, as the debug host reads its machine, model and rom, so a
 * launch.json entry that leaves the model to its default is still its machine; none for a machine the catalog lacks.
 */
export function catalogMachine(configuration: Record<string, unknown>): Machine | undefined {
    const alias = machineAliases[String(configuration.machine ?? "")];
    const kind = alias?.machine ?? String(configuration.machine ?? "");
    const named = typeof configuration.model === "string" ? configuration.model : alias?.model ?? "";
    const model = models[kind]?.[named] ?? named;
    // The Model I and the Model III choose Level I or Level II BASIC by their rom.
    const roms = kind === "trs80-model1" || kind === "trs80-model3";
    const rom = roms ? String(configuration.rom ?? "level2") : "";
    return machines.find(machine => machine.configuration.machine === kind
        && (machine.configuration.model ?? "") === model
        && (!roms || (machine.configuration.rom ?? "level2") === rom));
}

/** Whether a launch configuration starts with disks in its drives, which brings a disk controller with them. */
export function startsWithDisks(configuration: Record<string, unknown>): boolean {
    return Array.isArray(configuration.disks) && configuration.disks.length !== 0;
}

// The machines whose rom launch option picks Level I or Level II BASIC.
const romMachines = new Set(["trs80-model1", "trs80-model3"]);

/** Whether a launch configuration runs Level I BASIC, on a Model I or a Model III. */
export function isLevel1(configuration: Record<string, unknown>): boolean {
    return romMachines.has(String(configuration.machine ?? "")) && configuration.rom === "level1";
}

// The ROM a Model I or Model III configuration runs, as its ROM choice's value: level1, level2, or for the Model I's
// Level II 1.2, level2-1.2.
function romValue(configuration: Record<string, unknown>): string {
    const rom = typeof configuration.rom === "string" ? configuration.rom : "level2";
    return rom === "level2" && configuration.machine === "trs80-model1" && configuration.revision === "1.2" ? "level2-1.2" : rom;
}

// Whether a Model I has its Expansion Interface: as the launch says, or by default with Level II.
function hasExpansion(configuration: Record<string, unknown>): boolean {
    return typeof configuration.expansionInterface === "boolean" ? configuration.expansionInterface : !isLevel1(configuration);
}

/**
 * What a choice is when the configuration leaves it out, as the debug host decides: the choice's default, except that
 * disks given bring their disk controller, an Atari cartridge takes BASIC's place in the left slot, the ROM is Level II, the Model I's Expansion Interface comes with Level II,
 * and its memory is 48 KB with the interface, else 16 KB, or 4 KB for Level I.
 */
export function impliedValue(choice: MachineChoice, configuration: Record<string, unknown>): string | number | boolean {
    if (choice.option === "diskController" && startsWithDisks(configuration)) return true;
    if (choice.option === "basicCartridge" && typeof configuration.cartridge === "string") return "none";
    if (choice.option === "rom") return "level2";
    if (configuration.machine === "trs80-model1") {
        if (choice.option === "expansionInterface") return !isLevel1(configuration);
        if (choice.option === "ramKilobytes") return hasExpansion(configuration) ? 48 : isLevel1(configuration) ? 4 : 16;
    }
    return choice.default;
}

/** The value a launch configuration gives one of its machine's choices: its own, or what it is left out. */
export function settingValue(choice: MachineChoice, configuration: Record<string, unknown>): string | number | boolean {
    if (choice.option === "rom") return romValue(configuration);
    const value = configuration[choice.option];
    return typeof value === "string" || typeof value === "number" || typeof value === "boolean" ? value : impliedValue(choice, configuration);
}

// Leaves an option out when it is what the debug host would make it anyway.
function dropImplied(configuration: Record<string, unknown>, choice: MachineChoice): void {
    const { [choice.option]: value, ...rest } = configuration;
    if (value !== undefined && value === impliedValue(choice, rest)) delete configuration[choice.option];
}

/**
 * A launch configuration with one choice set, leaving the option out when it is what it would be without it, and
 * keeping what still fits: a Model I given more than 16 KB gets its Expansion Interface, and one whose interface comes
 * out gets 16 KB. A change of ROM keeps the tape; Level I takes out the disks and their controller, as it has none,
 * and the memory follows the new ROM's unless the launch gives its own.
 */
export function withSetting(configuration: Record<string, unknown>, choice: MachineChoice, value: string | number | boolean): Record<string, unknown> {
    const changed = { ...configuration };
    if (choice.option === "rom") {
        const launch = choice.values.find(candidate => candidate.value === value)?.launch ?? { rom: String(value) };
        delete changed.rom;
        delete changed.revision;
        if (launch.rom !== "level2") changed.rom = launch.rom;
        if (launch.revision !== undefined) changed.revision = launch.revision;
        if (isLevel1(changed)) {
            for (const option of ["disks", "diskController", "doubler"]) delete changed[option];
        }
    } else {
        changed[choice.option] = value;
    }

    if (changed.machine === "trs80-model1") {
        const ram = typeof changed.ramKilobytes === "number" ? changed.ramKilobytes : undefined;
        // More than 16 KB needs the Expansion Interface, and without it 16 KB is the most.
        if (choice.option === "expansionInterface" && value === false && ram !== undefined && ram > 16) changed.ramKilobytes = 16;
        else if (ram !== undefined && ram > 16) changed.expansionInterface = true;
        dropImplied(changed, model1Expansion(true));
        dropImplied(changed, model1Ram(48));
    }
    if (choice.option !== "rom") dropImplied(changed, choice);
    return changed;
}

/** What a choice is when the configuration leaves it out, as the views mark it "default". */
export function defaultValue(choice: MachineChoice, configuration: Record<string, unknown>): string | number | boolean {
    const { [choice.option]: _given, ...rest } = configuration;
    return impliedValue(choice, rest);
}
