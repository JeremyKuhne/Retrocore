// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { after, test } from "node:test";
import { fingerprint } from "../hardware";
import { activeTargetParams, findTarget, inProject, loadTargets, parseJsonc, projectLaunch, projectTargetKey, qualifiedName, savedLabel, savedName, splitSavedName, withProjectMachine } from "../project";

const sample = path.resolve(__dirname, "..", "..", "..", "sample", "project");

const scratches: string[] = [];
after(() => { for (const root of scratches) fs.rmSync(root, { recursive: true, force: true }); });

function scratch(files: Record<string, string>): string {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), "retrocore-project-"));
    scratches.push(root);
    for (const [name, text] of Object.entries(files)) {
        fs.mkdirSync(path.dirname(path.join(root, name)), { recursive: true });
        fs.writeFileSync(path.join(root, name), text);
    }
    return root;
}

test("comments and trailing commas are left out, and strings that look like them are kept", () => {
    assert.deepEqual(parseJsonc(`// a comment
        { "a": "// not a comment", /* gone */ "b": [1, 2,], "c": "x,]", "d": "\\"/*\\"", }`),
    { a: "// not a comment", b: [1, 2], c: "x,]", d: "\"/*\"" });
});

test("the sample project's targets are its two Apple IIs, by name and as project/target", () => {
    const targets = loadTargets(sample);
    assert.deepEqual(targets.map(qualifiedName), ["hello/apple2-iiplus", "hello/apple2-iie"]);
    assert.deepEqual(targets.map(target => target.machine), ["apple2-iiplus", "apple2-iie-enhanced"]);
    assert.equal(targets[0].file, path.join(sample, "retrocore.json"));
    assert.equal(findTarget(targets, "apple2-iie")?.name, "apple2-iie");
    assert.equal(findTarget(targets, "hello/apple2-iie")?.name, "apple2-iie");
    assert.equal(findTarget(targets, "pet"), undefined);
});

test("a root file's projects each give their targets, and a name they share needs its project", () => {
    const root = scratch({
        "retrocore.json": `{ "projects": ["game", "tools/editor"] }`,
        "game/retrocore.json": `{ "name": "game", "targets": { "apple2": { "machine": "apple2-iie" }, "pet": { "machine": "pet4032" } } }`,
        "tools/editor/retrocore.json": `{ "name": "editor", "targets": { "apple2": { "machine": "apple2-iiplus" } } }`
    });
    const targets = loadTargets(path.join(root, "retrocore.json"));
    assert.deepEqual(targets.map(qualifiedName), ["game/apple2", "game/pet", "editor/apple2"]);
    assert.equal(findTarget(targets, "apple2"), undefined, "two projects have an apple2");
    assert.equal(findTarget(targets, "editor/apple2")?.machine, "apple2-iiplus");
    assert.equal(findTarget(targets, "pet")?.file, path.join(root, "game", "retrocore.json"));
    const broken = scratch({ "retrocore.json": `{ "projects": "game", "targets": { "a": { "machine": "pet4032" } } }` });
    assert.deepEqual(loadTargets(broken), [], "a root whose projects are not a list has no targets, as the host refuses it");
});

test("a project launch gets its target's machine, and every target of one configuration keeps its own saved machine", () => {
    const launch = { type: "retrocore", request: "launch", name: "Debug project", project: sample, machine: "pet" };
    const plus = withProjectMachine({ ...launch, target: "apple2-iiplus" });
    const iie = withProjectMachine({ ...launch, target: "hello/apple2-iie" });
    assert.equal(plus.machine, "apple2");
    assert.equal(plus.model, "iiplus");
    assert.equal(iie.model, "iie-enhanced");
    assert.deepEqual((iie[projectTargetKey] as { target: string }).target, "hello/apple2-iie");
    assert.equal(savedLabel(savedName(plus) ?? ""), "Debug project · hello/apple2-iiplus");
    assert.deepEqual(splitSavedName(savedName(iie) ?? ""), { name: "Debug project", target: "hello/apple2-iie" });
    assert.notEqual(fingerprint(plus), fingerprint(iie));
    assert.equal(savedName(withProjectMachine({ ...launch, target: "apple2-iie" })), savedName(iie),
        "the target by name or as project/target is the same target");
    assert.equal(savedName({ ...launch, target: "apple2-iie" }), savedName(iie),
        "and a launch.json entry read as it is, as the off machine reads it, keeps the same name");
    assert.equal(fingerprint(withProjectMachine({ ...launch, project: path.join(sample, "retrocore.json"), target: "apple2-iie" })),
        fingerprint(iie), "and the same hardware, the project given as its folder or its file");
});

test("a launch that is not a project's, or names a target the extension cannot find, is left for the host", () => {
    const plain = { name: "Plain", machine: "apple2", model: "iie" };
    assert.equal(withProjectMachine(plain), plain);
    assert.equal(savedName(plain), "Plain");
    const missing = { name: "Missing", project: sample, target: "pet" };
    assert.equal(withProjectMachine(missing), missing);
    assert.equal(savedLabel(savedName(missing) ?? ""), "Missing · pet");
    const nowhere = { name: "Nowhere", project: path.join(sample, "no-such-folder"), target: "x" };
    assert.equal(withProjectMachine(nowhere), nowhere);
});

test("a target's launch, as F5 starts it, names its project file and its target as project/target", () => {
    const [plus] = loadTargets(sample);
    assert.deepEqual(projectLaunch(plus), {
        type: "retrocore", request: "launch", name: "hello · apple2-iiplus (Retrocore)",
        project: path.join(sample, "retrocore.json"), target: "hello/apple2-iiplus"
    });
});

test("the language server is told the active target's project file and name, or nulls without one", () => {
    const [, iie] = loadTargets(sample);
    assert.deepEqual(activeTargetParams(iie), { project: path.join(sample, "retrocore.json"), target: "apple2-iie" });
    assert.deepEqual(activeTargetParams(undefined), { project: null, target: null });
});

test("a file is in a project when it is in a project's folder or below it, and not the folder itself or beside it", () => {
    const folders = [path.join(sample)];
    assert.equal(inProject(path.join(sample, "src", "hello.s"), folders), true);
    assert.equal(inProject(path.join(sample, "a.inc"), folders), true);
    assert.equal(inProject(sample, folders), false);
    assert.equal(inProject(path.join(sample, "..", "iie", "main.s"), folders), false);
    assert.equal(inProject(path.join(sample + "-other", "a.s"), folders), false);
    assert.equal(inProject(path.join(sample, "..x", "a.s"), folders), true, "a folder whose name starts with .. is inside");
});
