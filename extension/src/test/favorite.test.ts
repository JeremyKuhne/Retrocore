// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import { test } from "node:test";
import { differences, expanded, favoriteFrom, favoriteSetup, isFavorite, keepResolved, local, portable, resolveVariables, type Favorite } from "../favorite";
import { setupConfiguration, setupFromConfiguration, type Setup } from "../startFlow";

test("a favorite is a setup under its own name, with its saved machine", () => {
    const setup: Setup = { machineId: "apple2-iiplus", kind: "basic", path: "C:\\work\\hello.bas", options: { ramKilobytes: 32 } };
    const state = { cards: { "5": "diskII16" }, media: {} };
    const favorite = favoriteFrom(setup, "Hello", "  Says hello  ", state);
    assert.deepEqual(favorite, {
        name: "Hello", description: "Says hello", machine: "apple2-iiplus", options: { ramKilobytes: 32 },
        run: { kind: "basic", path: "C:\\work\\hello.bas" }, machineState: state
    });

    // Its setup starts it under its own name, so its saved machine is its own.
    const again = favoriteSetup(favorite);
    assert.equal(setupConfiguration(again).name, "Hello");
    assert.equal(setupConfiguration(again).basic, "C:\\work\\hello.bas");
    assert.equal(setupConfiguration(again).ramKilobytes, 32);

    // A bare machine with defaults leaves out what is empty.
    assert.deepEqual(favoriteFrom({ machineId: "coco2", kind: "machine", options: {} }, "CoCo", "", undefined), { name: "CoCo", machine: "coco2" });
});

test("only a named favorite of a known machine is used", () => {
    assert.ok(isFavorite({ name: "A", machine: "apple1" }));
    assert.equal(isFavorite({ name: "", machine: "apple1" }), false);
    assert.equal(isFavorite({ name: "A", machine: "pdp10" }), false);
    assert.equal(isFavorite("A"), false);
});

test("a launch configuration becomes the setup Start Machine would make", () => {
    assert.deepEqual(setupFromConfiguration({ machine: "apple2", model: "iiplus", ramKilobytes: 32, slot0: "languageCard", debugFile: "x.dbg" }),
        { machineId: "apple2-iiplus", kind: "machine", options: { ramKilobytes: 32 } }, "the default slot 0 and the debug file are left out");
    assert.deepEqual(setupFromConfiguration({ machine: "trs80-model1", source: "C:\\a.asm" }),
        { machineId: "trs80-model1-level2", kind: "source", path: "C:\\a.asm", options: {} });
    assert.deepEqual(setupFromConfiguration({ machine: "apple2", source: "C:\\a.s", dos: "3.3" })?.kind, "dosSource");
    assert.equal(setupFromConfiguration({ machine: "pdp10" }), undefined);

    // Disks and tapes it starts with are what it runs, and a Color Computer's disks bring their controller.
    assert.deepEqual(setupFromConfiguration({ machine: "apple2", diskImage: "C:\\dos.dsk" }),
        { machineId: "apple2-iie-enhanced", kind: "disk", path: "C:\\dos.dsk", options: {} });
    assert.deepEqual(setupFromConfiguration({ machine: "coco", disks: ["C:\\a.dsk", "C:\\b.dsk"] }),
        { machineId: "coco2", kind: "disk", path: "C:\\a.dsk", options: { diskController: true } });
    assert.deepEqual(setupFromConfiguration({ machine: "coco", source: "C:\\a.asm", disks: ["C:\\a.dsk"] }),
        { machineId: "coco2", kind: "source", path: "C:\\a.asm", options: { diskController: true } }, "the controller stays when it runs a source");
    assert.deepEqual(setupFromConfiguration({ machine: "coco", disks: ["C:\\a.dsk"], diskController: false })?.options, {},
        "a controller turned off stays off");
    assert.deepEqual(setupFromConfiguration({ machine: "trs80-model1", source: "C:\\a.asm", disks: ["C:\\d.dsk"] })?.options, { diskController: true },
        "the Model I keeps its implied controller as the launch option");
    assert.deepEqual(setupFromConfiguration({ machine: "trs80-model3", model: "4", source: "C:\\a.asm", disks: ["C:\\d.dsk"] })?.options, { diskController: true },
        "the Model 4 keeps its implied controller");
    assert.deepEqual(setupFromConfiguration({ machine: "trs80-model1", diskController: true })?.options, { diskController: true },
        "and an explicit one is kept where the catalog has no such choice");
    const dos32 = setupFromConfiguration({ machine: "apple2", model: "iiplus", source: "C:\\a.s", dos: "3.2" });
    assert.equal(dos32?.dos, "3.2", "a DOS 3.2 source stays one");
    assert.equal(dos32 === undefined ? undefined : setupConfiguration(dos32).dos, "3.2");
    assert.equal(setupFromConfiguration({ machine: "apple2", source: "C:\\a.s", dos: "3.3" })?.dos, undefined);
    assert.equal(favoriteSetup(favoriteFrom(dos32!, "D", undefined, undefined)).dos, "3.2", "and through a favorite");
    assert.deepEqual(setupFromConfiguration({ machine: "trs80-model1", cassette: "C:\\a.cas" }),
        { machineId: "trs80-model1-level2", kind: "tape", path: "C:\\a.cas", options: {} });
});

test("paths inside the workspace are kept as ${workspaceFolder} and come back as they were", () => {
    const workspace = "C:\\Work\\Project";
    const favorite = {
        run: { path: "c:\\work\\project\\src\\main.s" },
        machineState: { media: { disk1: { path: "C:\\Work\\Project\\disks\\games.dsk" }, disk2: { path: "C:\\Work\\ProjectOther\\x.dsk" } } },
        name: "C:\\Work\\Project"
    };
    const kept = portable(favorite, workspace);
    assert.equal(kept.run.path, "${workspaceFolder}/src/main.s", "case does not matter on Windows");
    assert.equal(kept.machineState.media.disk1.path, "${workspaceFolder}/disks/games.dsk");
    assert.equal(kept.machineState.media.disk2.path, "C:\\Work\\ProjectOther\\x.dsk", "a folder that only starts the same is not inside");
    assert.equal(kept.name, "${workspaceFolder}");
    assert.equal(resolveVariables(kept.machineState.media.disk1.path, "D:\\Elsewhere"), "D:\\Elsewhere/disks/games.dsk");
    assert.equal(portable(favorite, undefined), favorite, "with no workspace nothing changes");
    assert.equal(portable({ path: "/home/me/project/a.dsk" }, "/home/me/project").path, "${workspaceFolder}/a.dsk");
    assert.equal(portable({ path: "/home/me/Project/a.dsk" }, "/home/me/project").path, "/home/me/Project/a.dsk", "elsewhere, case matters");
});

test("a launch entry read again keeps what only a launch resolves, and takes everything else as it is now", () => {
    const previous = { name: "Run", machine: "apple2", source: "C:\\work\\main.s", ramKilobytes: 48, disks: ["C:\\work\\a.dsk"] };
    const fresh = { name: "Run", machine: "apple2", source: "${file}", ramKilobytes: 32, disks: ["${fileDirname}\\a.dsk"], model: "iiplus" };
    assert.deepEqual(keepResolved(fresh, previous), {
        name: "Run", machine: "apple2", source: "C:\\work\\main.s", ramKilobytes: 32, disks: ["C:\\work\\a.dsk"], model: "iiplus"
    });
    assert.equal(keepResolved({ source: "${file}" }, {}).source, "${file}", "with nothing resolved before, it stays as written");
    assert.equal(keepResolved({ source: "${file}" }, { source: "${file}" }).source, "${file}");
});

test("a favorite is compared with its variables expanded and its separators made one", () => {
    const kept: Favorite = { name: "E", machine: "apple2-iiplus", run: { kind: "disk", path: "${env:RETRO_TEST_DISKS}/dos.dsk" } };
    const now: Favorite = { name: "E", machine: "apple2-iiplus", run: { kind: "disk", path: "C:\\disks\\dos.dsk" } };
    process.env.RETRO_TEST_DISKS = "C:\\disks";
    try {
        assert.deepEqual(differences(expanded(kept, undefined), expanded(now, undefined)), [], "the same disk, written two ways");
    } finally {
        delete process.env.RETRO_TEST_DISKS;
    }
});

test("a workspace path comes back as the workspace's own, with its separators", () => {
    assert.equal(local("${workspaceFolder}/disks/games.dsk", "C:\\Work\\Project"), "C:\\Work\\Project\\disks\\games.dsk");
    assert.equal(local("${workspaceFolder}/disks/games.dsk", "/home/me/project/"), "/home/me/project/disks/games.dsk");
    assert.deepEqual(local({ a: ["${workspaceFolder}/x", "C:\\other"] }, "D:\\w"), { a: ["D:\\w\\x", "C:\\other"] });
    assert.equal(local("${workspaceFolder}/x", undefined), "${workspaceFolder}/x");
});

test("a favorite differs from its machine by its settings, what it runs, its cards and its disks", () => {
    const kept: Favorite = {
        name: "A", machine: "apple2-iiplus", options: { ramKilobytes: 32 },
        machineState: { cards: { "4": "empty", "5": "diskII16" }, media: { slot5disk1: { path: "a.dsk", writeProtected: true }, slot5disk2: null } }
    };
    assert.deepEqual(differences(kept, { ...kept, machineState: { media: { slot5disk1: { writeProtected: true, path: "a.dsk" } }, cards: { "5": "diskII16" } } }), [],
        "key order, empty slots and empty drives do not count");
    assert.deepEqual(differences(kept, { ...kept, options: { ramKilobytes: 48 } }), ["its settings"]);
    assert.deepEqual(differences(kept, { ...kept, run: { kind: "basic", path: "b.bas" } }), ["what it runs"]);
    assert.deepEqual(differences(kept, { ...kept, machineState: { cards: { "5": "empty" }, media: { slot5disk1: { path: "a.dsk", writeProtected: true } } } }),
        ["its cards"], "a card taken out, its drives' empty entries gone with it");
    assert.deepEqual(differences(kept, { ...kept, machineState: { cards: { "5": "diskII16" }, media: { slot5disk1: { path: "a.dsk", writeProtected: false } } } }),
        ["its disks and tapes"], "write protection is part of the disk");
    const bare: Favorite = { name: "B", machine: "apple2-iiplus" };
    assert.deepEqual(differences(bare, { ...bare, machineState: { cards: { "0": "languageCard" } } }), [],
        "a favorite with no cards and media recorded is whatever its launch gives");
});
