// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The Apple II through the debug adapter: the original Monitor's * prompt and CONTROL-B into Integer BASIC, an
// Integer BASIC file launched and run, the AppleSoft firmware card in slot 0, and revision 0's board. The dumps are
// RETROCORE_II_ROMS and RETROCORE_IIPLUS_ROMS, or apple2-roms\APPLE II and apple2-roms\APPLE II+ under the
// external-files folder (RETROCORE_CACHE, or %USERPROFILE%\Retrocore).

import { startDap } from "./DapClient.mjs";
import { resolve, join } from "node:path";
import { existsSync, writeFileSync, unlinkSync } from "node:fs";
import { homedir } from "node:os";
import assert from "node:assert/strict";

const root = resolve(import.meta.dirname, "..");
const external = join(process.env.RETROCORE_CACHE || join(homedir(), "Retrocore"), "apple2-roms");
const roms = process.env.RETROCORE_II_ROMS || join(external, "APPLE II");
const plusRoms = process.env.RETROCORE_IIPLUS_ROMS || join(external, "APPLE II+");
if (!existsSync(join(roms, "APPLE II - 341-0004 - INTEGER BASIC MONITOR F800 - 2716.bin")) || !existsSync(plusRoms)) {
    console.log("II DAP skipped: set RETROCORE_II_ROMS and RETROCORE_IIPLUS_ROMS to the II's and II Plus's chip dumps.");
    process.exit(0);
}

const { request, event, events, fail, close, failure: failed } = startDap(root);
const timeout = setTimeout(() => fail(new Error("II DAP integration timed out.")), 90000);
const screen = async () => (await request("apple2/text")).rows.join("\n");
const waitFor = async (text, what) => {
    for (const end = performance.now() + 10000; performance.now() < end;) {
        if ((await screen()).includes(text)) return;
        await new Promise(done => setTimeout(done, 100));
    }
    assert.fail(`${what}: "${text}" never appeared:\n${await screen()}`);
};
const type = async keys => { for (const key of keys) await request("retro/key", { code: key.charCodeAt(0) }); };
const stop = async () => { await request("pause", { threadId: 1 }); await event("stopped"); };

try {
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });

    // The original Monitor: reset lands at its * prompt, and CONTROL-B starts Integer BASIC.
    await request("launch", { machine: "apple2", model: "ii", romDirectory: roms, stopOnEntry: false, firmwareCardRoms: plusRoms });
    const document = async () => (await request("retro/basic/document", { base: "retrocore-basic://ii/" })).uri;
    assert.equal(await document(), "retrocore-basic://ii/Program.integer.bas");
    await request("configurationDone");
    await waitFor("*", "the Monitor's prompt");
    await type("\u0002\r");
    await waitFor(">", "Integer BASIC's prompt");
    await type("print 6*7\r");
    await waitFor("42", "Integer BASIC runs a line");

    const frame = await request("apple2/text");
    assert.equal(frame.model, "Apple II");
    let rows = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
    assert.equal(rows.model.value, "6502, original Monitor");
    assert.equal(rows.slot0.value, "empty", "a plain II has nothing in slot 0");

    // The AppleSoft firmware card goes in slot 0 while running.
    const changed = await request("retro/hardware", { id: "slot0", action: "addFirmwareCard" });
    assert.equal(changed.hardware.find(row => row.id === "slot0").value, "AppleSoft firmware card (on)");
    // The program's document is named for the BASIC in memory now, so its stops open the right editor.
    let named = await document();
    for (const end = performance.now() + 5000; named.endsWith("integer.bas") && performance.now() < end;) {
        await new Promise(done => setTimeout(done, 100));
        named = await document();
    }
    assert.equal(named, "retrocore-basic://ii/Program.applesoft.bas");
    await stop();

    // An Integer BASIC file, tokenized by the II's own ROM, goes in and runs.
    const file = join(root, "artifacts", `ii-${process.pid}.integer.bas`);
    writeFileSync(file, "REM retrocore integer\n10 FOR I=1 TO 3\n20 PRINT I*11\n30 NEXT I\n");
    try {
        await request("launch", { machine: "apple2", model: "ii", romDirectory: roms, basic: file, stopOnEntry: false });
        await request("configurationDone");
        await waitFor("33", "the Integer BASIC program runs");
        await stop();

        // A line Integer BASIC refuses fails the launch with its message.
        writeFileSync(file, "10 PRINT (\n");
        await assert.rejects(
            request("launch", { machine: "apple2", model: "ii", romDirectory: roms, basic: file, stopOnEntry: true }),
            /ERR/);
    } finally {
        unlinkSync(file);
    }

    // With the firmware card in from the start, its AppleSoft and Autostart Monitor start the II like a II Plus.
    events.length = 0;
    await request("launch", {
        machine: "apple2", model: "ii", romDirectory: roms, stopOnEntry: false, slot0: "firmwareCard", firmwareCardRoms: plusRoms
    });
    await request("configurationDone");
    await waitFor("]", "AppleSoft from the firmware card");
    await stop();

    // Without dumps, the II runs ROMs built from the SDK's sources: the Autostart Monitor starts Integer BASIC.
    events.length = 0;
    await request("launch", { machine: "apple2", model: "ii", stopOnEntry: false, monitor: "autostart" });
    await request("configurationDone");
    await waitFor(">", "Integer BASIC from the SDK's ROMs");
    await stop();

    // Programmer's Aid #1 in the D0 socket, from the dump and from the SDK's source: CALL -12288 starts its hi-res
    // graphics, which picks page 1 in HPAG ($0326).
    for (const romDirectory of [roms, undefined]) {
        events.length = 0;
        await request("launch", { machine: "apple2", model: "ii", romDirectory, stopOnEntry: false, monitor: "autostart", programmersAid: true });
        await request("configurationDone");
        await waitFor(">", "Integer BASIC with Programmer's Aid");
        rows = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
        assert.equal(rows.d0Socket.value, "Programmer's Aid #1");
        // Stopping at $D000 shows the SDK's source for it.
        await request("setInstructionBreakpoints", { breakpoints: [{ instructionReference: "0xD000" }] });
        await type("CALL -12288\r");
        assert.equal((await event("stopped")).reason, "instruction breakpoint");
        const top = (await request("stackTrace", { threadId: 1 })).stackFrames[0];
        assert.match(top.source?.path ?? "", /HiResGraphics\.asm$/);
        await request("setInstructionBreakpoints", { breakpoints: [] });
        await request("continue", { threadId: 1 });
        let page = 0;
        for (const end = performance.now() + 5000; page !== 0x20 && performance.now() < end;) {
            await new Promise(done => setTimeout(done, 100));
            page = Buffer.from((await request("readMemory", { memoryReference: "0x0326", count: 1 })).data, "base64")[0];
        }
        assert.equal(page, 0x20, "CALL -12288 runs Programmer's Aid's hi-res setup");
        await stop();
    }

    // The D0 socket is the II's: other models refuse it.
    await assert.rejects(
        request("launch", { machine: "apple2", model: "iiplus", romDirectory: plusRoms, programmersAid: true }),
        /programmersAid/);

    // Revision 0 and the Autostart Monitor say so in the board's row.
    await request("launch", { machine: "apple2", model: "ii", romDirectory: roms, stopOnEntry: true, monitor: "autostart", boardRevision: 0 });
    await request("configurationDone");
    await event("stopped");
    rows = Object.fromEntries((await request("retro/devices")).hardware.map(row => [row.id, row]));
    assert.equal(rows.model.value, "6502, Autostart Monitor, revision 0");
    await request("disconnect");
    console.log("II DAP passed: the original Monitor and CONTROL-B into Integer BASIC, an Integer BASIC file tokenized by the ROM and run, refused lines reported, the AppleSoft firmware card, the Autostart Monitor, Programmer's Aid #1 and revision 0.");
} finally {
    clearTimeout(timeout);
    close();
}
if (failed()) throw failed();
