// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import { test } from "node:test";
import { groupCycleLines } from "../cycles";

test("cycle decorations group by file and displayed count", () => {
    const groups = groupCycleLines([
        { path: "C:\\Src\\A.asm", line: 1, cycles: 1000 },
        { path: "c:\\src\\a.asm", line: 2, cycles: 4000 },
        { path: "C:\\Src\\A.asm", line: 3, cycles: 999 },
        { path: "C:\\Src\\B.asm", line: 4, cycles: 1000 }
    ]);
    assert.deepEqual(groups.get("c:\\src\\a.asm")?.get(1000)?.map(line => line.line), [1, 2]);
    assert.deepEqual(groups.get("c:\\src\\a.asm")?.get(999)?.map(line => line.line), [3]);
    assert.deepEqual(groups.get("c:\\src\\b.asm")?.get(1000)?.map(line => line.line), [4]);
});
