// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Retrocore Memory's page: a hex and text grid over a whole 64K space, with go to, find, copy, editing with undo
// and an inspector. The page asks the extension for bytes and writes; the extension asks the debugger.

import { pageFunctions } from "./memoryModel";

/** The memory editor's page, with its script allowed by the nonce. */
export function memoryEditorHtml(nonce: string): string {
    return `<!doctype html><html><head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}'">
<style>
[hidden]{display:none!important}
html,body{height:100%}
body{margin:0;display:flex;flex-direction:column;background:var(--vscode-editor-background);color:var(--vscode-editor-foreground);font-family:var(--vscode-font-family);font-size:var(--vscode-font-size);overflow:hidden}
.bar{display:flex;gap:12px;align-items:center;padding:6px 10px;border-bottom:1px solid var(--vscode-panel-border)}
.bar label{display:flex;gap:4px;align-items:center;white-space:nowrap}
.bar .title{font-weight:600;margin-right:auto;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
input{font-family:var(--vscode-editor-font-family);font-size:12px;padding:2px 4px;border-radius:2px;width:150px;background:var(--vscode-input-background);color:var(--vscode-input-foreground);border:1px solid var(--vscode-input-border,transparent)}
input:focus{outline:1px solid var(--vscode-focusBorder);outline-offset:-1px}
.main{flex:1;display:flex;min-height:0}
#grid{flex:none;overflow:auto;position:relative;outline:none;font-family:var(--vscode-editor-font-family);font-size:var(--vscode-editor-font-size);white-space:pre;user-select:none;cursor:text}
#spacer{position:absolute;top:0;left:0;width:1px}
#rows{position:absolute;top:0;left:0;right:0}
.row{height:20px;line-height:20px;padding:0 10px;width:max-content}
.addr{display:inline-block;width:6ch;color:var(--vscode-editorLineNumber-foreground)}
.hex span{display:inline-block;width:3ch;text-align:left}
.hex span.mid{margin-left:1ch}
.txt{margin-left:2ch}
.txt span{display:inline-block;width:1ch}
.hi{color:var(--vscode-debugTokenExpression-string,var(--vscode-editor-foreground))}
.gap{color:var(--vscode-disabledForeground)}
.sel{background:var(--vscode-editor-inactiveSelectionBackground)}
.cur{outline:1px solid var(--vscode-editorCursor-foreground,var(--vscode-focusBorder));outline-offset:-1px}
#grid:focus .cur.on{background:var(--vscode-editor-selectionBackground)}
.pending{color:var(--vscode-editorWarning-foreground)}
#inspector{flex:1;min-width:0;overflow-y:auto;padding:8px 12px;border-left:1px solid var(--vscode-panel-border);font-size:12px}
#inspector .where{font-family:var(--vscode-editor-font-family);margin-bottom:8px}
.item{display:flex;gap:8px;padding:2px 0}
.item .k{width:9em;flex:none;color:var(--vscode-descriptionForeground);white-space:nowrap}
.item .v{font-family:var(--vscode-editor-font-family);white-space:pre}
body.narrow .main{flex-direction:column}
body.narrow #grid{flex:1}
body.narrow #inspector{flex:none;display:flex;flex-wrap:wrap;gap:2px 24px;align-items:baseline;max-height:35%;border-left:none;border-top:1px solid var(--vscode-panel-border)}
body.narrow #inspector .where{margin:0;padding:2px 0}
body.narrow .item .k{width:auto}
#status{padding:3px 10px;border-top:1px solid var(--vscode-panel-border);font-size:12px;color:var(--vscode-descriptionForeground);min-height:16px}
#status.error{color:var(--vscode-errorForeground)}
.ended{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;background:color-mix(in srgb,var(--vscode-editor-background) 80%,transparent);font-size:14px}
</style></head>
<body>
<div class="bar"><span class="title" id="title">Memory</span>
<label title="An address, label or expression, such as $0400, TEXT_PAGE or HL+2 (Ctrl+G)">Go to <input id="goto" aria-label="Go to address" placeholder="$0400"></label>
<label title="Hex bytes with ?? for any byte, such as A9 ?? 20, or text in quotes; Enter finds the next, Shift+Enter the one before (Ctrl+F, F3)">Find <input id="find" aria-label="Find" placeholder="A9 ?? 20 or &quot;TEXT&quot;"></label>
</div>
<div class="main"><div id="grid" tabindex="0" role="grid" aria-label="Memory bytes"><div id="spacer"></div><div id="rows"></div></div>
<div id="inspector" aria-live="polite"></div></div>
<div id="status" role="status"></div>
<div class="ended" id="ended" hidden>The debug session ended.</div>
<script nonce="${nonce}">
${pageFunctions.map(fn => fn.toString()).join("\n")}
const vscode = acquireVsCodeApi();
const SIZE = 0x10000, ROW = 16, ROWS = SIZE / ROW, LINE = 20, PAGE = 256;
const bytes = new Uint8Array(SIZE);
// 0 not read yet, 1 readable, 2 unreadable.
const readable = new Uint8Array(SIZE);
// 0 to read, 1 read and current, 2 being read.
const pages = new Uint8Array(SIZE / PAGE);
const grid = document.getElementById("grid"), rows = document.getElementById("rows"), inspector = document.getElementById("inspector");
const statusLine = document.getElementById("status"), gotoBox = document.getElementById("goto"), findBox = document.getElementById("find");
document.getElementById("spacer").style.height = (ROWS * LINE) + "px";
let info = { bank: null, label: "", readOnly: false };
let cursor = 0, anchor = 0, pane = "hex", nibble = null, ended = false, dragging = false, generation = 0;
const undoStack = [], redoStack = [];
let nextId = 1;
const pending = new Map();

function request(message) {
    const id = nextId++;
    message.id = id;
    vscode.postMessage(message);
    return new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
}

function status(text, error) {
    statusLine.textContent = text;
    statusLine.className = error ? "error" : "";
}

function decode(base64) {
    const binary = atob(base64);
    const data = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index++) data[index] = binary.charCodeAt(index);
    return data;
}

// The reads under way, which writes and the test hook wait for.
const loads = new Set();

function load(offset, count) {
    const loading = read(offset, count);
    loads.add(loading);
    loading.finally(() => loads.delete(loading));
    return loading;
}

// Waits until the bytes from an offset have been read at least once, reading them now if no one has.
async function loaded(offset, count) {
    await Promise.all(Array.from(loads));
    for (let index = 0; index < count; index++) {
        if (readable[offset + index] === 0) {
            const page = Math.floor((offset + index) / PAGE);
            await load(page * PAGE, PAGE);
        }
    }
}

async function read(offset, count) {
    const first = offset / PAGE, last = (offset + count) / PAGE;
    const loading = generation;
    for (let page = first; page < last; page++) pages[page] = 2;
    try {
        const result = await request({ type: "read", offset, count });
        const data = decode(result.data);
        for (let index = 0; index < count; index++) {
            bytes[offset + index] = data[index];
            readable[offset + index] = 1;
        }
        for (const gap of result.unreadable) {
            for (let index = 0; index < gap.count; index++) readable[offset + gap.offset + index] = 2;
        }
        for (let page = first; page < last; page++) pages[page] = loading === generation ? 1 : 0;
    } catch (error) {
        for (let page = first; page < last; page++) pages[page] = 0;
        status(String(error.message || error), true);
        return;
    }
    render();
}

// Reads the pages from one row to another that have not been read since memory last changed, in runs.
function ensure(firstRow, lastRow) {
    if (ended) return;
    const firstPage = Math.max(0, Math.floor(firstRow * ROW / PAGE));
    const lastPage = Math.min(SIZE / PAGE - 1, Math.floor((lastRow * ROW + ROW - 1) / PAGE));
    let start = -1;
    for (let page = firstPage; page <= lastPage + 1; page++) {
        const wanted = page <= lastPage && pages[page] === 0;
        if (wanted && start < 0) start = page;
        if (!wanted && start >= 0) {
            void load(start * PAGE, (page - start) * PAGE);
            start = -1;
        }
    }
}

// Reads all of memory not read yet, for find.
async function ensureAll() {
    if (pages.every(page => page === 1)) return;
    await load(0, SIZE);
}

function visibleRows() {
    return Math.max(1, Math.floor(grid.clientHeight / LINE));
}

function escape(character) {
    return character === "<" ? "&lt;" : character === ">" ? "&gt;" : character === "&" ? "&amp;" : character;
}

function rowHtml(row) {
    const base = row * ROW;
    const low = Math.min(cursor, anchor), high = Math.max(cursor, anchor);
    let hexPart = "", textPart = "";
    for (let index = 0; index < ROW; index++) {
        const offset = base + index;
        let classes = index === 8 ? "mid" : "";
        if (low !== high && offset >= low && offset <= high) classes += " sel";
        let shown = "  ", character = " ", textClasses = classes.replace("mid", "");
        if (readable[offset] === 1) {
            shown = hex(bytes[offset], 2);
            character = escape(textOf(bytes[offset]));
            if (bytes[offset] > 0x7F) textClasses += " hi";
        } else if (readable[offset] === 2) {
            shown = "··";
            character = "·";
            classes += " gap";
            textClasses += " gap";
        }
        if (offset === cursor) {
            classes += " cur" + (pane === "hex" ? " on" : "");
            textClasses += " cur" + (pane === "text" ? " on" : "");
            if (pane === "hex" && nibble !== null) {
                shown = nibble.toString(16).toUpperCase() + "_";
                classes += " pending";
            }
        }
        hexPart += '<span class="' + classes + '" data-o="' + offset + '">' + shown + "</span>";
        textPart += '<span class="' + textClasses + '" data-o="' + offset + '" data-t="1">' + character + "</span>";
    }
    return '<div class="row"><span class="addr">' + hex(base, 4) + '</span><span class="hex">' + hexPart
        + '</span><span class="txt">' + textPart + "</span></div>";
}

function render() {
    const top = Math.floor(grid.scrollTop / LINE);
    const count = visibleRows() + 2;
    let html = "";
    for (let row = top; row < Math.min(ROWS, top + count); row++) html += rowHtml(row);
    rows.style.transform = "translateY(" + (top * LINE) + "px)";
    rows.innerHTML = html;
    if (layout()) { render(); return; }
    ensure(top - count, top + 2 * count);
    showInspector();
}

function where(offset) {
    return (info.bank === null ? "" : info.bank + ":") + "$" + hex(offset, 4);
}

function showInspector() {
    const low = Math.min(cursor, anchor), high = Math.max(cursor, anchor);
    let html = '<div class="where">' + where(cursor);
    if (high > low) html += " · " + (high - low + 1) + " bytes, " + where(low) + "-$" + hex(high, 4);
    html += "</div>";
    for (const row of inspect(bytes, readable, cursor)) {
        html += '<div class="item"><span class="k">' + escapeText(row.label) + '</span><span class="v">' + escapeText(row.value) + "</span></div>";
    }
    inspector.innerHTML = html;
}

// The narrowest the inspector gets beside the bytes; narrower than that, it moves under them.
const INSPECTOR = 240;
let narrow = null;

// Fits the bytes' column to its rows and gives the inspector the rest, or docks the inspector under the bytes
// when both do not fit. Returns whether that changed, which changes how many rows show.
function layout() {
    const first = rows.firstElementChild;
    if (!first || !document.body) return false;
    const content = first.offsetWidth + (grid.offsetWidth - grid.clientWidth);
    const docked = document.body.clientWidth < content + INSPECTOR;
    grid.style.width = docked ? "" : content + "px";
    if (docked === narrow) return false;
    narrow = docked;
    document.body.classList.toggle("narrow", docked);
    return true;
}

function escapeText(text) {
    let result = "";
    for (const character of text) result += escape(character);
    return result;
}

function reveal(offset, center) {
    const row = Math.floor(offset / ROW), top = Math.floor(grid.scrollTop / LINE), shown = visibleRows();
    if (center) {
        grid.scrollTop = Math.max(0, row - Math.floor(shown / 3)) * LINE;
    } else if (row < top) {
        grid.scrollTop = row * LINE;
    } else if (row >= top + shown) {
        grid.scrollTop = (row - shown + 1) * LINE;
    }
}

function moveTo(offset, extend, center) {
    cursor = Math.min(SIZE - 1, Math.max(0, offset));
    if (!extend) anchor = cursor;
    nibble = null;
    reveal(cursor, center);
    render();
}

// Why bytes cannot be written, or null when they can be tried; the debugger refuses ROM in the CPU's memory.
function writeProblem(offset, count) {
    if (ended) return "The debug session ended.";
    if (info.readOnly) return info.label + " is read-only.";
    for (let index = 0; index < count; index++) {
        if (readable[offset + index] !== 1) return "There is no byte to write at " + where(offset + index) + ".";
    }
    return null;
}

async function write(offset, values, record) {
    await loaded(offset, values.length);
    const problem = writeProblem(offset, values.length);
    if (problem !== null) {
        status(problem, true);
        return false;
    }
    const before = values.map((_, index) => bytes[offset + index]);
    values.forEach((value, index) => { bytes[offset + index] = value; });
    render();
    try {
        await request({ type: "write", offset, data: values });
    } catch (error) {
        before.forEach((value, index) => { bytes[offset + index] = value; });
        render();
        status(String(error.message || error), true);
        return false;
    }
    if (record) {
        undoStack.push({ offset, before, after: values });
        redoStack.length = 0;
    }
    status("");
    return true;
}

async function undo() {
    const edit = undoStack.pop();
    if (edit === undefined) { status("Nothing to undo."); return; }
    if (await write(edit.offset, edit.before, false)) {
        redoStack.push(edit);
        moveTo(edit.offset, false, false);
    } else {
        undoStack.push(edit);
    }
}

async function redo() {
    const edit = redoStack.pop();
    if (edit === undefined) { status("Nothing to redo."); return; }
    if (await write(edit.offset, edit.after, false)) {
        undoStack.push(edit);
        moveTo(edit.offset, false, false);
    } else {
        redoStack.push(edit);
    }
}

// Typing a character: a hex digit in the hex column, which writes the byte at its second digit, or a character in
// the text column, which writes it at once.
async function typeKey(key) {
    if (pane === "text") {
        const value = typedText(key, bytes[cursor]);
        if (value === undefined) return;
        const at = cursor;
        if (await write(at, [value], true)) moveTo(at + 1, false, false);
        return;
    }
    const digit = parseInt(key, 16);
    if (isNaN(digit) || key.length !== 1) return;
    if (nibble === null) {
        await loaded(cursor, 1);
        const problem = writeProblem(cursor, 1);
        if (problem !== null) {
            status(problem, true);
            return;
        }
        nibble = digit;
        render();
        return;
    }
    const value = nibble * 16 + digit, at = cursor;
    nibble = null;
    if (await write(at, [value], true)) moveTo(at + 1, false, false);
    else render();
}

// Keys and undo run one at a time, in the order pressed, as each may wait for bytes to be read.
let typing = Promise.resolve();
function queue(action) {
    typing = typing.then(action, action);
}

async function goTo(text) {
    if (text.trim().length === 0) return;
    try {
        const result = await request({ type: "goto", text });
        moveTo(result.address, false, true);
        status("");
        grid.focus();
    } catch (error) {
        status(String(error.message || error), true);
    }
}

async function find(backward) {
    const pattern = parsePattern(findBox.value);
    if (typeof pattern === "string") { status(pattern, true); return; }
    await ensureAll();
    const at = findPattern(bytes, readable, pattern, backward ? cursor - 1 : cursor + 1, backward);
    if (at < 0) { status("Not found.", true); return; }
    anchor = at + pattern.length - 1;
    cursor = at;
    nibble = null;
    reveal(at, true);
    render();
    status("Found at " + where(at) + ".");
}

function copy() {
    const low = Math.min(cursor, anchor), high = Math.max(cursor, anchor);
    void request({ type: "copy", text: copyText(bytes, readable, low, high, pane === "text") });
}

grid.addEventListener("scroll", render);
window.addEventListener("resize", render);

function offsetAt(event) {
    const target = event.target.closest ? event.target.closest("[data-o]") : null;
    return target === null ? null : { offset: Number(target.dataset.o), text: target.dataset.t === "1" };
}

grid.addEventListener("mousedown", event => {
    const hit = offsetAt(event);
    if (hit === null) return;
    pane = hit.text ? "text" : "hex";
    dragging = true;
    moveTo(hit.offset, event.shiftKey, false);
    grid.focus();
    event.preventDefault();
});
grid.addEventListener("mousemove", event => {
    if (!dragging) return;
    const hit = offsetAt(event);
    if (hit !== null && hit.offset !== cursor) moveTo(hit.offset, true, false);
});
window.addEventListener("mouseup", () => { dragging = false; });

grid.addEventListener("keydown", event => {
    const control = event.ctrlKey || event.metaKey;
    const key = event.key;
    let handled = true;
    const page = visibleRows() * ROW;
    if (control && (key === "z" || key === "Z")) {
        queue(event.shiftKey ? redo : undo);
    } else if (control && (key === "y" || key === "Y")) {
        queue(redo);
    } else if (control && (key === "c" || key === "C")) {
        copy();
    } else if (control && (key === "g" || key === "G")) {
        gotoBox.focus();
        gotoBox.select();
    } else if (control && (key === "f" || key === "F")) {
        findBox.focus();
        findBox.select();
    } else if (key === "F3") {
        void find(event.shiftKey);
    } else if (key === "ArrowLeft") {
        moveTo(cursor - 1, event.shiftKey, false);
    } else if (key === "ArrowRight") {
        moveTo(cursor + 1, event.shiftKey, false);
    } else if (key === "ArrowUp") {
        moveTo(cursor - ROW, event.shiftKey, false);
    } else if (key === "ArrowDown") {
        moveTo(cursor + ROW, event.shiftKey, false);
    } else if (key === "PageUp") {
        grid.scrollTop -= visibleRows() * LINE;
        moveTo(cursor - page, event.shiftKey, false);
    } else if (key === "PageDown") {
        grid.scrollTop += visibleRows() * LINE;
        moveTo(cursor + page, event.shiftKey, false);
    } else if (key === "Home") {
        moveTo(control ? 0 : cursor - cursor % ROW, event.shiftKey, false);
    } else if (key === "End") {
        moveTo(control ? SIZE - 1 : cursor - cursor % ROW + ROW - 1, event.shiftKey, false);
    } else if (key === "Tab") {
        pane = pane === "hex" ? "text" : "hex";
        nibble = null;
        render();
    } else if (key === "Escape" && nibble !== null) {
        nibble = null;
        render();
    } else if (!control && !event.altKey && key.length === 1) {
        queue(() => typeKey(key));
    } else {
        handled = false;
    }
    if (handled) {
        event.preventDefault();
        // VS Code sees the keys a webview does not stop, and Ctrl+G would open its own Go to Line.
        event.stopPropagation();
    }
});

gotoBox.addEventListener("keydown", event => {
    if (event.key === "Enter") void goTo(gotoBox.value);
    else if (event.key === "Escape") grid.focus();
    else return;
    event.preventDefault();
    event.stopPropagation();
});
findBox.addEventListener("keydown", event => {
    if (event.key === "Enter" || event.key === "F3") void find(event.shiftKey);
    else if (event.key === "Escape") grid.focus();
    else return;
    event.preventDefault();
    event.stopPropagation();
});

// The test suite drives the page through the extension: these do what the keys do and report where it stands.
async function test(actions) {
    for (const action of actions) {
        if (action.goto !== undefined) moveTo(action.goto, false, true);
        if (action.pane !== undefined) { pane = action.pane; render(); }
        if (action.type !== undefined) { for (const key of action.type) await typeKey(key); }
        if (action.find !== undefined) { findBox.value = action.find; await find(false); }
        if (action.undo) await undo();
        if (action.redo) await redo();
        await loaded(cursor, 1);
    }
    return {
        cursor, anchor, pane,
        status: statusLine.textContent,
        inspector: inspect(bytes, readable, cursor),
        hex: Array.from(rows.querySelectorAll(".hex span")).map(span => span.textContent).slice(0, 64)
    };
}

window.addEventListener("message", event => {
    const message = event.data;
    if (message.type === "reply") {
        const waiting = pending.get(message.id);
        if (waiting === undefined) return;
        pending.delete(message.id);
        if (message.error !== undefined) waiting.reject(new Error(message.error));
        else waiting.resolve(message.result);
    } else if (message.type === "init") {
        info = message.info;
        document.getElementById("title").textContent = info.label + (info.bank === null ? "" : " (" + info.bank + ")");
        cursor = anchor = message.address;
        reveal(cursor, true);
        render();
        grid.focus();
    } else if (message.type === "changed") {
        generation++;
        pages.fill(0);
        render();
    } else if (message.type === "ended") {
        ended = true;
        document.getElementById("ended").hidden = false;
    } else if (message.type === "test") {
        test(message.actions).then(
            state => vscode.postMessage({ type: "testDone", id: message.id, state }),
            error => vscode.postMessage({ type: "testDone", id: message.id, error: String(error) }));
    }
});

vscode.postMessage({ type: "ready" });
</script></body></html>`;
}
