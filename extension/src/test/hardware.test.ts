// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import { test } from "node:test";
import { cardsFor, changesFrom, fingerprint, group, restorable, type HardwareRow } from "../hardware";

const row = (id: string, devices: string[] = []): HardwareRow => ({ id, name: id, value: "", description: "", devices });

test("each device sits under the row that claims it, in the rows' order, empty slots included", () => {
    const devices = [{ id: "disk1" }, { id: "disk2" }, { id: "slot7" }];
    const grouped = group([row("model"), row("slot5"), row("slot6", ["disk1", "disk2"]), row("slot7", ["slot7"])], devices);
    assert.deepEqual(grouped.rows.map(entry => [entry.row.id, entry.devices.map(device => device.id)]), [
        ["model", []], ["slot5", []], ["slot6", ["disk1", "disk2"]], ["slot7", ["slot7"]]
    ]);
    assert.deepEqual(grouped.loose, []);
});

test("devices no row claims, or a host without hardware rows, are listed on their own", () => {
    assert.deepEqual(group(undefined, [{ id: "cassette" }]), { rows: [], loose: [{ id: "cassette" }] });
    const grouped = group([row("disk", ["disk0", "missing"])], [{ id: "disk0" }, { id: "cassette" }]);
    assert.deepEqual(grouped.rows[0].devices, [{ id: "disk0" }], "an id with no device is skipped");
    assert.deepEqual(grouped.loose, [{ id: "cassette" }]);
});

test("the Mockingboard is offered only for slot 4, and Disk II, mouse, ProFile and 3.5 controller cards for any free slot", () => {
    assert.deepEqual(cardsFor("slot4").map(card => card.label), [
        "Disk II controller", "Disk II controller, 13-sector", "Mockingboard", "Mouse card", "ProFile interface card",
        "3.5 disk controller"
    ]);
    assert.deepEqual(cardsFor("slot5").map(card => card.label),
        ["Disk II controller", "Disk II controller, 13-sector", "Mouse card", "ProFile interface card", "3.5 disk controller"]);
    assert.deepEqual(cardsFor("slot0").map(card => card.label), ["Language card", "Firmware card"],
        "slot 0 takes the language and firmware cards");
});

test("the Apple III's slots are offered only the ProFile card", () => {
    assert.deepEqual(cardsFor("slot4", "apple3").map(card => card.label), ["ProFile interface card"]);
});

test("a saved machine comes back only while the launch's hardware options are the ones it was saved under", () => {
    const launch = { name: "IIe", machine: "apple2", diskImage: "a.dsk", stopOnEntry: true };
    const saved = { fingerprint: fingerprint(launch), configuration: { cards: { "4": "mockingboard" } } };
    assert.deepEqual(restorable(saved, { ...launch, stopOnEntry: false, program: "other.bin" }), saved.configuration,
        "options other than hardware do not matter");
    assert.equal(restorable(saved, { ...launch, diskImage: "b.dsk" }), undefined, "a new diskImage starts afresh");
    assert.equal(restorable(saved, { ...launch, mockingboard: true }), undefined, "so does a new hardware option");
    assert.equal(restorable(undefined, launch), undefined);
});

test("a saved machine's changes are what differs from the launch's own machine", () => {
    const base = { cards: { "0": "languageCard", "4": "empty", "6": "diskII16" }, media: { disk1: null, disk2: null } };
    const saved = {
        cards: { "0": "languageCard", "4": "mockingboard", "6": "diskII16" },
        media: { disk1: { path: "games.dsk", writeProtected: true }, disk2: null }
    };
    assert.deepEqual(changesFrom(saved, base), {
        cards: { "4": "mockingboard" },
        media: { disk1: { path: "games.dsk", writeProtected: true } }
    }, "slot 0 and the empty drive are the launch's own, so a setting can change them");
    assert.deepEqual(changesFrom({ media: { cassette: null } }, { media: {} }), { media: { cassette: null } }, "a drive the base lacks is kept");
    assert.deepEqual(changesFrom(undefined, base), {}, "nothing saved, nothing changed");
});
