// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The Apple II Plus through the debug adapter: it boots from its ROM dumps to AppleSoft's prompt, takes a line typed
// in lowercase, lists its own hardware (the language card in slot 0, slot 3 free, no auxiliary memory), and booting a
// program from a DOS 3.3 disk works as on the IIe. The dumps are RETROCORE_IIPLUS_ROMS, or apple2-roms\APPLE II+
// under the external-files folder (RETROCORE_CACHE, or %USERPROFILE%\Retrocore).

import { startDap } from "./DapClient.mjs";
import { resolve, join } from "node:path";
import { existsSync, writeFileSync, unlinkSync } from "node:fs";
import { homedir } from "node:os";
import assert from "node:assert/strict";

const root = resolve(import.meta.dirname, "..");
const roms = process.env.RETROCORE_IIPLUS_ROMS
    || join(process.env.RETROCORE_CACHE || join(homedir(), "Retrocore"), "apple2-roms", "APPLE II+");
if (!existsSync(join(roms, "APPLE II+ - 341-0020 - APPLESOFT BASIC AUTOSTART MONITOR F800 - 2716.bin"))) {
    console.log("II Plus DAP skipped: set RETROCORE_IIPLUS_ROMS to the II Plus's chip dumps.");
    process.exit(0);
}

const { request, event, events, fail, close, failure: failed } = startDap(root);
const timeout = setTimeout(() => fail(new Error("II Plus DAP integration timed out.")), 60000);
const screen = async () => (await request("apple2/text")).rows.join("\n");
const waitFor = async (text, what) => {
    for (const end = performance.now() + 10000; performance.now() < end;) {
        if ((await screen()).includes(text)) return;
        await new Promise(done => setTimeout(done, 100));
    }
    assert.fail(`${what}: "${text}" never appeared:\n${await screen()}`);
};

try {
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });
    await assert.rejects(
        request("launch", { machine: "apple2", model: "iiplus", romDirectory: join(root, "no-such-roms"), stopOnEntry: true }),
        /no-such-roms|Could not find/);

    await request("launch", { machine: "apple2", model: "iiplus", romDirectory: roms, stopOnEntry: false });
    await request("configurationDone");
    await waitFor("APPLE ][", "the II Plus powers on");
    await waitFor("]", "AppleSoft's prompt");

    // The keyboard has no lowercase: the line arrives in capitals, and AppleSoft runs it.
    for (const key of "print 6*7\r") await request("retro/key", { code: key.charCodeAt(0) });
    await waitFor("PRINT 6*7", "the typed line");
    await waitFor("42", "the line's result");

    const frame = await request("apple2/text");
    assert.equal(frame.machine, "apple2");
    assert.equal(frame.model, "Apple II Plus");
    const devices = await request("retro/devices");
    const rows = Object.fromEntries(devices.hardware.map(row => [row.id, row]));
    assert.deepEqual(Object.keys(rows),
        ["model", "memory", "builtIn", "gamePort", "slot0", "slot1", "slot2", "slot3", "slot4", "slot5", "slot6", "slot7"]);
    assert.equal(rows.model.value, "6502");
    assert.equal(rows.slot0.value, "Language card, 16 KB");
    assert.deepEqual(rows.slot3.actions, ["addCard"], "slot 3 takes a card");
    assert.equal(devices.configuration.cards["0"], "languageCard");

    // The language card comes out and goes back in like the other cards.
    let changed = await request("retro/hardware", { id: "slot0", action: "removeCard" });
    assert.equal(changed.hardware.find(row => row.id === "slot0").value, "empty");
    changed = await request("retro/hardware", { id: "slot0", action: "addLanguageCard" });
    assert.equal(changed.hardware.find(row => row.id === "slot0").value, "Language card, 16 KB");
    await request("pause", { threadId: 1 });
    await event("stopped");

    // No auxiliary memory: main RAM, the language card's bank 1 and the ROM.
    const banks = (await request("retro/memoryBanks")).banks;
    assert.deepEqual(banks.map(bank => bank.name), [null, "main", "bank1", "rom"]);

    // AppleSoft debugs on its BASIC thread as on the IIe, since the II Plus's AppleSoft is the original IIe's.
    const basicFile = join(root, "artifacts", `iiplus-${process.pid}.applesoft.bas`);
    writeFileSync(basicFile, "REM retrocore applesoft\n    HOME\nagain:\n    PRINT \"HELLO\": GOTO again\n");
    try {
        events.length = 0;
        await request("launch", { machine: "apple2", model: "iiplus", romDirectory: roms, basic: basicFile, stopOnEntry: true });
        await request("configurationDone");
        assert.equal((await event("stopped")).reason, "entry");
        assert.equal((await request("stackTrace", { threadId: 2 })).stackFrames[0].name, "10: HOME");
        await request("next", { threadId: 2 });
        assert.equal((await event("stopped")).reason, "step");
        assert.equal((await request("stackTrace", { threadId: 2 })).stackFrames[0].line, 4);
    } finally {
        unlinkSync(basicFile);
    }

    // Without dumps, the II Plus runs ROMs built from the SDK's sources.
    events.length = 0;
    await request("launch", { machine: "apple2", model: "iiplus", stopOnEntry: false });
    await request("configurationDone");
    await waitFor("APPLE ][", "the II Plus from the SDK's ROMs");
    await waitFor("]", "AppleSoft from the SDK's ROMs");
    await request("pause", { threadId: 1 });
    await event("stopped");

    // A program booted from a DOS 3.3 disk, as on the IIe: DOS runs HELLO, which BRUNs it, and a breakpoint in its
    // source stops there.
    const dosSource = join(root, "artifacts", `iiplus-dos-${process.pid}.s`);
    writeFileSync(dosSource, ".cpu Mos6502\nStart:\n    lda #$5A\n    sta $07\n    rts\n");
    try {
        events.length = 0;
        await request("launch", { machine: "apple2", model: "iiplus", romDirectory: roms, stopOnEntry: false,
            speed: "max", sound: "off", source: dosSource, loadAddress: 0x6000, dos: "3.3" });
        const breakpoints = await request("setBreakpoints", { source: { path: dosSource }, breakpoints: [{ line: 4 }] });
        assert.equal(breakpoints.breakpoints[0].verified, true);
        await request("configurationDone");
        assert.equal((await event("stopped")).reason, "breakpoint", "DOS booted and BRUN reached the program");
        await request("disconnect");
    } finally {
        unlinkSync(dosSource);
    }

    console.log("II Plus DAP passed: boot to AppleSoft from its dumps, an uppercase-only keyboard, its own hardware rows and slot 0 language card, AppleSoft on its BASIC thread, and booting a program from a DOS 3.3 disk.");
} finally {
    clearTimeout(timeout);
    close();
}
if (failed()) throw failed();
