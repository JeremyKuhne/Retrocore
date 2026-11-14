// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Retrocore Memory's logic that needs no DOM: references, find patterns, the text column and the inspector. The
// webview runs these same functions, which its page embeds as source, so each must use only the others and the
// language's globals.

/** A memory reference split into its bank, if it names one, and its address. */
export interface ParsedReference {
    bank: string | null;
    address: number;
}

/**
 * One byte of a find pattern: the bits of a byte to compare (0 for a wildcard) and what they must be, or for text in
 * the machine's character set, every code that shows the character.
 */
export interface PatternByte {
    value: number;
    mask: number;
    codes?: boolean[];
}

/** A label the debugger gives an address. */
export interface MemoryLabel {
    address: number;
    name: string;
}

/** A row of the inspector: what a value is and how it reads. */
export interface InspectorRow {
    label: string;
    value: string;
}

/** Hex digits, padded with zeros, in upper case. */
export function hex(value: number, digits: number): string {
    return value.toString(16).toUpperCase().padStart(digits, "0");
}

/**
 * The label or address under the cursor in an assembly file, such as TEXT_PAGE, $0400, 0400h or aux:$0400; a
 * label's own colon is left off.
 */
export function addressAt(line: string, character: number): string | undefined {
    const pattern = /[A-Za-z0-9_.@?$]+(?::[A-Za-z0-9_.@?$]+)?/g;
    for (let match = pattern.exec(line); match !== null; match = pattern.exec(line)) {
        if (character >= match.index && character <= match.index + match[0].length) return match[0];
    }
    return undefined;
}

/**
 * Splits a memory reference the debugger handed out, such as "0x0400", "aux:0x0400" or "0400", into its bank and
 * address; undefined when it is an expression the debugger must evaluate.
 */
export function parseReference(reference: string): ParsedReference | undefined {
    const match = /^\s*(?:([A-Za-z][A-Za-z0-9]*):)?\s*(?:0[xX]([0-9A-Fa-f]+)|([0-9][0-9A-Fa-f]*))\s*$/.exec(reference);
    if (match === null) return undefined;
    const address = parseInt(match[2] ?? match[3], 16);
    return address > 0xFFFF ? undefined : { bank: match[1]?.toLowerCase() ?? null, address };
}

/**
 * Reads a find pattern: hex bytes, with ?? for any byte, such as "A9 ?? 20", or text in quotes, such as "HELLO".
 * Text matches every code the machine's character set shows as each character, given the set as one character a
 * code; without it, ASCII with bit 7 clear or set, as the Apple II keeps text with it set. Returns a message for a
 * pattern it cannot read.
 */
export function parsePattern(text: string, characters?: string): PatternByte[] | string {
    const trimmed = text.trim();
    if (trimmed.length === 0) return "Type bytes such as A9 ?? 20, or text in quotes.";
    const quoted = /^(["'])(.*)\1$/.exec(trimmed);
    if (quoted !== null) {
        if (quoted[2].length === 0) return "The text is empty.";
        const bytes: PatternByte[] = [];
        for (const character of quoted[2]) {
            if (characters !== undefined) {
                const codes = Array.from(characters, shown => shown === character);
                if (!codes.includes(true)) return `The machine has no ${character} character.`;
                bytes.push({ value: 0, mask: 0, codes });
                continue;
            }
            const code = character.charCodeAt(0);
            if (code > 0x7F) return `${character} is not ASCII.`;
            bytes.push({ value: code, mask: 0x7F });
        }
        return bytes;
    }

    const digits = trimmed.replace(/[\s,]+/g, "").replace(/^\$/, "");
    if (digits.length % 2 !== 0) return "Each byte takes two hex digits.";
    const bytes: PatternByte[] = [];
    for (let index = 0; index < digits.length; index += 2) {
        const pair = digits.substring(index, index + 2);
        if (pair === "??") {
            bytes.push({ value: 0, mask: 0 });
        } else if (/^[0-9A-Fa-f]{2}$/.test(pair)) {
            bytes.push({ value: parseInt(pair, 16), mask: 0xFF });
        } else {
            return `${pair} is not a hex byte or ??.`;
        }
    }
    return bytes;
}

/**
 * Finds a pattern in memory, starting at an offset and going forward or backward, wrapping around once. Bytes
 * that cannot be read never match. Returns the offset of the match, or -1.
 */
export function findPattern(bytes: Uint8Array, readable: Uint8Array, pattern: PatternByte[], from: number, backward: boolean): number {
    const size = bytes.length;
    if (pattern.length === 0 || pattern.length > size) return -1;
    const last = size - pattern.length;
    const matches = (start: number): boolean => {
        for (let index = 0; index < pattern.length; index++) {
            const offset = start + index;
            const part = pattern[index];
            if (readable[offset] !== 1) return false;
            if (part.codes !== undefined ? !part.codes[bytes[offset]] : (bytes[offset] & part.mask) !== (part.value & part.mask)) return false;
        }
        return true;
    };
    const starts = last + 1;
    // A start past either end wraps, so Find Next from the last match and Find Previous from the first go on.
    const first = ((from % starts) + starts) % starts;
    for (let step = 0; step < starts; step++) {
        const start = backward ? (first - step + starts) % starts : (first + step) % starts;
        if (matches(start)) return start;
    }
    return -1;
}

/**
 * The character a byte shows as text, or a dot: from the machine's character set, given as one character a code
 * with NUL for graphics; without it, the low seven bits when printable, so the Apple II's text, kept with bit 7 set,
 * reads as text.
 */
export function textOf(value: number, characters?: string): string {
    if (characters !== undefined) {
        const shown = characters.charAt(value);
        return shown >= " " && shown !== "\x7F" ? shown : ".";
    }
    const code = value & 0x7F;
    return code >= 0x20 && code < 0x7F ? String.fromCharCode(code) : ".";
}

/**
 * The byte typing a character in the text column writes, so text stays as the column showed it. With the machine's
 * character set, a code that shows the character: its ASCII code with the old byte's bit 7, unless that looks
 * different from the code that also keeps the old byte's bit 6, as the Apple II's inverse and flashing text do;
 * then that one. Without the set, the character's code with the old byte's bit 7. Undefined for a character the
 * machine cannot show.
 */
export function typedText(character: string, old: number, characters?: string, looksSame?: (first: number, second: number) => boolean): number | undefined {
    const code = character.charCodeAt(0);
    if (character.length !== 1) return undefined;
    if (characters !== undefined) {
        const keepHigh = (old & 0x80) | (code & 0x7F), keepBoth = (old & 0xC0) | (code & 0x3F);
        const high = characters.charAt(keepHigh) === character, both = characters.charAt(keepBoth) === character;
        if (high && both) return looksSame === undefined || looksSame(keepHigh, keepBoth) ? keepHigh : keepBoth;
        if (high) return keepHigh;
        if (both) return keepBoth;
        let any: number | undefined;
        for (let value = 0; value < characters.length; value++) {
            if (characters.charAt(value) !== character) continue;
            if ((value & 0x80) === (old & 0x80)) return value;
            any ??= value;
        }
        return any;
    }
    if (code < 0x20 || code > 0x7E) return undefined;
    return (old & 0x80) | code;
}

/**
 * Names an offset by the closest label at or before it, such as "COUT" or "COUT+3", given the labels in address
 * order; undefined when none is within a page before it.
 */
export function labelOf(labels: MemoryLabel[], offset: number): string | undefined {
    let low = 0, high = labels.length - 1, found = -1;
    while (low <= high) {
        const middle = (low + high) >> 1;
        if (labels[middle].address <= offset) {
            found = middle;
            low = middle + 1;
        } else {
            high = middle - 1;
        }
    }
    if (found < 0 || offset - labels[found].address > 0xFF) return undefined;
    const distance = offset - labels[found].address;
    return distance === 0 ? labels[found].name : `${labels[found].name}+${distance}`;
}

/**
 * What the bytes at an offset are, for the inspector: as a byte, signed and unsigned, binary and text, then as a
 * word in each byte order. Rows needing bytes past the readable ones are left out.
 */
export function inspect(bytes: Uint8Array, readable: Uint8Array, offset: number, characters?: string): InspectorRow[] {
    if (readable[offset] !== 1) return [{ label: "Byte", value: "unreadable" }];
    const byte = bytes[offset];
    const rows: InspectorRow[] = [
        { label: "Byte", value: `$${hex(byte, 2)}` },
        { label: "Unsigned", value: String(byte) },
        { label: "Signed", value: String(byte > 0x7F ? byte - 0x100 : byte) },
        { label: "Binary", value: `%${byte.toString(2).padStart(8, "0").replace(/^(....)/, "$1 ")}` },
        {
            label: "Text",
            value: characters !== undefined
                ? characters.charAt(byte) < " " ? "graphics" : textOf(byte, characters)
                : (byte & 0x7F) < 0x20 || (byte & 0x7F) === 0x7F ? "none" : `${textOf(byte)}${byte > 0x7F ? " (bit 7 set)" : ""}`
        }
    ];
    if (offset + 1 < bytes.length && readable[offset + 1] === 1) {
        const little = byte | (bytes[offset + 1] << 8);
        const big = (byte << 8) | bytes[offset + 1];
        rows.push(
            { label: "Word, low first", value: `$${hex(little, 4)}  ${little}  ${little > 0x7FFF ? little - 0x10000 : little}` },
            { label: "Word, high first", value: `$${hex(big, 4)}  ${big}  ${big > 0x7FFF ? big - 0x10000 : big}` });
    }
    return rows;
}

/** The selection as text to copy: hex bytes separated by spaces, or the characters the bytes show. */
export function copyText(bytes: Uint8Array, readable: Uint8Array, start: number, end: number, asText: boolean, characters?: string): string {
    const parts: string[] = [];
    for (let offset = start; offset <= end; offset++) {
        if (readable[offset] !== 1) {
            parts.push(asText ? "." : "??");
        } else {
            parts.push(asText ? textOf(bytes[offset], characters) : hex(bytes[offset], 2));
        }
    }
    return parts.join(asText ? "" : " ");
}

/** How a RAM search narrows its candidates: by how each byte compares with what it was, or with a value. */
export type SearchTest = "changed" | "unchanged" | "increased" | "decreased" | "equal" | "notEqual";

/**
 * Reads a byte value as a RAM search or freeze takes it: hex with $ or 0x, binary with %, or decimal, from -128 to
 * 255. Returns a message for one it cannot read.
 */
export function parseByte(text: string): number | string {
    const trimmed = text.trim();
    let value: number;
    if (/^(\$|0[xX])[0-9A-Fa-f]{1,2}$/.test(trimmed)) value = parseInt(trimmed.replace(/^(\$|0[xX])/, ""), 16);
    else if (/^%[01]{1,8}$/.test(trimmed)) value = parseInt(trimmed.substring(1), 2);
    else if (/^-?[0-9]{1,3}$/.test(trimmed)) value = parseInt(trimmed, 10);
    else return "Type a byte, such as $1F, %00011111 or 31.";
    if (value < -128 || value > 255) return `${trimmed} does not fit in a byte.`;
    return value & 0xFF;
}

/** The offsets a RAM search starts from: every byte that can be read and written. */
export function searchStart(readable: Uint8Array, readOnly: Uint8Array): number[] {
    const offsets: number[] = [];
    for (let offset = 0; offset < readable.length; offset++) {
        if (readable[offset] === 1 && readOnly[offset] !== 1) offsets.push(offset);
    }
    return offsets;
}

/**
 * Narrows a RAM search: keeps the candidates whose byte now passes the test against what it was before, or against
 * a value. A byte that can no longer be read drops out.
 */
export function narrowSearch(candidates: number[], before: Uint8Array, now: Uint8Array, readable: Uint8Array, test: SearchTest, value = 0): number[] {
    return candidates.filter(offset => {
        if (readable[offset] !== 1) return false;
        const was = before[offset], is = now[offset];
        switch (test) {
            case "changed": return is !== was;
            case "unchanged": return is === was;
            case "increased": return is > was;
            case "decreased": return is < was;
            case "equal": return is === value;
            case "notEqual": return is !== value;
        }
    });
}

/** The functions the webview's script embeds, in the order they are declared. */
export const pageFunctions = [hex, parseReference, parsePattern, findPattern, textOf, typedText, labelOf, inspect, copyText, parseByte, searchStart, narrowSearch];
