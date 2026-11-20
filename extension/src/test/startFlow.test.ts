// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import * as path from "node:path";
import { test } from "node:test";
import { machineById, machines } from "../machines";
import { describeSetup, isUsable, optionValue, removesDrives, runChoices, setupConfiguration, withOption, type Setup } from "../startFlow";

interface OptionSchema { type?: string; enum?: unknown[]; anyOf?: OptionSchema[] }

const options: Record<string, OptionSchema> = JSON.parse(readFileSync(path.resolve(__dirname, "../../package.json"), "utf8"))
    .contributes.debuggers[0].configurationAttributes.launch.properties;

function allows(schema: OptionSchema, value: unknown): boolean {
    if (schema.anyOf !== undefined) return schema.anyOf.some(alternative => allows(alternative, value));
    if (schema.enum !== undefined) return schema.enum.includes(value);
    if (schema.type === "array") return Array.isArray(value);
    return schema.type === undefined || typeof value === schema.type;
}

const machine = (id: string) => {
    const found = machineById(id);
    assert.ok(found, id);
    return found;
};

test("each machine offers what it can run: itself, sources and binaries, and its BASIC, drives, tapes and DOS", () => {
    const kinds = (id: string) => runChoices(machine(id)).map(choice => choice.kind);
    assert.deepEqual(kinds("apple2-iie-enhanced"), ["machine", "source", "program", "basic", "disk", "dosSource"]);
    assert.deepEqual(kinds("trs80-model1-level2"), ["machine", "source", "program", "basic", "disk", "tape"]);
    assert.deepEqual(kinds("trs80-model1-level1"), ["machine", "source", "program", "tape"], "Level I has no BASIC file launch or disks");
    assert.deepEqual(kinds("apple1"), ["machine", "source", "program", "basic", "tape"], "the Apple-1 loads BASIC, and has no disks");
    assert.deepEqual(kinds("coco2"), ["machine", "source", "program", "basic", "disk", "tape"]);
    assert.deepEqual(kinds("coco3"), ["machine", "source", "program", "disk", "tape"], "the CoCo 3's BASIC files do not launch yet");
    assert.deepEqual(kinds("altair"), ["machine", "source", "program", "disk"], "an Altair disk boots through DBL; a tape needs a bootstrap keyed in first");
    assert.deepEqual(kinds("pet2001-basic2"), ["machine", "source", "program", "basic", "tape"], "the PET has tapes and no disks");
    assert.deepEqual(kinds("pet2001"), ["machine", "source", "program", "basic", "tape"]);
    assert.deepEqual(kinds("pet4032"), ["machine", "source", "program", "basic", "disk", "tape"], "the 4032 comes with a 4040");
    const pet4032 = runChoices(machine("pet4032"));
    assert.match(pet4032.find(choice => choice.kind === "basic")?.detail ?? "", /Commodore BASIC 4 \(PET\)/);
    assert.match(pet4032.find(choice => choice.kind === "disk")?.detail ?? "", /4040/);
    const pet = runChoices(machine("pet2001-basic2"));
    assert.deepEqual(pet.find(choice => choice.kind === "program")?.extensions, ["prg", "bin"], "a .prg, or a plain binary");
    assert.deepEqual(pet.find(choice => choice.kind === "tape")?.extensions, ["tap", "wav", "prg"]);
    assert.match(pet.find(choice => choice.kind === "tape")?.detail ?? "", /Datasette/);
    assert.match(pet.find(choice => choice.kind === "basic")?.detail ?? "", /Commodore BASIC 2 \(PET\)/);
    assert.match(runChoices(machine("pet2001")).find(choice => choice.kind === "basic")?.detail ?? "", /Commodore BASIC 1 \(PET\)/);
    assert.deepEqual(runChoices(machine("coco2")).find(choice => choice.kind === "program")?.extensions, ["bin"], "other machines load binaries");
    assert.deepEqual(kinds("kaypro2"), ["machine", "source", "program", "basic", "disk"], "the Kaypro II boots CP/M disks and runs MBASIC");
    assert.match(runChoices(machine("coco1")).find(choice => choice.kind === "basic")?.detail ?? "", /Color BASIC/);
    assert.match(runChoices(machine("apple2-ii")).find(choice => choice.kind === "basic")?.detail ?? "", /Integer BASIC/);
    assert.match(runChoices(machine("apple1")).find(choice => choice.kind === "basic")?.detail ?? "", /Apple-1 BASIC/);
});

test("each kind of setup becomes the launch options that run it, which package.json allows", () => {
    const cases: [Setup, Record<string, unknown>][] = [
        [{ machineId: "apple2-iiplus", kind: "machine", options: {} }, { name: "Apple II Plus (Retrocore)", stopOnEntry: false }],
        [{ machineId: "apple2-iie", kind: "source", path: "C:\\src\\main.s", options: {} }, { name: "Apple IIe: main.s", source: "C:\\src\\main.s", stopOnEntry: true }],
        [{ machineId: "apple2-iie", kind: "program", path: "/p/game.bin", options: {} }, { program: "/p/game.bin", stopOnEntry: true }],
        [{ machineId: "apple2-ii", kind: "basic", path: "a.integer.bas", options: {} }, { basic: "a.integer.bas", model: "ii" }],
        [{ machineId: "apple3", kind: "basic", path: "a.business.bas", basicDisk: "bb.dsk", options: {} }, { basic: "a.business.bas", disks: ["bb.dsk"] }],
        [{ machineId: "apple2-iiplus", kind: "disk", path: "dos.dsk", options: {} }, { diskImage: "dos.dsk" }],
        [{ machineId: "trs80-model1-level2", kind: "disk", path: "newdos.jv3", options: {} }, { disks: ["newdos.jv3"] }],
        [{ machineId: "trs80-model1-level2", kind: "tape", path: "game.cas", options: {} }, { cassette: "game.cas" }],
        [{ machineId: "apple1", kind: "tape", path: "basic.wav", options: {} }, { machine: "apple1", cassette: "basic.wav" }],
        [{ machineId: "apple1", kind: "basic", path: "a.apple1.bas", options: {} }, { machine: "apple1", basic: "a.apple1.bas" }],
        [{ machineId: "coco3", kind: "disk", path: "games.dsk", options: {} }, { machine: "coco", model: "coco3", disks: ["games.dsk"] }],
        [{ machineId: "pet2001-basic2", kind: "tape", path: "game.tap", options: {} }, { machine: "pet", model: "pet2001-basic2", cassette1: "game.tap", cassette: undefined }],
        [{ machineId: "pet2001", kind: "program", path: "hello.prg", options: { ramKilobytes: 32, snow: false } },
            { machine: "pet", model: "pet2001", program: "hello.prg", ramKilobytes: 32, snow: false }],
        [{ machineId: "pet2001", kind: "basic", path: "a.petbasic.bas", options: { sound: "off" } }, { basic: "a.petbasic.bas", sound: "off" }],
        [{ machineId: "pet4032", kind: "disk", path: "demo.d64", options: { ramKilobytes: 16 } }, { machine: "pet", model: "pet4032", disks: ["demo.d64"], ramKilobytes: 16 }],
        [{ machineId: "kaypro2", kind: "disk", path: "cpm.img", options: {} }, { machine: "kaypro2", disks: ["cpm.img"] }],
        [{ machineId: "kaypro2", kind: "basic", path: "a.mbasic.bas", basicDisk: "cpm.img", options: {} }, { machine: "kaypro2", basic: "a.mbasic.bas", disks: ["cpm.img"] }],
        [{ machineId: "apple2-iie-enhanced", kind: "dosSource", path: "hi.s", options: {} }, { source: "hi.s", dos: "3.3", stopOnEntry: false }]
    ];

    for (const [setup, expected] of cases) {
        const configuration = setupConfiguration(setup);
        for (const [key, value] of Object.entries(expected)) assert.deepEqual(configuration[key], value, `${setup.kind}: ${key}`);
        for (const [key, value] of Object.entries(configuration)) {
            if (key === "type" || key === "request" || key === "name") continue;
            assert.ok(options[key] && allows(options[key], value), `${setup.kind}: ${key} = ${JSON.stringify(value)}`);
        }
    }
});

test("options keep only what differs from the machine's defaults, and the configuration carries them", () => {
    const ii = machine("apple2-ii");
    let setup: Setup = { machineId: ii.id, kind: "machine", options: {} };
    setup = withOption(ii, setup, "monitor", "autostart");
    setup = withOption(ii, setup, "ramKilobytes", 32);
    assert.deepEqual(setup.options, { monitor: "autostart", ramKilobytes: 32 });
    assert.equal(optionValue(ii, setup, "slot0"), "empty", "an option not changed has its default");
    setup = withOption(ii, setup, "monitor", "original");
    assert.deepEqual(setup.options, { ramKilobytes: 32 }, "back at the default, an option is dropped");
    assert.equal(setupConfiguration(setup).ramKilobytes, 32);
    assert.throws(() => withOption(ii, setup, "lowercase", true), /no lowercase/);
});

test("a setup reads as the machine, what it runs and the options changed", () => {
    const setup: Setup = { machineId: "apple2-ii", kind: "basic", path: "C:\\x\\hello.integer.bas", options: { monitor: "autostart" } };
    assert.equal(describeSetup(setup), "Apple II · hello.integer.bas · Monitor: Autostart");
});

test("a kept setup is used only while it still names a machine and something it runs", () => {
    assert.ok(isUsable({ machineId: "apple2-iiplus", kind: "machine", options: {} }));
    assert.ok(!isUsable(undefined));
    assert.ok(!isUsable({ machineId: "apple4", kind: "machine", options: {} }), "an unknown machine");
    assert.ok(!isUsable({ machineId: "trs80-model1-level1", kind: "disk", path: "x.dsk", options: {} }), "Level I has no disks");
    assert.ok(!isUsable({ machineId: "apple2-iie", kind: "source", options: {} }), "a source needs its file");
    assert.equal(machines.length, 26);
});

test("a BBC Micro's disk goes in drive 0 without booting, as nothing presses SHIFT-BREAK", () => {
    const disk = (id: string) => runChoices(machineById(id)!).find(choice => choice.kind === "disk")?.detail;
    assert.equal(disk("bbcb"), "Puts it in drive 0, without booting it");
    assert.equal(disk("apple2-iie-enhanced"), "Boots it from the first drive");
});

test("a setup that starts from a disk keeps the drives it needs", () => {
    const disk: Setup = { machineId: "bbcb", kind: "disk", path: "welcome.ssd", options: {} };
    assert.ok(removesDrives(disk, "diskInterface", false));
    assert.ok(!removesDrives(disk, "diskInterface", true));
    assert.ok(!removesDrives({ ...disk, kind: "machine" }, "diskInterface", false));
});
