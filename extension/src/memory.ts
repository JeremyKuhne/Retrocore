// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Memory views: VS Code opens debug memory in the Hex Editor through its vscode-debug-memory file system, which reads
// and writes through the debug host's readMemory and writeMemory. The Open Memory command picks memory as the CPU
// maps it or one of the machine's banks, such as the IIe's auxiliary RAM, and an address in it.

import * as vscode from "vscode";

/** Memory as the CPU maps it, or a bank, as the debug host's retro/memoryBanks describes it. */
export interface MemoryBank {
    /** The bank's prefix in memory references, such as "aux"; null for memory as the CPU maps it. */
    name: string | null;
    label: string;
    memoryReference: string;
    readOnly: boolean;
    /** Where the memory map reads the bank now, such as "$0000-$01FF, $0400-$07FF", or "nowhere". */
    reads: string;
    /** Where it writes the bank now; null for a read-only bank. */
    writes: string | null;
}

const hexEditor = "ms-vscode.hexeditor";

/** The URI VS Code's debug memory file system gives a memory reference, as its own View Binary Data opens it. */
export function memoryUri(session: vscode.DebugSession, memoryReference: string, name = "memory", range?: { from: number; to: number }): vscode.Uri {
    return vscode.Uri.from({
        scheme: "vscode-debug-memory",
        authority: session.id,
        path: `/${encodeURIComponent(memoryReference)}/${encodeURIComponent(name)}.bin`,
        query: range ? `?range=${range.from}:${range.to}` : undefined
    });
}

function bankDetail(bank: MemoryBank): string {
    if (bank.name === null) return "$0000-$FFFF as the soft switches map it now";
    if (bank.readOnly) return `read-only · read at ${bank.reads}`;
    return `read at ${bank.reads} · written at ${bank.writes}`;
}

/** Registers the Open Memory command. */
export function registerMemory(context: vscode.ExtensionContext): void {
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.memory.open", async () => {
        const session = vscode.debug.activeDebugSession;
        if (session?.type !== "retrocore") {
            void vscode.window.showWarningMessage("Start a Retrocore debug session first.");
            return;
        }

        const { banks } = await session.customRequest("retro/memoryBanks") as { banks: MemoryBank[] };
        const picked = banks.length === 1 ? { bank: banks[0] } : await vscode.window.showQuickPick(banks.map(bank => ({
            label: bank.name ?? "CPU",
            description: bank.label,
            detail: bankDetail(bank),
            bank
        })), { title: "Open memory", matchOnDescription: true });
        if (!picked) return;

        const start = picked.bank.memoryReference.replace(/^[a-z0-9]+:/i, "").replace(/^0x/i, "$");
        const address = await vscode.window.showInputBox({
            title: `Open ${picked.bank.label}`,
            prompt: "An address, label or expression, such as $0400 or TEXT_PAGE",
            value: start
        });
        if (address === undefined || address.trim().length === 0) return;

        // The debug host resolves the expression once, so the view stays at that address.
        const expression = picked.bank.name === null ? address : `${picked.bank.name}:${address}`;
        let memoryReference: string | undefined;
        try {
            memoryReference = (await session.customRequest("evaluate", { expression, context: "watch" }) as { memoryReference?: string }).memoryReference;
        } catch (error) {
            void vscode.window.showErrorMessage(`Retrocore: ${error instanceof Error ? error.message : String(error)}`);
            return;
        }
        if (!memoryReference) {
            void vscode.window.showErrorMessage(`Retrocore: ${expression} is not an address in the CPU's 64K.`);
            return;
        }

        if (!vscode.extensions.getExtension(hexEditor)) {
            const install = "Install Hex Editor";
            if (await vscode.window.showInformationMessage("Memory opens in Microsoft's Hex Editor extension.", install) !== install) return;
            await vscode.commands.executeCommand("workbench.extensions.installExtension", hexEditor);
        }
        await vscode.commands.executeCommand("vscode.openWith", memoryUri(session, memoryReference, memoryReference.replace(":", "-")), "hexEditor.hexedit");
    }));

    // The test suite reads the banks through this command.
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.memory.banks", async () => {
        const session = vscode.debug.activeDebugSession;
        if (session?.type !== "retrocore") return [];
        return (await session.customRequest("retro/memoryBanks") as { banks: MemoryBank[] }).banks;
    }));
}
