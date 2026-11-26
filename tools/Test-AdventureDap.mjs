// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The adventure sample's 6502 engine through the debug adapter, from its project file. It plays Pirate Adventure,
// linked in, from start to finish on bare targets of sample/adventure/retrocore.json (the win and the death on the
// Apple-1 with 32K, the PET 4032, the Apple II Plus and the BBC Micro), its win on the Apple-1's wozmon target, which a
// launch loads as if its hex had been typed in, both on the Apple II Plus's dos33 target, booted from its DOS 3.3 disk,
// which loads the game from the disk as PIRATE.DAT, and the test game's transcripts on apple2-test,
// through project launches, each running the project's steps, which pack the games with the sample's packer, and
// building the same core with its machine's platform folder. It checks that what the engine writes matches the C#
// reference engine's transcript in the matching .out file character for character. A logpoint on the console's Write
// records each character the engine sends, and one on ReadLine marks where it reads a command, so the commands can be
// put back where the screen shows them. Each logs once a call, though the PET's and BBC's IRQs come in as they run.
// The Apple II's, PET's and BBC's screens are checked for the game's end as well. The launches check Keeps: contracts
// and fail on a broken one. A false Keeps: on the top-level LocateTables stops the run, but one on
// Numbers::NextRandom, inside a .scope, did not, so the engine's scoped contracts are checked by reading rather than
// here. On the SDK's ROMs, so it needs no dumps. Give target names to play only those, such as
// `node tools/Test-AdventureDap.mjs pet`.

import { startDap } from "./DapClient.mjs";
import { resolve, join } from "node:path";
import { readFileSync } from "node:fs";
import assert from "node:assert/strict";

const root = resolve(import.meta.dirname, "..");
const sample = join(root, "sample", "adventure");

// The targets played, each with its platform folder and the transcripts it plays. The Apple III's console is built
// but not played: a bare Apple III has no character set loaded.
const plays = {
    apple1: { family: "apple1", transcripts: ["pirate-win", "pirate-die"] },
    "apple1-wozmon": { family: "apple1", transcripts: ["pirate-win"], hex: true },
    pet: { family: "pet", transcripts: ["pirate-win", "pirate-die"] },
    apple2: { family: "apple2", transcripts: ["pirate-win", "pirate-die"] },
    "apple2-dos": { family: "apple2", transcripts: ["pirate-win", "pirate-die"] },
    bbc: { family: "bbc", transcripts: ["pirate-win", "pirate-die"] },
    "apple2-test": { family: "apple2", transcripts: ["test-win", "test-fall", "test-drown"] }
};
const allTargets = Object.keys(plays);
const targets = process.argv.length > 2 ? process.argv.slice(2) : allTargets;

// The screens kept in memory: the PET's 1,000 screen codes at $8000, where 1-26 are the capitals and 32-63 are as in
// ASCII, in capitals as the console writes them; and MODE 7's 1K at $7C00 on the model B, as the BBC writes the
// characters. MODE 7 scrolls by moving the screen's start through that 1K, so a row can run from its end to its start:
// its memory is searched twice over, joined where it wraps.
const screens = {
    pet: {
        address: 0x8000,
        count: 1000,
        wraps: false,
        text: code => String.fromCharCode((code & 0x7F) < 32 ? (code & 0x7F) + 64 : code & 0x7F),
        expected: "THE GAME IS NOW OVER."
    },
    bbc: {
        address: 0x7C00,
        count: 1024,
        wraps: true,
        text: code => String.fromCharCode(code & 0x7F),
        expected: "The game is now over."
    }
};
const gameOver = "The game is now over.\n";

// The line of the first instruction of a routine of a console.s, which each call reaches once.
function firstLine(consoleSource, routine) {
    const lines = readFileSync(consoleSource, "utf8").split(/\r?\n/);
    const start = lines.indexOf(`.proc ${routine}`);
    assert.ok(start >= 0, `${routine} is in ${consoleSource}`);
    const isInstruction = text => text !== "" && !text.startsWith(";") && !/^[A-Za-z_][A-Za-z0-9_]*:$/.test(text);
    const first = lines.findIndex((line, at) => at > start && isInstruction(line.trim()));
    assert.ok(first > start, `${routine} has an instruction`);
    return first + 1;
}

// Checks that a target's Woz Monitor hex stores, line by line, the bytes the launch loaded, and that its last line runs
// the program at the entry the launch started at.
async function checkHex(target, entry) {
    const lines = readFileSync(join(sample, "artifacts", target, "adventure.hex"), "utf8").split("\r\n").filter(line => line);
    const run = lines.pop();
    let bytes = 0;
    for (const line of lines) {
        const [address, data] = line.split(": ");
        const expected = data.split(" ").map(pair => parseInt(pair, 16));
        const loaded = [...Buffer.from((await request("readMemory", {
            memoryReference: `0x${address}`, count: expected.length
        })).data, "base64")];
        assert.deepEqual(loaded, expected, `${target}: the hex's line ${line} stores what the launch loaded`);
        bytes += expected.length;
    }
    assert.equal(run, `${entry.toString(16).toUpperCase().padStart(4, "0")}R`, `${target}: the hex's last line runs the program at its entry`);
    console.log(`${target}: its hex stores the ${bytes} bytes the launch loaded, and ${run} runs them.`);
}

const { request, event, events, fail, close, failure } = startDap(root);
// A whole run takes about two minutes; each play may take three.
const timeout = setTimeout(() => fail(new Error("Adventure DAP integration timed out.")),
    180000 * Math.max(1, targets.reduce((count, target) => count + (plays[target]?.transcripts.length ?? 0), 0)));

// What the engine has written, with each command after the prompt it answers, as the screen shows them: Write's
// logpoint logs each character's code, and ReadLine's each read.
function transcript(commands) {
    let text = "";
    let next = 0;
    for (const message of events) {
        if (message.event !== "output" || message.body.category !== "console") continue;
        const output = message.body.output.trimEnd();
        if (output === "READ") {
            text += `${commands[next++] ?? ""}\n`;
        } else if (/^\d+$/.test(output)) {
            text += String.fromCharCode(Number(output));
        }
    }
    return text;
}

try {
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });
    for (const target of targets) {
        assert.ok(allTargets.includes(target), `there is no target ${target} to play`);
        const { family, transcripts } = plays[target];
        const consoleSource = join(sample, "src", "platform", family, "console.s");
        const readLine = firstLine(consoleSource, "ReadLine");
        const write = firstLine(consoleSource, "Write");
        for (const name of transcripts) {
            const commands = readFileSync(join(sample, "games", `${name}.in`), "utf8").split(/\r?\n/);
            if (commands.at(-1) === "") commands.pop();
            const expected = readFileSync(join(sample, "games", `${name}.out`), "utf8").replace(/\r\n/g, "\n");
            events.length = 0;
            const launched = await request("launch", { project: sample, target, stopOnEntry: false, speed: "max",
                sound: "off", logpointLimit: 0, checkContracts: "stop" });

            // A wozmon target's hex, typed in, stores what the launch loaded, and runs it at its entry.
            if (plays[target].hex) await checkHex(target, launched.project.entry);
            const set = await request("setBreakpoints", { source: { path: consoleSource }, breakpoints: [
                { line: readLine, logMessage: "READ" }, { line: write, logMessage: "{A,d}" }
            ] });
            assert.ok(set.breakpoints.every(breakpoint => breakpoint.verified), "the console's logpoints map to their source");
            await request("configurationDone");
            await request("retro/type", { text: commands.map(command => `${command}\n`).join("") });

            // The engine runs to the end of the game.
            for (const end = performance.now() + 180000; performance.now() < end && !transcript(commands).endsWith(gameOver);) {
                const broken = events.find(message => message.event === "stopped" && message.body.reason === "exception");
                assert.ok(!broken, `${target} ${name}: the machine stopped: ${broken?.body.description}`);
                await new Promise(done => setTimeout(done, 200));
            }

            const stopped = events.find(message => message.event === "stopped" && message.body.reason === "exception");
            assert.ok(!stopped, `${target} ${name}: the machine stopped: ${stopped?.body.description}`);
            const played = transcript(commands);
            let differs = 0;
            while (differs < played.length && played[differs] === expected[differs]) differs++;
            if (differs < Math.max(played.length, expected.length)) {
                const around = text => text.slice(Math.max(0, differs - 300), differs + 200);
                console.log(`${target} ${name}: differs at ${differs}: played\n${around(played)}\n--- expected\n${around(expected)}`);
            }
            assert.equal(played, expected, `${target} ${name}: the 6502 engine's transcript matches the reference engine's`);

            // The Apple II's screen shows it in capitals, as the Apple II Plus has no lowercase.
            if (family === "apple2") {
                const screen = (await request("apple2/text")).rows.join("\n");
                assert.match(screen, /^THE GAME IS NOW OVER\. *$/m, `${name}: the screen shows the game's end:\n${screen}`);
            }

            // The PET's and BBC's screens show it too, so their consoles' output calls are checked as well as what the
            // engine hands them. The Apple-1's terminal keeps no screen in memory.
            if (screens[family]) {
                const { address, count, wraps, text, expected: end } = screens[family];
                const bytes = [...Buffer.from((await request("readMemory", {
                    memoryReference: `0x${address.toString(16)}`, count
                })).data, "base64")];
                assert.equal(bytes.length, count, `${target}: the screen's memory reads`);

                const screen = (wraps ? [...bytes, ...bytes] : bytes).map(text).join("");
                assert.ok(screen.includes(end), `${target} ${name}: the screen shows "${end}"`);
            }
            await request("pause", { threadId: 1 });
            await event("stopped");
            console.log(`${target} ${name}: ${commands.length} commands, ${played.length} characters, as the reference engine plays them.`);
        }
    }

    await request("disconnect");
    console.log(`Adventure DAP passed: the 6502 engine plays each transcript on ${targets.join(", ")} as the reference engine does.`);
} finally {
    clearTimeout(timeout);
    close();
}
if (failure()) throw failure();
