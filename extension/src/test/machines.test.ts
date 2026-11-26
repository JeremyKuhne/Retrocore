// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import * as path from "node:path";
import { test } from "node:test";
import { catalogMachine, launchConfiguration, machineById, machines, settingValue, withSetting, type MachineChoice } from "../machines";

interface OptionSchema { type?: string; enum?: unknown[]; default?: unknown; anyOf?: OptionSchema[] }

// The launch options package.json declares, which VS Code checks launch.json against.
const options: Record<string, OptionSchema> = JSON.parse(readFileSync(path.resolve(__dirname, "../../package.json"), "utf8"))
    .contributes.debuggers[0].configurationAttributes.launch.properties;

// Whether the schema allows a value: in its enum, of its type, or in one of its alternatives.
function allows(schema: OptionSchema, value: unknown): boolean {
    if (schema.anyOf !== undefined) return schema.anyOf.some(alternative => allows(alternative, value));
    if (schema.enum !== undefined) return schema.enum.includes(value);
    return schema.type === undefined || typeof value === schema.type;
}

test("each machine's configuration is launch options package.json declares, with values it allows", () => {
    for (const machine of machines) {
        for (const [option, value] of Object.entries(machine.configuration)) {
            assert.ok(options[option], `${machine.label}: ${option} is a launch option`);
            assert.ok(allows(options[option], value), `${machine.label}: ${option} allows ${value}`);
        }
    }
});

test("each choice sets a launch option to values it allows, and its default is one of them", () => {
    for (const machine of machines) {
        for (const choice of machine.choices) {
            const schema = options[choice.option];
            assert.ok(schema, `${machine.label}: ${choice.option} is a launch option`);
            for (const value of choice.values) {
                // A value that stands for several launch options, as Level II 1.2 does, is checked as those options.
                for (const [option, launched] of Object.entries(value.launch ?? { [choice.option]: value.value })) {
                    assert.ok(options[option] && allows(options[option], launched), `${machine.label}: ${option} allows ${String(launched)}`);
                    if (option === "rom") assert.ok(["level1", "level2"].includes(String(launched)), `${machine.label}: the host knows rom ${String(launched)}`);
                }
            }
            assert.ok(choice.values.some(value => value.value === choice.default), `${machine.label}: ${choice.option}'s default is a value`);
            // The schema's defaults are the Apple II's; the TRS-80s' differ, as their own descriptions say.
            if (schema.default !== undefined && machine.configuration.machine === "apple2") {
                assert.equal(choice.default, schema.default, `${machine.label}: ${choice.option} defaults as the debug host does`);
            }
        }
    }
});

test("the machines are the ones agreed, each with its own id and name, in order", () => {
    assert.deepEqual(machines.map(machine => machine.label), [
        "Apple IIe (enhanced)", "Apple IIe", "Apple II Plus", "Apple II", "Apple III", "TRS-80 Model I (Level II)",
        "TRS-80 Model I (Level I)", "TRS-80 Model III", "TRS-80 Model III (Level I)", "TRS-80 Model 4", "TRS-80 Model 4P",
        "TRS-80 Model II", "TRS-80 Model 12", "TRS-80 Model 16 (Z80 side)", "TRS-80 Model 100", "Tandy 102", "Apple-1", "TRS-80 Color Computer",
        "TRS-80 Color Computer 2", "TRS-80 Color Computer 3", "Commodore PET 2001 (BASIC 2)", "Commodore PET 2001",
        "Commodore PET 4032", "Commodore PET 4032 (business keyboard)", "BBC Micro Model B", "BBC Micro Model A",
        "Atari 800", "Atari 400", "MITS Altair 8800", "Kaypro II"
    ]);
    assert.deepEqual(machineById("altair")?.configuration, { machine: "altair" });
    assert.deepEqual(machineById("trs80-model100")?.configuration, { machine: "trs80-model100", model: "100" });
    assert.deepEqual(machineById("tandy102")?.configuration, { machine: "trs80-model100", model: "102" });
    assert.deepEqual(machineById("tandy102")?.diskFormats, [], "the Model 100 has no disk drive of its own");
    assert.deepEqual(machineById("altair")?.diskFormats, ["dsk"], "the 88-DCDD's SIMH images");
    assert.deepEqual(machineById("altair")?.tapeFormats, [], "an Altair tape needs a bootstrap, so it cannot start the machine");
    assert.deepEqual(machineById("apple3")?.configuration, { machine: "apple3" });
    assert.deepEqual(machineById("apple3")?.basicDialects, ["business"]);
    assert.equal(machineById("apple3")?.basicDisk, "The Business BASIC disk");
    assert.equal(new Set(machines.map(machine => machine.id)).size, machines.length);
    assert.equal(machineById("apple2-iiplus")?.configuration.model, "iiplus");
    assert.equal(machineById("nothing"), undefined);
});

test("a machine's launch configuration boots it with the packaged debug host", () => {
    const plus = machineById("apple2-iiplus");
    assert.ok(plus);
    assert.deepEqual(launchConfiguration(plus), {
        type: "retrocore", request: "launch", name: "Apple II Plus (Retrocore)", machine: "apple2", model: "iiplus", stopOnEntry: false
    });
    assert.equal(launchConfiguration(plus, "Mine").name, "Mine");
    for (const machine of machines) assert.equal("debugHost" in launchConfiguration(machine), false);
});

test("what each machine runs: Apple disks and DOS, the Model I's disks and tapes, the Apple-1's tapes, and each BASIC", () => {
    for (const machine of machines) {
        if (machine.configuration.machine === "apple2") {
            assert.deepEqual(machine.diskFormats, ["dsk", "do", "po", "woz", "d13"]);
            assert.equal(machine.dos, true);
        }
    }
    assert.deepEqual(machineById("apple2-ii")?.basicDialects, ["integer"]);
    assert.deepEqual(machineById("coco2")?.basicDialects, ["colorbasic"]);
    assert.deepEqual(machineById("trs80-model1-level2")?.tapeFormats, ["cas"]);
    assert.deepEqual(machineById("trs80-model1-level1")?.diskFormats, [], "Level I has no disks");
    assert.deepEqual(machineById("trs80-model4p")?.tapeFormats, [], "the 4P has no cassette port");
    assert.deepEqual(machineById("trs80-model4")?.configuration, { machine: "trs80-model3", model: "4" });
    assert.deepEqual(machineById("trs80-model3")?.basicDialects, ["level2"], "Model III BASIC is Level II's");
    assert.deepEqual(machineById("trs80-model3-level1")?.configuration,
        { machine: "trs80-model3", model: "3", rom: "level1" });
    assert.deepEqual(machineById("trs80-model4p")?.basicDialects, [], "the 4P boots from disk");
    assert.deepEqual(machineById("trs80-model2")?.diskFormats, ["imd", "dmk", "jv3", "dsk"]);
    assert.deepEqual(machineById("kaypro2")?.diskFormats, ["img", "dsk", "imd", "dmk"]);
    assert.deepEqual(machineById("kaypro2")?.basicDialects, ["mbasic"], "CP/M's MBASIC");
    assert.equal(machineById("kaypro2")?.basicDisk, "A CP/M system disk with MBASIC.COM", "a BASIC file needs CP/M and MBASIC");
    assert.deepEqual(machineById("apple1")?.tapeFormats, ["wav"]);
    assert.deepEqual(machineById("apple1")?.diskFormats, [], "the Apple-1 has no disks");
    assert.deepEqual(machineById("apple1")?.basicDialects, ["apple1"], "Apple-1 BASIC loads into its $E000 bank");
    for (const id of ["coco1", "coco2", "coco3"]) {
        const coco = machineById(id);
        assert.equal(coco?.configuration.machine, "coco");
        assert.equal(coco?.configuration.model, id);
        assert.deepEqual(coco?.diskFormats, ["dsk"]);
        assert.deepEqual(coco?.tapeFormats, ["cas"]);
    }
    for (const id of ["pet2001-basic2", "pet2001"]) {
        const pet = machineById(id);
        assert.deepEqual(pet?.configuration, { machine: "pet", model: id });
        assert.deepEqual(pet?.diskFormats, [], "the 2001's disks are added in the Machine view");
        assert.deepEqual(pet?.tapeFormats, ["tap", "wav", "prg"], "a .prg goes in as the tape SAVE writes");
        assert.equal(pet?.tapeOption, "cassette1", "a tape starts in the built-in Datasette");
        assert.deepEqual(pet?.programFormats, ["prg", "bin"]);
        assert.deepEqual(pet?.choices.map(choice => choice.option), ["ramKilobytes", "sound", "snow"]);
        assert.equal(pet?.choices[0].default, 8);
        assert.equal(pet?.choices[2].default, id === "pet2001", "snow by default only on the 2001 with BASIC 1, as the launch has it");
    }
    assert.deepEqual(machineById("pet2001")?.basicDialects, ["petbasic"], "one dialect, whose version the ROMs pick");
    assert.deepEqual(machineById("pet2001-basic2")?.basicDialects, ["petbasic"]);
    for (const id of ["pet4032", "pet4032-business"]) {
        const pet = machineById(id);
        assert.deepEqual(pet?.configuration, { machine: "pet", model: id });
        assert.deepEqual(pet?.diskFormats, ["d64", "g64"], "a disk goes in the 4040 the 4032 comes with");
        assert.deepEqual(pet?.tapeFormats, ["tap", "wav", "prg"]);
        assert.deepEqual(pet?.basicDialects, ["petbasic"]);
        assert.deepEqual(pet?.choices.map(choice => choice.option), ["ramKilobytes", "sound"], "the 4032's board has no snow");
        assert.equal(pet?.choices[0].default, 32);
    }
    assert.deepEqual(machineById("bbcb")?.configuration, { machine: "bbc", model: "bbcb" });
    assert.deepEqual(machineById("bbcb")?.diskFormats, ["ssd", "dsd"]);
    assert.deepEqual(machineById("bbcb")?.basicDialects, ["bbcbasic"]);
    assert.deepEqual(machineById("bbca")?.diskFormats, [], "the Model A has no disk interface");
    assert.deepEqual(machineById("bbca")?.tapeFormats, ["uef"]);
    for (const id of ["atari800", "atari400"]) {
        const atari = machineById(id);
        assert.deepEqual(atari?.configuration, { machine: "atari800", model: id });
        assert.deepEqual(atari?.diskFormats, ["atr", "xfd"]);
        assert.deepEqual(atari?.tapeFormats, ["cas"]);
        assert.deepEqual(atari?.basicDialects, ["atari"]);
        assert.deepEqual(atari?.executableFormats, ["xex"]);
        assert.deepEqual(atari?.cartridgeFormats, ["rom", "car"]);
        assert.deepEqual(atari?.choices.map(choice => choice.option), ["basicCartridge", "video", "diskDrive", "sound"]);
    }
});

test("a launch configuration finds its catalog machine as the host reads its model", () => {
    for (const machine of machines) {
        assert.equal(catalogMachine(launchConfiguration(machine))?.id, machine.id, `${machine.label} finds itself`);
    }
    assert.equal(catalogMachine({ machine: "apple2" })?.id, "apple2-iie-enhanced", "the IIe enhanced is the Apple II default");
    assert.equal(catalogMachine({ machine: "apple2", model: "enhanced" })?.id, "apple2-iie-enhanced");
    assert.equal(catalogMachine({ machine: "apple2", model: "original" })?.id, "apple2-iie");
    assert.equal(catalogMachine({ machine: "coco" })?.id, "coco2", "the CoCo 2 is the Color Computer default");
    assert.equal(catalogMachine({ machine: "bbc" })?.id, "bbcb", "the Model B is the BBC Micro default");
    assert.equal(catalogMachine({ machine: "atari800" })?.id, "atari800", "the 800 is the Atari default");
    assert.equal(catalogMachine({ machine: "atari800", model: "atari400" })?.id, "atari400");
    assert.equal(catalogMachine({ machine: "trs80-model1" })?.id, "trs80-model1-level2");
    assert.equal(catalogMachine({ machine: "trs80-model1", rom: "level1" })?.id, "trs80-model1-level1");
    assert.equal(catalogMachine({ machine: "trs80-model3" })?.id, "trs80-model3", "the Model III is its machine's default");
    assert.equal(catalogMachine({ machine: "trs80-model3", model: "III" })?.id, "trs80-model3");
    assert.equal(catalogMachine({ machine: "trs80-model3", rom: "level1" })?.id, "trs80-model3-level1");
    assert.equal(catalogMachine({ machine: "trs80-model3", rom: "level2" })?.id, "trs80-model3");
    assert.equal(catalogMachine({ machine: "trs80-model4" })?.id, "trs80-model4", "the Model 4's own machine name is a 4");
    assert.equal(catalogMachine({ machine: "trs80-model4", model: "4p" })?.id, "trs80-model4p");
    assert.equal(catalogMachine({ machine: "trs80-model2" })?.id, "trs80-model2");
    assert.equal(catalogMachine({ machine: "trs80-model2", model: "16b" })?.id, "trs80-model16");
    assert.equal(catalogMachine({ machine: "altair" })?.id, "altair");
    assert.equal(catalogMachine({ machine: "pet" })?.id, "pet2001-basic2", "BASIC 2 is the PET's default");
    assert.equal(catalogMachine({ machine: "pet", model: "pet2001" })?.id, "pet2001");
    assert.equal(catalogMachine({ machine: "pet", model: "pet4032-business" })?.id, "pet4032-business");
    assert.equal(catalogMachine({ machine: "kaypro2" })?.id, "kaypro2");
    assert.equal(catalogMachine({ machine: "pdp10" }), undefined);
});

test("a favorite can name every catalog machine, and only those", () => {
    const schema = JSON.parse(readFileSync(path.resolve(__dirname, "../../package.json"), "utf8"))
        .contributes.configuration.properties["retrocore.favorites"].items.properties.machine.enum as string[];
    assert.deepEqual([...schema].sort(), machines.map(machine => machine.id).sort());
});

test("a setting reads its default when the configuration leaves it out, and is left out when set back to it", () => {
    const plus = machineById("apple2-iiplus");
    const memory = plus?.choices.find(choice => choice.option === "ramKilobytes");
    assert.ok(plus && memory);
    const configuration = launchConfiguration(plus);
    assert.equal(settingValue(memory, configuration), 48);
    const smaller = withSetting(configuration, memory, 32);
    assert.equal(settingValue(memory, smaller), 32);
    assert.equal(configuration.ramKilobytes, undefined, "the original is unchanged");
    assert.equal("ramKilobytes" in withSetting(smaller, memory, 48), false, "the default is left out");
});

test("a Color Computer given disks shows the disk controller they bring", () => {
    const coco = machineById("coco2");
    const controller = coco?.choices.find(choice => choice.option === "diskController");
    assert.ok(coco && controller);
    const withDisks = { ...launchConfiguration(coco), disks: ["a.dsk"] };
    assert.equal(settingValue(controller, launchConfiguration(coco)), false, "none without disks");
    assert.equal(settingValue(controller, withDisks), true, "the controller its disks bring");
    assert.equal("diskController" in withSetting(withDisks, controller, true), false, "left out, as the disks imply it");
    assert.equal(withSetting(withDisks, controller, false).diskController, false, "turned off explicitly, not by leaving it out");
});

test("an Atari given a cartridge shows BASIC out of the left slot", () => {
    const atari = machineById("atari800");
    const basic = atari?.choices.find(choice => choice.option === "basicCartridge");
    assert.ok(atari && basic);
    const withCartridge = { ...launchConfiguration(atari), cartridge: "star.rom" };
    assert.equal(settingValue(basic, launchConfiguration(atari)), "c", "rev. C without a cartridge");
    assert.equal(settingValue(basic, withCartridge), "none", "the cartridge takes BASIC's place");
    assert.equal("basicCartridge" in withSetting(withCartridge, basic, "none"), false, "left out, as the cartridge implies it");
});

// A catalog machine and one of its choices, as the tests need them.
function choiceOf(id: string, option: string): { machine: NonNullable<ReturnType<typeof machineById>>; choice: MachineChoice } {
    const machine = machineById(id);
    const choice = machine?.choices.find(candidate => candidate.option === option);
    assert.ok(machine && choice, `${id} has ${option}`);
    return { machine, choice };
}

test("the Model I and the Model III choose their ROM, each Level's entry the same choice", () => {
    for (const id of ["trs80-model1-level2", "trs80-model1-level1"]) {
        const { choice } = choiceOf(id, "rom");
        assert.deepEqual(choice.values.map(value => value.label), ["Level II BASIC 1.3", "Level II BASIC 1.2", "Level I BASIC"]);
    }
    for (const id of ["trs80-model3", "trs80-model3-level1"]) {
        const { choice } = choiceOf(id, "rom");
        assert.deepEqual(choice.values.map(value => value.label), ["Model III ROM", "Level I BASIC"]);
        assert.deepEqual(machineById(id)?.choices.map(candidate => candidate.option), ["rom", "ramKilobytes"],
            "the Model III's memory is 16, 32 or 48 KB under either ROM");
    }
    assert.equal(machineById("trs80-model4")?.choices.some(candidate => candidate.option === "rom"), false, "only the Model III has Level I");

    const { machine, choice } = choiceOf("trs80-model1-level2", "rom");
    const level2 = launchConfiguration(machine);
    assert.equal(settingValue(choice, level2), "level2");
    assert.equal(settingValue(choice, { ...level2, revision: "1.2" }), "level2-1.2", "1.2 is the revision option");
    assert.equal(settingValue(choice, { ...level2, revision: "1.3" }), "level2");
    assert.deepEqual(withSetting(level2, choice, "level2-1.2"), { ...level2, revision: "1.2" });
    assert.deepEqual(withSetting({ ...level2, revision: "1.2" }, choice, "level2"), level2, "1.3 leaves the revision out");
    const level1 = withSetting({ ...level2, revision: "1.2" }, choice, "level1");
    assert.equal(level1.rom, "level1");
    assert.equal("revision" in level1, false, "Level I has no revision");
    assert.equal(catalogMachine(level1)?.id, "trs80-model1-level1", "the setting moves it to Level I's entry");
    assert.equal(catalogMachine(withSetting(level1, choice, "level2"))?.id, "trs80-model1-level2");
});

test("a change of ROM keeps the tape, takes out what Level I lacks, and memory follows the ROM unless chosen", () => {
    const { machine, choice } = choiceOf("trs80-model1-level2", "rom");
    const memory = choiceOf("trs80-model1-level2", "ramKilobytes").choice;
    const expansion = choiceOf("trs80-model1-level2", "expansionInterface").choice;
    const withMedia = { ...launchConfiguration(machine), cassette: "eliza.cas", disks: ["ldos.dsk"], diskController: true, doubler: "percom" };
    const level1 = withSetting(withMedia, choice, "level1");
    assert.equal(level1.cassette, "eliza.cas", "the tape stays in");
    for (const option of ["disks", "diskController", "doubler"]) assert.equal(option in level1, false, `Level I has no ${option}`);
    assert.equal(settingValue(memory, level1), 4, "Level I's own memory");
    assert.equal(settingValue(expansion, level1), false, "and no Expansion Interface");
    assert.equal(settingValue(memory, withSetting(level1, choice, "level2")), 48, "Level II's, with its Expansion Interface");

    const chosen = withSetting(launchConfiguration(machine), memory, 16);
    assert.equal(chosen.ramKilobytes, 16);
    assert.equal(settingValue(memory, withSetting(chosen, choice, "level1")), 16, "a size chosen stays");
    const big = withSetting(launchConfiguration(machine), memory, 32);
    const bigLevel1 = withSetting(big, choice, "level1");
    assert.deepEqual([bigLevel1.ramKilobytes, bigLevel1.expansionInterface], [32, true], "32 KB on Level I brings the interface");

    const model3 = choiceOf("trs80-model3", "rom");
    const disks = { ...launchConfiguration(model3.machine), cassette: "a.cas", disks: ["trsdos.dsk"], ramKilobytes: 32 };
    const model3Level1 = withSetting(disks, model3.choice, "level1");
    assert.deepEqual([model3Level1.rom, model3Level1.cassette, model3Level1.ramKilobytes, model3Level1.disks], ["level1", "a.cas", 32, undefined]);
    assert.equal(catalogMachine(model3Level1)?.id, "trs80-model3-level1");
});

test("the Model I's memory is its own setting, kept to what the Expansion Interface allows", () => {
    const { machine, choice: memory } = choiceOf("trs80-model1-level2", "ramKilobytes");
    const expansion = choiceOf("trs80-model1-level2", "expansionInterface").choice;
    assert.deepEqual(memory.values.map(value => value.value), [48, 32, 16, 4]);
    const level2 = launchConfiguration(machine);
    assert.equal(settingValue(memory, level2), 48, "48 KB with the Expansion Interface by default");
    assert.equal(settingValue(memory, withSetting(level2, expansion, false)), 16, "16 KB without it");
    assert.deepEqual(withSetting(level2, expansion, false), { ...level2, expansionInterface: false });
    assert.equal(settingValue(memory, { ...level2, rom: "level1" }), 4, "4 KB for Level I");

    const small = withSetting(level2, memory, 16);
    assert.equal(small.ramKilobytes, 16, "16 KB with the interface is a choice");
    const noInterface = withSetting(withSetting(level2, memory, 32), expansion, false);
    assert.deepEqual([settingValue(memory, noInterface), noInterface.expansionInterface], [16, false],
        "taking out the interface brings memory down to 16 KB");
    assert.equal("ramKilobytes" in noInterface, false, "which is what no interface gives");
    const grown = withSetting(noInterface, memory, 48);
    assert.equal("ramKilobytes" in grown, false, "48 KB with the interface is the default again");
    assert.equal("expansionInterface" in grown, false, "and 48 KB brings the interface back");

    const level1 = launchConfiguration(choiceOf("trs80-model1-level1", "ramKilobytes").machine);
    assert.deepEqual(withSetting(level1, memory, 16), { ...level1, ramKilobytes: 16 }, "Level I with 16 KB, as Level I machines were sold");
    assert.deepEqual(withSetting(level1, memory, 48), { ...level1, expansionInterface: true },
        "48 KB on Level I brings the interface, with which 48 KB is the default");
    assert.equal("ramKilobytes" in withSetting(level1, memory, 4), false, "4 KB is Level I's default");
});
