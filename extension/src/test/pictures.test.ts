// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import { test } from "node:test";
import { PictureCache } from "../pictures";

const frame = (pixels?: string): Record<string, unknown> => ({
    machine: "apple2", running: true, video: { width: 560, height: 192, pixelFormat: "rgba", ...(pixels === undefined ? {} : { pixels }) }
});

test("a new panel gets the last picture when its first frame has none; an open one does not", () => {
    const cache = new PictureCache();
    const first = frame("AAAA");
    assert.equal(cache.frame(first, false), first, "a frame with pixels passes as it is");
    const still = frame();
    assert.equal(cache.frame(still, false), still, "an open panel already has the picture");
    assert.deepEqual(cache.frame(still, true), frame("AAAA"));
    assert.deepEqual(still, frame(), "the frame itself is not changed");
});

test("a new picture replaces the kept one, and a new session forgets it", () => {
    const cache = new PictureCache();
    cache.frame(frame("AAAA"), false);
    cache.frame(frame("BBBB"), false);
    assert.deepEqual(cache.frame(frame(), true), frame("BBBB"));
    cache.reset();
    assert.deepEqual(cache.frame(frame(), true), frame());
    assert.equal(cache.frame(undefined, true), undefined, "a body that is not a frame passes as it is");
});
