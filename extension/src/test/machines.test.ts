// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import * as path from "node:path";
import { test } from "node:test";
import { launchConfiguration, machineById, machines } from "../machines";

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

test("the machines are the ones agreed, each with its own id and name, in order", () => {
    assert.deepEqual(machines.map(machine => machine.label), [
        "Apple IIe (enhanced)", "Apple IIe", "Apple II Plus", "Apple II", "Apple III", "TRS-80 Model I (Level II)",
        "TRS-80 Model I (Level I)", "TRS-80 Model III", "TRS-80 Model 4", "TRS-80 Model 4P", "TRS-80 Model II",
        "TRS-80 Model 12", "TRS-80 Model 16 (Z80 side)", "Apple-1", "TRS-80 Color Computer", "TRS-80 Color Computer 2",
        "TRS-80 Color Computer 3"
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
    assert.deepEqual(machineById("trs80-model1-level2")?.tapeFormats, ["cas"]);
    assert.deepEqual(machineById("trs80-model1-level1")?.diskFormats, [], "Level I has no disks");
    assert.deepEqual(machineById("trs80-model4p")?.tapeFormats, [], "the 4P has no cassette port");
    assert.deepEqual(machineById("trs80-model4")?.configuration, { machine: "trs80-model3", model: "4" });
    assert.deepEqual(machineById("trs80-model2")?.diskFormats, ["imd", "dmk", "jv3", "dsk"]);
    assert.deepEqual(machineById("apple1")?.tapeFormats, ["wav"]);
    assert.deepEqual(machineById("apple1")?.diskFormats, [], "the Apple-1 has no disks");
    for (const id of ["coco1", "coco2", "coco3"]) {
        const coco = machineById(id);
        assert.equal(coco?.configuration.machine, "coco");
        assert.equal(coco?.configuration.model, id);
        assert.deepEqual(coco?.diskFormats, ["dsk"]);
        assert.deepEqual(coco?.tapeFormats, ["cas"]);
    }
});
