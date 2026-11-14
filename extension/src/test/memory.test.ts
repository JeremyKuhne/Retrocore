// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import { test } from "node:test";
import { Script, createContext } from "node:vm";
import { addressAt, copyText, findPattern, inspect, labelOf, narrowSearch, parseByte, parsePattern, parseReference, searchStart, textOf, typedText, type PatternByte } from "../memoryModel";
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
    assert.equal(findPattern(bytes, readable, text, -1, true), 3, "backward from before the start wraps to the end");
    assert.equal(findPattern(bytes, readable, text, 7, false), 0, "forward from past the end wraps to the start");
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

// Answers the page's reads with a byte everywhere, or by offset, and its other requests with what they name.
function answer(page: ReturnType<typeof runPage>, fill: (offset: number) => number, readOnly: (offset: number) => boolean = () => false): void {
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
            page.send({ type: "reply", id: sent.id, result: { labels: [{ address: 0x0400, name: "TEXT_PAGE" }] } });
        } else if (sent.type === "characters") {
            page.send({ type: "reply", id: sent.id, result: {} });
        }
    }
}

test("labels show in the gutter and the inspector", async () => {
    const page = runPage();
    page.send({ type: "init", address: 0x0402, info: { bank: null, label: "Memory", readOnly: false } });
    for (let round = 0; round < 3; round++) {
        answer(page, () => 0xA0);
        await page.settle();
    }
    assert.match(page.elements.get("rows")!.innerHTML, /class="lab" style="width:9ch" title="TEXT_PAGE">TEXT_PAGE</);
    assert.match(page.elements.get("rows")!.innerHTML, /class=" lb" data-o="1024" title="TEXT_PAGE"/);
    assert.match(page.elements.get("inspector")!.innerHTML, /\$0402 · TEXT_PAGE\+2/);
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
    assert.match(page.elements.get("inspector")!.innerHTML, /At the last stop.*\$A0/);

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
    assert.match(page.elements.get("inspector")!.innerHTML, /Watch<\/button><button data-act="freeze" title="Stop holding these bytes[^"]*">Thaw</);
    assert.equal(page.elements.get("frozenTab")!.textContent, "Frozen (1)");

    state = await drive(page, [{ type: "41" }], () => 0xA0, lists);
    assert.deepEqual(Array.from(lists.frozen), [[0x0400, 0x41]], "the frozen value follows what was typed");
    state = await drive(page, [{ goto: 0x0400 }, { freeze: true }], () => 0xA0, lists);
    assert.equal(state.frozen, null);
    assert.equal(page.elements.get("frozenTab")!.textContent, "Frozen");
    assert.deepEqual(Array.from(lists.watched), ["[aux:$0400]"]);
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
    assert.match(page.elements.get("inspector")!.innerHTML, /In the snapshot.*\$02/);
    state = await drive(page, [{ compare: false }], fill, lists);
    assert.equal(state.differs, false, "without comparing, changes count from the last stop");
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
});
