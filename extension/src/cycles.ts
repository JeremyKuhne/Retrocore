// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

export interface CycleLine { path: string; line: number; cycles: number; }

export function groupCycleLines(lines: CycleLine[]): Map<string, Map<number, CycleLine[]>> {
    const groups = new Map<string, Map<number, CycleLine[]>>();
    for (const line of lines) {
        const path = line.path.toLowerCase();
        let counts = groups.get(path);
        if (counts === undefined) { counts = new Map(); groups.set(path, counts); }
        const count = Math.min(line.cycles, 1000);
        let group = counts.get(count);
        if (group === undefined) { group = []; counts.set(count, group); }
        group.push(line);
    }
    return groups;
}
