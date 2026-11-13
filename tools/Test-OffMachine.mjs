// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The language server's off machine (retrocore/machine/describe and retrocore/machine/change): each machine,
// built without running it, lists the same hardware and devices as the debug host's retro/devices once the same
// configuration launches; a card added and a disk inserted while off are in the saved machine, and a launch with
// that saved machine has them. Needs nothing external: without ROM dumps every machine's ROMs are built from the
// SDK's sources.

import { startDap } from "./DapClient.mjs";
import { spawn } from "node:child_process";
import { join, resolve } from "node:path";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import assert from "node:assert/strict";

const root = resolve(import.meta.dirname, "..");
const host = join(root, "artifacts", "AnyCPU", "Release", "Retrocore.Debug", "net10.0", "Retrocore.Debug.dll");

/** Starts the language server and returns request(method, params). */
function startLanguageServer() {
    const child = spawn("dotnet", [host, "--language-server"]);
    let buffer = Buffer.alloc(0);
    let id = 1;
    const pending = new Map();
    child.stderr.on("data", data => process.stderr.write(data));
    child.stdout.on("data", data => {
        buffer = Buffer.concat([buffer, data]);
        for (;;) {
            const end = buffer.indexOf("\r\n\r\n");
            if (end < 0) return;
            const length = Number(/Content-Length:\s*(\d+)/i.exec(buffer.subarray(0, end).toString("ascii"))[1]);
            if (buffer.length < end + 4 + length) return;
            const message = JSON.parse(buffer.subarray(end + 4, end + 4 + length).toString("utf8"));
            buffer = buffer.subarray(end + 4 + length);
            const waiter = message.id === undefined ? undefined : pending.get(message.id);
            if (waiter === undefined) continue;
            pending.delete(message.id);
            if (message.error) waiter.reject(new Error(message.error.message));
            else waiter.resolve(message.result);
        }
    });
    const request = (method, params) => new Promise((resolve, reject) => {
        const message = JSON.stringify({ jsonrpc: "2.0", id, method, params });
        pending.set(id++, { resolve, reject });
        child.stdin.write(`Content-Length: ${Buffer.byteLength(message)}\r\n\r\n${message}`);
    });
    return { request, close: () => child.kill() };
}

// What both sides must agree on: each row's id, name and value (the game port's says what it reads only while
// running), and each device's id, kind and media.
const rows = body => body.hardware.map(row => row.id === "gamePort" ? `${row.id}: ${row.name}` : `${row.id}: ${row.name} = ${row.value} [${row.devices.join(",")}]`);
const devices = body => body.devices.map(device => `${device.id} ${device.kind} ${device.media?.label ?? "empty"}`);

const machines = [
    { name: "Apple IIe (enhanced)", configuration: { machine: "apple2" } },
    { name: "Apple IIe", configuration: { machine: "apple2", model: "original" } },
    { name: "Apple II Plus", configuration: { machine: "apple2", model: "iiplus" } },
    { name: "Apple II", configuration: { machine: "apple2", model: "ii" } },
    { name: "Apple III", configuration: { machine: "apple3" } },
    { name: "Apple-1", configuration: { machine: "apple1" } },
    { name: "TRS-80 Model I", configuration: { machine: "trs80-model1", expansionInterface: true, diskController: true } },
    { name: "Color Computer 2", configuration: { machine: "coco", model: "coco2" } }
];

const lsp = startLanguageServer();
const dap = startDap(root);
const timeout = setTimeout(() => { lsp.close(); dap.fail(new Error("Off machine test timed out.")); }, 180000);
const scratch = mkdtempSync(join(tmpdir(), "retrocore-off-"));
const launched = async (configuration, machineState) => {
    await dap.request("launch", { ...configuration, stopOnEntry: true, ...machineState ? { machineState } : {} });
    return await dap.request("retro/devices");
};

try {
    await lsp.request("initialize", { processId: null, rootUri: null, capabilities: {} });
    await dap.request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });

    // Each machine off lists what it lists once launched.
    for (const { name, configuration } of machines) {
        const started = performance.now();
        const off = await lsp.request("retrocore/machine/describe", { configuration });
        const took = performance.now() - started;
        const on = await launched(configuration);
        assert.deepEqual(rows(off), rows(on), `${name}: the off machine's hardware`);
        assert.deepEqual(devices(off), devices(on), `${name}: the off machine's devices`);
        assert.deepEqual(off.problems, [], `${name}: nothing to restore`);
        console.log(`${name}: ${off.hardware.length} rows, ${off.devices.length} devices, described in ${took.toFixed(0)} ms.`);
    }

    // A Disk II added to the IIe's slot 5 and a disk in its first drive, while off, are in the saved machine.
    const iie = { machine: "apple2" };
    const disk = join(scratch, "blank.dsk");
    writeFileSync(disk, Buffer.alloc(143360));
    let off = await lsp.request("retrocore/machine/change", {
        configuration: iie, request: "hardware", arguments: { id: "slot5", action: "addDiskII", sectors: 16 }
    });
    const slot5 = off.hardware.find(row => row.id === "slot5");
    assert.match(slot5.value, /Disk II/, "slot 5 has the card");
    assert.equal(slot5.devices.length, 2, "with its two drives");
    off = await lsp.request("retrocore/machine/change", {
        configuration: iie, machineState: off.configuration, request: "device", arguments: { id: slot5.devices[0], action: "insert", path: disk }
    });
    assert.equal(off.devices.find(device => device.id === slot5.devices[0]).media?.label, disk, "the disk is in the drive");
    assert.equal(off.configuration.media[slot5.devices[0]]?.path, disk, "and in the saved machine");

    // Described again from the saved machine alone, it is the same; launched with it, the machine has both.
    const again = await lsp.request("retrocore/machine/describe", { configuration: iie, machineState: off.configuration });
    assert.deepEqual(rows(again), rows(off), "the saved machine describes the same hardware");
    assert.deepEqual(devices(again), devices(off), "and the same media");
    const on = await launched(iie, off.configuration);
    assert.deepEqual(rows(on), rows(off), "a launch with the saved machine has the card");
    assert.deepEqual(devices(on), devices(off), "and the disk");

    // Removing the card while off takes its drives and the disk with it.
    off = await lsp.request("retrocore/machine/change", {
        configuration: iie, machineState: off.configuration, request: "hardware", arguments: { id: "slot5", action: "removeCard" }
    });
    assert.equal(off.hardware.find(row => row.id === "slot5").value, "empty", "slot 5 is empty again");
    assert.equal(off.configuration.media[slot5.devices[0]], undefined, "its drive is gone from the saved machine");

    // A saved disk that is gone is reported, and the rest still describes.
    rmSync(disk);
    const missing = await lsp.request("retrocore/machine/describe", { configuration: iie, machineState: again.configuration });
    assert.equal(missing.problems.length, 1, "the missing disk is one problem");
    assert.match(missing.problems[0], /no longer exists/);

    // Bad requests fail with a message rather than an empty answer.
    await assert.rejects(lsp.request("retrocore/machine/describe", { configuration: { machine: "pdp10" } }), /Unknown machine/);
    await assert.rejects(lsp.request("retrocore/machine/describe", {}), /configuration is required/);
    await assert.rejects(lsp.request("retrocore/machine/change", {
        configuration: iie, request: "bogus", arguments: { id: "slot5", action: "removeCard" }
    }), /hardware or device/);
    await assert.rejects(lsp.request("retrocore/machine/change", {
        configuration: iie, request: "device", arguments: { id: "nowhere", action: "eject" }
    }), /no device 'nowhere'/);

    console.log("Off machine passed: every machine describes off as it launches, and a card and disk added off are in the saved machine and the next launch.");
} finally {
    clearTimeout(timeout);
    lsp.close();
    dap.close();
    rmSync(scratch, { recursive: true, force: true });
}
