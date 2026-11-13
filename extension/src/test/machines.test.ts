// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import * as path from "node:path";
import { test } from "node:test";
import { catalogMachine, launchConfiguration, machineById, machines, settingValue, withSetting } from "../machines";

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
                assert.ok(allows(schema, value.value), `${machine.label}: ${choice.option} allows ${String(value.value)}`);
            }
            assert.ok(choice.values.some(value => value.value === choice.default), `${machine.label}: ${choice.option}'s default is a value`);
            // The schema's defaults are the Apple II's; the TRS-80s' differ, as their own descriptions say.
            if (schema.default !== undefined && machine.configuration.machine === "apple2") {
                assert.equal(choice.default, schema.default, `${machine.label}: ${choice.option} defaults as the debug host does`);
            }
        }
    }
});

test("the machines are the ten agreed, each with its own id and name, in order", () => {
    assert.deepEqual(machines.map(machine => machine.label), [
        "Apple IIe (enhanced)", "Apple IIe", "Apple II Plus", "Apple II", "Apple III", "TRS-80 Model I (Level II)",
        "TRS-80 Model I (Level I)", "Apple-1", "TRS-80 Color Computer", "TRS-80 Color Computer 2", "TRS-80 Color Computer 3"
    ]);
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
});

test("a launch configuration finds its catalog machine as the host reads its model", () => {
    for (const machine of machines) {
        assert.equal(catalogMachine(launchConfiguration(machine))?.id, machine.id, `${machine.label} finds itself`);
    }
    assert.equal(catalogMachine({ machine: "apple2" })?.id, "apple2-iie-enhanced", "the IIe enhanced is the Apple II default");
    assert.equal(catalogMachine({ machine: "apple2", model: "enhanced" })?.id, "apple2-iie-enhanced");
    assert.equal(catalogMachine({ machine: "apple2", model: "original" })?.id, "apple2-iie");
    assert.equal(catalogMachine({ machine: "coco" })?.id, "coco2", "the CoCo 2 is the Color Computer default");
    assert.equal(catalogMachine({ machine: "trs80-model1" })?.id, "trs80-model1-level2");
    assert.equal(catalogMachine({ machine: "trs80-model1", rom: "level1" })?.id, "trs80-model1-level1");
    assert.equal(catalogMachine({ machine: "pdp10" }), undefined);
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
