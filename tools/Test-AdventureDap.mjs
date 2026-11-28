// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The adventure sample's 6502 engine through the debug adapter, from its project file. It plays Pirate Adventure,
// linked in, from start to finish on bare targets of sample/adventure/retrocore.json (the win and the death on the
// Apple-1 with 32K, the PET 4032, the Apple II Plus and the BBC Micro), its win on the Apple-1's wozmon target, which a
// launch loads as if its hex had been typed in, both on the Apple II Plus's dos33 target and the BBC Micro's dfs
// target, each booted from its disk, which loads the game from the disk, both on the PET's basic target, LOADed from
// its tape and RUN, the win on its 4040 disk (skipped, and said to be, without the drive's ROMs), both on the Apple II
// Plus's prodos target, booted from a ProDOS 2.4.3 disk whose ProDOS is found by its hash (skipped, and said to be,
// without it), which loads the game from the disk through the MLI, and the test game's
// transcripts on apple2-test,
// through project launches, each running the project's steps, which pack the games with the sample's packer, and
// building the same core with its machine's platform folder. It checks that what the engine writes matches the C#
// reference engine's transcript in the matching .out file character for character. A logpoint on the console's Write
// records each character the engine sends, and one on ReadLine marks where it reads a command, so the commands can be
// put back where the screen shows them. Each logs once a call, though the PET's and BBC's IRQs come in as they run.
// The Apple II's, PET's and BBC's screens are checked for the game's end as well. The launches check Keeps: contracts
// and fail on a broken one. A false Keeps: on the top-level LocateTables stops the run, but one on
// Numbers::NextRandom, inside a .scope, did not, so the engine's scoped contracts are checked by reading rather than
// here. On the SDK's ROMs, so it needs no dumps but the 4040's for pet-disk, and ProDOS 2.4.3 for apple2-prodos. Give target names to play only those, such as
// `node tools/Test-AdventureDap.mjs pet`.

import { startDap } from "./DapClient.mjs";
import { resolve, join } from "node:path";
import { readFileSync } from "node:fs";
import assert from "node:assert/strict";

const root = resolve(import.meta.dirname, "..");
const sample = join(root, "sample", "adventure");
const ioModeOverride = process.env.RETROCORE_DAP_IO_MODE;
const inputBackend = process.env.RETROCORE_DAP_INPUT ?? "guestDemand";
assert.ok(ioModeOverride === undefined || ioModeOverride === "realistic" || ioModeOverride === "fast",
    "RETROCORE_DAP_IO_MODE must be realistic or fast");
assert.ok(inputBackend === "physical" || inputBackend === "guestDemand", "RETROCORE_DAP_INPUT must be physical or guestDemand");

// Transcripts are exact with either peripheral timing, so every target defaults to fast; realistic timing would pace
// every Apple-1 byte through its beam-synchronized terminal at hardware speed. RETROCORE_DAP_IO_MODE=realistic checks
// the games with hardware peripheral timing.
const ioModeFor = () => ioModeOverride ?? "fast";
console.log(`Adventure DAP: ${inputBackend} input (physical on Apple-1), `
    + `${ioModeFor()} peripheral timing`);

// The targets played, each with its platform folder and the transcripts it plays. The bare Apple III's console is
// built but not played: a bare Apple III has no character set loaded. Its sos target plays, with its own console.
const plays = {
    apple1: { family: "apple1", transcripts: ["pirate-win", "pirate-die"] },
    "apple1-wozmon": { family: "apple1", transcripts: ["pirate-win"], hex: true },
    pet: { family: "pet", transcripts: ["pirate-win", "pirate-die"] },
    "pet-basic": { family: "pet", transcripts: ["pirate-win", "pirate-die"] },
    "apple3-sos": { family: "apple3", folder: "sos", transcripts: ["pirate-win", "pirate-die"] },
    "pet-disk": { family: "pet", transcripts: ["pirate-win"], needs: "the 4040's ROMs" },
    "apple2-prodos": { family: "apple2", transcripts: ["pirate-win", "pirate-die"], needs: "ProDOS 2.4.3's disk" },
    apple2: { family: "apple2", transcripts: ["pirate-win", "pirate-die"] },
    "apple2-dos": { family: "apple2", transcripts: ["pirate-win", "pirate-die"] },
    bbc: { family: "bbc", transcripts: ["pirate-win", "pirate-die"] },
    "bbc-dfs": { family: "bbc", transcripts: ["pirate-win", "pirate-die"] },
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

const { request, event, events, fail, close, failure, received } = startDap(root);
const skippedTargets = [];
const measured = { prepMs: 0, playMs: 0, prepCycles: 0, playCycles: 0 };
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

async function addressOf(routine) {
    const result = await request("evaluate", { expression: `Console::${routine}`, context: "repl" });
    const match = /^\$([0-9A-F]+)\b/i.exec(result.result);
    assert.ok(match, `${routine} resolves to an instruction address: ${result.result}`);
    return parseInt(match[1], 16);
}

async function runTo(address, input) {
    const wait = await request("retro/runUntil", {
        stopOn: { kind: "instruction", address }, input, policy: "scripted", maxCycles: 1_000_000_000
    });
    const result = await event("retro/run/result", body => body.launchId === wait.launchId && body.runId === wait.runId);
    const stopped = await event("stopped");
    assert.notEqual(stopped.reason, "exception", `the machine stopped: ${stopped.description}`);
    return result;
}

try {
    await request("initialize", { adapterID: "retrocore", linesStartAt1: true, columnsStartAt1: true });
    for (const target of targets) {
        assert.ok(allTargets.includes(target), `there is no target ${target} to play`);
        const { family, transcripts } = plays[target];
        const consoleSource = join(sample, "src", "platform", plays[target].folder ?? family, "console.s");
        const readLine = firstLine(consoleSource, "ReadLine");
        const write = firstLine(consoleSource, "Write");
        let skipped = false;
        for (const name of transcripts) {
            if (skipped) break;
            const script = readFileSync(join(sample, "games", `${name}.in`), "utf8").split(/\r?\n/);
            if (script.at(-1) === "") script.pop();
            const expected = readFileSync(join(sample, "games", `${name}.out`), "utf8").replace(/\r\n/g, "\n");
            // test-drown ends before its last scripted command. Compare both backends on the actual reference work.
            const commands = [...expected.matchAll(/^> (.*)$/gm)].map(match => match[1]);
            assert.ok(commands.length > 0, `${name}: the reference ran commands`);
            assert.deepEqual(script.slice(0, commands.length), commands, `${name}: the reference used this script`);
            events.length = 0;
            const launchArgs = { project: sample, target, stopOnEntry: true, speed: "max", sound: "off", textOnly: true,
                ioMode: ioModeFor(),
                logpointLimit: 0, checkContracts: "stop" };

            // A target that needs dumps the SDK does not build, such as the 4040's ROMs for the PET's disk, is skipped,
            // and reported as skipped, when the launch does not find them.
            const preparationStarted = performance.now();
            let launched;
            try {
                launched = await request("launch", launchArgs);
            } catch (error) {
                if (!plays[target].needs || !/(were not found by their hashes|was not found by its hash)/.test(error.message)) throw error;
                console.log(`SKIPPED ${target}, which needs ${plays[target].needs}: ${error.message}`);
                skippedTargets.push(target);
                skipped = true;
                break;
            }

            // A wozmon target's hex, typed in, stores what the launch loaded, and runs it at its entry.
            if (plays[target].hex) await checkHex(target, launched.project.entry);
            const set = await request("setBreakpoints", { source: { path: consoleSource }, breakpoints: [
                { line: readLine, logMessage: "READ" }, { line: write, logMessage: "{A,d}" }
            ] });
            assert.ok(set.breakpoints.every(breakpoint => breakpoint.verified), "the console's logpoints map to their source");
            const readAddress = await addressOf("ReadLine");
            const finishAddress = await addressOf("Finish");
            await request("configurationDone");
            assert.equal((await event("stopped")).reason, "entry");

            // This application's ReadLine is a stable start barrier even when preceded by an OS boot. Apple-1's
            // own RAM PIA loop is not a verified firmware demand path, so use physical input there explicitly.
            const ready = await runTo(readAddress);
            assert.equal(ready.outcome, "matched", `${target} ${name}: first application read`);
            measured.prepMs += performance.now() - preparationStarted;
            measured.prepCycles += ready.cycles - ready.startCycle;
            const backend = family === "apple1" ? "physical" : inputBackend;
            const text = script.slice(0, commands.length).map(command => `${command}\n`).join("");
            const playStarted = performance.now();
            const result = await runTo(finishAddress, { text, backend });
            measured.playMs += performance.now() - playStarted;
            measured.playCycles += result.cycles - result.startCycle;
            if (result.outcome !== "matched") {
                console.log(`${target} ${name}: partial transcript\n${transcript(commands)}\n${JSON.stringify(result)}`);
            }
            assert.equal(result.outcome, "matched", `${target} ${name}: the game reaches Console::Finish`);
            assert.equal(result.input.skipped + result.input.rejected + result.input.cancelled + result.input.pending, 0,
                `${target} ${name}: every command byte was delivered`);
            assert.equal(result.input.delivered, text.length, `${target} ${name}: all mapped bytes were delivered`);
            if (backend === "guestDemand") {
                assert.equal(result.input.unconfirmed, 0, `${target} ${name}: no unconfirmed delivery`);
                assert.equal(result.input.accepted, text.length, `${target} ${name}: all mapped bytes were admitted`);
            }
            assert.ok(!events.some(message => ["retro/frame", "retro/cycles", "retro/audio"].includes(message.event)),
                `${target} ${name}: text-only launch suppresses video, audio and cycle events`);
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
                const screen = (await request("retro/text")).rows.join("\n");
                assert.match(screen, /^THE GAME IS NOW OVER\. *$/m, `${name}: the screen shows the game's end:\n${screen}`);
            }

            // The Apple III's console under SOS shows it too, through the console driver, in the character set SOS
            // loaded.
            if (family === "apple3") {
                const screen = (await request("retro/text")).rows.join("\n");
                assert.match(screen, /^The game is now over\. *$/m, `${target} ${name}: the screen shows the game's end:\n${screen}`);
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
            console.log(`${target} ${name} (${backend}): ${commands.length} commands, ${played.length} characters, exact transcript.`);
        }
    }

    await request("disconnect");
    const played = targets.filter(target => !skippedTargets.includes(target));
    if (played.length !== 0) {
        console.log(`Adventure DAP passed: the 6502 engine plays each transcript on ${played.join(", ")} as the reference engine does.`);
    }
    if (skippedTargets.length !== 0) {
        console.log(`Adventure DAP skipped ${skippedTargets.join(", ")}: not played, so not passed, as the dumps or disks they need were not found.`);
    }
    console.log(`Adventure work: ${JSON.stringify({ ...measured, ...received() })}`);
} finally {
    clearTimeout(timeout);
    close();
}
if (failure()) throw failure();
