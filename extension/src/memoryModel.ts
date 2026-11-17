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
 * The label or address under the cursor in an assembly file, such as TEXT_PAGE, $0400, 0400h, aux:$0400 or a
 * scoped label, such as ca65's screen::clear, whole wherever the cursor is in it; a label's own colon is left off.
 */
export function addressAt(line: string, character: number): string | undefined {
    const pattern = /(?:[A-Za-z][A-Za-z0-9]*:(?!:)(?=[A-Za-z0-9_.@?$]))?[A-Za-z0-9_.@?$]+(?:::[A-Za-z0-9_.@?$]+)*/g;
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
    // cpu: names memory as the machine's own CPU maps it, as no bank does.
    const bank = match[1]?.toLowerCase();
    return address > 0xFFFF ? undefined : { bank: bank === undefined || bank === "cpu" ? null : bank, address };
}

/**
 * The function breakpoint the listing's gutter sets at an address of a view's bank, such as $0300 or aux:$0400,
 * which the debugger stops at as an instruction breakpoint, in that bank's code only.
 */
export function breakpointName(bank: string | null, address: number): string {
    return (bank === null ? "" : `${bank}:`) + "$" + hex(address, 4);
}

/**
 * Whether a function breakpoint's name is the address of a view's bank the listing's gutter sets: $0300, 0x0300 or
 * cpu:$0300 in the CPU's view, aux:$0400 in aux's, whatever the case. Only a name written in hex counts: bare digits
 * are decimal in an expression, so 1024 stops at $0400, not $1024.
 */
export function breakpointAt(name: string, bank: string | null, address: number): boolean {
    if (!/^\s*(?:[a-z][a-z0-9]*:)?\s*(?:\$|0x)/i.test(name)) return false;
    const parsed = parseReference(name.trim().replace(/(^|:)\s*\$/, (_, before: string) => `${before}0x`));
    return parsed !== undefined && parsed.bank === bank && parsed.address === address;
}

/**
 * Where an address, label or expression points in a view's bank, through the debugger's evaluate, which gives the
 * memory reference an expression names in a frame. It is evaluated in the focused frame first, so a register such as
 * the Z80's PC, or SP in a caller's frame, reads as that frame shows it; when that gives an address in another bank,
 * as $0400 does in the CPU's view while the Z80's frame is focused, in the CPU's own frame; see referenceIn.
 * Undefined when neither names an address in the bank. The extension runs this, not the page.
 */
export async function resolveIn(
    evaluate: (expression: string, frameId?: number) => Promise<string | undefined>,
    bank: string | null,
    text: string,
    frameId?: number): Promise<number | undefined> {
    const reference = await referenceIn(evaluate, bank === null ? text : `${bank}:${text}`, frameId, parsed => parsed.bank === bank);
    return reference === undefined ? undefined : parseReference(reference)?.address;
}

/**
 * The watch expressions the CPU's view adds: VS Code evaluates a watch in the focused frame, where [$0400] is the
 * coprocessor's memory while a coprocessor's frame is, such as the SoftCard's Z80's, so on a machine with one each
 * names the machine's CPU, as [cpu:$0400]. An expression that names a bank already is left as it is. The extension
 * runs this, not the page.
 */
export function cpuWatches(expressions: string[], coprocessor: boolean): string[] {
    return coprocessor ? expressions.map(expression => expression.replace(/^\[\$/, "[cpu:$")) : expressions;
}

/**
 * The memory reference an expression names, evaluated in the focused frame and, when that names one the caller does
 * not accept, such as the Z80's $0400 in the CPU's view, in the CPU's own frame. A frame that names none, as a Pascal
 * local the debugger cannot place, or that fails, is the answer: the CPU's frame would read the name as something
 * else, such as a Pascal local X as the 6502's X register. (The debugger itself evaluates an address in the CPU's
 * frame while a BASIC frame is focused, as BASIC names no memory.) The extension runs this, not the page.
 */
export async function referenceIn(
    evaluate: (expression: string, frameId?: number) => Promise<string | undefined>,
    expression: string,
    frameId?: number,
    accept: (parsed: ParsedReference) => boolean = () => true): Promise<string | undefined> {
    const reference = await evaluate(expression, frameId);
    const parsed = reference === undefined ? undefined : parseReference(reference);
    if (parsed === undefined || accept(parsed)) return parsed === undefined ? undefined : reference;
    if (frameId === undefined) return undefined;
    const again = await evaluate(expression, undefined);
    const reparsed = again === undefined ? undefined : parseReference(again);
    return reparsed !== undefined && accept(reparsed) ? again : undefined;
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
    // A start past where the pattern last fits wraps forward to the start and goes back to that last place, and
    // one before the start wraps backward to it, so Find Next from the last match and Find Previous from the
    // first go on, and the nearest match is never skipped.
    const first = backward ? (from < 0 || from > last ? last : from) : (from < 0 || from > last ? 0 : from);
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

/**
 * A value a RAM search compares with: a byte, or with a size of 2 a 16-bit word, as hex with $ or 0x, binary with %,
 * or decimal, which may be negative; or why the text is not one.
 */
export function parseValue(text: string, size = 1): number | string {
    if (size === 1) return parseByte(text);
    const trimmed = text.trim();
    let value: number;
    if (/^(\$|0[xX])[0-9A-Fa-f]{1,4}$/.test(trimmed)) value = parseInt(trimmed.replace(/^(\$|0[xX])/, ""), 16);
    else if (/^%[01]{1,16}$/.test(trimmed)) value = parseInt(trimmed.substring(1), 2);
    else if (/^-?[0-9]{1,5}$/.test(trimmed)) value = parseInt(trimmed, 10);
    else return "Type a word, such as $1F00, %0001111100000000 or 7936.";
    if (value < -32768 || value > 0xFFFF) return `${trimmed} does not fit in a word.`;
    return value & 0xFFFF;
}

/** A bookmark: a name for an address in memory as the CPU maps it or in a bank. */
export interface MemoryBookmark {
    name: string;
    bank: string | null;
    address: number;
}

/**
 * The bookmarks kept in the workspace's state, by launch configuration name: pairs of a name and its bookmarks.
 * Anything else, such as nothing saved yet, is none.
 */
export function bookmarkStore(saved: unknown): Map<string, MemoryBookmark[]> {
    const store = new Map<string, MemoryBookmark[]>();
    if (!Array.isArray(saved)) return store;
    for (const entry of saved) {
        if (Array.isArray(entry) && typeof entry[0] === "string" && Array.isArray(entry[1])) store.set(entry[0], entry[1] as MemoryBookmark[]);
    }
    return store;
}

/**
 * Sets, renames or removes the bookmark at an address of a space: a name replaces the one there, and an empty name
 * removes it. Returns the new list, in address order within each space.
 */
export function withBookmark(list: readonly MemoryBookmark[], bank: string | null, address: number, name: string): MemoryBookmark[] {
    const kept = list.filter(item => item.bank !== bank || item.address !== address);
    const trimmed = name.trim();
    if (trimmed.length > 0) kept.push({ name: trimmed, bank, address });
    return kept.sort((first, second) => (first.bank ?? "").localeCompare(second.bank ?? "") || first.address - second.address);
}

/** A number Find looks for, in each form it can take: its bytes, labelled as the inspector labels them. */
export interface ValueForm {
    label: string;
    bytes: number[];
}

/**
 * Reads the number Find looks for after its =, such as =1000, =$C000, =%1010 or =-2.5, as the inspector's forms:
 * a byte when it fits one, else a word low first and high first when it fits one. A fraction or exponent has no such
 * forms, only the BASIC's floats, which the debugger encodes from the decimal: the text as typed, or a hex or binary
 * number's value. Returns a message for text that is no number.
 */
export function valueForms(text: string): { forms: ValueForm[]; decimal: string } | string {
    const trimmed = text.trim();
    let value: number;
    // Decimal text goes to the debugger as typed, as Level II's double holds more digits than a number here does.
    let decimal: string | undefined;
    // Whether the number is whole, which a fraction too small for a number here, as in 1.0000000000000001, is not.
    let whole = true;
    if (/^(\$|0[xX])[0-9A-Fa-f]{1,8}$/.test(trimmed)) value = parseInt(trimmed.replace(/^(\$|0[xX])/, ""), 16);
    else if (/^%[01]{1,32}$/.test(trimmed)) value = parseInt(trimmed.substring(1), 2);
    else if (/^[-+]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][-+]?[0-9]+)?$/.test(trimmed)) {
        value = Number(trimmed);
        decimal = trimmed;
        // Whole when the digits' trailing zeros cover the places the exponent leaves after the point.
        const [, digitsText, exponentText] = /^[-+]?([0-9.]*)(?:[eE]([-+]?[0-9]+))?$/.exec(trimmed) ?? ["", "", ""];
        const [wholePart, fraction = ""] = digitsText.split(".");
        const digits = (wholePart + fraction).replace(/^0+/, "");
        const places = fraction.length - Number(exponentText ?? 0);
        whole = digits.length === 0 || places <= 0 || (digits.length - digits.replace(/0+$/, "").length) >= places;
    } else return "Type a number after =, such as =1000, =$C000, =%1010 or =-2.5.";
    if (!Number.isFinite(value)) return `${trimmed} is too large.`;
    const forms: ValueForm[] = [];
    if (whole && Number.isInteger(value)) {
        if (value >= -128 && value <= 255) {
            forms.push({ label: "a byte", bytes: [value & 0xFF] });
        } else if (value >= -32768 && value <= 0xFFFF) {
            const word = value & 0xFFFF;
            forms.push({ label: "a word, low first", bytes: [word & 0xFF, word >> 8] }, { label: "a word, high first", bytes: [word >> 8, word & 0xFF] });
        }
    }
    return { forms, decimal: decimal ?? String(value) };
}

/** The value at an offset: a byte, or with a size of 2 a word in the CPU's byte order. */
export function valueAt(data: Uint8Array, offset: number, size = 1, bigEndian = false): number {
    if (size === 1) return data[offset];
    return bigEndian ? (data[offset] << 8) | data[offset + 1] : data[offset] | (data[offset + 1] << 8);
}

/**
 * The offsets a RAM search starts from: every byte that can be read and written, or with a size of 2 every word
 * whose two bytes can.
 */
export function searchStart(readable: Uint8Array, readOnly: Uint8Array, size = 1): number[] {
    const offsets: number[] = [];
    for (let offset = 0; offset + size <= readable.length; offset++) {
        let usable = true;
        for (let index = 0; index < size && usable; index++) usable = readable[offset + index] === 1 && readOnly[offset + index] !== 1;
        if (usable) offsets.push(offset);
    }
    return offsets;
}

/**
 * Narrows a RAM search: keeps the candidates whose value now passes the test against what it was before, or against
 * a value. A byte that can no longer be read drops out, and so does a word with one.
 */
export function narrowSearch(
    candidates: number[], before: Uint8Array, now: Uint8Array, readable: Uint8Array, test: SearchTest, value = 0, size = 1, bigEndian = false
): number[] {
    return candidates.filter(offset => {
        for (let index = 0; index < size; index++) {
            if (readable[offset + index] !== 1) return false;
        }
        const was = valueAt(before, offset, size, bigEndian), is = valueAt(now, offset, size, bigEndian);
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
export const pageFunctions = [hex, parseReference, parsePattern, findPattern, valueForms, textOf, typedText, labelOf, inspect, copyText, parseByte, parseValue, valueAt, searchStart, narrowSearch];
