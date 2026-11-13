// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import { test } from "node:test";
import { Script, createContext } from "node:vm";
import { copyText, findPattern, inspect, parsePattern, parseReference, textOf, typedText, type PatternByte } from "../memoryModel";
import { memoryEditorHtml } from "../memoryView";

test("memory references split into a bank and an address; expressions do not", () => {
    assert.deepEqual(parseReference("0x0400"), { bank: null, address: 0x0400 });
    assert.deepEqual(parseReference("aux:0x0400"), { bank: "aux", address: 0x0400 });
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
    assert.equal(findPattern(bytes, readable, text, -1, true), 0, "backward from before the start");
    assert.equal(findPattern(bytes, readable, parsePattern("A9 ??") as PatternByte[], 0, false), 6);
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
}

/** Runs the page's script with fake elements, recording what it posts to the extension. */
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
    return { elements, posted, send, settle, key };
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
    const write = page.posted.shift()!;
    assert.deepEqual({ type: write.type, offset: write.offset, data: write.data }, { type: "write", offset: 0x0400, data: [0x41] });
    page.send({ type: "reply", id: write.id, result: { bytesWritten: 1 } });
    await page.settle();
    assert.match(page.elements.get("inspector")!.innerHTML, /aux:\$0401/, "the cursor moves on");

    page.key("z", { ctrlKey: true });
    await page.settle();
    const undo = page.posted.shift()!;
    assert.deepEqual({ offset: undo.offset, data: undo.data }, { offset: 0x0400, data: [0xA0] });
    page.send({ type: "reply", id: undo.id, result: { bytesWritten: 1 } });
    await page.settle();

    // A refused write puts the byte back and says why.
    page.key("F");
    page.key("F");
    await page.settle();
    const refused = page.posted.shift()!;
    page.send({ type: "reply", id: refused.id, error: "$0400 reads the system ROM now, not RAM." });
    await page.settle();
    assert.equal(page.elements.get("status")!.textContent, "$0400 reads the system ROM now, not RAM.");
    assert.match(page.elements.get("inspector")!.innerHTML, /\$A0/);
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
