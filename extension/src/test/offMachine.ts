// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import * as vscode from "vscode";

interface Row { id: string; value: string; actions?: string[] }

async function until<T>(what: string, probe: () => Promise<T | undefined> | T | undefined, timeout = 20000): Promise<T> {
    for (const end = Date.now() + timeout; ;) {
        const value = await probe();
        if (value !== undefined) return value;
        if (Date.now() > end) throw new Error(`Timed out waiting for ${what}.`);
        await new Promise(resolve => setTimeout(resolve, 100));
    }
}

const rows = (): Thenable<Row[]> => vscode.commands.executeCommand<Row[]>("retrocore.device.hardware");
const offName = (): Thenable<string | undefined> => vscode.commands.executeCommand<string | undefined>("retrocore.machine.off");

// Waits for the views to show this off machine with a row that is wanted.
async function offRow(name: string, id: string, wanted: (row: Row) => boolean, what: string): Promise<Row> {
    return await until(what, async () => {
        if (await offName() !== name) return undefined;
        const row = (await rows()).find(candidate => candidate.id === id);
        return row !== undefined && wanted(row) ? row : undefined;
    });
}

/**
 * The Machine and Drives views with no session: the last machine started, off, with a card added while off that its
 * next launch has; another machine picked with Switch Machine.
 */
export async function testOffMachine(workspace: vscode.WorkspaceFolder): Promise<void> {
    // The views describe the off machine only while they are in sight.
    await vscode.commands.executeCommand("workbench.view.extension.retrocore");

    // The machine menu's test ended with Start Last Machine's II Plus with 32 KB.
    const plus = "Apple II Plus (Retrocore)";
    await offRow(plus, "memory", row => row.value === "32 KB", "the II Plus, off, with its 32 KB");
    const slot5 = (await rows()).find(row => row.id === "slot5");
    assert.equal(slot5?.value, "empty");
    assert.ok(slot5?.actions?.includes("addCard"), "a free slot takes a card while off");

    // A Disk II added while off is in the next launch, and still there, off, once it ends.
    await vscode.commands.executeCommand("retrocore.machine.change", "hardware", { id: "slot5", action: "addDiskII", sectors: 16 });
    await offRow(plus, "slot5", row => /Disk II/.test(row.value), "the Disk II in slot 5, off");
    assert.ok(await vscode.commands.executeCommand<boolean>("retrocore.machine.boot"), "the off machine starts");
    const session = vscode.debug.activeDebugSession;
    if (session?.type !== "retrocore") throw new Error("Start This Machine did not start a Retrocore session.");
    try {
        assert.equal(session.name, plus);
        assert.equal(await offName(), undefined, "a running machine is not off");
        const hardware = (await session.customRequest("retro/devices") as { hardware: Row[] }).hardware;
        assert.match(hardware.find(row => row.id === "slot5")?.value ?? "", /Disk II/, "the launch has the card added off");
        assert.equal(hardware.find(row => row.id === "memory")?.value, "32 KB", "and its setup's memory");
    } finally {
        await vscode.debug.stopDebugging(session);
    }
    await offRow(plus, "slot5", row => /Disk II/.test(row.value), "the Disk II in slot 5, off again");

    // A setting changed while off: slot 0's firmware card in place of the language card the launch gives. The Disk II
    // added in slot 5 stays, while the saved slot 0 does not put the language card back.
    await vscode.commands.executeCommand("retrocore.machine.setting", "slot0", "firmwareCard");
    await offRow(plus, "slot0", row => /Firmware/i.test(row.value), "the firmware card in slot 0, off");
    assert.match((await rows()).find(row => row.id === "slot5")?.value ?? "", /Disk II/, "the card added off stays");
    assert.equal((await rows()).find(row => row.id === "memory")?.value, "32 KB", "and the other settings");
    assert.ok(await vscode.commands.executeCommand<boolean>("retrocore.machine.boot"), "the changed machine starts");
    const changed = vscode.debug.activeDebugSession;
    if (changed?.type !== "retrocore") throw new Error("Start This Machine did not start a Retrocore session.");
    try {
        assert.equal(changed.configuration.slot0, "firmwareCard", "the setup has the setting");
        const hardware = (await changed.customRequest("retro/devices") as { hardware: Row[] }).hardware;
        assert.match(hardware.find(row => row.id === "slot0")?.value ?? "", /Firmware/i, "the launch has the setting");
        assert.match(hardware.find(row => row.id === "slot5")?.value ?? "", /Disk II/, "and the card added off");
        await vscode.commands.executeCommand("retrocore.machine.setting", "slot0", "languageCard");
        assert.equal(changed.configuration.slot0, "firmwareCard", "a running machine's settings do not change");
    } finally {
        await vscode.debug.stopDebugging(changed);
    }

    // Setting slot 0 back and taking the card out leaves the II Plus as the menu's test found it.
    await offRow(plus, "slot0", row => /Firmware/i.test(row.value), "the II Plus off again");
    await vscode.commands.executeCommand("retrocore.machine.setting", "slot0", "languageCard");
    await offRow(plus, "slot0", row => /Language/i.test(row.value), "the language card back in slot 0");
    await vscode.commands.executeCommand("retrocore.machine.change", "hardware", { id: "slot5", action: "removeCard" });
    await offRow(plus, "slot5", row => row.value === "empty", "slot 5 empty again");

    // Two changes sent together both land: each starts from the saved machine the one before left.
    await Promise.all([
        vscode.commands.executeCommand("retrocore.machine.change", "hardware", { id: "slot4", action: "addDiskII", sectors: 16 }),
        vscode.commands.executeCommand("retrocore.machine.change", "hardware", { id: "slot6", action: "addDiskII", sectors: 16 })
    ]);
    await offRow(plus, "slot4", row => /Disk II/.test(row.value), "the first of two cards sent together");
    assert.match((await rows()).find(row => row.id === "slot6")?.value ?? "", /Disk II/, "and the second");
    await Promise.all([
        vscode.commands.executeCommand("retrocore.machine.change", "hardware", { id: "slot4", action: "removeCard" }),
        vscode.commands.executeCommand("retrocore.machine.change", "hardware", { id: "slot6", action: "removeCard" })
    ]);
    await offRow(plus, "slot4", row => row.value === "empty", "both taken out together");
    assert.equal((await rows()).find(row => row.id === "slot6")?.value, "empty");

    // Switch Machine shows another machine off: the Model I with its cassette.
    const model1 = { type: "retrocore", request: "launch", name: "Retrocore test: Model I off", machine: "trs80-model1" };
    await vscode.commands.executeCommand("retrocore.machine.switch", { configuration: model1, source: { kind: "configuration" } });
    await offRow(model1.name, "cassette", () => true, "the Model I, off, with its cassette");
    const drives = await vscode.commands.executeCommand<{ id: string }[]>("retrocore.device.list");
    assert.ok(drives.some(device => device.id === "cassette"), "the Drives view has its cassette");

    // Back to the II Plus, so later tests find what they expect.
    await vscode.commands.executeCommand("retrocore.machine.switch", {
        configuration: { type: "retrocore", request: "launch", name: plus, machine: "apple2", model: "iiplus", ramKilobytes: 32 },
        source: { kind: "setup", setup: { machineId: "apple2-iiplus", kind: "machine", options: { ramKilobytes: 32 } } }
    });
    await offRow(plus, "memory", row => row.value === "32 KB", "the II Plus again");
    void workspace;

    console.log("Off machine passed: the last machine shows off, a card added off is in its next launch, a setting changed off takes effect under that card, and Switch Machine shows another.");
}
