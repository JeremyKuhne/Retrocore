// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as vscode from "vscode";

interface Row { id: string; value: string }
interface Favorite { name: string; description?: string; machine: string; options?: Record<string, unknown>; machineState?: { cards?: Record<string, string> } }
type Kept = Record<"user" | "workspace", Favorite[]>;

async function until<T>(what: string, probe: () => Promise<T | undefined> | T | undefined, timeout = 20000): Promise<T> {
    for (const end = Date.now() + timeout; ;) {
        const value = await probe();
        if (value !== undefined) return value;
        if (Date.now() > end) throw new Error(`Timed out waiting for ${what}.`);
        await new Promise(resolve => setTimeout(resolve, 100));
    }
}

const list = (): Thenable<Kept> => vscode.commands.executeCommand<Kept>("retrocore.favorite.list");
interface Mark { state: "none" | "saved" | "changed"; name?: string; differences?: string[] }
const mark = (): Thenable<Mark> => vscode.commands.executeCommand<Mark>("retrocore.favorite.mark");

// Waits for the machine's heart to be in a state.
async function heart(state: Mark["state"], what: string): Promise<Mark> {
    return await until(what, async () => {
        const found = await mark();
        return found.state === state ? found : undefined;
    });
}
const rows = (): Thenable<Row[]> => vscode.commands.executeCommand<Row[]>("retrocore.device.hardware");

// Waits for the views to show this off machine with a row that is wanted.
async function offRow(name: string, id: string, wanted: (row: Row) => boolean, what: string): Promise<void> {
    await until(what, async () => {
        if (await vscode.commands.executeCommand<string | undefined>("retrocore.machine.off") !== name) return undefined;
        const row = (await rows()).find(candidate => candidate.id === id);
        return row !== undefined && wanted(row) ? true : undefined;
    });
}

/**
 * Favorites: the off II Plus with a card added kept as one, loaded back after switching away, started, described,
 * renamed, shared with the workspace and back, and removed.
 */
export async function testFavorites(workspace: vscode.WorkspaceFolder): Promise<void> {
    await vscode.commands.executeCommand("workbench.view.extension.retrocore");
    const plus = "Apple II Plus (Retrocore)";
    const name = "Retrocore test: II Plus with a Disk II";
    await offRow(plus, "memory", row => row.value === "32 KB", "the II Plus the off machine's test left");
    assert.deepEqual((await list()).user.filter(favorite => favorite.name === name), [], "no favorite of that name yet");

    // Kept with its setting and the card added off; the machine's heart goes from empty to filled.
    await vscode.commands.executeCommand("retrocore.machine.change", "hardware", { id: "slot5", action: "addDiskII", sectors: 16 });
    await offRow(plus, "slot5", row => /Disk II/.test(row.value), "the Disk II in slot 5");
    await heart("none", "an empty heart on a machine not saved");
    assert.ok(await vscode.commands.executeCommand<boolean>("retrocore.favorite.add", name, "Boots DOS from slot 5"));
    assert.equal((await heart("saved", "a filled heart once saved")).name, name);
    const kept = (await list()).user.find(favorite => favorite.name === name);
    assert.ok(kept, "the favorite is in user settings");
    assert.equal(kept.machine, "apple2-iiplus");
    assert.equal(kept.description, "Boots DOS from slot 5");
    assert.deepEqual(kept.options, { ramKilobytes: 32 });
    assert.equal(kept.machineState?.cards?.["5"], "diskII16", "with the card");
    assert.equal(await vscode.commands.executeCommand<boolean>("retrocore.favorite.add", name, "again"), false, "names are unique");

    // The II Plus goes back as it was, which breaks the heart: its card has changed since it was saved. The favorite
    // brings the card back when loaded.
    await vscode.commands.executeCommand("retrocore.machine.change", "hardware", { id: "slot5", action: "removeCard" });
    await offRow(plus, "slot5", row => row.value === "empty", "slot 5 empty on the II Plus");
    assert.deepEqual((await heart("changed", "a broken heart once the card is out")).differences, ["its cards"]);
    assert.ok(await vscode.commands.executeCommand<boolean>("retrocore.favorite.load", { name, scope: "user" }));
    await offRow(name, "slot5", row => /Disk II/.test(row.value), "the favorite set up, with its card");
    assert.equal((await rows()).find(row => row.id === "memory")?.value, "32 KB", "and its setting");
    await heart("saved", "a filled heart on the favorite loaded");

    // A card added breaks the heart; updating takes the machine as it is, and fills it again.
    await vscode.commands.executeCommand("retrocore.machine.change", "hardware", { id: "slot4", action: "addDiskII", sectors: 16 });
    await heart("changed", "a broken heart once another card is in");
    assert.ok(await vscode.commands.executeCommand<boolean>("retrocore.favorite.updateShown"));
    await heart("saved", "a filled heart once updated");
    assert.equal((await list()).user.find(favorite => favorite.name === name)?.machineState?.cards?.["4"], "diskII16", "the favorite has the new card");

    // Started, it has them, under its own name.
    assert.ok(await vscode.commands.executeCommand<boolean>("retrocore.favorite.start", name));
    const session = vscode.debug.activeDebugSession;
    if (session?.type !== "retrocore") throw new Error("The favorite did not start a Retrocore session.");
    try {
        assert.equal(session.name, name);
        const hardware = (await session.customRequest("retro/devices") as { hardware: Row[] }).hardware;
        assert.match(hardware.find(row => row.id === "slot5")?.value ?? "", /Disk II/, "the started favorite has its card");
        assert.equal(hardware.find(row => row.id === "memory")?.value, "32 KB");
    } finally {
        await vscode.debug.stopDebugging(session);
    }

    // Described, renamed, shared with the workspace and moved back; the workspace's settings are put back as they were.
    assert.ok(await vscode.commands.executeCommand<boolean>("retrocore.favorite.editDescription", { name, scope: "user" }, "DOS 3.3 in slot 5"));
    assert.equal((await list()).user.find(favorite => favorite.name === name)?.description, "DOS 3.3 in slot 5");
    const renamed = `${name}, renamed`;
    assert.ok(await vscode.commands.executeCommand<boolean>("retrocore.favorite.rename", { name, scope: "user" }, renamed));
    assert.deepEqual((await list()).user.filter(favorite => favorite.name === name), [], "the old name is gone");
    const settingsFile = path.join(workspace.uri.fsPath, ".vscode", "settings.json");
    const before = fs.existsSync(settingsFile) ? fs.readFileSync(settingsFile, "utf8") : undefined;
    try {
        assert.ok(await vscode.commands.executeCommand<boolean>("retrocore.favorite.share", { name: renamed, scope: "user" }));
        let now = await list();
        assert.ok(now.workspace.some(favorite => favorite.name === renamed), "shared with the workspace");
        assert.equal(now.user.some(favorite => favorite.name === renamed), false, "and no longer in user settings");
        assert.ok(await vscode.commands.executeCommand<boolean>("retrocore.favorite.moveToUser", { name: renamed, scope: "workspace" }));
        now = await list();
        assert.ok(now.user.some(favorite => favorite.name === renamed), "back in user settings");
        assert.equal(now.workspace.some(favorite => favorite.name === renamed), false);
    } finally {
        if (before === undefined) fs.rmSync(settingsFile, { force: true });
        else fs.writeFileSync(settingsFile, before);
    }

    // Removed, and the II Plus set up again for the tests after.
    assert.ok(await vscode.commands.executeCommand<boolean>("retrocore.favorite.remove", { name: renamed, scope: "user" }, true));
    assert.deepEqual((await list()).user.filter(favorite => favorite.name === renamed), []);
    await vscode.commands.executeCommand("retrocore.machine.switch", {
        configuration: { type: "retrocore", request: "launch", name: plus, machine: "apple2", model: "iiplus", ramKilobytes: 32 },
        source: { kind: "setup", setup: { machineId: "apple2-iiplus", kind: "machine", options: { ramKilobytes: 32 } } }
    });
    await offRow(plus, "memory", row => row.value === "32 KB", "the II Plus again");
    await heart("none", "an empty heart once its favorite is removed");

    // The empty heart saves at once under the machine's own name, nothing to pick; removed again after. VS Code gives
    // an inline button's command the row it is on, as here.
    const row = { machine: (await rows()).find(candidate => candidate.id === "model") };
    assert.ok(await vscode.commands.executeCommand<boolean>("retrocore.favorite.add", row, [row]));
    const quick = await heart("saved", "a filled heart after saving with no name given");
    assert.match(quick.name ?? "", /^Apple II Plus( \d+)?$/, "named for the machine");
    assert.ok(await vscode.commands.executeCommand<boolean>("retrocore.favorite.remove", { name: quick.name, scope: "user" }, true));
    await heart("none", "an empty heart again");

    console.log("Favorites passed: the heart saves a machine set up off with its setting and card, breaks when it changes and fills again on update; a favorite loads back, starts under its name, and is described, renamed, shared, moved back and removed.");
}
