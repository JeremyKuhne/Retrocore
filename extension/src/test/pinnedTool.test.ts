// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { after, test } from "node:test";
import { chooseHost, findPin, packagesFolder, restoredHost, sameVersion } from "../pinnedTool";

const scratches: string[] = [];
after(() => { for (const root of scratches) fs.rmSync(root, { recursive: true, force: true }); });

function scratch(files: Record<string, string>): string {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), "retrocore-pin-"));
    scratches.push(root);
    for (const [name, text] of Object.entries(files)) {
        fs.mkdirSync(path.dirname(path.join(root, name)), { recursive: true });
        fs.writeFileSync(path.join(root, name), text);
    }
    return root;
}

const manifest = (tools: Record<string, string>, isRoot = true): string => JSON.stringify({
    version: 1,
    isRoot,
    tools: Object.fromEntries(Object.entries(tools).map(([name, version]) => [name, { version, commands: [name] }]))
});

test("the nearest manifest that lists retrocore pins it, from a folder below its repository's root", () => {
    const root = scratch({
        ".config/dotnet-tools.json": manifest({ retrocore: "0.1.0-dev" }),
        "games/adventure/retrocore.json": "{}"
    });
    assert.deepEqual(findPin(path.join(root, "games", "adventure")),
        { manifest: path.join(root, ".config", "dotnet-tools.json"), folder: root, version: "0.1.0-dev" });

    const top = scratch({ "dotnet-tools.json": manifest({ retrocore: "0.2.0" }) });
    assert.equal(findPin(top)?.version, "0.2.0", "a manifest beside the folder is read as dotnet reads it");
    const capitals = scratch({ ".config/dotnet-tools.json": manifest({ Retrocore: "0.3.0" }) });
    assert.equal(findPin(capitals)?.version, "0.3.0", "a tool's id is compared without regard to case, as NuGet's are");
});

test("a root manifest without retrocore stops the search, and one that is not the root does not", () => {
    const root = scratch({
        ".config/dotnet-tools.json": manifest({ retrocore: "0.1.0-dev" }),
        "inner/.config/dotnet-tools.json": manifest({ "dotnet-ef": "9.0.0" }),
        "loose/.config/dotnet-tools.json": manifest({ "dotnet-ef": "9.0.0" }, false)
    });
    assert.equal(findPin(path.join(root, "inner")), undefined, "inner's manifest is the root, and pins no retrocore");
    assert.equal(findPin(path.join(root, "loose"))?.version, "0.1.0-dev", "loose's manifest is not the root, so the search goes on");
    assert.equal(findPin(scratch({ ".config/dotnet-tools.json": "{ not json" })), undefined);
});

test("a restored pin's host is in the NuGet packages folder, under its lowercase version, the newest framework first", () => {
    const packages = scratch({
        "retrocore/0.1.0-dev/tools/net9.0/any/Retrocore.Debug.dll": "",
        "retrocore/0.1.0-dev/tools/net11.0/any/Retrocore.Debug.dll": ""
    });
    assert.equal(restoredHost("0.1.0-DEV", packages), path.join(packages, "retrocore", "0.1.0-dev", "tools", "net11.0", "any", "Retrocore.Debug.dll"));
    assert.equal(restoredHost("0.2.0", packages), undefined);
    assert.equal(packagesFolder({ NUGET_PACKAGES: packages }), packages);
    assert.equal(packagesFolder({}), path.join(os.homedir(), ".nuget", "packages"));
    assert.equal(packagesFolder({ NUGET_PACKAGES: "" }), path.join(os.homedir(), ".nuget", "packages"), "an empty NUGET_PACKAGES is unset");
});

test("the pinned tool runs once restored; until then the extension's own runs, with a warning when it differs", () => {
    const pin = { manifest: "/repo/.config/dotnet-tools.json", folder: "/repo", version: "0.2.0" };
    assert.deepEqual(chooseHost({ configured: "/mine.dll", pin, restored: "/pinned.dll", fallback: "/own.dll" }),
        { host: "/mine.dll", pin, pinned: false }, "a host the settings name always runs");
    assert.deepEqual(chooseHost({ fallback: "/own.dll" }), { host: "/own.dll", pinned: false });
    assert.deepEqual(chooseHost({ pin, restored: "/pinned.dll", fallback: "/own.dll" }), { host: "/pinned.dll", pin, pinned: true });
    assert.deepEqual(chooseHost({ pin, fallback: "/own.dll", fallbackVersion: "0.2.0" }), { host: "/own.dll", pin, pinned: false },
        "the extension's own host of the pinned version is the pinned tool, so no warning");
    assert.equal(chooseHost({ pin: { ...pin, version: "0.2.0-DEV" }, fallback: "/own.dll", fallbackVersion: "0.2.0-dev" }).warning, undefined,
        "versions are compared without regard to case");
    assert.ok(sameVersion("1.0.0-Preview.1", "1.0.0-preview.1"));
    assert.ok(!sameVersion(undefined, "1.0.0"));
    assert.match(chooseHost({ pin, unrunnable: true, fallback: "/own.dll", fallbackVersion: "0.1.0-dev" }).warning ?? "",
        /which is restored but does not run as that version \(is the \.NET runtime it needs installed\?\), so Retrocore runs its own 0\.1\.0-dev instead/);

    const differs = chooseHost({ pin, fallback: "/own.dll", fallbackVersion: "0.1.0-dev" });
    assert.equal(differs.host, "/own.dll");
    assert.match(differs.warning ?? "", /^This repository pins retrocore 0\.2\.0 \(\/repo\/\.config\/dotnet-tools\.json\), which is not restored, so Retrocore runs its own 0\.1\.0-dev instead; a project whose SDK it does not carry fails to build\. Run dotnet tool restore/);
    assert.match(chooseHost({ pin }).warning ?? "", /and Retrocore has no host of its own to run instead/);
});
