// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import * as vscode from "vscode";

/** A drive row as the Drives view draws it. */
interface DriveRow { id: string; label: string; description: string; contextValue: string; icon?: string; mark: string; tooltip: string }

const driveRows = (): Thenable<DriveRow[]> => vscode.commands.executeCommand<DriveRow[]>("retrocore.device.driveRows");

// Waits for a drive's row to be as wanted, as the host's retro/devices events redraw it.
async function row(id: string, wanted: (row: DriveRow) => boolean, what: string, timeout = 20000): Promise<DriveRow> {
    let last: DriveRow | undefined;
    for (const end = Date.now() + timeout; ;) {
        last = (await driveRows()).find(candidate => candidate.id === id);
        if (last !== undefined && wanted(last)) return last;
        if (Date.now() > end) throw new Error(`Timed out waiting for ${what}; the row was ${JSON.stringify(last)}.`);
        await new Promise(resolve => setTimeout(resolve, 100));
    }
}

/**
 * The Drives view: a Color Computer's disk drive shows its picture with its lock badge and the image's state, and the
 * image changing on disk or being marked read-only shows in its row as the host's watcher sees it.
 */
export async function testDrivesView(workspace: vscode.WorkspaceFolder): Promise<void> {
    const root = workspace.uri.fsPath;
    const folder = fs.mkdtempSync(path.join(os.tmpdir(), "retrocore-drives-"));
    const disk = path.join(folder, "work.dsk");
    const blank = Buffer.alloc(35 * 18 * 256, 0xFF);
    fs.writeFileSync(disk, blank);
    await vscode.commands.executeCommand("workbench.view.extension.retrocore");
    try {
        assert.equal(await vscode.debug.startDebugging(workspace, {
            type: "retrocore", request: "launch", name: "Drives view", machine: "coco", model: "coco2",
            sdkRoms: path.join(root, "src", "Retrocore.Machines.Coco", "Roms"), disks: [disk], stopOnEntry: true,
            speed: "max", sound: "off",
            debugHost: path.join(root, "artifacts", "AnyCPU", "Release", "Retrocore.Debug", "net11.0", "Retrocore.Debug.dll")
        }), true);

        // The disk as read: unlocked, the same as its image, with Save As in its menu and the lock toggle.
        const read = await row("disk0", candidate => candidate.description.startsWith("work.dsk"), "drive 0's disk");
        assert.equal(read.mark, "", "the disk is the same as its image");
        assert.match(read.contextValue, /\bunlocked\b/);
        assert.match(read.contextValue, /\bsave\b/);
        assert.doesNotMatch(read.contextValue, /\bchanged/);
        assert.match(path.basename(read.icon ?? ""), /^floppy525-unlocked-idle-light-[0-9a-f]{8}\.svg$/);
        assert.ok(fs.existsSync(read.icon ?? ""), "the icon is written out");
        assert.match(read.tooltip, /The same as its image/);
        assert.match(read.tooltip, /Unlocked: the machine can write it/);

        // Written by something else: the row marks the image stale and says so.
        const outside = Buffer.from(blank);
        outside[0] = 0x55;
        fs.writeFileSync(disk, outside);
        const stale = await row("disk0", candidate => candidate.mark === "stale", "the image changed on disk");
        assert.match(stale.description, /image changed on disk/);
        assert.match(stale.tooltip, /Image changed on disk: .*when read/);

        // Reverted, the disk is the image as it is now, so the mark goes; a disk the machine did not change leaves
        // nothing for Undo.
        await vscode.commands.executeCommand("retrocore.machine.change", "device", { id: "disk0", action: "revert" });
        const reverted = await row("disk0", candidate => candidate.mark === "", "the disk read again from its image");
        assert.doesNotMatch(reverted.description, /image changed on disk/);

        // Marked read-only: a read-only image.
        fs.chmodSync(disk, 0o444);
        const readOnly = await row("disk0", candidate => /read-only image/.test(candidate.description), "the read-only image");
        assert.match(readOnly.tooltip, /Read-only file/);

        // Locked from the menu: the badge closes.
        await vscode.commands.executeCommand("retrocore.machine.change", "device", { id: "disk0", action: "writeProtect", writeProtected: true });
        const locked = await row("disk0", candidate => /\blocked\b/.test(candidate.contextValue), "the locked disk");
        assert.match(path.basename(locked.icon ?? ""), /^floppy525-locked-/);

        const session = vscode.debug.activeDebugSession;
        if (session !== undefined) await vscode.debug.stopDebugging(session);
        console.log("Isolated VS Code passed: the Drives view draws a disk's picture and lock badge, and marks its image changed on disk and read-only as the host's watcher sees them, and reverts to it.");
    } finally {
        try { fs.chmodSync(disk, 0o644); } catch { /* Gone. */ }
        fs.rmSync(folder, { recursive: true, force: true });
    }
}
