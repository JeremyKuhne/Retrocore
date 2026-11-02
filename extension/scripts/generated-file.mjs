// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Writes or checks a generated file. Git checks text out with the platform's line endings, so a file's line endings
// are kept as they are when it is rewritten, and a check ignores them.

import { existsSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";

/**
 * Writes generated text, or with --check throws when the file on disk says something else.
 * @param {string} output The file's path.
 * @param {string} text The generated text, with LF line endings.
 * @param {string} stale The error message for a stale file.
 */
export function writeGenerated(output, text, stale) {
    const existing = existsSync(output) ? readFileSync(output, "utf8") : undefined;
    if (process.argv.includes("--check")) {
        if (existing?.replaceAll("\r\n", "\n") !== text) throw new Error(stale);
        return;
    }

    const content = existing?.includes("\r\n") ? text.replaceAll("\n", "\r\n") : text;
    if (content === existing) return;
    mkdirSync(dirname(output), { recursive: true });
    writeFileSync(output, content);
}
