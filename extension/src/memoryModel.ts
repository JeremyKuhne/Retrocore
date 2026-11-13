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

/** One byte of a find pattern: the bits of a byte to compare (0 for a wildcard) and what they must be. */
export interface PatternByte {
    value: number;
    mask: number;
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
 * Reads a find pattern: hex bytes, with ?? for any byte, such as "A9 ?? 20", or text in quotes, such as "HELLO",
 * whose characters match with bit 7 clear or set, as the Apple II keeps text with it set. Returns a message for
 * a pattern it cannot read.
 */
export function parsePattern(text: string): PatternByte[] | string {
    const trimmed = text.trim();
    if (trimmed.length === 0) return "Type bytes such as A9 ?? 20, or text in quotes.";
    const quoted = /^(["'])(.*)\1$/.exec(trimmed);
    if (quoted !== null) {
        if (quoted[2].length === 0) return "The text is empty.";
        const bytes: PatternByte[] = [];
        for (const character of quoted[2]) {
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
            if (readable[offset] !== 1 || (bytes[offset] & pattern[index].mask) !== (pattern[index].value & pattern[index].mask)) return false;
        }
        return true;
    };
    const starts = last + 1;
    const first = Math.min(Math.max(from, 0), last);
    for (let step = 0; step < starts; step++) {
        const start = backward ? (first - step + starts) % starts : (first + step) % starts;
        if (matches(start)) return start;
    }
    return -1;
}

/**
 * The character the text column shows for a byte: its low seven bits when printable, so the Apple II's text, kept
 * with bit 7 set, reads as text, or a dot.
 */
export function textOf(value: number): string {
    const code = value & 0x7F;
    return code >= 0x20 && code < 0x7F ? String.fromCharCode(code) : ".";
}

/**
 * The byte typing a character in the text column writes: the character's code, keeping the old byte's bit 7, so
 * text stays as the column showed it. Undefined for a character that has no seven-bit code.
 */
export function typedText(character: string, old: number): number | undefined {
    const code = character.charCodeAt(0);
    if (character.length !== 1 || code < 0x20 || code > 0x7E) return undefined;
    return (old & 0x80) | code;
}

/**
 * What the bytes at an offset are, for the inspector: as a byte, signed and unsigned, binary and text, then as a
 * word in each byte order. Rows needing bytes past the readable ones are left out.
 */
export function inspect(bytes: Uint8Array, readable: Uint8Array, offset: number): InspectorRow[] {
    if (readable[offset] !== 1) return [{ label: "Byte", value: "unreadable" }];
    const byte = bytes[offset];
    const rows: InspectorRow[] = [
        { label: "Byte", value: `$${hex(byte, 2)}` },
        { label: "Unsigned", value: String(byte) },
        { label: "Signed", value: String(byte > 0x7F ? byte - 0x100 : byte) },
        { label: "Binary", value: `%${byte.toString(2).padStart(8, "0").replace(/^(....)/, "$1 ")}` },
        { label: "Text", value: (byte & 0x7F) < 0x20 || (byte & 0x7F) === 0x7F ? "none" : `${textOf(byte)}${byte > 0x7F ? " (bit 7 set)" : ""}` }
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

/** The selection as text to copy: hex bytes separated by spaces, or the text column's characters. */
export function copyText(bytes: Uint8Array, readable: Uint8Array, start: number, end: number, asText: boolean): string {
    const parts: string[] = [];
    for (let offset = start; offset <= end; offset++) {
        if (readable[offset] !== 1) {
            parts.push(asText ? "." : "??");
        } else {
            parts.push(asText ? textOf(bytes[offset]) : hex(bytes[offset], 2));
        }
    }
    return parts.join(asText ? "" : " ");
}

/** The functions the webview's script embeds, in the order they are declared. */
export const pageFunctions = [hex, parseReference, parsePattern, findPattern, textOf, typedText, inspect, copyText];
