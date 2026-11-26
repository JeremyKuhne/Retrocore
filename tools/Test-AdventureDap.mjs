// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The adventure sample's 6502 engine through the debug adapter. It packs the test game with the sample's packer,
// then plays each of the test game's transcripts on a bare Apple II Plus, from
// sample/adventure/src/platform/apple2-bare.s as a source launch, and checks that what the engine writes matches the
// C# reference engine's transcript in the matching .out file character for character. A logpoint on the console's
// Write records each character the engine sends, and one on ReadLine marks where it reads a command, so the commands
// can be put back where the screen shows them. The launches check the routines' Keeps: contracts and stop on a broken
// one. On the SDK's ROMs, so it needs no dumps.

import { startDap } from "./DapClient.mjs";
import { resolve, join } from "node:path";
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import assert from "node:assert/strict";

const root = resolve(import.meta.dirname, "..");
const sample = join(root, "sample", "adventure");
const source = join(sample, "src", "platform", "apple2-bare.s");
const configuration = join(sample, "src", "platform", "apple2-bare.cfg");
const consoleSource = join(sample, "src", "platform", "apple2", "console.s");
const transcripts = ["test-win", "test-fall", "test-drown"];
const gameOver = "The game is now over.\n";

// The game, packed as the target's .incbin expects it.
execFileSync("dotnet", ["run", join(sample, "tools", "packer.cs"), "--", "pack",
    join(sample, "games", "test.dat"), join(sample, "obj", "test.bin")], { stdio: "inherit" });

// The line of an instruction inside a routine of console.s.
function lineAfter(routine, instruction) {
    const lines = readFileSync(consoleSource, "utf8").split(/\r?\n/);
    const start = lines.indexOf(`.proc ${routine}`);
    assert.ok(start >= 0, `${routine} is in console.s`);
    const index = lines.findIndex((line, at) => at > start && line.trim() === instruction);
    assert.ok(index >= 0, `${routine} has ${instruction}`);
    return index + 1;
}

const writeLine = lineAfter("Write", "sta SavedA");
const readLine = lineAfter("ReadLine", "jsr GetLineNoPrompt");
const { request, event, events, fail, close, failure } = startDap(root);
const timeout = setTimeout(() => fail(new Error("Adventure DAP integration timed out.")), 240000);

// What the engine has written, with each command after the prompt it answers, as the screen shows them.
function transcript(commands) {
    let text = "";
    let next = 0;
    for (const message of events) {
        if (message.event !== "output" || message.body.category !== "console") continue;
        const output = message.body.output.trimEnd();
        if (output === "READ") text += `${commands[next++] ?? ""}\n`;
        else if (/^\d+$/.test(output)) text += String.fromCharCode(Number(output));
    }
    return text;
}

try {
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });
    for (const name of transcripts) {
        const commands = readFileSync(join(sample, "games", `${name}.in`), "utf8").split(/\r?\n/);
        if (commands.at(-1) === "") commands.pop();
        const expected = readFileSync(join(sample, "games", `${name}.out`), "utf8").replace(/\r\n/g, "\n");
        events.length = 0;
        await request("launch", { machine: "apple2", model: "iiplus", stopOnEntry: false, speed: "max", sound: "off",
            source, linkerConfiguration: configuration, logpointLimit: 0, checkContracts: "stop" });
        const set = await request("setBreakpoints", { source: { path: consoleSource }, breakpoints: [
            { line: writeLine, logMessage: "{A,d}" },
            { line: readLine, logMessage: "READ" }
        ] });
        assert.ok(set.breakpoints.every(breakpoint => breakpoint.verified), "the console's logpoints map to its source");
        await request("configurationDone");
        await request("retro/type", { text: commands.map(command => `${command}\n`).join("") });

        // The engine runs to the end of the game.
        for (const end = performance.now() + 60000; performance.now() < end && !transcript(commands).endsWith(gameOver);) {
            await new Promise(done => setTimeout(done, 200));
        }

        const played = transcript(commands);
        assert.equal(played, expected, `${name}: the 6502 engine's transcript matches the reference engine's`);

        // The screen shows it in capitals, as the Apple II Plus has no lowercase.
        const screen = (await request("apple2/text")).rows.join("\n");
        assert.match(screen, /^THE GAME IS NOW OVER\. *$/m, `${name}: the screen shows the game's end:\n${screen}`);
        await request("pause", { threadId: 1 });
        await event("stopped");
        console.log(`${name}: ${commands.length} commands, ${played.length} characters, as the reference engine plays them.`);
    }

    await request("disconnect");
    console.log("Adventure DAP passed: the 6502 engine plays each test transcript on a bare Apple II Plus as the reference engine does.");
} finally {
    clearTimeout(timeout);
    close();
}
if (failure()) throw failure();
