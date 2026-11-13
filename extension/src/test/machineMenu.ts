// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as vscode from "vscode";

interface Frame { machine?: string; model?: string; rows?: string[] }

// Polls the session's display until it shows what is wanted, failing after a while.
async function waitForScreen(session: vscode.DebugSession, wanted: (frame: Frame) => boolean, what: string): Promise<Frame> {
    let last: Frame = {};
    for (const end = Date.now() + 20000; Date.now() < end;) {
        last = await session.customRequest("retro/display") as Frame & { running?: boolean };
        if (wanted(last)) return last;

        // The workspace's breakpoint settings apply to every session, such as stopping at the reset as it powers on.
        if ((last as { running?: boolean }).running === false) await session.customRequest("continue", { threadId: 1 });
        await new Promise(resolve => setTimeout(resolve, 200));
    }
    throw new Error(`${what}: the screen never showed it (${JSON.stringify(Object.keys(last))}, ${session.name}):\n${(last.rows ?? []).join("\n")}`);
}

function activeRetrocore(): vscode.DebugSession {
    const session = vscode.debug.activeDebugSession;
    if (session?.type !== "retrocore") throw new Error("No Retrocore session started.");
    return session;
}

// The memory row's value in the Retro Devices list, such as 48 KB.
async function memoryRow(session: vscode.DebugSession): Promise<string | undefined> {
    const devices = await session.customRequest("retro/devices") as { hardware?: { id: string; value: string }[] };
    return devices.hardware?.find(row => row.id === "memory")?.value;
}

async function start(workspace: vscode.WorkspaceFolder, configuration: vscode.DebugConfiguration): Promise<vscode.DebugSession> {
    assert.ok(await vscode.debug.startDebugging(workspace, configuration), `${configuration.name} starts`);
    const session = vscode.debug.activeDebugSession;
    if (session?.type !== "retrocore") throw new Error(`${configuration.name} did not start a Retrocore session.`);
    return session;
}

/** Each machine is in the Run and Debug dropdown without a launch.json, and two of them boot from it. */
export async function testMachineMenu(workspace: vscode.WorkspaceFolder): Promise<void> {
    const configurations = await vscode.commands.executeCommand<vscode.DebugConfiguration[]>("retrocore.machine.configurations");
    assert.deepEqual(configurations.map(configuration => configuration.name), [
        "Apple IIe (enhanced) (Retrocore)", "Apple IIe (Retrocore)", "Apple II Plus (Retrocore)", "Apple II (Retrocore)", "Apple III (Retrocore)",
        "TRS-80 Model I (Level II) (Retrocore)", "TRS-80 Model I (Level I) (Retrocore)", "TRS-80 Model III (Retrocore)",
        "TRS-80 Model III (Level I) (Retrocore)",
        "TRS-80 Model 4 (Retrocore)", "TRS-80 Model 4P (Retrocore)", "TRS-80 Model II (Retrocore)", "TRS-80 Model 12 (Retrocore)",
        "TRS-80 Model 16 (Z80 side) (Retrocore)", "Apple-1 (Retrocore)",
        "TRS-80 Color Computer (Retrocore)", "TRS-80 Color Computer 2 (Retrocore)", "TRS-80 Color Computer 3 (Retrocore)"
    ]);
    assert.ok(configurations.every(configuration => configuration.debugHost === undefined), "the packaged host runs them");

    // The II Plus boots to AppleSoft from the SDK's ROMs.
    const plus = configurations.find(configuration => configuration.model === "iiplus");
    assert.ok(plus);
    let session = await start(workspace, plus);
    try {
        const frame = await waitForScreen(session, screen => (screen.rows ?? []).some(row => row.startsWith("]")), "the II Plus's prompt");
        assert.equal(frame.model, "Apple II Plus");
    } finally {
        await vscode.debug.stopDebugging(session);
    }

    // The Model I with Level II asks for its memory size: MEM SIZE? in revision 1.3, the default.
    const model1 = configurations.find(configuration => configuration.machine === "trs80-model1" && configuration.rom === undefined);
    assert.ok(model1);
    session = await start(workspace, model1);
    try {
        const frame = await waitForScreen(session, screen => (screen.rows ?? []).some(row => row.includes("MEM SIZE?")), "Level II's first question");
        assert.equal(frame.machine, "trs80-model1");
    } finally {
        await vscode.debug.stopDebugging(session);
    }

    // Start Machine, given its setup as the quick picks would build it: a II Plus with 32 KB.
    const setup = { machineId: "apple2-iiplus", kind: "machine", options: { ramKilobytes: 32 } };
    assert.ok(await vscode.commands.executeCommand<boolean>("retrocore.startMachine", setup));
    session = activeRetrocore();
    try {
        await waitForScreen(session, screen => (screen.rows ?? []).some(row => row.startsWith("]")), "Start Machine's II Plus");
        assert.equal(await memoryRow(session), "32 KB");
    } finally {
        await vscode.debug.stopDebugging(session);
    }

    // The panel offers to restart the session that ended, and Restart starts the same launch again.
    const ended = session.name;
    for (const end = Date.now() + 10000; await vscode.commands.executeCommand<string | undefined>("retrocore.display.ended") !== ended;) {
        if (Date.now() > end) throw new Error("The panel never offered to restart the ended session.");
        await new Promise(resolve => setTimeout(resolve, 100));
    }
    assert.ok(await vscode.commands.executeCommand<boolean>("retrocore.display.restart"));
    session = activeRetrocore();
    try {
        assert.equal(session.name, ended);
        await waitForScreen(session, screen => (screen.rows ?? []).some(row => row.startsWith("]")), "the restarted II Plus");
        assert.equal(await memoryRow(session), "32 KB");
        assert.equal(await vscode.commands.executeCommand<string | undefined>("retrocore.display.ended"), undefined, "a running machine is not offered");
    } finally {
        await vscode.debug.stopDebugging(session);
    }

    // Start Last Machine starts the same setup again.
    assert.ok(await vscode.commands.executeCommand<boolean>("retrocore.startLastMachine"));
    session = activeRetrocore();
    try {
        assert.equal(session.name, "Apple II Plus (Retrocore)");
        await waitForScreen(session, screen => (screen.rows ?? []).some(row => row.startsWith("]")), "Start Last Machine's II Plus");
        assert.equal(await memoryRow(session), "32 KB");
    } finally {
        await vscode.debug.stopDebugging(session);
    }

    // Saving puts the setup in launch.json under the name given; the file is put back as it was.
    const launchFile = path.join(workspace.uri.fsPath, ".vscode", "launch.json");
    const before = fs.existsSync(launchFile) ? fs.readFileSync(launchFile, "utf8") : undefined;
    try {
        assert.ok(await vscode.commands.executeCommand<boolean>("retrocore.saveLaunchConfiguration", "Retrocore test: II Plus"));
        const saved = vscode.workspace.getConfiguration("launch", workspace.uri).get<Record<string, unknown>[]>("configurations") ?? [];
        const entry = saved.find(configuration => configuration.name === "Retrocore test: II Plus");
        assert.deepEqual(
            { machine: entry?.machine, model: entry?.model, ramKilobytes: entry?.ramKilobytes, type: entry?.type },
            { machine: "apple2", model: "iiplus", ramKilobytes: 32, type: "retrocore" });
    } finally {
        if (before === undefined) fs.rmSync(launchFile, { force: true });
        else fs.writeFileSync(launchFile, before);
    }

    console.log("Machine menu passed: every machine is in the Run and Debug dropdown, the II Plus and Model I boot from it, and Start Machine, Start Last Machine and Save as Launch Configuration work.");
}
