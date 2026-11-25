// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import * as path from "node:path";
import * as vscode from "vscode";
import { openMemory } from "../memory";
import { untilStopShown } from "./stops";

export async function testMemorySubscriptions(workspace: vscode.WorkspaceFolder): Promise<void> {
    const root = workspace.uri.fsPath;
    const reads: { memoryReference: string; subscriber: string }[] = [];
    const unsubscribed: string[] = [];
    const events: string[] = [];
    let stopped = false;
    let changesOnly = false;
    const tracker = vscode.debug.registerDebugAdapterTrackerFactory("retrocore", {
        createDebugAdapterTracker() {
            return {
                onWillReceiveMessage(message: { command?: string; arguments?: Record<string, unknown> }) {
                    const args = message.arguments;
                    if (message.command === "retro/memory/read" && typeof args?.subscriber === "string" && typeof args.memoryReference === "string") {
                        reads.push({ subscriber: args.subscriber, memoryReference: args.memoryReference });
                    } else if (message.command === "retro/memory/unsubscribe" && typeof args?.subscriber === "string") {
                        unsubscribed.push(args.subscriber);
                    } else if (message.command === "retro/cycles" && args?.changesOnly === true) {
                        changesOnly = true;
                    }
                },
                onDidSendMessage(message: { event?: string; body?: Record<string, unknown> }) {
                    if (message.event === "stopped") stopped = true;
                    if (message.event === "memory" && typeof message.body?.memoryReference === "string") {
                        events.push(message.body.memoryReference);
                    }
                }
            };
        }
    });
    const wait = async (condition: () => boolean, description: string): Promise<void> => {
        for (let attempt = 0; attempt < 100; attempt++) {
            if (condition()) return;
            await new Promise(resolve => setTimeout(resolve, 100));
        }
        throw new Error(`Timed out waiting for ${description}.`);
    };
    let session: vscode.DebugSession | undefined;
    try {
        assert.equal(await vscode.debug.startDebugging(workspace, {
            type: "retrocore", request: "launch", name: "Memory subscriptions",
            machine: "trs80-model1", stopOnEntry: true,
            sdkRoms: path.join(root, "src", "Retrocore.Machines.Trs80", "Roms"),
            source: path.join(root, "sample", "trs80", "hello.asm"),
            debugHost: path.join(root, "artifacts", "AnyCPU", "Release", "Retrocore.Debug", "net11.0", "Retrocore.Debug.dll")
        }), true);
        await wait(() => stopped && changesOnly, "the stopped session and cycle subscription");
        session = vscode.debug.activeDebugSession;
        if (session === undefined) throw new Error("No debug session.");
        await untilStopShown(session);
        await openMemory(session, "0x4000");
        await wait(() => reads.length > 0, "the first editor's reads");
        const first = reads[0].subscriber;
        await openMemory(session, "0x6000");
        await wait(() => reads.some(read => read.subscriber !== first), "the second editor's reads");
        const second = reads.find(read => read.subscriber !== first)!.subscriber;
        const tab = vscode.window.tabGroups.all.flatMap(group => group.tabs).find(item =>
            item.input instanceof vscode.TabInputCustom && item.input.uri.path.startsWith("/0x4000/"));
        assert.ok(tab, "the first memory editor is open");
        await vscode.window.tabGroups.close(tab);
        await wait(() => unsubscribed.includes(first), "the first editor's unsubscribe");
        assert.equal(unsubscribed.includes(second), false);

        const low = await session.customRequest("readMemory", { memoryReference: "0x4000", count: 1 });
        const high = await session.customRequest("readMemory", { memoryReference: "0x6000", count: 1 });
        const lowByte = Buffer.from(low.data, "base64")[0], highByte = Buffer.from(high.data, "base64")[0];
        events.length = 0;
        await session.customRequest("writeMemory", { memoryReference: "0x4000", data: Buffer.of(lowByte ^ 0xFF).toString("base64") });
        assert.equal(events.includes("0x0000"), false, "the closed editor no longer tracks its page");
        await session.customRequest("writeMemory", { memoryReference: "0x6000", data: Buffer.of(highByte ^ 0xFF).toString("base64") });
        assert.ok(events.includes("0x0000"), "the open editor still tracks its page");
        console.log("Isolated VS Code passed: cycle subscription and independent memory-editor lifetimes.");
    } finally {
        if (session !== undefined) await vscode.debug.stopDebugging(session);
        tracker.dispose();
    }
}
