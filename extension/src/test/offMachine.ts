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

    // Taking it out again leaves the II Plus as the menu's test found it.
    await vscode.commands.executeCommand("retrocore.machine.change", "hardware", { id: "slot5", action: "removeCard" });
    await offRow(plus, "slot5", row => row.value === "empty", "slot 5 empty again");

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

    console.log("Off machine passed: the last machine shows off, a card added off is in its next launch, and Switch Machine shows another.");
}
