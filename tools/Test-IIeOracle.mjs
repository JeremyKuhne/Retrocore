// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import { createRequire } from "node:module";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import assert from "node:assert/strict";

const root = resolve(import.meta.dirname, "..");
const require = createRequire(import.meta.url);
const image = readFileSync(join(process.env.RETROCORE_CACHE ?? join(process.env.USERPROFILE ?? "", "Retrocore"), "m1-dependencies", "ProDOS_2_4_3.po"));
for (const model of ["original", "enhanced"]) {
    const probe = spawnSync("dotnet", [
        join(root, "artifacts", "AnyCPU", "Release", "Retrocore.Debug", "net10.0", "Retrocore.Debug.dll"),
        "--boot-state", process.env.RETROCORE_IIE_ROMS,
        join(process.env.RETROCORE_CACHE ?? join(process.env.USERPROFILE ?? "", "Retrocore"), "m1-dependencies", "ProDOS_2_4_3.po"), model
    ], { encoding: "utf8", timeout: 30000, maxBuffer: 2 * 1024 * 1024 });
    if (probe.status !== 0) throw new Error(probe.stderr || "IIe boot-state probe failed.");
    const expected = JSON.parse(probe.stdout);
    delete require.cache[require.resolve("../artifacts/apple2ts-oracle/oracle.cjs")];
    const { mem, cpu, ins, sw } = require("../artifacts/apple2ts-oracle/oracle.cjs");
    sw.resetSoftSwitches();
    mem.doSetRom(model === "original" ? "APPLE2EU" : "APPLE2EE");
    const variant = model === "original" ? "UNENHANCED" : "ENHANCED";
    const cd = model === "original" ? "342-0135 - B" : "342-0304 - A";
    const ef = model === "original" ? "342-0134 - A" : "342-0303 - A";
    // Restore the caller's unmodified firmware after the oracle's optional legacy-ROM boot patch.
    mem.memory.set(Buffer.concat([
        readFileSync(join(process.env.RETROCORE_IIE_ROMS, `APPLE IIe - CD ${variant} - ${cd} - 2764.bin`)),
        readFileSync(join(process.env.RETROCORE_IIE_ROMS, `APPLE IIe - EF ${variant} - ${ef} - 2764.bin`))
    ]), 0x10000);
    mem.updateAddressTables();
    mem.setSlotDriver(7, Buffer.from(expected.firmware, "base64"));
    mem.setSlotIOCallback(7, (address, value) => {
        if (value >= 0) return -1;
        if (address === 0xC0F1) return (image.length / 512) & 255;
        if (address === 0xC0F2) return (image.length / 512) >> 8;
        if (address !== 0xC0F0) return -1;
        const command = mem.memGet(0x42, false);
        if (command === 0) return 0;
        if (command !== 1) return command === 2 ? 0x2B : 1;
        const block = mem.memGet(0x46, false) | (mem.memGet(0x47, false) << 8);
        const buffer = mem.memGet(0x44, false) | (mem.memGet(0x45, false) << 8);
        if (block * 512 >= image.length) return 0x27;
        for (let i = 0; i < 512; i++) mem.memSet((buffer + i) & 65535, image[block * 512 + i]);
        return 0;
    });
    ins.reset6502();
    ins.s6502.StackPtr = 0xFA;
    ins.s6502.cycleCount = 7;
    let reached = false;
    for (let i = 0; i < 5000000; i++) {
        const pc = ins.s6502.PC;
        sw.SWITCHES.VBLINV.isSet = Math.floor(ins.s6502.cycleCount / 65) % 262 < 192;
        if (mem.memGet(0xBF00, false) === 0x4C && mem.memGet(pc, false) === 0xAD
            && mem.memGet((pc + 1) & 65535, false) === 0 && mem.memGet((pc + 2) & 65535, false) === 0xC0) {
            reached = true; break;
        }
        cpu.processInstruction();
    }
    assert.equal(reached, true, "Oracle did not boot ProDOS to its keyboard checkpoint.");
    const actual = ins.s6502;
    for (const [key, field] of [["pc", "PC"], ["a", "Accum"], ["x", "XReg"], ["y", "YReg"], ["s", "StackPtr"]]) {
        assert.equal(actual[field], expected[key], `${model} register ${key}`);
    }
    // B is an interrupt-stack encoding, not a physical status latch.
    assert.equal(actual.PStatus & ~0x10, expected.p & ~0x10, `${model} physical status flags`);
    const differences = [];
    for (const [bank, start] of [["main", 0], ["auxiliary", mem.memory.length - 0x10100]]) {
        const bytes = Buffer.from(expected[bank], "base64");
        for (let address = 0; address < 0x10000; address++) {
            if(mem.memory[start + address] !== bytes[address]) differences.push(`${bank}:$${address.toString(16)}:${mem.memory[start + address].toString(16)}/${bytes[address].toString(16)}`);
        }
    }
    assert.equal(differences.length,0,`${model} physical RAM mismatches: ${differences.slice(0,30).join(", ")}`);
    console.log(`${model}: ProDOS boot agrees with pinned Apple2TS on CPU registers and all 128 KiB of RAM.`);
}
