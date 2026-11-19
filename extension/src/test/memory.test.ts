// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import { test } from "node:test";
import { Script, createContext } from "node:vm";
import { addressAt, copyAs, intelHex, parseIntelHex, parseData, breakpointAt, breakpointName, copyText, cpuWatches, findPattern, hex, inspect, labelOf, narrowSearch, parseByte, parsePattern, parseValue, parseReference, referenceIn, resolveIn, searchStart, textOf, typedText, valueAt, valueForms, withBookmark, bookmarkStore, type PatternByte } from "../memoryModel";
import { memoryEditorHtml } from "../memoryView";

test("memory references split into a bank and an address; expressions do not", () => {
    assert.deepEqual(parseReference("0x0400"), { bank: null, address: 0x0400 });
    assert.deepEqual(parseReference("aux:0x0400"), { bank: "aux", address: 0x0400 });
    assert.deepEqual(parseReference("cpu:0400"), { bank: null, address: 0x0400 }, "cpu: is the CPU's memory, and its digits hex");
    assert.deepEqual(parseReference("CPU:0x0400"), { bank: null, address: 0x0400 });
    assert.deepEqual(parseReference("0400"), { bank: null, address: 0x0400 });
    assert.deepEqual(parseReference("bank1:0xD000"), { bank: "bank1", address: 0xD000 });
    assert.equal(parseReference("HL"), undefined);
    assert.equal(parseReference("TEXT_PAGE"), undefined);
    assert.equal(parseReference("0x10000"), undefined, "past the CPU's 64K");
});

test("find patterns are hex bytes with wildcards, or text in quotes", () => {
    assert.deepEqual(parsePattern("A9 ?? 20"), [{ value: 0xA9, mask: 0xFF }, { value: 0, mask: 0 }, { value: 0x20, mask: 0xFF }]);
    assert.deepEqual(parsePattern("a920"), [{ value: 0xA9, mask: 0xFF }, { value: 0x20, mask: 0xFF }]);
    assert.deepEqual(parsePattern('"HI"'), [{ value: 0x48, mask: 0x7F }, { value: 0x49, mask: 0x7F }]);
    assert.equal(typeof parsePattern("A9 2"), "string");
    assert.equal(typeof parsePattern("ZZ"), "string");
    assert.equal(typeof parsePattern(""), "string");
});

test("find wraps around, skips unreadable bytes and matches text with bit 7 either way", () => {
    const bytes = Uint8Array.from([0xC8, 0xC9, 0x00, 0x48, 0x49, 0x00, 0xA9, 0x05]);
    const readable = new Uint8Array(bytes.length).fill(1);
    const text = parsePattern('"HI"') as PatternByte[];
    assert.equal(findPattern(bytes, readable, text, 0, false), 0, "Apple II text, with bit 7 set");
    assert.equal(findPattern(bytes, readable, text, 1, false), 3);
    assert.equal(findPattern(bytes, readable, text, 4, false), 0, "wraps to the start");
    assert.equal(findPattern(bytes, readable, text, 2, true), 0, "backward");
    assert.equal(findPattern(bytes, readable, text, -1, true), 3, "backward from before the start wraps to the end");
    assert.equal(findPattern(bytes, readable, text, 7, false), 0, "forward from past the end wraps to the start");
    assert.equal(findPattern(bytes, readable, parsePattern("A9 ??") as PatternByte[], 0, false), 6);
    // A five-byte pattern fits from 0 to 3: from 6 forward wraps to 0, and from 6 backward starts at 3.
    const zeros = new Uint8Array(8), all = new Uint8Array(8).fill(1);
    const five = parsePattern("00 00 00 00 00") as PatternByte[];
    assert.equal(findPattern(zeros, all, five, 6, false), 0, "past the last fit, forward wraps to the start");
    assert.equal(findPattern(zeros, all, five, 6, true), 3, "past the last fit, backward is the last fit");
    readable[6] = 2;
    assert.equal(findPattern(bytes, readable, parsePattern("A9 ??") as PatternByte[], 0, false), -1);
});

test("the text column shows seven-bit text, and typing keeps bit 7", () => {
    assert.equal(textOf(0xC1), "A");
    assert.equal(textOf(0x41), "A");
    assert.equal(textOf(0x0D), ".");
    assert.equal(typedText("B", 0xC1), 0xC2);
    assert.equal(typedText("B", 0x00), 0x42);
    assert.equal(typedText("é", 0x00), undefined);
});

test("the inspector reads a byte and the words in each order", () => {
    const bytes = Uint8Array.from([0xED, 0xFD]);
    const readable = Uint8Array.from([1, 1]);
    const rows = Object.fromEntries(inspect(bytes, readable, 0).map(row => [row.label, row.value]));
    assert.equal(rows["Byte"], "$ED");
    assert.equal(rows["Signed"], "-19");
    assert.equal(rows["Binary"], "%1110 1101");
    assert.equal(rows["Word, low first"], "$FDED  65005  -531");
    assert.equal(rows["Word, high first"], "$EDFD  60925  -4611");
    assert.equal(inspect(bytes, readable, 1).length, 5, "no word past the end");
    assert.deepEqual(inspect(bytes, Uint8Array.from([2, 1]), 0), [{ label: "Byte", value: "unreadable" }]);
});

// The Apple II's character set as the debugger describes it: inverse below $40, flashing to $7F, then normal, with
// lowercase at $E0.
function appleText(): string {
    let text = "";
    for (let code = 0; code < 256; code++) {
        const glyph = code >= 0x40 && code < 0x80 ? (code & 0x3F) | 0x80 : code;
        const low = glyph & 0x7F;
        text += String.fromCharCode((low & 0x60) === 0 ? low + 0x40 : low);
    }
    return text;
}

test("with the machine's characters, typing keeps the byte's style and find matches any style", () => {
    const apple = appleText();
    assert.equal(textOf(0x01, apple), "A");
    assert.equal(textOf(0xE1, apple), "a");
    // Inverse, flashing and normal text each look different.
    const style = (code: number) => code < 0x40 ? 0 : code < 0x80 ? 1 : 2;
    const looksSame = (first: number, second: number) => style(first) === style(second);
    assert.equal(typedText("A", 0xA0, apple, looksSame), 0xC1, "normal text stays normal");
    assert.equal(typedText("A", 0x20, apple, looksSame), 0x01, "inverse stays inverse");
    assert.equal(typedText("A", 0x60, apple, looksSame), 0x41, "flashing stays flashing");
    assert.equal(typedText("A", 0x20, apple, () => true), 0x41, "where both look the same, the ASCII code");
    assert.equal(typedText("a", 0xA0, apple, looksSame), 0xE1);
    assert.equal(typedText("é", 0xA0, apple, looksSame), undefined);
    const graphics = apple.slice(0, 0x80) + "\0".repeat(0x80);
    assert.equal(textOf(0x80, graphics), ".", "graphics show as a dot");
    const graphicsRows = inspect(Uint8Array.of(0x80), Uint8Array.of(1), 0, graphics);
    assert.equal(graphicsRows.find(row => row.label === "Text")?.value, "graphics");
    assert.equal(typedText("A", 0x80, graphics), 0x01, "a code from the other half when this half has none");

    const pattern = parsePattern('"HI"', apple) as PatternByte[];
    const bytes = Uint8Array.from([0x00, 0x08, 0x09, 0x00, 0xC8, 0xC9]);
    const readable = new Uint8Array(bytes.length).fill(1);
    assert.equal(findPattern(bytes, readable, pattern, 0, false), 1, "inverse HI");
    assert.equal(findPattern(bytes, readable, pattern, 2, false), 4, "normal HI");
    assert.equal(parsePattern('"~"', graphics.replace("~", "\0")), "The machine has no ~ character.");
    assert.equal(copyText(bytes, readable, 1, 2, true, apple), "HI");
    assert.equal(Object.fromEntries(inspect(bytes, readable, 1, apple).map(row => [row.label, row.value]))["Text"], "H");
});

test("an address is named by the closest label before it", () => {
    const labels = [{ address: 0x0300, name: "START" }, { address: 0x0310, name: "MSG" }];
    assert.equal(labelOf(labels, 0x0300), "START");
    assert.equal(labelOf(labels, 0x0305), "START+5");
    assert.equal(labelOf(labels, 0x0320), "MSG+16");
    assert.equal(labelOf(labels, 0x02FF), undefined);
    assert.equal(labelOf(labels, 0x0411), undefined, "too far past any label");
});

test("a RAM search reads values and narrows by how bytes changed", () => {
    assert.equal(parseByte("$1F"), 0x1F);
    assert.equal(parseByte("0x1f"), 0x1F);
    assert.equal(parseByte("%101"), 5);
    assert.equal(parseByte("31"), 31);
    assert.equal(parseByte("-1"), 0xFF);
    assert.equal(typeof parseByte("256"), "string");
    assert.equal(typeof parseByte("lives"), "string");

    const readable = Uint8Array.from([1, 1, 1, 1, 2]);
    const start = searchStart(readable, Uint8Array.from([0, 0, 1, 0, 0]));
    assert.deepEqual(start, [0, 1, 3], "readable RAM only");
    const before = Uint8Array.from([3, 5, 9, 7, 0]), now = Uint8Array.from([2, 5, 9, 8, 0]);
    assert.deepEqual(narrowSearch(start, before, now, readable, "changed"), [0, 3]);
    assert.deepEqual(narrowSearch(start, before, now, readable, "unchanged"), [1]);
    assert.deepEqual(narrowSearch(start, before, now, readable, "increased"), [3]);
    assert.deepEqual(narrowSearch(start, before, now, readable, "decreased"), [0]);
    assert.deepEqual(narrowSearch(start, before, now, readable, "equal", 5), [1]);
    assert.deepEqual(narrowSearch(start, before, now, readable, "notEqual", 5), [0, 3]);
    assert.deepEqual(narrowSearch(start, before, now, Uint8Array.from([2, 1, 1, 1, 2]), "decreased"), [], "a byte that cannot be read drops out");
});

test("a RAM search for words reads them in the CPU's byte order", () => {
    assert.equal(parseValue("$1F00", 2), 0x1F00);
    assert.equal(parseValue("7936", 2), 7936);
    assert.equal(parseValue("-1", 2), 0xFFFF);
    assert.equal(parseValue("%1", 2), 1);
    assert.equal(typeof parseValue("65536", 2), "string");
    assert.equal(typeof parseValue("$12345", 2), "string");
    assert.equal(parseValue("$1F"), 0x1F, "a byte by default");
    assert.equal(typeof parseValue("$1F00"), "string");

    const data = Uint8Array.from([0x34, 0x12, 0x00]);
    assert.equal(valueAt(data, 0, 2), 0x1234, "low byte first");
    assert.equal(valueAt(data, 0, 2, true), 0x3412, "high byte first, as on the 6809");
    assert.equal(valueAt(data, 1), 0x12);

    // A word needs both bytes readable and writable, and one starting at the last byte has no second.
    const readable = Uint8Array.from([1, 1, 1, 2, 1, 1]);
    const start = searchStart(readable, Uint8Array.from([0, 0, 0, 0, 0, 1]), 2);
    assert.deepEqual(start, [0, 1]);
    // Bytes 00 01 00 become 00 02 00: low byte first, the word at 0 rises from $0100 to $0200; high byte first, the
    // word at 1 does.
    const before = Uint8Array.from([0x00, 0x01, 0x00, 0, 0, 0]), now = Uint8Array.from([0x00, 0x02, 0x00, 0, 0, 0]);
    assert.deepEqual(narrowSearch(start, before, now, readable, "equal", 0x0200, 2), [0]);
    assert.deepEqual(narrowSearch(start, before, now, readable, "equal", 0x0200, 2, true), [1]);
    assert.deepEqual(narrowSearch(start, before, now, readable, "increased", 0, 2), [0, 1]);
    assert.deepEqual(narrowSearch([1, 2], before, now, readable, "changed", 0, 2), [1], "a word with an unreadable byte drops out");
});

test("copying gives hex or text, with unreadable bytes marked", () => {
    const bytes = Uint8Array.from([0xC8, 0xC9, 0x00]);
    assert.equal(copyText(bytes, Uint8Array.from([1, 1, 2]), 0, 2, false), "C8 C9 ??");
    assert.equal(copyText(bytes, Uint8Array.from([1, 1, 2]), 0, 2, true), "HI.");
});

type Listener = (event: Record<string, unknown>) => void;

/** A stand-in for the DOM pieces the page uses. */
class Element {
    readonly listeners = new Map<string, Listener[]>();
    readonly style: Record<string, string> = {};
    readonly dataset: Record<string, string> = {};
    readonly classes = new Set<string>();
    readonly classList = {
        toggle: (name: string, on?: boolean) => { if (on ?? !this.classes.has(name)) this.classes.add(name); else this.classes.delete(name); },
        add: (name: string) => { this.classes.add(name); },
        remove: (name: string) => { this.classes.delete(name); },
        contains: (name: string) => this.classes.has(name)
    };
    hidden = true;
    textContent = "";
    innerHTML = "";
    className = "";
    value = "";
    scrollTop = 0;
    clientHeight = 200;
    addEventListener(name: string, listener: Listener): void {
        this.listeners.set(name, [...(this.listeners.get(name) ?? []), listener]);
    }
    dispatch(name: string, event: Record<string, unknown>): void {
        for (const listener of this.listeners.get(name) ?? []) listener(event);
    }
    focus(): void { /* nothing to focus */ }
    select(): void { /* nothing to select */ }
    querySelectorAll(): Element[] { return []; }
    getBoundingClientRect(): { left: number; width: number } { return { left: 0, width: 256 }; }
}

/** Runs the page's script with fake elements, recording what it posts to the extension. */
/** The page's window, which takes the mouse's back and forward buttons. */
function window(page: ReturnType<typeof runPage>): Element {
    return page.window;
}

function runPage() {
    const html = memoryEditorHtml("NONCE");
    const open = '<script nonce="NONCE">';
    const script = html.slice(html.indexOf(open) + open.length, html.lastIndexOf("</script>"));
    const elements = new Map<string, Element>();
    const window = new Element();
    const posted: Record<string, unknown>[] = [];
    const context = createContext({
        document: { getElementById: (id: string) => elements.get(id) ?? elements.set(id, new Element()).get(id) },
        window,
        atob: (text: string) => Buffer.from(text, "base64").toString("latin1"),
        setTimeout, clearTimeout,
        // Messages cross into this realm as the webview would send them, as JSON.
        acquireVsCodeApi: () => ({ postMessage: (message: Record<string, unknown>) => posted.push(JSON.parse(JSON.stringify(message))) })
    });
    new Script(script).runInContext(context);
    const send = (data: Record<string, unknown>) => window.dispatch("message", { data });
    // Keys run one at a time behind promises, so a few turns let each finish.
    const settle = async () => { for (let turn = 0; turn < 5; turn++) await new Promise(resolve => setImmediate(resolve)); };
    const key = (key: string, extra: Record<string, unknown> = {}) => elements.get("grid")!.dispatch("keydown", {
        key, ctrlKey: false, metaKey: false, shiftKey: false, altKey: false,
        preventDefault: () => undefined, stopPropagation: () => undefined, ...extra
    });
    // The first message of a kind the page posted, taken from the list.
    const take = (type: string) => {
        const index = posted.findIndex(message => message.type === type);
        assert.ok(index >= 0, `the page posts a ${type}`);
        return posted.splice(index, 1)[0];
    };
    return { elements, posted, send, settle, key, take, context, window };
}

test("the page's script parses", () => {
    const html = memoryEditorHtml("NONCE");
    const open = '<script nonce="NONCE">';
    assert.doesNotThrow(() => new Script(html.slice(html.indexOf(open) + open.length, html.lastIndexOf("</script>"))));
});

test("the page reads what it shows, writes a byte at its second hex digit, and undoes it", async () => {
    const page = runPage();
    assert.deepEqual(page.posted.shift(), { type: "ready" });
    page.send({ type: "init", address: 0x0400, info: { bank: "aux", label: "Auxiliary RAM", readOnly: false } });
    const reads = page.posted.splice(0).filter(message => message.type === "read");
    assert.ok(reads.length > 0, "the page reads the rows it shows");
    for (const read of reads) {
        const count = read.count as number;
        const data = Buffer.alloc(count, 0xA0);
        page.send({ type: "reply", id: read.id, result: { data: data.toString("base64"), unreadable: [] } });
    }
    await page.settle();
    page.posted.splice(0);
    assert.match(page.elements.get("inspector")!.innerHTML, /aux:\$0400/);
    assert.match(page.elements.get("inspector")!.innerHTML, /\$A0/);

    page.key("4");
    await page.settle();
    assert.equal(page.posted.length, 0, "one digit writes nothing");
    page.key("1");
    await page.settle();
    const write = page.take("write");
    assert.deepEqual({ type: write.type, offset: write.offset, data: write.data }, { type: "write", offset: 0x0400, data: [0x41] });
    page.send({ type: "reply", id: write.id, result: { bytesWritten: 1 } });
    await page.settle();
    assert.match(page.elements.get("inspector")!.innerHTML, /aux:\$0401/, "the cursor moves on");

    // The page reads back what it wrote, and shows what memory holds, which can differ.
    const readBack = page.take("read");
    assert.equal(readBack.offset, 0x0400);
    const held = Buffer.alloc(readBack.count as number, 0xA0);
    held[0] = 0x40;
    page.send({ type: "reply", id: readBack.id, result: { data: held.toString("base64"), unreadable: [] } });
    await page.settle();
    page.key("ArrowLeft");
    await page.settle();
    assert.match(page.elements.get("inspector")!.innerHTML, /\$40/, "the byte read back shows");

    page.key("z", { ctrlKey: true });
    await page.settle();
    const undo = page.take("write");
    assert.deepEqual({ offset: undo.offset, data: undo.data }, { offset: 0x0400, data: [0xA0] });
    page.send({ type: "reply", id: undo.id, result: { bytesWritten: 1 } });
    await page.settle();
    const undoneBack = page.take("read");
    page.send({ type: "reply", id: undoneBack.id, result: { data: Buffer.alloc(undoneBack.count as number, 0xA0).toString("base64"), unreadable: [] } });
    await page.settle();

    // A refused write puts the byte back and says why.
    page.key("F");
    page.key("F");
    await page.settle();
    const refused = page.take("write");
    page.send({ type: "reply", id: refused.id, error: "$0400 reads the system ROM now, not RAM." });
    await page.settle();
    assert.equal(page.elements.get("status")!.textContent, "$0400 reads the system ROM now, not RAM.");
    assert.match(page.elements.get("inspector")!.innerHTML, /\$A0/);
});

test("moving while a write waits keeps the cursor where it went, and drops a first digit typed before the move", async () => {
    const page = runPage();
    page.posted.splice(0);
    page.send({ type: "init", address: 0x0400, info: { bank: null, label: "Memory", readOnly: false } });
    for (const read of page.posted.splice(0).filter(message => message.type === "read")) {
        page.send({ type: "reply", id: read.id, result: { data: Buffer.alloc(read.count as number, 0x20).toString("base64"), unreadable: [] } });
    }
    await page.settle();
    page.posted.splice(0);

    page.key("4");
    page.key("1");
    await page.settle();
    const write = page.take("write");
    page.key("ArrowDown");
    page.send({ type: "reply", id: write.id, result: { bytesWritten: 1 } });
    await page.settle();
    assert.match(page.elements.get("inspector")!.innerHTML, /\$0410/, "the write does not pull the cursor back to $0401");

    // Answers the reads waiting, such as a write's read-back, leaving the writes.
    const answerReads = async () => {
        for (let index = page.posted.findIndex(message => message.type === "read"); index >= 0; index = page.posted.findIndex(message => message.type === "read")) {
            const read = page.posted.splice(index, 1)[0];
            page.send({ type: "reply", id: read.id, result: { data: Buffer.alloc(read.count as number, 0x20).toString("base64"), unreadable: [] } });
        }
        await page.settle();
    };
    // Keys pressed while a write waits, before a move, are dropped rather than written where the cursor went.
    page.key("4");
    page.key("2");
    page.key("4");
    page.key("3");
    await page.settle();
    await answerReads();
    const next = page.take("write");
    assert.equal(next.offset, 0x0410);
    page.key("ArrowDown");
    page.send({ type: "reply", id: next.id, result: { bytesWritten: 1 } });
    await page.settle();
    await answerReads();
    assert.equal(page.posted.filter(message => message.type === "write").length, 0, "43 is not written at $0420");
    assert.match(page.elements.get("inspector")!.innerHTML, /\$0420/);

    // Typing on without moving steps on byte by byte.
    page.posted.splice(0);
    page.key("4");
    page.key("4");
    page.key("4");
    page.key("5");
    await page.settle();
    await answerReads();
    const first = page.take("write");
    page.send({ type: "reply", id: first.id, result: { bytesWritten: 1 } });
    await page.settle();
    await answerReads();
    const second = page.take("write");
    assert.deepEqual({ offset: second.offset, data: second.data }, { offset: 0x0421, data: [0x45] });
    page.send({ type: "reply", id: second.id, result: { bytesWritten: 1 } });
    await page.settle();
    await answerReads();

    // In the text column, too, a character typed before a move is not written where the cursor went.
    page.key("Tab");
    page.key("A");
    page.key("B");
    await page.settle();
    await answerReads();
    const typed = page.take("write");
    assert.equal(typed.offset, 0x0422);
    page.key("ArrowDown");
    page.send({ type: "reply", id: typed.id, result: { bytesWritten: 1 } });
    await page.settle();
    await answerReads();
    assert.equal(page.posted.filter(message => message.type === "write").length, 0, "B is not written at $0432");

    // HTML from labels is escaped inside attributes, quotes too.
    assert.equal((page.context as { escapeText(text: string): string }).escapeText('START" data-go="4096'), "START&quot; data-go=&quot;4096");
});

test("a snapshot whose read fails is not taken, and says why", async () => {
    const page = runPage();
    page.posted.splice(0);
    page.send({ type: "init", address: 0x0400, info: { bank: "slot6", label: "Slot 6 ROM", readOnly: true } });
    for (const read of page.posted.splice(0).filter(message => message.type === "read")) {
        page.send({ type: "reply", id: read.id, result: { data: Buffer.alloc(read.count as number, 0x20).toString("base64"), unreadable: [] } });
    }
    await page.settle();
    page.posted.splice(0);

    page.send({ type: "test", id: 1, actions: [{ snapshot: true }] });
    await page.settle();
    const all = page.take("read");
    page.send({ type: "reply", id: all.id, error: "The machine has no memory bank named slot6." });
    await page.settle();
    assert.equal(page.elements.get("status")!.textContent, "The machine has no memory bank named slot6.");
    assert.doesNotMatch(page.elements.get("compareWith")!.innerHTML, /snapshot/, "there is no snapshot to compare with");
});

// Answers the page's reads with a byte everywhere, or by offset, and its other requests with what they name.
// The marks the page sent.
const marksSent: Record<string, unknown>[] = [];

// The writes drive answered, the assemble requests, and the questions the page asked with the answers given.
const writesSent: Record<string, unknown>[] = [];
const assemblesSent: Record<string, unknown>[] = [];
const confirmsSent: Record<string, unknown>[] = [];
let assembleReply: Record<string, unknown> = { cancelled: true };
let confirmChoice: string | null = null;
// What the input box and the clipboard give the page.
let inputReply: Record<string, unknown> = { cancelled: true };
const inputsSent: Record<string, unknown>[] = [];
let clipboardText = "";
// What Copy as copied and the choice it was given, and what Save and Load were sent and give back.
const copiesSent: string[] = [];
let pickReply: Record<string, unknown> = { cancelled: true };
const savesSent: Record<string, unknown>[] = [];
let saveReply: Record<string, unknown> = { cancelled: true };
let loadReply: Record<string, unknown> = { cancelled: true };
// The inspect requests the page sent.
const inspectsSent: Record<string, unknown>[] = [];
// The Decode from here starts the page asked about after a mark.
const startsSent: Record<string, unknown>[] = [];

// The spaces the page asked to show in an editor's place.
const switchesSent: Record<string, unknown>[] = [];

// The breakpoints the page set or took away, and the instructions it looked for.
const breakpointsSent: Record<string, unknown>[] = [];
const findsSent: Record<string, unknown>[] = [];

// Where the fake debugger says PC is.
let pcNow = 0x0300;

// The starts each listing request the page sent asked for.
const listingStarts: number[][] = [];

function answer(
    page: ReturnType<typeof runPage>,
    fill: (offset: number) => number,
    readOnly: (offset: number) => boolean = () => false,
    labels: { address: number; name: string }[] = [{ address: 0x0400, name: "TEXT_PAGE" }]
): void {
    for (const sent of page.posted.splice(0)) {
        if (sent.type === "read") {
            const offset = sent.offset as number, count = sent.count as number;
            const data = Buffer.alloc(count);
            for (let index = 0; index < count; index++) data[index] = fill(offset + index);
            const runs = [];
            for (let index = 0; index < count; index++) {
                if (readOnly(offset + index)) runs.push({ offset: index, count: 1 });
            }
            page.send({ type: "reply", id: sent.id, result: { data: data.toString("base64"), unreadable: [], readOnly: runs } });
        } else if (sent.type === "labels") {
            page.send({ type: "reply", id: sent.id, result: { labels } });
        } else if (sent.type === "characters") {
            page.send({ type: "reply", id: sent.id, result: {} });
        } else if (sent.type === "listing") {
            // An instruction, a jump to a label, and data, from the address asked for, or nothing from $E000, as
            // past a bank's end; the starts asked for are kept.
            listingStarts.push(sent.starts as number[]);
            const at = sent.address as number;
            page.send({
                type: "reply", id: sent.id, result: {
                    lines: at >= 0xE000 ? [] : [
                        { address: at, size: 2, text: "LDA #$C1", kind: "code", label: "START", target: null, path: "C:/src/hello.s", line: 3 },
                        { address: at + 2, size: 3, text: "JMP START", kind: "code", label: null, target: at, path: "C:/src/hello.s", line: 4 },
                        { address: at + 5, size: 2, text: ".byte $01, $02", kind: "data", label: "TABLE", target: null, path: null, line: null },
                        { address: at + 7, size: 1, text: "RTS", kind: "code", guess: true, label: null, target: null, path: null, line: null, comment: "Returns", breakpoints: [7] }
                    ]
                }
            });
        } else if (sent.type === "assemble") {
            assemblesSent.push(sent);
            page.send({ type: "reply", id: sent.id, result: assembleReply });
        } else if (sent.type === "input") {
            inputsSent.push(sent);
            page.send({ type: "reply", id: sent.id, result: inputReply });
        } else if (sent.type === "paste") {
            page.send({ type: "reply", id: sent.id, result: { text: clipboardText } });
        } else if (sent.type === "pick") {
            page.send({ type: "reply", id: sent.id, result: pickReply });
        } else if (sent.type === "copy") {
            copiesSent.push(String(sent.text));
            page.send({ type: "reply", id: sent.id, result: null });
        } else if (sent.type === "save") {
            savesSent.push(sent);
            page.send({ type: "reply", id: sent.id, result: saveReply });
        } else if (sent.type === "load") {
            page.send({ type: "reply", id: sent.id, result: loadReply });
        } else if (sent.type === "confirm") {
            confirmsSent.push(sent);
            page.send({ type: "reply", id: sent.id, result: { choice: confirmChoice } });
        } else if (sent.type === "mark") {
            marksSent.push(sent);
            page.send({ type: "reply", id: sent.id, result: { path: "C:/src/hello.hints.json", address: sent.address, count: sent.count } });
        } else if (sent.type === "breakpoint") {
            breakpointsSent.push(sent);
            page.send({ type: "reply", id: sent.id, result: { status: `Breakpoint at $${hex(Number(sent.address), 4)}.` } });
        } else if (sent.type === "map") {
            page.send({
                type: "reply", id: sent.id, result: {
                    regions: [{ start: 0x0000, length: 0x0100, name: "Zero page", kind: "ram" }, { start: 0x0400, length: 0x0400, name: "Text page 1", kind: "video" }],
                    areas: [
                        { start: 0x0000, length: 0xC000, name: "main RAM", kind: "ram", mapped: true },
                        { start: 0xC000, length: 0x1000, name: "I/O", kind: "io", mapped: false },
                        { start: 0xD000, length: 0x3000, name: "system ROM", kind: "rom", mapped: false, written: true }
                    ]
                }
            });
        } else if (sent.type === "inspect") {
            const address = Number(sent.address);
            inspectsSent.push(sent);
            page.send({
                type: "reply", id: sent.id, result: address === 0x0300
                    ? {
                        address, region: null, label: "READY", offset: 0, summary: "Bit 7 is set when ready.", values: [],
                        bits: [{ bit: 7, name: null, meaning: "is set when ready" }, { bit: 0, name: "BUSY", meaning: "The busy bit." }],
                        instruction: { text: "BNE READY", size: 2, cycles: 2, cyclesTaken: 3, flags: "none", summary: "Branches when Z is clear." },
                        references: [{ address: 0x0310, text: "BIT READY", label: "WAIT+2", kind: "reads" }],
                        referenceCount: 34
                    }
                    : address === 0x0024
                    ? { address, region: "Zero page", kind: "ram", detail: null, mapped: "Reads and writes main RAM", label: "CH", offset: 0, summary: "The cursor's column.", path: null, line: null, values: [] }
                    : { address, region: "Text page 1", kind: "video", detail: "row 0, column 3", mapped: null, label: "START", offset: 3, summary: "Starts it.", path: "C:/src/hello.s", line: 4, values: [{ label: "Float, 5 bytes", value: "1" }] }
            });
        } else if (sent.type === "find") {
            findsSent.push(sent);
            page.send({ type: "reply", id: sent.id, result: { address: 0x0310, size: 3, text: "STA SPKR" } });
        } else if (sent.type === "starts") {
            // Each start is one byte here: those in the marked bytes go.
            const address = Number(sent.address), end = address + Number(sent.count);
            startsSent.push(sent);
            page.send({ type: "reply", id: sent.id, result: { starts: (sent.starts as number[]).filter(start => start < address || start >= end) } });
        } else if (sent.type === "goto") {
            // PC is wherever the test says the CPU stopped; anything else is hex.
            const text = String(sent.text);
            page.send({ type: "reply", id: sent.id, result: { address: text === "PC" ? pcNow : parseInt(text.replace(/^\$/, ""), 16) } });
        } else if (sent.type === "numbers") {
            // AppleSoft's five bytes: 1000 is $8A $7A $00 $00 $00.
            page.send({ type: "reply", id: sent.id, result: { formats: sent.value === "1000" ? [{ label: "Float, 5 bytes", bytes: [0x8A, 0x7A, 0, 0, 0] }] : [] } });
        } else if (sent.type === "bookmark") {
            page.send({ type: "reply", id: sent.id, result: { bookmarks: [{ address: 0x0400, name: String(sent.name ?? "here") }] } });
        } else if (sent.type === "bookmarks") {
            page.send({ type: "reply", id: sent.id, result: { bookmarks: [{ address: 0x0400, name: "TEXT_PAGE" }], address: 0x0400, name: "TEXT_PAGE" } });
        } else if (sent.type === "banks") {
            page.send({
                type: "reply", id: sent.id, result: {
                    banks: [{ memoryReference: "aux:0x0000", label: "Auxiliary RAM (aux)" }],
                    spaces: [{ name: null, label: "Memory as the CPU maps it now" }, { name: "aux", label: "Auxiliary RAM (aux)" }]
                }
            });
        } else if (sent.type === "switch") {
            switchesSent.push(sent);
            page.send({ type: "reply", id: sent.id, result: null });
        } else if (sent.type === "readOther") {
            // Auxiliary RAM differs from what the editor shows only at $0481.
            const data = Buffer.alloc(sent.count as number);
            for (let index = 0; index < data.length; index++) data[index] = fill(index) ^ (index === 0x0481 ? 0xFF : 0);
            page.send({ type: "reply", id: sent.id, result: { data: data.toString("base64"), unreadable: [{ offset: 0x0490, count: 16 }] } });
        }
    }
}

test("tooltips are drawn in the page, taking over an element's title", async () => {
    const page = runPage();
    const attributes = new Map<string, string>([["title", "Snapshot: keep a copy of every byte now"]]);
    const button = {
        dataset: {} as Record<string, string>, isConnected: true,
        hasAttribute: (name: string) => attributes.has(name),
        getAttribute: (name: string) => attributes.get(name) ?? null,
        setAttribute: (name: string, value: string) => { attributes.set(name, value); },
        removeAttribute: (name: string) => { attributes.delete(name); },
        getBoundingClientRect: () => ({ left: 10, top: 10, bottom: 30, width: 24 }),
        closest: () => button
    };
    page.window.dispatch("mouseover", { target: button });
    assert.equal(attributes.has("title"), false, "the browser shows no tooltip of its own");
    assert.equal(attributes.get("aria-description"), "Snapshot: keep a copy of every byte now");
    await new Promise(resolve => setTimeout(resolve, 600));
    const tip = page.elements.get("tip")!;
    assert.deepEqual([tip.hidden, tip.textContent], [false, "Snapshot: keep a copy of every byte now"]);
    page.window.dispatch("mousedown", {});
    assert.equal(tip.hidden, true, "a click hides it");
});

test("the label, byte and text columns collapse into strips and expand again", async () => {
    const page = runPage();
    page.send({ type: "init", address: 0x0402, info: { bank: null, label: "Memory", readOnly: false } });
    for (let round = 0; round < 3; round++) {
        answer(page, () => 0xA0);
        await page.settle();
    }
    const fold = (name: string) => page.window.dispatch("click", { target: { closest: (selector: string) => selector === "[data-fold]" ? { dataset: { fold: name } } : null } });
    // The headings that collapse their columns are buttons, which Tab reaches and Enter or Space press.
    assert.match(page.elements.get("head")!.innerHTML, /<button class="hex heading" data-fold="bytes" aria-label="Collapse the Bytes column">/);
    fold("label");
    fold("bytes");
    const heading = page.elements.get("head")!.innerHTML, html = page.elements.get("rows")!.innerHTML;
    assert.match(heading, /<span class="fold" data-strip="label"><\/span><span class="fold" data-strip="bytes"><\/span><span class="txt">/);
    assert.match(html, /<span class="addr">0400<\/span><span class="fold"><\/span><span class="fold"><\/span><span class="txt">/);
    assert.doesNotMatch(html, /class="hex"/);
    // With the bytes collapsed, the cursor is in the text, and stays there when a label is clicked.
    page.elements.get("grid")!.dispatch("mousedown", {
        button: 0, shiftKey: false, preventDefault: () => undefined,
        target: { closest: (selector: string) => selector === ".lab[data-a]" ? { dataset: { a: "1026" } } : null }
    });
    page.key("ArrowRight");
    assert.match(page.elements.get("rows")!.innerHTML, /cur on" data-o="1027" data-t="1"/);
    fold("bytes");
    assert.match(page.elements.get("rows")!.innerHTML, /<span class="hex">/);
    // The bytes and the text cannot both collapse, as the cursor edits in one of them.
    fold("text");
    fold("bytes");
    assert.match(page.elements.get("rows")!.innerHTML, /<span class="hex">/, "the bytes stay");
    // With the text collapsed, Tab leaves the grid rather than typing into the hidden text.
    page.key("Tab");
    const lists = { frozen: new Map<number, number>(), watched: new Set<string>() };
    assert.equal((await drive(page, [], () => 0xA0, lists)).pane, "hex");
    fold("text");
});

test("the inspector starts beside the bytes, and its dock buttons move it under them and back", async () => {
    const page = runPage();
    page.send({ type: "init", address: 0x0400, info: { bank: null, label: "Memory", readOnly: false } });
    const docks = () => page.elements.get("docks")!.innerHTML;
    assert.match(docks(), /codicon-layout-sidebar-right" disabled aria-pressed="true"/);
    assert.match(docks(), /codicon-layout-panel-dock" data-dock="bottom"/);
    const dockTo = (place: string) => page.elements.get("side")!.dispatch("click", { target: { closest: (selector: string) => selector === "[data-dock]" ? { dataset: { dock: place } } : null } });
    dockTo("bottom");
    assert.match(docks(), /codicon-layout-sidebar-right-dock" data-dock="right"/);
    assert.match(docks(), /codicon-layout-panel" disabled aria-pressed="true"/);
    dockTo("right");
    assert.match(docks(), /codicon-layout-panel-dock" data-dock="bottom"/);
});

test("labels show in the gutter and the inspector", async () => {
    const page = runPage();
    page.send({ type: "init", address: 0x0402, info: { bank: null, label: "Memory", readOnly: false } });
    for (let round = 0; round < 3; round++) {
        answer(page, () => 0xA0);
        await page.settle();
    }
    assert.match(page.elements.get("rows")!.innerHTML, /class="lab" style="width:10ch" data-a="1024" title="TEXT_PAGE at \$0400&#10;Click to go to \$0400.">TEXT_PAGE</);
    // The headings name the columns, the label column's at its width.
    const heading = page.elements.get("head")!.innerHTML;
    assert.match(heading, /<span class="addr"[^>]*>Addr<\/span><span class="lab" style="width:10ch"><button class="heading" data-fold="label" aria-label="Collapse the Label column" title="The first label starting in each row[^"]*">Label<\/button><button class="tog codicon codicon-list-tree" data-toggle="align" aria-pressed="false" aria-label="Align to labels"/);
    assert.match(heading, />00<\/span>.*>0F<\/span><\/button><span class="txt"><button class="heading" data-fold="text" aria-label="Collapse the Text column" title="The bytes as text\. Click to collapse the column\.">Text</);
    assert.match(page.elements.get("rows")!.innerHTML, /class=" lb" data-o="1024" title="TEXT_PAGE"/);
    assert.match(page.elements.get("inspector")!.innerHTML, /\$0402  TEXT_PAGE\+2/);
    // Clicking a name goes to its label's byte.
    page.elements.get("grid")!.dispatch("mousedown", {
        button: 0, shiftKey: false, preventDefault: () => undefined,
        target: { closest: (selector: string) => selector === ".lab[data-a]" ? { dataset: { a: "1024" } } : null }
    });
    await page.settle();
    assert.match(page.elements.get("inspector")!.innerHTML, /class="where">\$0400  TEXT_PAGE</);
});

test("rows aligned to labels start where each label does, and moving keeps the column", async () => {
    const page = runPage();
    const labels = [{ address: 0x0400, name: "TEXT_PAGE" }, { address: 0x0405, name: "MSG", kind: "data", size: 3 }];
    // The cursor's address, as the inspector shows it.
    const at = () => parseInt(/class="where">\$([0-9A-F]{4})/.exec(page.elements.get("inspector")!.innerHTML)![1], 16);
    page.send({ type: "init", address: 0x0402, info: { bank: null, label: "Memory", readOnly: false } });
    for (let round = 0; round < 3; round++) {
        answer(page, () => 0xA0, () => false, labels);
        await page.settle();
    }
    // Rows of 16 until asked, with the row's first label and how many more start in it, which its tooltip lists; the
    // gutter is wide enough for +1.
    assert.match(page.elements.get("rows")!.innerHTML,
        /<span class="lab" style="width:13ch" data-a="1024" title="TEXT_PAGE at \$0400&#10;MSG at \$0405, data, 3 bytes&#10;Click to go to \$0400."><span class="nm">TEXT_PAGE<\/span><span class="more" aria-label="1 more labels">&#8943;1</);
    // A label on data shades its bytes.
    assert.match(page.elements.get("rows")!.innerHTML, /class=" dt" data-o="1031"/);
    assert.match(page.elements.get("rows")!.innerHTML, /class="mid" data-o="1032"/);
    page.key("ArrowDown");
    assert.equal(at(), 0x0412);
    page.key("ArrowUp");
    // Align to labels is a toggle in the Label heading, which shows once there are labels.
    assert.match(page.elements.get("head")!.innerHTML, /data-toggle="align" aria-pressed="false"/);
    page.elements.get("head")!.dispatch("click", { target: { closest: (selector: string) => selector === "[data-toggle]" ? { dataset: { toggle: "align" } } : null } });
    assert.match(page.elements.get("head")!.innerHTML, /data-toggle="align" aria-pressed="true"/);
    // The marks on the bytes labels start at show until the Label heading's other toggle hides them.
    assert.match(page.elements.get("head")!.innerHTML, /data-toggle="marks" aria-pressed="true"/);
    page.elements.get("head")!.dispatch("click", { target: { closest: (selector: string) => selector === "[data-toggle]" ? { dataset: { toggle: "marks" } } : null } });
    assert.match(page.elements.get("head")!.innerHTML, /data-toggle="marks" aria-pressed="false"/);
    await page.settle();
    const html = page.elements.get("rows")!.innerHTML;
    assert.match(html, /<span class="addr">0400<\/span>/);
    assert.match(html, /<span class="addr">0405<\/span><span class="lab" style="width:13ch" data-a="1029" title="MSG at \$0405, data, 3 bytes&#10;Click to go to \$0405.">MSG</);
    // Row $0400 ends before MSG, and row $0405 leaves its first five columns empty.
    page.key("End");
    assert.equal(at(), 0x0404);
    page.key("ArrowDown");
    assert.equal(at(), 0x0405, "column 4 is before the row's first byte, so the cursor goes to it");
    page.key("ArrowDown");
    assert.equal(at(), 0x0415);
    page.key("Home");
    assert.equal(at(), 0x0410);
    page.key("ArrowUp");
    assert.equal(at(), 0x0405);
    page.key("ArrowUp");
    assert.equal(at(), 0x0404, "column 5 is past the row's last byte, so the cursor goes to it");
});

test("a stop leaves the view where it was scrolled to, away from the cursor", async () => {
    const page = runPage();
    page.send({ type: "init", address: 0x0402, info: { bank: null, label: "Memory", readOnly: false } });
    for (let round = 0; round < 3; round++) {
        answer(page, () => 0xA0);
        await page.settle();
    }
    const grid = page.elements.get("grid")!;
    // Partway into a row, too.
    grid.scrollTop = 0x200 * 20 + 3;
    page.send({ type: "stopped" });
    for (let round = 0; round < 3; round++) {
        answer(page, () => 0xA0);
        await page.settle();
    }
    assert.equal(grid.scrollTop, 0x200 * 20 + 3);
});

test("bytes that are not RAM are shaded and refuse typing", async () => {
    const page = runPage();
    page.send({ type: "init", address: 0x0400, info: { bank: null, label: "Memory", readOnly: false } });
    answer(page, () => 0, offset => offset >= 0x0400 && offset < 0x0410);
    await page.settle();
    page.posted.splice(0);
    assert.match(page.elements.get("rows")!.innerHTML, /class=" ro[^"]*" data-o="1024"/);
    page.key("1");
    await page.settle();
    assert.equal(page.posted.filter(message => message.type === "write").length, 0);
    assert.equal(page.elements.get("status")!.textContent, "$0400 is not RAM now, so it cannot be written.");
});

test("a stop colors the bytes that changed since the stop before", async () => {
    const page = runPage();
    page.send({ type: "init", address: 0x0400, info: { bank: null, label: "Memory", readOnly: false } });
    for (let round = 0; round < 3; round++) {
        answer(page, () => 0xA0);
        await page.settle();
    }
    assert.doesNotMatch(page.elements.get("rows")!.innerHTML, /chg/);

    page.send({ type: "stopped" });
    for (let round = 0; round < 3; round++) {
        answer(page, offset => offset === 0x0400 ? 0xC1 : 0xA0);
        await page.settle();
    }
    assert.match(page.elements.get("rows")!.innerHTML, /class=" chg lb[^"]*" data-o="1024"/);
    assert.doesNotMatch(page.elements.get("rows")!.innerHTML, /data-o="1025"[^>]*chg|chg[^"]*" data-o="1025"/);
    assert.match(page.elements.get("inspector")!.innerHTML, /Was<\/span> \$A0 <span class="meta">at the last stop/);
    // The highlight toggle turns the highlighting off and on.
    page.elements.get("highlight")!.dispatch("click", {});
    assert.doesNotMatch(page.elements.get("rows")!.innerHTML, /chg/);
    page.elements.get("highlight")!.dispatch("click", {});
    assert.match(page.elements.get("rows")!.innerHTML, /class=" chg lb[^"]*" data-o="1024"/);

    // A read between stops, such as after a memory event, keeps what the stop found.
    page.send({ type: "changed" });
    answer(page, offset => offset === 0x0400 ? 0xC1 : 0xA0);
    await page.settle();
    assert.match(page.elements.get("rows")!.innerHTML, /chg/);

    // The next stop compares with this one.
    page.send({ type: "stopped" });
    for (let round = 0; round < 3; round++) {
        answer(page, offset => offset === 0x0400 ? 0xC1 : 0xA0);
        await page.settle();
    }
    assert.doesNotMatch(page.elements.get("rows")!.innerHTML, /chg/);
});

test("a copy or freeze whose read fails acts on nothing, and says why", async () => {
    const page = runPage();
    page.send({ type: "init", address: 0x0400, info: { bank: null, label: "Memory", readOnly: false } });
    for (let round = 0; round < 3; round++) {
        answer(page, () => 0xA0);
        await page.settle();
    }
    page.key("End", { ctrlKey: true, shiftKey: true });
    for (let round = 0; round < 3; round++) {
        answer(page, () => 0xA0);
        await page.settle();
    }
    page.send({ type: "stopped" });
    for (let round = 0; round < 3; round++) {
        answer(page, () => 0xC1);
        await page.settle();
    }

    // The selection's start is out of view, so it is read again first, and that read fails.
    const fail = async () => {
        for (let round = 0; round < 5; round++) {
            await page.settle();
            for (const sent of page.posted.splice(0)) {
                if (sent.type === "read") page.send({ type: "reply", id: sent.id, error: "The debug session ended." });
                else if (sent.type === "copy" || sent.type === "freeze") throw new Error(`The page sent ${sent.type as string}.`);
            }
        }
    };
    page.key("c", { ctrlKey: true });
    await fail();
    assert.equal(page.elements.get("status")!.textContent, "The debug session ended.");
    page.send({ type: "test", id: 6, actions: [{ freeze: true }] });
    await fail();
    assert.equal(page.elements.get("status")!.textContent, "The debug session ended.");
});

test("copying after a stop copies what memory holds now, out of view too", async () => {
    const page = runPage();
    page.send({ type: "init", address: 0x0400, info: { bank: null, label: "Memory", readOnly: false } });
    for (let round = 0; round < 3; round++) {
        answer(page, () => 0xA0);
        await page.settle();
    }
    // The selection runs from $0400 to the end, so its start is far out of view.
    page.key("End", { ctrlKey: true, shiftKey: true });
    for (let round = 0; round < 3; round++) {
        answer(page, () => 0xA0);
        await page.settle();
    }

    page.send({ type: "stopped" });
    for (let round = 0; round < 3; round++) {
        answer(page, () => 0xC1);
        await page.settle();
    }
    page.key("c", { ctrlKey: true });
    let copied: Record<string, unknown> | undefined;
    for (let round = 0; round < 5 && copied === undefined; round++) {
        await page.settle();
        copied = page.posted.find(message => message.type === "copy");
        answer(page, () => 0xC1);
    }
    assert.ok(copied !== undefined, "the page copies");
    assert.equal(copied.text, Array(0x10000 - 0x0400).fill("C1").join(" "));
});

test("the machine changing while stopped reads the bytes and labels again", async () => {
    const page = runPage();
    page.send({ type: "init", address: 0x0400, info: { bank: null, label: "Memory", readOnly: false } });
    for (let round = 0; round < 3; round++) {
        answer(page, () => 0xA0);
        await page.settle();
    }
    page.posted.splice(0);

    page.send({ type: "invalidated" });
    await page.settle();
    const asked = page.posted.map(message => message.type);
    assert.ok(asked.includes("read"), "the bytes are read again");
    assert.ok(asked.includes("labels"), "and the labels");
    for (let round = 0; round < 3; round++) {
        answer(page, offset => offset === 0x0400 ? 0xC1 : 0xA0);
        await page.settle();
    }
    assert.match(page.elements.get("rows")!.innerHTML, /data-o="1024"[^>]*>C1</, "the byte the change made shows");
});

test("an address resolves in the focused frame, else in the CPU's", async () => {
    // As the SoftCard's debugger answers: the Z80's frame is 1001, where PC is z80:$0100; the 6502's is 1.
    const evaluate = async (expression: string, frameId?: number): Promise<string | undefined> => {
        const z80 = frameId === 1001;
        if (expression === "z80:PC") return z80 ? "z80:0x0100" : "z80:0x6000";
        if (expression === "PC") return z80 ? "z80:0x0100" : "0x6000";
        if (expression === "$0400") return z80 ? "z80:0x0400" : "0x0400";
        if (expression === "HL") { if (z80) return "z80:0x1234"; throw new Error("HL is not a 6502 register."); }
        return undefined;
    };
    assert.equal(await resolveIn(evaluate, "z80", "PC", 1001), 0x0100, "the Z80's PC in the Z80's view");
    assert.equal(await resolveIn(evaluate, null, "PC", 1), 0x6000);
    assert.equal(await resolveIn(evaluate, null, "$0400", 1001), 0x0400, "an address in the CPU's view is the CPU's");
    assert.equal(await resolveIn(evaluate, null, "PC", 1001), 0x6000, "the CPU's PC in its view");
    assert.equal(await resolveIn(evaluate, null, "z80:$0100", 1), undefined, "another bank's address is not this view's");
    await assert.rejects(resolveIn(evaluate, null, "HL"), /not a 6502 register/);
    await assert.rejects(resolveIn(evaluate, null, "HL", 1), /not a 6502 register/);
});

test("a name the focused frame cannot place is not read in the CPU's frame", async () => {
    // As the debugger answers: a Pascal frame, 1500, has a local X it cannot place, and the CPU's frame reads X as the
    // 6502's X register.
    const evaluate = async (expression: string, frameId?: number): Promise<string | undefined> => {
        if (frameId === 1500) {
            if (expression === "X") return undefined;
            if (expression === "COUNT") return "aux:0x2000";
            throw new Error(`${expression} is not a Pascal variable.`);
        }
        return expression === "X" ? "0x0012" : expression === "TEXT_PAGE" ? "0x0400" : undefined;
    };
    assert.equal(await referenceIn(evaluate, "X", 1500), undefined, "not the X register's value");
    assert.equal(await referenceIn(evaluate, "COUNT", 1500), "aux:0x2000");
    assert.equal(await referenceIn(evaluate, "TEXT_PAGE"), "0x0400");
    await assert.rejects(referenceIn(evaluate, "NOWHERE", 1500), /not a Pascal variable/);
});

// Runs the page's test hook, answering what it asks as the debugger would.
async function drive(page: ReturnType<typeof runPage>, actions: unknown[], fill: (offset: number) => number, lists: { frozen: Map<number, number>; watched: Set<string> }): Promise<Record<string, unknown>> {
    page.send({ type: "test", id: 7, actions });
    for (let round = 0; round < 20; round++) {
        await page.settle();
        for (const sent of page.posted.splice(0)) {
            if (sent.type === "testDone") return sent.state as Record<string, unknown>;
            if (sent.type === "freeze") {
                for (const offset of sent.thaw as number[]) lists.frozen.delete(offset);
                for (const item of sent.freeze as { offset: number; value: number }[]) lists.frozen.set(item.offset, item.value);
                page.send({ type: "reply", id: sent.id, result: { frozen: Array.from(lists.frozen, ([address, value]) => ({ address, value })) } });
            } else if (sent.type === "watch") {
                for (const expression of sent.expressions as string[]) lists.watched.add(expression);
                page.send({ type: "reply", id: sent.id, result: null });
            } else if (sent.type === "write") {
                writesSent.push(sent);
                page.send({ type: "reply", id: sent.id, result: { bytesWritten: 1 } });
            } else {
                page.posted.push(sent);
                answer(page, fill);
            }
        }
    }
    throw new Error("The page's test did not finish.");
}

test("the inspector watches bytes in VS Code's Watch view, freezes them, and typing moves a frozen value", async () => {
    const page = runPage();
    const lists = { frozen: new Map<number, number>(), watched: new Set<string>() };
    page.send({ type: "init", address: 0x0400, info: { bank: "aux", label: "Auxiliary RAM", readOnly: false } });
    let state = await drive(page, [{ watch: true }, { freeze: true }], () => 0xA0, lists);
    assert.deepEqual(state.lastWatch, ["[aux:$0400]"]);
    assert.equal(state.frozen, 0xA0);
    assert.deepEqual(Array.from(lists.frozen), [[0x0400, 0xA0]]);
    assert.match(page.elements.get("rows")!.innerHTML, /class="[^"]*frz[^"]*" data-o="1024"/);
    // Watch, Freeze, Name and Comment are buttons; the rest are in the Mark, Edit and Export menus.
    assert.match(page.elements.get("inspector")!.innerHTML, /Watch<\/button><button data-act="freeze" title="Thaw: let the program change these bytes again\.">Thaw</);
    assert.match(page.elements.get("inspector")!.innerHTML, /data-act="name".*data-act="comment".*data-menu="mark".*data-menu="edit".*data-menu="export"/);
    assert.doesNotMatch(page.elements.get("inspector")!.innerHTML, /data-act="fill"/);
    page.elements.get("side")!.dispatch("click", { target: { closest: (selector: string) => selector === "[data-act]" ? { dataset: { act: "menu", menu: "edit" } } : null } });
    assert.equal(page.elements.get("actionMenu")!.hidden, false, "Edit opens its menu");
    assert.match(page.elements.get("actionMenu")!.innerHTML, /role="menuitem" data-act="fill".*data-act="load"/);
    assert.doesNotMatch(page.elements.get("actionMenu")!.innerHTML, /data-act="copyAs"/, "Edit lists only its own");
    assert.equal(page.elements.get("frozenTab")!.textContent, "Frozen (1)");

    state = await drive(page, [{ type: "41" }], () => 0xA0, lists);
    assert.deepEqual(Array.from(lists.frozen), [[0x0400, 0x41]], "the frozen value follows what was typed");
    state = await drive(page, [{ goto: 0x0400 }, { freeze: true }], () => 0xA0, lists);
    assert.equal(state.frozen, null);
    assert.equal(page.elements.get("frozenTab")!.textContent, "Frozen");
    assert.deepEqual(Array.from(lists.watched), ["[aux:$0400]"]);
});

test("the CPU's view watches name the machine's CPU where it has a coprocessor", () => {
    assert.deepEqual(cpuWatches(["[$0400]", "[$0400].w"], true), ["[cpu:$0400]", "[cpu:$0400].w"]);
    assert.deepEqual(cpuWatches(["[$0400]"], false), ["[$0400]"], "no prefix where no coprocessor can take the frame");
    assert.deepEqual(cpuWatches(["[aux:$0400]"], true), ["[aux:$0400]"], "a bank's watch names its bank already");
});

test("watching says what the extension added, which can name the machine's CPU", async () => {
    const page = runPage();
    page.send({ type: "init", address: 0x0400, info: { bank: null, label: "Memory", readOnly: false } });
    for (let round = 0; round < 3; round++) {
        answer(page, () => 0);
        await page.settle();
    }
    page.posted.splice(0);
    page.send({ type: "test", id: 5, actions: [{ watch: true }] });
    await page.settle();
    const watch = page.take("watch");
    assert.deepEqual(watch.expressions, ["[$0400]"]);
    page.send({ type: "reply", id: watch.id, result: { expressions: ["[cpu:$0400]"] } });
    let done: Record<string, unknown> | undefined;
    for (let round = 0; round < 5 && done === undefined; round++) {
        await page.settle();
        done = page.posted.find(message => message.type === "testDone");
        answer(page, () => 0);
    }
    assert.deepEqual((done?.state as Record<string, unknown>).lastWatch, ["[cpu:$0400]"]);
    assert.equal(page.elements.get("status")!.textContent, "Added [cpu:$0400] to the Watch view.");
});

test("a RAM search reads again when a stop comes during its read", async () => {
    const page = runPage();
    page.send({ type: "init", address: 0x0400, info: { bank: null, label: "Memory", readOnly: false } });
    for (let round = 0; round < 3; round++) {
        answer(page, () => 0);
        await page.settle();
    }
    page.posted.splice(0);

    page.send({ type: "test", id: 3, actions: [{ search: "start" }] });
    await page.settle();
    const whole = page.posted.splice(page.posted.findIndex(message => message.type === "read" && message.count === 0x10000), 1)[0];
    // The machine stops before the reply: what it holds is from before, and a RAM search must not start from it.
    page.send({ type: "stopped" });
    await page.settle();
    page.send({ type: "reply", id: whole.id, result: { data: Buffer.alloc(0x10000, 7).toString("base64"), unreadable: [] } });
    let done: Record<string, unknown> | undefined;
    for (let round = 0; round < 10 && done === undefined; round++) {
        await page.settle();
        done = page.posted.find(message => message.type === "testDone");
        answer(page, () => 9);
    }
    assert.ok(done !== undefined, "the search starts");
    assert.match(page.elements.get("search")!.innerHTML, /65536/);
    page.send({ type: "test", id: 4, actions: [{ search: "unchanged" }] });
    done = undefined;
    for (let round = 0; round < 10 && done === undefined; round++) {
        await page.settle();
        done = page.posted.find(message => message.type === "testDone");
        answer(page, () => 9);
    }
    assert.equal((done?.state as Record<string, unknown>).candidates, 0x10000, "the search started from the bytes read after the stop");
});

test("a RAM search narrows all of RAM to the byte that holds a value", async () => {
    const page = runPage();
    const lists = { frozen: new Map<number, number>(), watched: new Set<string>() };
    page.send({ type: "init", address: 0x0400, info: { bank: null, label: "Memory", readOnly: false } });
    let lives = 3;
    const fill = (offset: number) => offset === 0x0480 ? lives : offset === 0x0500 ? 3 : 0;
    let state = await drive(page, [{ search: "start" }], fill, lists);
    assert.equal(state.candidates, 0x10000);
    lives = 2;
    state = await drive(page, [{ search: "decreased" }], fill, lists);
    assert.equal(state.candidates, 1);
    assert.match(page.elements.get("search")!.innerHTML, /\$0480 TEXT_PAGE\+128<\/span><span class="v">\$03 → \$02/);
    state = await drive(page, [{ search: "start" }, { search: "equal", value: "3" }], fill, lists);
    assert.equal(state.candidates, 1, "only $0500 still holds 3");

    // A snapshot highlights what differs from it.
    state = await drive(page, [{ snapshot: true }, { goto: 0x0480 }], fill, lists);
    assert.equal(state.differs, false);
    lives = 1;
    page.send({ type: "changed" });
    state = await drive(page, [{ goto: 0x0480 }], fill, lists);
    assert.equal(state.differs, true);
    assert.match(page.elements.get("inspector")!.innerHTML, /Was<\/span> \$02 <span class="meta">in the snapshot/);
    assert.match(page.elements.get("compareWith")!.innerHTML, /<option value="snapshot">the snapshot<\/option><option value="aux:0x0000">Auxiliary RAM \(aux\)<\/option>/);
    // The space list shows this editor's space, and picking another asks for it in this editor's place, at the cursor.
    const space = page.elements.get("space")!;
    assert.equal(space.hidden, false, "a machine with banks lists its spaces");
    assert.match(space.innerHTML, /<option value="" selected>Memory as the CPU maps it now<\/option><option value="aux">Auxiliary RAM \(aux\)<\/option>/);
    switchesSent.length = 0;
    space.value = "aux";
    space.dispatch("change", {});
    await drive(page, [], fill, lists);
    assert.deepEqual(switchesSent.map(sent => [sent.bank, sent.address]), [["aux", 0x0480]]);
    state = await drive(page, [{ compare: false }], fill, lists);
    assert.equal(state.differs, false, "without comparing, changes count from the last stop");

    // Another bank highlights the bytes that differ from it at the same addresses, and not where it has none.
    state = await drive(page, [{ compare: "aux:0x0000" }, { goto: 0x0481 }], fill, lists);
    assert.equal(state.differs, true);
    assert.match(page.elements.get("inspector")!.innerHTML, /Was<\/span> \$FF <span class="meta">in Auxiliary RAM \(aux\)/);
    assert.equal(page.elements.get("status")!.textContent, "The bytes that differ from Auxiliary RAM (aux) are highlighted.");
    state = await drive(page, [{ goto: 0x0480 }], fill, lists);
    assert.equal(state.differs, false);
    state = await drive(page, [{ goto: 0x0491 }], fill, lists);
    assert.equal(state.differs, false, "auxiliary RAM has no byte there");
});

test("a RAM search for words finds a score in the CPU's byte order", async () => {
    const page = runPage();
    const lists = { frozen: new Map<number, number>(), watched: new Set<string>() };
    page.send({ type: "init", address: 0x0400, info: { bank: null, label: "Memory", readOnly: false, bigEndian: true } });
    let score = 0x0123;
    const fill = (offset: number) => offset === 0x0480 ? score >> 8 : offset === 0x0481 ? score & 0xFF : 0;
    let state = await drive(page, [{ search: "start", size: 2 }], fill, lists);
    assert.equal(state.candidates, 0xFFFF, "every word but the one that starts at the last byte");
    score = 0x0124;
    state = await drive(page, [{ search: "increased" }, { search: "equal", value: "$0124" }], fill, lists);
    assert.equal(state.candidates, 1);
    const panel = page.elements.get("search")!.innerHTML;
    assert.match(panel, /1<\/span> word left after 2 steps/);
    assert.match(panel, /\$0480 TEXT_PAGE\+128<\/span><span class="v">\$0124 → \$0124/);
    assert.match(panel, /data-w="\[\$0480\]\.w"/);
    assert.equal(page.elements.get("status")!.textContent, "1 word left.");
});

test("starting a RAM search over while a step reads memory leaves the new search alone", async () => {
    const page = runPage();
    const lists = { frozen: new Map<number, number>(), watched: new Set<string>() };
    page.send({ type: "init", address: 0x0400, info: { bank: null, label: "Memory", readOnly: false } });
    await drive(page, [{ search: "start" }], () => 0, lists);
    page.elements.get("search")!.innerHTML = "";
    page.posted.splice(0);
    // A step begins reading all of memory; Start over comes before the read does.
    page.elements.get("side")!.dispatch("click", { target: { closest: (selector: string) => selector === "[data-act]" ? { dataset: { act: "narrow", test: "changed" } } : null } });
    await page.settle();
    const pending = page.take("read");
    page.elements.get("side")!.dispatch("click", { target: { closest: (selector: string) => selector === "[data-act]" ? { dataset: { act: "reset" } } : null } });
    page.send({ type: "reply", id: pending.id, result: { data: Buffer.alloc(pending.count as number).toString("base64"), unreadable: [] } });
    await page.settle();
    assert.match(page.elements.get("search")!.innerHTML, /Start with all RAM/, "the search stays started over");
    assert.doesNotMatch(page.elements.get("status")!.textContent, /left/);
});

test("the listing shows the bytes in view as instructions, selects a line's bytes, and decodes from the cursor", async () => {
    const page = runPage();
    const lists = { frozen: new Map<number, number>(), watched: new Set<string>() };
    page.send({ type: "init", address: 0x0300, info: { bank: null, label: "Memory", readOnly: false } });
    let state = await drive(page, [{ goto: 0x0300 }], () => 0, lists);
    const html = page.elements.get("listing")!.innerHTML;
    const top = (state.listing as string[])[0].substring(0, 4);
    assert.deepEqual((state.listing as string[]).map(line => line.substring(5)), ["LDA #$C1", "JMP START", ".byte $01, $02", "RTS"]);
    // A comment follows its line.
    assert.match(html, /<span class="t">RTS<\/span><span class="cm">; Returns<\/span>/);
    // Analysis's guesses say so.
    assert.match(html, /class="ln code guess" role="listitem" aria-keyshortcuts="F9 F2" title="A guess: no source describes these bytes, and analysis takes them for code"/);
    assert.match(html, /<span class="l" title="START">START<\/span><span class="t">LDA #\$C1<\/span><a class="src" role="link" tabindex="-1" data-src="C:\/src\/hello.s" data-line="3"[^>]*>hello.s:3<\/a>/);
    assert.match(html, new RegExp('<span class="t">JMP <a role="link" tabindex="-1" data-go="' + parseInt(top, 16) + '"[^>]*>START</a></span>'), "an operand's target is a link");
    assert.match(html, /class="ln data"/);
    // The listing scrolls both ways, as a long .byte line is wider than it, and takes one tab stop.
    assert.match(memoryEditorHtml("NONCE"), /#listing\{[^}]*overflow:auto/);
    // One grid column, as wide as the widest line or the pane: each line's source stays in reach and lines out.
    assert.match(memoryEditorHtml("NONCE"), /#listing\{[^}]*display:grid;align-content:start/);
    assert.match(memoryEditorHtml("NONCE"), /#listing \.src\{flex:none/);
    assert.equal((html.match(/tabindex="0"/g) ?? []).length, 1);
    assert.match(html, /^<div class="ln code" role="listitem" aria-keyshortcuts="F9 F2" tabindex="0"/, "the first line, when the cursor is in none");

    // A line selects its bytes, the cursor on the first.
    state = await drive(page, [{ listingLine: 1 }], () => 0, lists);
    assert.deepEqual([state.cursor, state.anchor], [parseInt(top, 16) + 2, parseInt(top, 16) + 4]);
    assert.match(page.elements.get("listing")!.innerHTML, /class="ln code sel cur" role="listitem" aria-keyshortcuts="F9 F2" tabindex="0" data-a="[0-9]+" data-s="3"/);

    // Enter on a line does what a click does.
    const lineElement = { dataset: { a: String(parseInt(top, 16)), s: "2" }, querySelectorAll: () => [] };
    const focusedLine = { ...lineElement, closest: (selector: string) => selector === "[data-a]" ? lineElement : null };
    page.elements.get("listing")!.dispatch("keydown", { key: "Enter", target: focusedLine, preventDefault: () => undefined, stopPropagation: () => undefined });
    state = await drive(page, [], () => 0, lists);
    assert.deepEqual([state.cursor, state.anchor], [parseInt(top, 16), parseInt(top, 16) + 1]);

    // A write asks for the listing again, as the bytes it decodes changed.
    listingStarts.length = 0;
    state = await drive(page, [{ goto: 0x0300 }, { pane: "hex" }, { type: "EA" }], () => 0, lists);
    assert.ok(listingStarts.length > 0, "the listing is asked for after the write");

    // Decode from here asks for the listing again, starting an instruction at the cursor.
    listingStarts.length = 0;
    state = await drive(page, [{ goto: 0x0301 }, { decode: true }], () => 0, lists);
    assert.ok(listingStarts.some(starts => starts.includes(0x0301)), JSON.stringify(listingStarts));
    assert.equal(state.status, "The listing decodes an instruction from $0301.");
    // The right button selects nothing, so its menu acts on the selection it opens over.
    page.elements.get("grid")!.dispatch("mousedown", { button: 2, shiftKey: false, preventDefault: () => undefined, target: { closest: () => null } });
    // The bytes' right-click menu lists every action, Decode from here among them while the listing shows.
    page.elements.get("grid")!.dispatch("contextmenu", { target: {}, clientX: 10, clientY: 20, preventDefault: () => undefined });
    assert.match(page.elements.get("actionMenu")!.innerHTML, /data-act="freeze".*role="separator".*data-act="name".*data-act="decode".*role="separator".*data-act="fill".*role="separator".*data-act="copyAs"/);
    assert.equal(page.elements.get("actionMenu")!.style.left, "10px");

    // Marking the selection as data keeps it in the hints file, and reads the labels and listing again.
    marksSent.length = 0;
    listingStarts.length = 0;
    state = await drive(page, [{ goto: 0x0300 }, { mark: { kind: "data" } }], () => 0, lists);
    assert.deepEqual(marksSent.map(sent => [sent.address, sent.count, sent.kind]), [[0x0300, 1, "data"]]);
    // Decode from here's starts give way to the data marked.
    assert.deepEqual(startsSent.map(sent => [sent.address, sent.count]), [[0x0300, 1]]);
    assert.equal(state.status, "Kept in hello.hints.json.");
    assert.ok(listingStarts.length > 0, "the listing is asked for again");
    assert.match(page.elements.get("actionMenu")!.innerHTML, /data-act="markData"/);

    // Where nothing lists, the old lines go.
    await drive(page, [{ goto: 0xE100 }], () => 0, lists);
    assert.equal(page.elements.get("listing")!.innerHTML, "");
});

test("the listing's gutter sets breakpoints, and Find finds instructions", async () => {
    const page = runPage();
    const lists = { frozen: new Map<number, number>(), watched: new Set<string>() };
    page.send({ type: "init", address: 0x0300, info: { bank: null, label: "Memory", readOnly: false } });
    let state = await drive(page, [{ goto: 0x0300 }], () => 0, lists);
    const top = parseInt((state.listing as string[])[0].substring(0, 4), 16);
    // A line where a breakpoint stops has its dot filled.
    assert.deepEqual(state.breakpoints, [top + 7]);
    const html = page.elements.get("listing")!.innerHTML;
    assert.ok(html.includes(`<span class="bp on" data-bp="1" aria-hidden="true" title="Take the breakpoint at $${hex(top + 7, 4)} away (F9)">&#9679;</span><span class="sr">Breakpoint, </span>`), html);
    assert.ok(html.includes('role="listitem" aria-keyshortcuts="F9 F2"'), html);
    assert.ok(html.includes(`<span class="bp" data-bp="1" aria-hidden="true" title="Stop at $${hex(top, 4)} (F9)">`), html);

    // F9 sets one at the cursor's line.
    breakpointsSent.length = 0;
    state = await drive(page, [{ listingLine: 0 }, { breakpoint: true }], () => 0, lists);
    assert.deepEqual(breakpointsSent.map(sent => [sent.address, sent.ids]), [[top, null]]);
    assert.equal(state.status, `Breakpoint at $${hex(top, 4)}.`);

    // While the listing is hidden, its old lines don't say where a line starts, so F9 sets nothing.
    // The Disassembly heading collapses the listing, and its strip expands it.
    const box = { dispatch: (_name: string, _event: object) => page.window.dispatch("click", { target: { closest: (selector: string) => selector === "[data-fold]" ? { dataset: { fold: "listing" } } : null } }) };
    box.dispatch("click", {});
    breakpointsSent.length = 0;
    state = await drive(page, [{ breakpoint: true }], () => 0, lists);
    assert.deepEqual([breakpointsSent.length, state.status], [0, "Show the listing to set a breakpoint."]);
    box.dispatch("click", {});
    await drive(page, [], () => 0, lists);

    // Clicking a filled dot sends the breakpoints that stop there, to take them away.
    breakpointsSent.length = 0;
    const line = { dataset: { a: String(top + 7) } };
    const dot = { closest: (selector: string) => selector === "[data-bp]" ? { closest: () => line } : null };
    page.elements.get("listing")!.dispatch("click", { target: dot });
    await drive(page, [], () => 0, lists);
    assert.deepEqual(breakpointsSent.map(sent => [sent.address, sent.ids]), [[top + 7, [7]]]);

    // Breakpoints set anywhere ask for the listing again; until it comes, a dot's breakpoints may have moved, so a
    // click sets or takes away nothing.
    listingStarts.length = 0;
    page.send({ type: "breakpoints" });
    breakpointsSent.length = 0;
    page.elements.get("listing")!.dispatch("click", { target: dot });
    // F9 on a listing line waits for it too.
    page.elements.get("listing")!.dispatch("keydown", { key: "F9", target: { closest: () => ({ ...line, querySelectorAll: () => [] }) }, preventDefault() { } });
    assert.equal(breakpointsSent.length, 0);
    await drive(page, [], () => 0, lists);
    assert.ok(listingStarts.length > 0, "the listing is asked for again");

    // Text that is neither bytes nor quoted text is an instruction, which the debugger finds; its bytes are selected.
    findsSent.length = 0;
    state = await drive(page, [{ goto: 0x0300 }, { find: "STA $C0??" }], () => 0, lists);
    assert.deepEqual(findsSent.map(sent => [sent.pattern, sent.from, sent.backward]), [["STA $C0??", 0x0301, false]]);
    assert.deepEqual([state.cursor, state.anchor, state.status], [0x0310, 0x0312, "Found STA SPKR at $0310."]);
    // Bytes and text are found in the page.
    await drive(page, [{ find: "A9 ??" }, { find: '"HI' }], () => 0, lists);
    assert.equal(findsSent.length, 1);
});

test("the map bar shows what memory reads across the space, the bytes in view, and goes where it is clicked", async () => {
    const page = runPage();
    const lists = { frozen: new Map<number, number>(), watched: new Set<string>() };
    page.send({ type: "init", address: 0x0000, info: { bank: null, label: "Memory", readOnly: false } });
    await drive(page, [{ goto: 0x0000 }], () => 0, lists);
    const bar = page.elements.get("map")!;
    assert.equal(bar.hidden, false);
    assert.ok(bar.innerHTML.includes('<div class="seg ram" style="left:0%;width:75%"></div>'), bar.innerHTML);
    assert.ok(bar.innerHTML.includes('<div class="seg io off" style="left:75%;width:6.25%"></div>'), bar.innerHTML);
    assert.ok(bar.innerHTML.includes('<div class="seg rom wo" style="left:81.25%;width:18.75%"></div>'), "striped where the CPU only writes: " + bar.innerHTML);
    assert.ok(bar.innerHTML.includes('<div class="edge" style="left:1.5625%"></div>'), "a line where text page 1 starts");
    assert.equal(page.elements.get("mapView")!.style.left, "0%");

    // Hovering names the address, its region and what reads there; a click goes there.
    bar.dispatch("mousemove", { clientX: 4 });
    assert.equal(bar.dataset.tip, "$0400 · Text page 1 · main RAM", "in the page's own hover, not the browser's");
    const state = await drive(page, [], () => 0, lists);
    bar.dispatch("click", { clientX: 208 });
    const moved = await drive(page, [], () => 0, lists);
    assert.notEqual(state.cursor, moved.cursor);
    assert.equal(moved.cursor, 0xD000);
});

test("the inspector says where the cursor's address is, what it is and what the firmware says of it", async () => {
    const page = runPage();
    const lists = { frozen: new Map<number, number>(), watched: new Set<string>() };
    page.send({ type: "init", address: 0x0024, info: { bank: null, label: "Memory", readOnly: false } });
    await drive(page, [{ goto: 0x0024 }], () => 0, lists);
    let html = page.elements.get("inspector")!.innerHTML;
    assert.ok(html.includes('<span class="meta">In</span> Zero page</div>'), html);
    assert.ok(html.includes('<div class="line">Reads and writes main RAM</div>'), html);
    assert.ok(html.includes('<div class="doc">The cursor&#39;s column.</div>') || html.includes("<div class=\"doc\">The cursor's column.</div>"), html);

    // Inside a label, the label and offset, its documentation, the source line and the BASIC's floats.
    await drive(page, [{ goto: 0x0403 }], () => 0, lists);
    html = page.elements.get("inspector")!.innerHTML;
    assert.ok(html.includes('<span class="meta">In</span> Text page 1, row 0, column 3</div>'), html);
    assert.ok(html.includes('<span class="meta">Inside</span> START+3</div>'), html);
    assert.ok(html.includes("START: Starts it."), html);
    assert.ok(html.includes('data-src="C:/src/hello.s" data-line="4"') && html.includes('<button class="link" data-src="C:/src/hello.s"') && html.includes(">hello.s:4</button>"), html);
    assert.ok(html.includes('<span class="meta">Float, 5 bytes</span> <button class="link" data-edit="Float, 5 bytes" title="Float, 5 bytes: click to write a new value at $0403">1</button>'), html);
    assert.ok(!html.includes("Reads and writes"), "no map line on a machine without banks");
    // The inspector's groups, the byte's forms on one line, and the word in the CPU's byte order until asked for both.
    assert.ok(html.includes('<section class="group" aria-label="Where"><h3>Where</h3>') && html.includes('aria-label="As a number"'), html);
    assert.match(html, /<div class="line values"><button class="link" data-edit="Byte"[^>]*>\$00<\/button><button class="link" data-edit="Unsigned"/);
    assert.ok(html.includes(">Word, low byte first<") && !html.includes(">Word, high byte first<"), html);
    page.elements.get("side")!.dispatch("click", { target: { closest: (selector: string) => selector === "[data-act]" ? { dataset: { act: "orders" } } : null } });
    assert.ok(page.elements.get("inspector")!.innerHTML.includes(">Word, high byte first<"), "both byte orders when asked");
});

test("the inspector names a byte's bits, shows the instruction starting there and goes to the code that uses it", async () => {
    const page = runPage();
    const lists = { frozen: new Map<number, number>(), watched: new Set<string>() };
    page.send({ type: "init", address: 0x0300, info: { bank: null, label: "Memory", readOnly: false } });
    await drive(page, [{ goto: 0x0300 }], () => 0x81, lists);
    const html = page.elements.get("inspector")!.innerHTML;
    assert.ok(html.includes('<span class="meta">Bit 7</span> 1 <span class="meta">is set when ready</span>'), html);
    assert.ok(html.includes('<span class="meta">Bit 0 BUSY</span> 1 '), html);
    assert.ok(html.includes('<span class="v">BNE READY</span> <span class="meta">2 bytes · 2 cycles, 3 taken · leaves the flags alone</span>'), html);
    assert.ok(!html.includes("As a number") && !html.includes("Word, low byte first"), "an instruction's bytes are no number");
    assert.ok(html.includes('<div class="doc">Branches when Z is clear.</div>'), html);
    assert.ok(html.includes('<h3>Used by</h3>') && html.includes("and 33 more"), html);
    assert.ok(html.includes('<button class="hit ref" data-go="784"') && html.includes("$0310 WAIT+2") && html.includes("BIT READY"), html);

    // Decode from here's starts go with the request, as the listing's do.
    await drive(page, [{ decode: true }], () => 0x81, lists);
    assert.deepEqual(inspectsSent[inspectsSent.length - 1].starts, [0x0300]);

    // A reference goes to its instruction.
    page.elements.get("side")!.dispatch("click", { target: { closest: (selector: string) => selector === "[data-go]" ? { dataset: { go: "784" } } : null } });
    const state = await drive(page, [], () => 0x81, lists);
    assert.equal(state.cursor, 0x0310);
});

test("the inspector's values are written as typed, the selection is filled and the clipboard is pasted", async () => {
    const page = runPage();
    const lists = { frozen: new Map<number, number>(), watched: new Set<string>() };
    page.send({ type: "init", address: 0x0403, info: { bank: null, label: "Memory", readOnly: false } });
    let state = await drive(page, [{ goto: 0x0403 }], () => 0, lists);
    const sent = () => writesSent.map(item => [item.offset, item.data]);

    // A word low first, a signed byte and the BASIC's float, each one write at the cursor.
    writesSent.length = 0;
    inputReply = { text: "$1234" };
    state = await drive(page, [{ edit: "Word, low first" }], () => 0, lists);
    assert.equal(inputsSent[inputsSent.length - 1].title, "Word, low first at $0403");
    inputReply = { text: "-1" };
    await drive(page, [{ edit: "Signed" }], () => 0, lists);
    // A value accepted as shown writes nothing, as a float shows rounded.
    const before = writesSent.length;
    inputReply = { text: "1" };
    state = await drive(page, [{ goto: 0x0403 }, { edit: "Float, 5 bytes" }], () => 0, lists);
    assert.deepEqual([writesSent.length, state.status], [before, "Float, 5 bytes at $0403 is unchanged."]);
    // The Binary row takes its own grouping back.
    inputReply = { text: "%1010 1001" };
    await drive(page, [{ edit: "Binary" }], () => 0, lists);
    assert.deepEqual(writesSent[writesSent.length - 1].data, [0xA9]);
    writesSent.pop();
    inputReply = { text: "1000" };
    state = await drive(page, [{ edit: "Float, 5 bytes" }], () => 0, lists);
    assert.deepEqual(sent(), [[0x0403, [0x34, 0x12]], [0x0403, [0xFF]], [0x0403, [0x8A, 0x7A, 0, 0, 0]]]);
    assert.equal(state.status, "Float, 5 bytes at $0403 written.");
    // Text that is no value writes nothing and says why; undo takes back the last write.
    writesSent.length = 0;
    inputReply = { text: "70000" };
    state = await drive(page, [{ edit: "Word, high first" }], () => 0, lists);
    assert.deepEqual([sent(), state.status], [[], "70000 does not fit in a word."]);
    // (The stand-in reads zeros back after each write, so those are what the float replaced.)
    await drive(page, [{ undo: true }], () => 0, lists);
    assert.deepEqual(sent(), [[0x0403, [0, 0, 0, 0, 0]]]);

    // Fill repeats bytes or text over the selection, a listing line's two bytes here.
    const top = parseInt((state.listing as string[])[0].substring(0, 4), 16);
    writesSent.length = 0;
    inputReply = { text: "EA" };
    await drive(page, [{ listingLine: 0 }, { fill: true }], () => 0, lists);
    inputReply = { text: "01 02 03" };
    await drive(page, [{ listingLine: 0 }, { fill: true }], () => 0, lists);
    inputReply = { text: '"A"' };
    state = await drive(page, [{ listingLine: 0 }, { fill: true }], () => 0, lists);
    assert.deepEqual(sent(), [[top, [0xEA, 0xEA]], [top, [0x01, 0x02]], [top, [0x41, 0x41]]]);
    assert.equal(state.status, `Filled $${hex(top, 4)}-$${hex(top + 1, 4)} (2 bytes).`);

    // Paste takes the Monitor's lines as hex, or in the text pane the characters.
    writesSent.length = 0;
    clipboardText = "0300: A9 C1\n0302- 20 ED FD ; JSR COUT";
    state = await drive(page, [{ goto: 0x0500 }, { paste: true }], () => 0, lists);
    assert.deepEqual([sent(), state.status], [[[0x0500, [0xA9, 0xC1, 0x20, 0xED, 0xFD]]], "Pasted 5 bytes at $0500."]);
    // A hex digit typed before the paste does not join the next key to the pasted byte.
    writesSent.length = 0;
    clipboardText = "01";
    await drive(page, [{ goto: 0x0600 }, { type: ["A"] }, { paste: true }, { type: ["2"] }], () => 0, lists);
    assert.deepEqual(sent()[0], [0x0600, [0x01]]);
    assert.ok(!sent().some(item => (item[1] as number[])[0] === 0xA2), JSON.stringify(sent()));
    await drive(page, [{ goto: 0x0500 }], () => 0, lists);
    // A key typed just before goes first, and the paste after it.
    writesSent.length = 0;
    clipboardText = "02";
    await drive(page, [{ goto: 0x0700 }, { type: ["0", "1"] }, { paste: true }], () => 0, lists);
    assert.deepEqual(sent(), [[0x0700, [0x01]], [0x0701, [0x02]]]);
    await drive(page, [{ goto: 0x0500 }], () => 0, lists);
    writesSent.length = 0;
    clipboardText = "HI";
    await drive(page, [{ pane: "text" }, { paste: true }], () => 0, lists);
    assert.deepEqual(sent(), [[0x0500, [0x48, 0x49]]]);
    writesSent.length = 0;
    clipboardText = "not hex";
    state = await drive(page, [{ pane: "hex" }, { paste: true }], () => 0, lists);
    assert.deepEqual([sent().length, state.status], [0, "The clipboard does not hold hex bytes: not is not hex bytes: each byte takes two hex digits."]);
});

test("the selection is copied in another form, saved and loaded, a file's bytes undone as one edit", async () => {
    const page = runPage();
    const lists = { frozen: new Map<number, number>(), watched: new Set<string>() };
    page.send({ type: "init", address: 0x0300, info: { bank: null, label: "Memory", readOnly: false } });
    const fill = (offset: number) => offset & 0xFF;
    let state = await drive(page, [{ goto: 0x0300 }], fill, lists);
    const top = parseInt((state.listing as string[])[0].substring(0, 4), 16);

    // Copy as asks which form, then copies the selection in it: a listing line's two bytes here.
    copiesSent.length = 0;
    pickReply = { index: 1 };
    state = await drive(page, [{ listingLine: 0 }, { copyAs: true }], fill, lists);
    assert.deepEqual(copiesSent, [`${hex(top, 4)}: ${hex(top & 0xFF, 2)} ${hex((top + 1) & 0xFF, 2)}`]);
    assert.equal(state.status, `Copied 2 bytes from $${hex(top, 4)} as Monitor lines.`);

    // Save sends the selection's bytes and the starts; the host says where and how it saved them.
    savesSent.length = 0;
    saveReply = { path: "memory.asm", form: "assembly", exact: true };
    state = await drive(page, [{ listingLine: 0 }, { save: true }], fill, lists);
    assert.deepEqual([savesSent[0].offset, savesSent[0].data], [top, [top & 0xFF, (top + 1) & 0xFF]]);
    assert.equal(state.status, `Saved 2 bytes from $${hex(top, 4)} to memory.asm, which assembles back to the same bytes.`);
    saveReply = { path: "memory.asm", form: "assembly", exact: false };
    state = await drive(page, [{ listingLine: 0 }, { save: true }], fill, lists);
    assert.equal(state.status, `Saved 2 bytes from $${hex(top, 4)} to memory.asm as .byte lines, as its instructions would not assemble back to the same bytes.`);

    // A binary loads at the cursor, and Intel HEX at its addresses, which one undo takes back together.
    writesSent.length = 0;
    loadReply = { name: "game.bin", data: [0xA9, 0xC1] };
    state = await drive(page, [{ goto: 0x0800 }, { load: true }], fill, lists);
    assert.deepEqual(writesSent.map(item => [item.offset, item.data]), [[0x0800, [0xA9, 0xC1]]]);
    assert.equal(state.status, "Loaded 2 bytes from game.bin at $0800.");
    writesSent.length = 0;
    loadReply = { name: "game.hex", runs: [{ address: 0x0900, data: [1, 2] }, { address: 0x0A00, data: [3] }] };
    state = await drive(page, [{ load: true }], fill, lists);
    assert.deepEqual(writesSent.map(item => [item.offset, item.data]), [[0x0900, [1, 2]], [0x0A00, [3]]]);
    assert.equal(state.status, "Loaded 3 bytes from game.hex in 2 runs from $0900.");
    writesSent.length = 0;
    await drive(page, [{ undo: true }], fill, lists);
    assert.deepEqual(writesSent.map(item => [item.offset, item.data]), [[0x0A00, [0x00]], [0x0900, [0x00, 0x01]]]);
    // A binary longer than what is left of memory stops at $FFFF.
    writesSent.length = 0;
    loadReply = { name: "big.bin", data: [1, 2, 3, 4] };
    state = await drive(page, [{ goto: 0xFFFE }, { load: true }], fill, lists);
    assert.deepEqual(writesSent.map(item => [item.offset, item.data]), [[0xFFFE, [1, 2]]]);
    assert.equal(state.status, "Loaded 2 bytes from big.bin at $FFFE; 2 more ran past $FFFF.");
    loadReply = { cancelled: true };
});

test("Copy as writes hex, the Monitor's lines, .byte lines, BASIC DATA, a C array and base64", () => {
    const values = [0xA9, 0xC1, 0x20, 0xED, 0xFD, 0x60, 0x00, 0x01, 0xFF];
    assert.equal(copyAs(values.slice(0, 3), 0x0300, "hex"), "A9 C1 20");
    assert.equal(copyAs(values, 0x0300, "monitor"), "0300: A9 C1 20 ED FD 60 00 01\n0308: FF");
    assert.equal(copyAs(values.slice(0, 2), 0x0300, "byte"), "    .byte $A9, $C1");
    assert.equal(copyAs(values, 0x0300, "data"), "1000 DATA 169,193,32,237,253,96,0,1\n1010 DATA 255");
    assert.equal(copyAs(values.slice(0, 2), 0x0300, "c"), "unsigned char memory_0300[2] = {\n    0xA9, 0xC1\n};");
    assert.equal(copyAs([0xA9, 0xC1, 0x20], 0, "base64"), Buffer.from([0xA9, 0xC1, 0x20]).toString("base64"));
    assert.equal(copyAs([0xA9, 0xC1], 0, "base64"), Buffer.from([0xA9, 0xC1]).toString("base64"));
    assert.equal(copyAs([0xA9], 0, "base64"), Buffer.from([0xA9]).toString("base64"));
    // A long listing's lines step closer, staying under BASIC's last line number, 63999.
    const listing = copyAs(new Array(0x10000).fill(0), 0, "data").split(String.fromCharCode(10));
    assert.ok(Number(listing[listing.length - 1].split(" ")[0]) <= 63999, listing[listing.length - 1].slice(0, 20));
});

test("Intel HEX is written in 16-byte records and read back into runs", () => {
    const values = Array.from({ length: 20 }, (_, index) => index);
    const text = intelHex(values, 0x0300);
    assert.equal(text.split("\r\n")[0], ":10030000000102030405060708090A0B0C0D0E0F75");
    assert.ok(text.endsWith(":00000001FF\r\n"));
    assert.deepEqual(parseIntelHex(text), [{ address: 0x0300, data: values }]);
    // Two places, a start address record ignored, and the errors.
    assert.deepEqual(parseIntelHex(":0103000001FB\n:0104000002F9\n:0400000300000300F6\n:00000001FF"), [{ address: 0x0300, data: [1] }, { address: 0x0400, data: [2] }]);
    assert.equal(parseIntelHex(":0103000001FC"), "Line 1's checksum is wrong.");
    assert.equal(parseIntelHex("hello"), "Line 1 is not an Intel HEX record.");
    assert.equal(parseIntelHex(":020000040001F9\n:0100000001FE"), "Line 2 puts bytes past $FFFF.");
    assert.equal(parseIntelHex(":00000001FF"), "The file holds no bytes.");
    // A file cut short on a record's end has no end of file record.
    assert.equal(parseIntelHex(":0103000001FB"), "The file has no end of file record, so it may be cut short.");
    // An extended linear address of $8000 or more stays positive, so its bytes are refused as past $FFFF.
    assert.equal(parseIntelHex(":0200000480007A\n:0100000001FE"), "Line 2 puts bytes past $FFFF.");
});

test("bytes to fill or paste are hex, the Monitor's lines, or text in quotes", () => {
    assert.deepEqual(parseData("A9 C1,20 $ED 0xFD"), [0xA9, 0xC1, 0x20, 0xED, 0xFD]);
    assert.deepEqual(parseData("0300: A9C1\n0302- 20 ; JSR\n"), [0xA9, 0xC1, 0x20]);
    assert.deepEqual(parseData('"HELLO"'), { text: "HELLO" });
    assert.equal(parseData(""), "Type bytes such as A9 C1, or text in quotes.");
    assert.equal(parseData("ABC"), "ABC is not hex bytes: each byte takes two hex digits.");
    assert.equal(parseData('""'), "The text is empty.");
});

test("assembling in place types an instruction over a listing line, padding or overwriting as the user says", async () => {
    const page = runPage();
    const lists = { frozen: new Map<number, number>(), watched: new Set<string>() };
    page.send({ type: "init", address: 0x0300, info: { bank: null, label: "Memory", readOnly: false } });
    let state = await drive(page, [{ goto: 0x0300 }], () => 0, lists);
    const top = parseInt((state.listing as string[])[0].substring(0, 4), 16);
    const at = (offset: number) => "$" + hex(offset, 4);

    // The line's text is offered to type over; a cancel writes nothing.
    assemblesSent.length = 0;
    writesSent.length = 0;
    assembleReply = { cancelled: true };
    await drive(page, [{ listingLine: 0 }, { assemble: true }], () => 0, lists);
    assert.deepEqual([assemblesSent[0].address, assemblesSent[0].text, writesSent.length], [top, "LDA #$C1", 0]);

    // A shorter instruction pads the rest with NOP when asked.
    assembleReply = { bytes: [0xEA], text: "NOP", nop: [0xEA], line: "NOP" };
    confirmChoice = "Pad with NOP";
    confirmsSent.length = 0;
    state = await drive(page, [{ listingLine: 0 }, { assemble: true }], () => 0, lists);
    assert.equal(confirmsSent[0].message, "NOP is 1 byte, 1 fewer than LDA #$C1. Pad the rest with NOP?");
    assert.deepEqual(writesSent.map(sent => [sent.offset, sent.data]), [[top, [0xEA, 0xEA]]]);
    assert.equal(state.status, `Assembled NOP at ${at(top)}.`);
    // Undo takes the whole write back.
    writesSent.length = 0;
    await drive(page, [{ undo: true }], () => 0, lists);
    assert.deepEqual(writesSent.map(sent => [sent.offset, sent.data]), [[top, [0, 0]]]);

    // Leaving the rest writes only the instruction.
    writesSent.length = 0;
    confirmChoice = "Leave the rest";
    await drive(page, [{ listingLine: 0 }, { assemble: true }], () => 0, lists);
    assert.deepEqual(writesSent.map(sent => [sent.offset, sent.data]), [[top, [0xEA]]]);

    // A longer one says what it overwrites, and writes only on Write.
    writesSent.length = 0;
    confirmsSent.length = 0;
    assembleReply = { bytes: [0x20, 0xED, 0xFD], text: "JSR COUT", nop: [0xEA], line: "JSR COUT" };
    confirmChoice = null;
    await drive(page, [{ listingLine: 0 }, { assemble: true }], () => 0, lists);
    assert.equal(confirmsSent[0].message, `JSR COUT is 3 bytes, 1 more than LDA #$C1: it overwrites JMP START at ${at(top + 2)} (in part).`);
    assert.equal(writesSent.length, 0);
    confirmChoice = "Write";
    await drive(page, [{ listingLine: 0 }, { assemble: true }], () => 0, lists);
    assert.deepEqual(writesSent.map(sent => [sent.offset, sent.data]), [[top, [0x20, 0xED, 0xFD]]]);

    // The line's text accepted as it was writes nothing, as it may assemble to another encoding.
    writesSent.length = 0;
    assembleReply = { bytes: [0xA9, 0xC1], text: "LDA #$C1", nop: [0xEA], line: "lda  #$C1" };
    state = await drive(page, [{ listingLine: 0 }, { assemble: true }], () => 0, lists);
    assert.deepEqual([writesSent.length, state.status], [0, "LDA #$C1 is unchanged."]);

    // An operand spelled in another case is another name, so it writes.
    writesSent.length = 0;
    assembleReply = { bytes: [0xA9, 0xC2], text: "LDA #$c1", nop: [0xEA], line: "LDA #$c1" };
    await drive(page, [{ listingLine: 0 }, { assemble: true }], () => 0, lists);
    assert.equal(writesSent.length, 1);

    // An instruction of the same size writes without asking.
    writesSent.length = 0;
    confirmsSent.length = 0;
    assembleReply = { bytes: [0xA9, 0x01], text: "LDA #$01", nop: [0xEA], line: "LDA #1" };
    await drive(page, [{ listingLine: 0 }, { assemble: true }], () => 0, lists);
    assert.deepEqual([confirmsSent.length, writesSent.map(sent => sent.data)], [0, [[0xA9, 0x01]]]);
    // Assemble is in the Edit menu while the listing shows.
    page.elements.get("side")!.dispatch("click", { target: { closest: (selector: string) => selector === "[data-act]" ? { dataset: { act: "menu", menu: "edit" } } : null } });
    assert.ok(page.elements.get("actionMenu")!.innerHTML.includes('data-act="assemble"'));

    // A double-click while the listing is hidden asks for nothing, as its old lines may be of other bytes.
    // The Disassembly heading collapses the listing, and its strip expands it.
    const box = { dispatch: (_name: string, _event: object) => page.window.dispatch("click", { target: { closest: (selector: string) => selector === "[data-fold]" ? { dataset: { fold: "listing" } } : null } }) };
    box.dispatch("click", {});
    assemblesSent.length = 0;
    const line = { dataset: { a: String(top), s: "2" } };
    page.elements.get("listing")!.dispatch("dblclick", { target: { closest: (selector: string) => selector === "[data-a]" ? line : null } });
    state = await drive(page, [], () => 0, lists);
    assert.deepEqual([assemblesSent.length, state.status], [0, "Show the listing to assemble an instruction."]);

    // With it shown, a double-click that reaches the listing itself, as when its first click drew it again, types
    // over the cursor's line.
    box.dispatch("click", {});
    await drive(page, [{ listingLine: 0 }], () => 0, lists);
    assembleReply = { cancelled: true };
    page.elements.get("listing")!.dispatch("dblclick", { target: { closest: () => null } });
    await drive(page, [], () => 0, lists);
    assert.deepEqual(assemblesSent.map(sent => sent.address), [top]);
});

test("the gutter's breakpoints are function breakpoints named by address", () => {
    assert.equal(breakpointName(null, 0x0300), "$0300");
    assert.equal(breakpointName("aux", 0x0400), "aux:$0400");
    assert.ok(breakpointAt("$0300", null, 0x0300));
    assert.ok(breakpointAt(" cpu:$0300 ", null, 0x0300));
    assert.ok(breakpointAt("0x0300", null, 0x0300));
    assert.ok(breakpointAt("AUX:$0400", "aux", 0x0400));
    assert.ok(!breakpointAt("aux:$0400", null, 0x0400));
    assert.ok(!breakpointAt("$0301", null, 0x0300));
    assert.ok(!breakpointAt("START", null, 0x0300));
    // Bare digits are decimal in an expression, so 768 is $0300 and 0300 is not this address's name.
    assert.ok(!breakpointAt("0300", null, 0x0300));
    assert.ok(!breakpointAt("aux:0400", "aux", 0x0400));
});

test("a read-only bank refuses typing before writing", async () => {
    const page = runPage();
    page.send({ type: "init", address: 0xD000, info: { bank: "rom", label: "System ROM", readOnly: true } });
    for (const read of page.posted.splice(0).filter(message => message.type === "read")) {
        page.send({ type: "reply", id: read.id, result: { data: Buffer.alloc(read.count as number).toString("base64"), unreadable: [] } });
    }
    await page.settle();
    page.posted.splice(0);
    page.key("1");
    await page.settle();
    assert.equal(page.posted.length, 0);
    assert.equal(page.elements.get("status")!.textContent, "System ROM is read-only.");
});

test("the label or address under the cursor is what the editor's menu opens", () => {
    const line = "LOOP:   LDA TEXT_PAGE+1,X ; aux:$0400 and 0400h";
    assert.equal(addressAt(line, 2), "LOOP", "a label's colon is left off");
    assert.equal(addressAt(line, 14), "TEXT_PAGE");
    assert.equal(addressAt(line, line.indexOf("aux") + 5), "aux:$0400", "a bank prefix comes along");
    assert.equal(addressAt(line, line.length - 2), "0400h");
    assert.equal(addressAt(line, 6), undefined, "between words there is nothing");
    const scoped = "        jsr screen::clear";
    assert.equal(addressAt(scoped, scoped.length - 1), "screen::clear", "a scoped label is whole from its name");
    assert.equal(addressAt(scoped, scoped.indexOf("screen") + 1), "screen::clear", "and from its scope");
});

test("find by value reads a number as a byte or as words either way round", () => {
    assert.deepEqual(valueForms("200"), { forms: [{ label: "a byte", bytes: [200] }], decimal: "200" });
    assert.deepEqual(valueForms("-1"), { forms: [{ label: "a byte", bytes: [0xFF] }], decimal: "-1" });
    assert.deepEqual(valueForms("$C000"), {
        forms: [{ label: "a word, low first", bytes: [0x00, 0xC0] }, { label: "a word, high first", bytes: [0xC0, 0x00] }],
        decimal: "49152"
    });
    assert.deepEqual(valueForms("%101"), { forms: [{ label: "a byte", bytes: [5] }], decimal: "5" });
    assert.deepEqual(valueForms("-2.5"), { forms: [], decimal: "-2.5" }, "a fraction is only the BASIC's floats");
    assert.deepEqual(valueForms("1.0000000000000001"), { forms: [], decimal: "1.0000000000000001" }, "a fraction a number here rounds away is still one");
    assert.deepEqual(valueForms("100E-2"), { forms: [{ label: "a byte", bytes: [1] }], decimal: "100E-2" });
    assert.deepEqual(valueForms("1.50e1"), { forms: [{ label: "a byte", bytes: [15] }], decimal: "1.50e1" });
    assert.deepEqual(valueForms("12.30"), { forms: [], decimal: "12.30" });
    assert.deepEqual(valueForms("0.0"), { forms: [{ label: "a byte", bytes: [0] }], decimal: "0.0" });
    assert.deepEqual(valueForms("1E6"), { forms: [], decimal: "1E6" }, "too big for a word");
    assert.equal((valueForms("9007199254740993") as { decimal: string }).decimal, "9007199254740993", "every digit goes to the debugger");
    assert.equal(typeof valueForms("HELLO"), "string");
});

test("bookmarks are kept by any launch configuration name, and anything else saved is none", () => {
    assert.equal(bookmarkStore(undefined).size, 0);
    assert.equal(bookmarkStore({ constructor: [] }).size, 0);
    assert.equal(bookmarkStore([]).get("constructor"), undefined, "no inherited property is a list");
    const store = bookmarkStore([["__proto__", [{ name: "Here", bank: null, address: 1 }]]]);
    assert.deepEqual(store.get("__proto__"), [{ name: "Here", bank: null, address: 1 }]);
    assert.deepEqual(bookmarkStore(JSON.parse(JSON.stringify([...store]))).get("__proto__")?.[0].name, "Here");
});

test("bookmarks are one a space and address, renamed in place and removed by an empty name", () => {
    let list = withBookmark([], null, 0x0400, " Screen ");
    list = withBookmark(list, "aux", 0x0400, "Aux screen");
    list = withBookmark(list, null, 0x0300, "Start");
    assert.deepEqual(list.map(item => item.name), ["Start", "Screen", "Aux screen"]);
    list = withBookmark(list, null, 0x0400, "Text");
    assert.deepEqual(list.map(item => item.name), ["Start", "Text", "Aux screen"]);
    list = withBookmark(list, null, 0x0300, "");
    assert.deepEqual(list.map(item => `${item.bank ?? ""}${item.address}`), ["1024", "aux1024"]);
});

test("go-tos go back and forward, and a stop moves a view that follows", async () => {
    const page = runPage();
    const lists = { frozen: new Map<number, number>(), watched: new Set<string>() };
    page.send({ type: "init", address: 0x0000, info: { bank: null, label: "Memory", readOnly: false }, bookmarks: [] });
    let state = await drive(page, [{ jump: 0x0400 }, { jump: 0x0800 }], () => 0, lists);
    assert.deepEqual(state.back, [0x0000, 0x0400]);
    assert.equal((page.elements.get("back") as unknown as { disabled: boolean }).disabled, false);
    state = await drive(page, [{ back: true }], () => 0, lists);
    assert.equal(state.cursor, 0x0400);
    assert.deepEqual(state.forward, [0x0800]);

    // The mouse's forward button, then Alt+Left.
    window(page).dispatch("mouseup", { button: 4, preventDefault: () => undefined });
    state = await drive(page, [], () => 0, lists);
    assert.equal(state.cursor, 0x0800);
    window(page).dispatch("keydown", { key: "ArrowLeft", altKey: true, ctrlKey: false, metaKey: false, shiftKey: false, preventDefault: () => undefined, stopPropagation: () => undefined });
    state = await drive(page, [], () => 0, lists);
    assert.equal(state.cursor, 0x0400);

    // A new go-to drops what Forward had.
    state = await drive(page, [{ gotoText: "$0C00" }], () => 0, lists);
    assert.equal(state.cursor, 0x0C00);
    assert.deepEqual(state.forward, []);

    // Following PC goes where it is now and again at each stop; unchecking stays put.
    pcNow = 0x0300;
    state = await drive(page, [{ gotoText: "PC" }, { follow: true }], () => 0, lists);
    assert.equal(state.following, "PC");
    assert.equal(state.cursor, 0x0300);
    pcNow = 0x0350;
    page.send({ type: "stopped" });
    // The first answers what the stop asks for, the second reports where the page went.
    await drive(page, [], () => 0, lists);
    state = await drive(page, [], () => 0, lists);
    assert.equal(state.cursor, 0x0350);
    assert.equal((state.back as number[]).at(-1), 0x0300, "a followed move is one Back undoes");
    // Back while the stop's answer is on its way stays back, and keeps Forward.
    pcNow = 0x0370;
    page.send({ type: "stopped" });
    const asked = page.posted.splice(page.posted.findIndex(message => message.type === "goto"), 1)[0];
    state = await drive(page, [{ back: true }], () => 0, lists);
    page.send({ type: "reply", id: asked.id, result: { address: 0x0370 } });
    state = await drive(page, [], () => 0, lists);
    assert.equal(state.cursor, 0x0300);
    assert.deepEqual(state.forward, [0x0350]);
    // Two stops before the first's answer: the second's answer is where the view goes, whichever comes first.
    page.send({ type: "stopped" });
    const first = page.posted.splice(page.posted.findIndex(message => message.type === "goto"), 1)[0];
    page.send({ type: "stopped" });
    const second = page.posted.splice(page.posted.findIndex(message => message.type === "goto"), 1)[0];
    page.send({ type: "reply", id: first.id, result: { address: 0x0380 } });
    page.send({ type: "reply", id: second.id, result: { address: 0x0390 } });
    await drive(page, [], () => 0, lists);
    state = await drive(page, [], () => 0, lists);
    assert.equal(state.cursor, 0x0390);
    state = await drive(page, [{ back: true }, { follow: false }], () => 0, lists);
    pcNow = 0x0360;
    page.send({ type: "stopped" });
    // The first answers what the stop asks for, the second reports where the page went.
    await drive(page, [], () => 0, lists);
    state = await drive(page, [], () => 0, lists);
    assert.equal(state.cursor, 0x0300, "a view that does not follow stays where it is");
    assert.equal(state.following, "");
});

test("find by value finds the nearest form, the BASIC's float included", async () => {
    const page = runPage();
    const lists = { frozen: new Map<number, number>(), watched: new Set<string>() };
    // 1000 as a word low first at $2000, high first at $1000, and as AppleSoft's float at $0900.
    const fill = (offset: number) => {
        const placed: Record<number, number> = { 0x2000: 0xE8, 0x2001: 0x03, 0x1000: 0x03, 0x1001: 0xE8, 0x0900: 0x8A, 0x0901: 0x7A, 0x0902: 0, 0x0903: 0, 0x0904: 0 };
        return placed[offset] ?? 0x55;
    };
    page.send({ type: "init", address: 0x0000, info: { bank: null, label: "Memory", readOnly: false }, bookmarks: [] });
    let state = await drive(page, [{ findValue: "=1000" }], fill, lists);
    assert.equal(state.cursor, 0x0900);
    assert.equal(state.status, "Found 1000 as a float, 5 bytes at $0900.");
    state = await drive(page, [{ findValue: "=1000" }], fill, lists);
    assert.equal(state.cursor, 0x1000);
    assert.match(String(state.status), /as a word, high first at \$1000/);
    state = await drive(page, [{ findValue: "=1000" }], fill, lists);
    assert.equal(state.cursor, 0x2000);
    assert.equal(state.anchor, 0x2001, "the match is selected");
    assert.deepEqual(state.back, [0x0000, 0x0900, 0x1000], "each match is one Back returns from");
    state = await drive(page, [{ findValue: "=1000", backward: true }], fill, lists);
    assert.equal(state.cursor, 0x1000);
    state = await drive(page, [{ findValue: "=-2.5" }], fill, lists);
    assert.match(String(state.status), /does not fit/);
});

test("a find whose read fails finds nothing, and says why", async () => {
    const page = runPage();
    page.send({ type: "init", address: 0x0000, info: { bank: null, label: "Memory", readOnly: false }, bookmarks: [] });
    page.send({ type: "test", id: 9, actions: [{ findValue: "=$41" }] });
    let done: Record<string, unknown> | undefined;
    for (let round = 0; round < 20 && done === undefined; round++) {
        await page.settle();
        for (const sent of page.posted.splice(0)) {
            if (sent.type === "testDone") done = sent.state as Record<string, unknown>;
            else if (sent.type === "read") page.send({ type: "reply", id: sent.id, error: "The debug session ended." });
            else if (sent.type === "numbers") page.send({ type: "reply", id: sent.id, result: { formats: [] } });
            else if (sent.type !== "labels" && sent.type !== "characters" && sent.type !== "map" && sent.type !== "banks" && sent.type !== "inspect" && sent.type !== "listing") page.send({ type: "reply", id: sent.id, result: {} });
        }
    }
    assert.ok(done !== undefined, "the find finished");
    assert.equal(done.cursor, 0x0000, "no match from bytes never read");
    assert.match(String(done.status), /session ended/);
});

test("bookmarks mark their bytes and the list goes to one", async () => {
    const page = runPage();
    const lists = { frozen: new Map<number, number>(), watched: new Set<string>() };
    page.send({ type: "init", address: 0x0000, info: { bank: null, label: "Memory", readOnly: false }, bookmarks: [{ address: 0x0002, name: "Two" }] });
    let state = await drive(page, [{ goto: 0x0000 }], () => 0, lists);
    assert.deepEqual(state.bookmarks, [{ address: 2, name: "Two" }]);
    assert.ok(page.elements.get("rows")!.innerHTML.includes('class=" bm" data-o="2" title="Bookmark: Two"'), page.elements.get("rows")!.innerHTML);
    state = await drive(page, [{ bookmarks: true }], () => 0, lists);
    assert.equal(state.cursor, 0x0400);
    assert.deepEqual(state.back, [0x0000]);
    assert.equal(state.status, "Bookmark TEXT_PAGE at $0400.");
    state = await drive(page, [{ bookmark: true }], () => 0, lists);
    assert.deepEqual(state.bookmarks, [{ address: 0x0400, name: "TEXT_PAGE" }], "the label is the name it suggests");

    // Another editor's change shows here.
    page.send({ type: "bookmarks", bookmarks: [] });
    state = await drive(page, [], () => 0, lists);
    assert.deepEqual(state.bookmarks, []);
});
