// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Retrocore Memory's page: a hex and text grid over a whole 64K space, with labels, rows aligned to them, the
// machine's own characters, read-only shading, changes since the last stop or differences from a snapshot or another
// bank, go to, find, copy, editing with undo, an inspector, RAM search of bytes or words, watching in VS Code's Watch
// view and frozen bytes. The page asks the extension for bytes, labels,
// characters, writes, freezes and watches; the extension asks the debugger, or VS Code for watches.

import { pageFunctions } from "./memoryModel";

/** The memory editor's page, with its script allowed by the nonce. */
export function memoryEditorHtml(nonce: string): string {
    return `<!doctype html><html><head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; script-src 'nonce-${nonce}'">
<style>
[hidden]{display:none!important}
html,body{height:100%}
body{margin:0;display:flex;flex-direction:column;background:var(--vscode-editor-background);color:var(--vscode-editor-foreground);font-family:var(--vscode-font-family);font-size:var(--vscode-font-size);overflow:hidden}
.bar{display:flex;flex-wrap:wrap;gap:6px 12px;align-items:center;padding:6px 10px;border-bottom:1px solid var(--vscode-panel-border)}
.bar label{display:flex;gap:4px;align-items:center;white-space:nowrap}
.bar .title{font-weight:600;margin-right:auto;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
input{font-family:var(--vscode-editor-font-family);font-size:12px;padding:2px 4px;border-radius:2px;width:150px;background:var(--vscode-input-background);color:var(--vscode-input-foreground);border:1px solid var(--vscode-input-border,transparent)}
select{font-family:var(--vscode-font-family);font-size:12px;padding:1px 2px;border-radius:2px;background:var(--vscode-dropdown-background);color:var(--vscode-dropdown-foreground);border:1px solid var(--vscode-dropdown-border,transparent)}
input[type=checkbox]{width:auto;margin:0}
input:focus{outline:1px solid var(--vscode-focusBorder);outline-offset:-1px}
button{font-family:var(--vscode-font-family);font-size:12px;padding:2px 8px;border-radius:2px;cursor:pointer;color:var(--vscode-button-secondaryForeground);background:var(--vscode-button-secondaryBackground);border:1px solid var(--vscode-button-border,transparent)}
button:hover{background:var(--vscode-button-secondaryHoverBackground)}
button:focus-visible{outline:1px solid var(--vscode-focusBorder);outline-offset:1px}
button:disabled{opacity:.5;cursor:default}
.main{flex:1;display:flex;min-height:0}
#grid{flex:none;overflow:auto;position:relative;outline:none;font-family:var(--vscode-editor-font-family);font-size:var(--vscode-editor-font-size);white-space:pre;user-select:none;cursor:text}
#spacer{position:absolute;top:0;left:0;width:1px}
#rows{position:absolute;top:0;left:0;right:0}
.row{height:20px;line-height:20px;padding:0 10px;width:max-content}
.addr{display:inline-block;width:6ch;color:var(--vscode-editorLineNumber-foreground)}
.lab{display:inline-block;overflow:hidden;text-overflow:ellipsis;vertical-align:top;margin-right:1ch;color:var(--vscode-symbolIcon-functionForeground,var(--vscode-editor-foreground))}
.lab.in{opacity:.6}
.hex span.lb{background-image:linear-gradient(135deg,var(--vscode-symbolIcon-functionForeground,var(--vscode-focusBorder)) 5px,transparent 5px)}
.ro{background-color:color-mix(in srgb,var(--vscode-editor-foreground) 8%,transparent)}
.chg{background-color:var(--vscode-debugView-valueChangedHighlight,rgba(86,156,214,.35))}
.frz{color:var(--vscode-charts-blue,#3794ff);font-weight:600}
.txt.g span{height:16px;vertical-align:middle;background-size:100% 100%;background-repeat:no-repeat;image-rendering:pixelated}
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
#side{flex:1;min-width:0;display:flex;flex-direction:column;border-left:1px solid var(--vscode-panel-border);font-size:12px}
.tabs{display:flex;gap:2px;padding:4px 8px 0;border-bottom:1px solid var(--vscode-panel-border)}
.tabs button{background:none;border:none;border-bottom:2px solid transparent;border-radius:0;color:var(--vscode-descriptionForeground);padding:4px 8px}
.tabs button.on{color:var(--vscode-foreground);border-bottom-color:var(--vscode-focusBorder)}
.panel{flex:1;min-height:0;overflow-y:auto;padding:8px 12px}
.acts{display:flex;gap:6px;margin-bottom:8px}
.panel p{margin:0 0 8px;color:var(--vscode-descriptionForeground)}
.filters{display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin:8px 0}
.filters input{width:70px}
.count{font-weight:600}
.hits{font-family:var(--vscode-editor-font-family);margin-top:8px}
.hit{display:flex;gap:12px;align-items:center;padding:1px 4px;cursor:pointer;border-radius:2px}
.hit:hover{background:var(--vscode-list-hoverBackground)}
.hit .a{min-width:16ch}
.hit .v{min-width:9ch}
.hit button,.hit label{margin-left:auto}
.hit label{display:flex;gap:4px;align-items:center;font-family:var(--vscode-font-family)}
#inspector .where{font-family:var(--vscode-editor-font-family);margin-bottom:8px}
.item{display:flex;gap:8px;padding:2px 0}
.item .k{width:9em;flex:none;color:var(--vscode-descriptionForeground);white-space:nowrap}
.item .v{font-family:var(--vscode-editor-font-family);white-space:pre}
#listing{flex:none;width:46ch;overflow:hidden;border-left:1px solid var(--vscode-panel-border);font-family:var(--vscode-editor-font-family);font-size:var(--vscode-editor-font-size);white-space:pre}
#listing .ln{height:20px;line-height:20px;padding:0 8px;cursor:pointer;display:flex;gap:1ch}
#listing .ln:hover{background:var(--vscode-list-hoverBackground)}
#listing .ln.sel{background:var(--vscode-editor-inactiveSelectionBackground)}
#listing .ln.cur{outline:1px solid var(--vscode-editorCursor-foreground,var(--vscode-focusBorder));outline-offset:-1px}
#listing .a{color:var(--vscode-editorLineNumber-foreground)}
#listing .l{width:10ch;flex:none;overflow:hidden;text-overflow:ellipsis;color:var(--vscode-symbolIcon-functionForeground,var(--vscode-editor-foreground))}
#listing .unknown .t{opacity:.7}
#listing .data .t{color:var(--vscode-debugTokenExpression-number,var(--vscode-editor-foreground))}
#listing a{color:var(--vscode-textLink-foreground);text-decoration:none;cursor:pointer}
#listing a:hover{text-decoration:underline}
#listing .src{margin-left:auto;padding-left:1ch;overflow:hidden;text-overflow:ellipsis;color:var(--vscode-descriptionForeground)}
#listing p{margin:8px;white-space:normal;color:var(--vscode-descriptionForeground);font-family:var(--vscode-font-family);font-size:12px}
body.narrow #listing{display:none}
body.narrow .main{flex-direction:column}
body.narrow #grid{flex:1}
body.narrow #side{flex:none;max-height:40%;border-left:none;border-top:1px solid var(--vscode-panel-border)}
body.narrow #inspector{display:flex;flex-wrap:wrap;gap:2px 24px;align-items:baseline}
body.narrow #inspector .acts{margin:0}
body.narrow #inspector .where{margin:0;padding:2px 0}
body.narrow .item .k{width:auto}
#status{padding:3px 10px;border-top:1px solid var(--vscode-panel-border);font-size:12px;color:var(--vscode-descriptionForeground);min-height:16px}
#status.error{color:var(--vscode-errorForeground)}
.ended{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;background:color-mix(in srgb,var(--vscode-editor-background) 80%,transparent);font-size:14px}
</style></head>
<body>
<div class="bar"><span class="title" id="title">Memory</span>
<label title="Show the bytes as instructions and data beside them"><input type="checkbox" id="listingBox" checked> Listing</label>
<label id="alignLabel" title="Start a row where each label starts, so a label's bytes begin a row of their own" hidden><input type="checkbox" id="align"> Align to labels</label>
<label id="machineLabel" title="Draw the text column in the machine's own characters, or as ASCII" hidden><input type="checkbox" id="machineText" checked> Machine text</label>
<button id="snapshot" title="Keep a copy of every byte now, to compare with">Snapshot</button>
<label title="Highlight the bytes that differ from what they held at the stop before, from the snapshot, or from another bank's bytes at the same addresses">Compare with <select id="compareWith" aria-label="Compare with"><option value="">the last stop</option></select></label>
<label title="An address, label or expression, such as $0400, TEXT_PAGE or HL+2 (Ctrl+G)">Go to <input id="goto" aria-label="Go to address" placeholder="$0400"></label>
<label title="Hex bytes with ?? for any byte, such as A9 ?? 20, or text in quotes; Enter finds the next, Shift+Enter the one before (Ctrl+F, F3)">Find <input id="find" aria-label="Find" placeholder="A9 ?? 20 or &quot;TEXT&quot;"></label>
</div>
<div class="main"><div id="grid" tabindex="0" role="grid" aria-label="Memory bytes"><div id="spacer"></div><div id="rows"></div></div>
<div id="listing" role="list" aria-label="Listing"></div>
<div id="side"><div class="tabs" role="tablist"><button role="tab" data-tab="inspector" class="on">Inspector</button><button role="tab" data-tab="search">RAM search</button><button role="tab" data-tab="frozen" id="frozenTab">Frozen</button></div>
<div id="inspector" class="panel" aria-live="polite"></div><div id="search" class="panel" hidden></div><div id="frozen" class="panel" hidden></div></div></div>
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
// 1 where a write cannot reach now, such as ROM.
const readOnly = new Uint8Array(SIZE);
// Changes since the last stop: each byte as first read after it, the stop each page was last compared at, which
// bytes differ and what they were.
const seen = new Uint8Array(SIZE), seenStop = new Int32Array(SIZE / PAGE).fill(-1);
const changed = new Uint8Array(SIZE), was = new Uint8Array(SIZE);
let stops = 0;
// The labels in address order and by address, and how wide the gutter shows them.
let labels = [], labelAt = new Map(), labelWidth = 0;
// The machine's character set as the debugger gave it, whether the text column uses it (the page remembers), and the set in effect.
let machineSet = null, machineText = true, charset = null, glyphStyle = null, flashTimer = null;
// Whether rows start where labels do; then each row's first address, else every row is ROW bytes from a multiple of ROW.
let aligned = false, rowStarts = null;
// Whether the listing shows (the page remembers), the lines it shows, which request they answer, its width, and the
// addresses Decode from here started an instruction at.
let showListing = true, listingLines = [], listingKey = "", listingWidth = 0;
const forcedStarts = new Set();
try {
    const saved = vscode.getState();
    if (saved && typeof saved.showListing === "boolean") showListing = saved.showListing;
    if (saved && typeof saved.machineText === "boolean") machineText = saved.machineText;
    if (saved && typeof saved.aligned === "boolean") aligned = saved.aligned;
} catch {
    // A page without saved state uses the machine's characters, in rows of ROW bytes.
}

// Remembers the page's choices, which are conveniences.
function remember() {
    try {
        vscode.setState({ machineText, aligned, showListing });
    } catch {
        // Nothing to do: the page works without them.
    }
}

// The rows: with rows aligned to labels, a row starts at each multiple of ROW and at each label between.
function layoutRows() {
    // What shows stays: the cursor's row where it is when it shows, else the top row's address at the top.
    const top = Math.floor(grid.scrollTop / LINE), within = grid.scrollTop - top * LINE, shownAt = rowOf(cursor) - top, topAddress = rowStart(Math.min(top, rowCount() - 1));
    const showing = shownAt >= 0 && shownAt < visibleRows();
    rowStarts = null;
    if (aligned && labels.length > 0) {
        const starts = [];
        let next = 0;
        for (let block = 0; block < SIZE; block += ROW) {
            starts.push(block);
            while (next < labels.length && labels[next].address < block + ROW) {
                if (labels[next].address > block && labels[next].address !== starts[starts.length - 1]) starts.push(labels[next].address);
                next++;
            }
        }
        rowStarts = Int32Array.from(starts);
    }
    document.getElementById("spacer").style.height = (rowCount() * LINE) + "px";
    // Partway into a row, the view stays as far into it.
    grid.scrollTop = (showing ? Math.max(0, rowOf(cursor) - shownAt) : rowOf(topAddress)) * LINE + within;
}

function rowCount() {
    return rowStarts === null ? ROWS : rowStarts.length;
}

// A row's first address.
function rowStart(row) {
    return rowStarts === null ? row * ROW : rowStarts[row];
}

// A row's last address.
function rowEnd(row) {
    return row + 1 >= rowCount() ? SIZE - 1 : rowStart(row + 1) - 1;
}

// The row an address is in.
function rowOf(offset) {
    if (rowStarts === null) return Math.floor(offset / ROW);
    let low = 0, high = rowStarts.length - 1;
    while (low < high) {
        const middle = (low + high + 1) >> 1;
        if (rowStarts[middle] <= offset) low = middle;
        else high = middle - 1;
    }
    return low;
}

// The address in a row at a column, or the nearest the row has, as moving up and down keeps the column.
function atColumn(row, column) {
    const start = rowStart(row), end = rowEnd(row);
    return Math.min(end, Math.max(start, start - start % ROW + column));
}

// Moves the cursor by rows, keeping its column.
function moveRows(count, extend) {
    const row = Math.min(rowCount() - 1, Math.max(0, rowOf(cursor) + count));
    moveTo(atColumn(row, cursor % ROW), extend, false);
}
const machineBox = document.getElementById("machineText"), machineLabel = document.getElementById("machineLabel");
const alignBox = document.getElementById("align"), alignLabel = document.getElementById("alignLabel");
alignBox.checked = aligned;

// Puts the machine's characters in effect, or ASCII, as the toggle says; the toggle shows when there is a set.
function applyText() {
    charset = machineText ? machineSet : null;
    machineLabel.hidden = machineSet === null;
    machineBox.checked = machineText;
}
// What the grid highlights the bytes that differ from: "" for what they held at the stop before, "snapshot", or
// another bank's memory reference. Then the snapshot of every byte, the other banks, and the compared bank's bytes,
// read again at each stop.
let comparison = "", snapshot = null, otherBanks = [], other = null;
// A RAM search: the size of the values it looks for, 1 or 2 bytes, the offsets still in it, every byte as the last
// step saw it, and the steps before, to go back.
let search = null;
// The frozen bytes as the debugger keeps them, by the value each is held at, and the last watch expressions added.
let frozen = new Map(), lastWatch = [];
const listingPanel = document.getElementById("listing"), listingBox = document.getElementById("listingBox");
listingBox.checked = showListing;
listingPanel.hidden = !showListing;
const side = document.getElementById("side"), searchPanel = document.getElementById("search"), frozenPanel = document.getElementById("frozen");
const compareSelect = document.getElementById("compareWith");
let tab = "inspector";
let info = { bank: null, label: "", readOnly: false, bigEndian: false };
let cursor = 0, anchor = 0, pane = "hex", nibble = null, ended = false, dragging = false, generation = 0;
// Counts the cursor's moves and pane switches, so an edit still waiting on the debugger knows the user went elsewhere.
let moves = 0;
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

// Waits until the bytes from an offset are as memory holds them now, reading the pages not read since the last stop
// or change, as one scrolled out of view is not; copying, freezing, typing and undo take the bytes they act on from
// here. Reports whether they are: a read that fails, or that a stop or change overtakes a few times running, leaves
// bytes from before, which the caller must not act on. A failed read's status line says why.
async function loaded(offset, count) {
    if (count <= 0) return true;
    const first = Math.floor(offset / PAGE), last = Math.floor((offset + count - 1) / PAGE);
    for (let attempt = 0; attempt < 3; attempt++) {
        await Promise.all(Array.from(loads));
        let current = true;
        // Each run of such pages is one read.
        for (let page = first; page <= last; page++) {
            if (pages[page] === 1) continue;
            current = false;
            let end = page;
            while (end < last && pages[end + 1] !== 1) end++;
            if (!await load(page * PAGE, (end - page + 1) * PAGE)) return false;
            page = end;
        }
        if (current) return true;
    }
    for (let page = first; page <= last; page++) {
        if (pages[page] !== 1) {
            status("Memory kept changing while it was read; try again.", true);
            return false;
        }
    }
    return true;
}

// Reads bytes into the cache, reporting whether it could. A reply to a read begun before a stop or a change still
// fills in the bytes, so writes waiting on them go on, but does not count toward the changes since the stop: the
// pages stay unread, to be read and compared again.
async function read(offset, count) {
    const first = offset / PAGE, last = (offset + count) / PAGE;
    const loading = generation;
    for (let page = first; page < last; page++) pages[page] = 2;
    try {
        const result = await request({ type: "read", offset, count });
        const current = loading === generation;
        const data = decode(result.data);
        for (let index = 0; index < count; index++) {
            bytes[offset + index] = data[index];
            readable[offset + index] = 1;
        }
        for (const gap of result.unreadable) {
            for (let index = 0; index < gap.count; index++) readable[offset + gap.offset + index] = 2;
        }
        readOnly.fill(0, offset, offset + count);
        for (const run of result.readOnly ?? []) readOnly.fill(1, offset + run.offset, offset + run.offset + run.count);
        if (current) compare(offset, count);
        for (let page = first; page < last; page++) pages[page] = current ? 1 : 0;
    } catch (error) {
        for (let page = first; page < last; page++) pages[page] = 0;
        if (loading === generation) status(String(error.message || error), true);
        return false;
    }
    render();
    return true;
}

// Notes which bytes of freshly read pages changed since the last stop: a page compares once each stop, against
// what it held when it was first read after the stop before.
function compare(offset, count) {
    for (let page = offset / PAGE; page < (offset + count) / PAGE; page++) {
        if (seenStop[page] === stops) continue;
        for (let at = page * PAGE; at < (page + 1) * PAGE; at++) {
            const differs = seenStop[page] >= 0 && readable[at] === 1 && seen[at] !== bytes[at];
            changed[at] = differs ? 1 : 0;
            if (differs) was[at] = seen[at];
            seen[at] = bytes[at];
        }
        seenStop[page] = stops;
    }
}

// Asks for the labels and the character set, which can change at each stop as banks switch.
async function loadExtras() {
    try {
        const result = await request({ type: "labels" });
        labels = result.labels;
        labelAt = new Map(labels.map(label => [label.address, label.name]));
        labelWidth = Math.min(16, labels.reduce((widest, label) => Math.max(widest, label.name.length), 0));
        alignLabel.hidden = labels.length === 0;
        layoutRows();
        render();
    } catch {
        // Labels are extra; the bytes show without them.
    }
    try {
        useCharacters(await request({ type: "characters" }));
    } catch {
        // As are the machine's characters.
    }
    try {
        await freeze([], []);
    } catch {
        // And the frozen bytes.
    }
}

// The glyphs' height in the text column; their width keeps the machine's proportions.
const GLYPH = 16;

// Draws each code's character from the machine's character generator into a class the text column uses, with the
// other phase of flashing characters shown while the page's flash class is on.
function useCharacters(result) {
    if (result === null || result === undefined || typeof result.text !== "string") {
        machineSet = null;
        applyText();
        render();
        return;
    }
    const width = result.width, height = result.height;
    const glyphs = decode(result.glyphs), flashed = typeof result.flashed === "string" ? decode(result.flashed) : null;
    const ink = getComputedStyle(document.body).color;
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext("2d");
    const image = (data, code) => {
        context.clearRect(0, 0, width, height);
        context.fillStyle = ink;
        for (let line = 0; line < height; line++) {
            for (let pixel = 0; pixel < width; pixel++) {
                if (data[code * height + line] & (0x80 >> pixel)) context.fillRect(pixel, line, 1, 1);
            }
        }
        return canvas.toDataURL();
    };
    let css = ".txt.g span{width:" + Math.round(width * GLYPH / height) + "px}";
    let flashing = false;
    for (let code = 0; code < 256; code++) {
        css += ".k" + code + "{background-image:url(" + image(glyphs, code) + ")}";
        if (flashed === null) continue;
        const rows = flashed.subarray(code * height, (code + 1) * height);
        if (rows.every((row, line) => row === glyphs[code * height + line])) continue;
        css += "body.flash .k" + code + "{background-image:url(" + image(flashed, code) + ")}";
        flashing = true;
    }
    if (glyphStyle === null) {
        glyphStyle = document.createElement("style");
        document.head.appendChild(glyphStyle);
    }
    glyphStyle.textContent = css;
    // Two codes look the same when they draw the same rows in each phase.
    const looksSame = (first, second) => {
        for (let line = 0; line < height; line++) {
            if (glyphs[first * height + line] !== glyphs[second * height + line]) return false;
            if (flashed !== null && flashed[first * height + line] !== flashed[second * height + line]) return false;
        }
        return true;
    };
    machineSet = { text: result.text, looksSame };
    applyText();
    // The Apple II flashes about twice a second.
    if (flashing && flashTimer === null) flashTimer = setInterval(() => document.body.classList.toggle("flash"), 270);
    if (!flashing && flashTimer !== null) {
        clearInterval(flashTimer);
        flashTimer = null;
        document.body.classList.remove("flash");
    }
    render();
}

// Reads the pages from one row to another that have not been read since memory last changed, in runs.
function ensure(firstRow, lastRow) {
    if (ended) return;
    const firstPage = Math.floor(rowStart(Math.max(0, firstRow)) / PAGE);
    const lastPage = Math.floor(rowEnd(Math.min(rowCount() - 1, Math.max(0, lastRow))) / PAGE);
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

// Escapes a character for the page's HTML, inside text or a quoted attribute, as labels from debug files can hold
// any character.
const ESCAPES = { "<": "&lt;", ">": "&gt;", "&": "&amp;", '"': "&quot;", "'": "&#39;" };
function escape(character) {
    return ESCAPES[character] ?? character;
}

function rowHtml(row) {
    const start = rowStart(row), end = rowEnd(row), base = start - start % ROW;
    const low = Math.min(cursor, anchor), high = Math.max(cursor, anchor);
    let hexPart = "", textPart = "";
    for (let index = 0; index < ROW; index++) {
        const offset = base + index;
        let classes = index === 8 ? "mid" : "";
        // A row aligned to a label leaves the columns before it, and after the next, empty.
        if (offset < start || offset > end) {
            hexPart += '<span class="' + classes + '"> </span>';
            textPart += "<span> </span>";
            continue;
        }
        if (low !== high && offset >= low && offset <= high) classes += " sel";
        if (readable[offset] === 1 && differs(offset)) classes += " chg";
        if (frozen.has(offset)) classes += " frz";
        else if (readable[offset] === 1 && readOnly[offset]) classes += " ro";
        let shown = "  ", character = " ", textClasses = classes.replace("mid", ""), title = "";
        if (labelAt.has(offset)) {
            classes += " lb";
            title = ' title="' + escapeText(labelAt.get(offset)) + '"';
        }
        if (readable[offset] === 1) {
            shown = hex(bytes[offset], 2);
            if (charset !== null) {
                character = "";
                textClasses += " k" + bytes[offset];
            } else {
                character = escape(textOf(bytes[offset]));
                if (bytes[offset] > 0x7F) textClasses += " hi";
            }
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
        hexPart += '<span class="' + classes + '" data-o="' + offset + '"' + title + ">" + shown + "</span>";
        textPart += '<span class="' + textClasses + '" data-o="' + offset + '" data-t="1">' + character + "</span>";
    }
    let gutter = "";
    if (labelWidth > 0) {
        let name = "", inside = false;
        for (let offset = start; offset <= end && name === ""; offset++) {
            if (labelAt.has(offset)) {
                name = labelAt.get(offset);
                inside = offset > start;
            }
        }
        gutter = '<span class="lab' + (inside ? " in" : "") + '" style="width:' + labelWidth + 'ch"'
            + (name === "" ? "" : ' title="' + escapeText(name) + '"') + ">" + escapeText(name) + "</span>";
    }
    return '<div class="row"><span class="addr">' + hex(start, 4) + "</span>" + gutter + '<span class="hex">' + hexPart
        + '</span><span class="txt' + (charset !== null ? " g" : "") + '">' + textPart + "</span></div>";
}

function render() {
    const top = Math.floor(grid.scrollTop / LINE);
    const count = visibleRows() + 2;
    let html = "";
    for (let row = top; row < Math.min(rowCount(), top + count); row++) html += rowHtml(row);
    rows.style.transform = "translateY(" + (top * LINE) + "px)";
    rows.innerHTML = html;
    if (layout()) { render(); return; }
    ensure(top - count, top + 2 * count);
    showInspector();
    wantListing();
    showListingLines();
    if (tab === "frozen") showFrozen();
}

// Asks for the listing of the bytes in view, when they, memory, the labels or the starts Decode from here made
// have changed since it was last asked for.
function wantListing() {
    if (!showListing || ended || narrow === true) return;
    const top = Math.min(Math.floor(grid.scrollTop / LINE), rowCount() - 1);
    const start = rowStart(top), end = rowEnd(Math.min(rowCount() - 1, top + visibleRows() + 1));
    const key = start + ":" + end + ":" + generation + ":" + labels.length + ":" + forcedStarts.size;
    if (key === listingKey) return;
    listingKey = key;
    void loadListing(start, Math.min(0x1000, end - start + 1), key);
}

async function loadListing(start, count, key) {
    try {
        const result = await request({ type: "listing", address: start, count, starts: Array.from(forcedStarts) });
        if (key !== listingKey) return;
        listingLines = result.lines;
    } catch (error) {
        if (key !== listingKey) return;
        listingLines = [];
        listingPanel.innerHTML = "<p>" + escapeText(String(error.message || error)) + "</p>";
        return;
    }
    showListingLines();
}

// The file's name in a path, for the listing's source column.
function fileName(path) {
    return path.substring(Math.max(path.lastIndexOf("/"), path.lastIndexOf(String.fromCharCode(92))) + 1);
}

// Shows the listing's lines, marking those in the selection and the one the cursor is in.
function showListingLines() {
    if (!showListing || listingLines.length === 0) return;
    const low = Math.min(cursor, anchor), high = Math.max(cursor, anchor);
    let html = "";
    for (const line of listingLines) {
        const last = line.address + line.size - 1;
        let classes = "ln " + line.kind;
        if (high > low && line.address <= high && last >= low) classes += " sel";
        if (cursor >= line.address && cursor <= last) classes += " cur";
        const space = line.text.indexOf(" ");
        const mnemonic = space < 0 ? line.text : line.text.substring(0, space), operand = space < 0 ? "" : line.text.substring(space + 1);
        let text = escapeText(mnemonic);
        if (operand !== "") {
            text += " " + (line.target === null || line.target === undefined
                ? escapeText(operand)
                : '<a data-go="' + line.target + '" title="Go to ' + where(line.target) + '">' + escapeText(operand) + "</a>");
        }
        const source = line.path === null || line.path === undefined ? ""
            : '<a class="src" data-src="' + escapeText(line.path) + '" data-line="' + line.line + '" title="Open ' + escapeText(line.path) + ", line " + line.line + '">'
                + escapeText(fileName(line.path)) + ":" + line.line + "</a>";
        const label = line.label === null || line.label === undefined ? "" : line.label;
        html += '<div class="' + classes + '" role="listitem" data-a="' + line.address + '" data-s="' + line.size + '"><span class="a">' + hex(line.address, 4) + "</span>"
            + '<span class="l"' + (label === "" ? "" : ' title="' + escapeText(label) + '"') + ">" + escapeText(label) + '</span><span class="t">' + text + "</span>" + source + "</div>";
    }
    listingPanel.innerHTML = html;
}

// Selects a line's bytes, the cursor on its first.
function selectLine(address, size) {
    moveTo(address + size - 1, false, false);
    moveTo(address, true, false);
}

// Starts an instruction at the cursor, where the listing decoded from the wrong byte.
function decodeHere() {
    forcedStarts.add(cursor);
    render();
    status("The listing decodes an instruction from " + where(cursor) + ".");
}

listingPanel.addEventListener("click", event => {
    const target = event.target;
    if (!target.closest) return;
    const source = target.closest("[data-src]");
    if (source !== null) {
        void request({ type: "open", path: source.dataset.src, line: Number(source.dataset.line) }).catch(error => status(String(error.message || error), true));
        return;
    }
    const go = target.closest("[data-go]");
    if (go !== null) {
        moveTo(Number(go.dataset.go), false, true);
        grid.focus();
        return;
    }
    const line = target.closest("[data-a]");
    if (line !== null) {
        selectLine(Number(line.dataset.a), Number(line.dataset.s));
        grid.focus();
    }
});

// The bytes the grid compares with, when not the stop before: the snapshot or the other bank, once read.
function compared() {
    return comparison === "snapshot" ? snapshot : comparison === "" ? null : other;
}

// Whether the grid highlights a byte: it differs from the snapshot or the other bank, or else changed at the last stop.
function differs(offset) {
    if (comparison === "") return changed[offset] === 1;
    const base = compared();
    return base !== null && base.readable[offset] === 1 && readable[offset] === 1 && base.bytes[offset] !== bytes[offset];
}

// What the grid compares with, for the inspector and the status line.
function comparedName() {
    if (comparison === "snapshot") return "the snapshot";
    return otherBanks.find(bank => bank.memoryReference === comparison)?.label ?? comparison;
}

// Lists what the grid can compare with: the stop before, the snapshot once taken, and the other banks.
function compareOptions() {
    let html = '<option value="">the last stop</option>';
    if (snapshot !== null) html += '<option value="snapshot">the snapshot</option>';
    for (const bank of otherBanks) html += '<option value="' + escapeText(bank.memoryReference) + '">' + escapeText(bank.label) + "</option>";
    compareSelect.innerHTML = html;
    compareSelect.value = comparison;
}

// Asks for the other banks, which a card going in or out changes; a bank compared with that has gone is no longer.
async function loadBanks() {
    try {
        otherBanks = (await request({ type: "banks" })).banks;
    } catch {
        otherBanks = [];
    }
    if (comparison !== "" && comparison !== "snapshot" && !otherBanks.some(bank => bank.memoryReference === comparison)) {
        comparison = "";
        other = null;
        render();
    }
    compareOptions();
}

// Reads the bank compared with, reporting whether it could.
async function readOther() {
    const reference = comparison;
    if (reference === "" || reference === "snapshot") return true;
    try {
        const result = await request({ type: "readOther", reference, offset: 0, count: SIZE });
        if (comparison !== reference) return false;
        const known = new Uint8Array(SIZE).fill(1);
        for (const gap of result.unreadable) known.fill(2, gap.offset, gap.offset + gap.count);
        other = { bytes: decode(result.data), readable: known };
        render();
        return true;
    } catch (error) {
        if (comparison === reference) status(String(error.message || error), true);
        return false;
    }
}

// Compares with the stop before, the snapshot or another bank.
async function compareWith(value) {
    comparison = value;
    other = null;
    compareOptions();
    render();
    if (value === "") { status(""); return; }
    if (value !== "snapshot" && !await readOther()) return;
    if (comparison === value) status("The bytes that differ from " + comparedName() + " are highlighted.");
}

function where(offset) {
    return (info.bank === null ? "" : info.bank + ":") + "$" + hex(offset, 4);
}

// What freezing and thawing do, for their buttons' hover text.
const freezeTitle = {
    freeze: "Hold these bytes at their values now while the machine runs: the debugger writes them back every few "
        + "milliseconds, so the program cannot change them. Typing here changes the value they are held at.",
    thaw: "Stop holding these bytes, so the program can change them again."
};

function showInspector() {
    const low = Math.min(cursor, anchor), high = Math.max(cursor, anchor);
    const allFrozen = range(low, high).every(offset => frozen.has(offset));
    const count = high > low ? " " + (high - low + 1) + " bytes" : "";
    const watchTitle = "Add to VS Code's Watch view as " + watchExpressions(low, high).join(", ");
    let html = '<div class="acts"><button data-act="watch" title="' + escapeText(watchTitle) + '">' + (high === low + 1 ? "Watch word" : "Watch" + count) + "</button>"
        + '<button data-act="freeze" title="' + (allFrozen ? freezeTitle.thaw : freezeTitle.freeze) + '">' + (allFrozen ? "Thaw" : "Freeze") + count + "</button>"
        + (showListing ? '<button data-act="decode" title="Start an instruction at the cursor in the listing, where it decodes from the wrong byte (Ctrl+D)">Decode from here</button>' : "") + "</div>";
    html += '<div class="where">' + where(cursor);
    const name = labelOf(labels, cursor);
    if (name !== undefined) html += " · " + escapeText(name);
    if (high > low) html += " · " + (high - low + 1) + " bytes, " + where(low) + "-$" + hex(high, 4);
    html += "</div>";
    const rows = inspect(bytes, readable, cursor, charset === null ? undefined : charset.text);
    if (comparison !== "" && differs(cursor)) rows.push({ label: comparison === "snapshot" ? "In the snapshot" : "In " + comparedName(), value: "$" + hex(compared().bytes[cursor], 2) });
    else if (readable[cursor] === 1 && changed[cursor]) rows.push({ label: "At the last stop", value: "$" + hex(was[cursor], 2) });
    if (frozen.has(cursor)) rows.push({ label: "Frozen at", value: "$" + hex(frozen.get(cursor), 2) });
    if (readable[cursor] === 1 && readOnly[cursor]) rows.push({ label: "Writes", value: "refused: not RAM now" });
    for (const row of rows) {
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
    // The listing takes its width too, while it shows.
    if (showListing && listingPanel.offsetWidth > 0) listingWidth = listingPanel.offsetWidth;
    const docked = document.body.clientWidth < content + INSPECTOR + (showListing ? listingWidth : 0);
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
    const row = rowOf(offset), top = Math.floor(grid.scrollTop / LINE), shown = visibleRows();
    if (center) {
        grid.scrollTop = Math.max(0, row - Math.floor(shown / 3)) * LINE;
    } else if (row < top) {
        grid.scrollTop = row * LINE;
    } else if (row >= top + shown) {
        grid.scrollTop = (row - shown + 1) * LINE;
    }
}

// Moves the cursor. A move the queue makes itself, as typing a byte steps on, is not a move of the user's, which
// keys typed before it must know.
function moveTo(offset, extend, center, queued = false) {
    if (!queued) moves++;
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
        if (readOnly[offset + index]) return where(offset + index) + " is not RAM now, so it cannot be written.";
    }
    return null;
}

async function write(offset, values, record) {
    // Undo puts back the bytes from before, so they must be what memory held.
    if (!await loaded(offset, values.length)) return false;
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
    const refrozen = values.map((value, index) => ({ offset: offset + index, value })).filter(item => frozen.has(item.offset));
    if (refrozen.length > 0) await freeze(refrozen, []);
    status("");
    // Memory may hold other than what was written, such as the Model I's video RAM without its lowercase
    // modification, and the debugger tells no view of the writer's reference: the pages written are read again.
    void readBack(offset, values.length);
    return true;
}

// Reads again the pages that hold a range, so they show what memory holds.
async function readBack(offset, count) {
    for (let page = Math.floor(offset / PAGE); page <= Math.floor((offset + count - 1) / PAGE); page++) {
        try {
            await load(page * PAGE, PAGE);
        } catch {
            // The bytes written show until the next read.
        }
    }
    render();
}

async function undo() {
    const edit = undoStack.pop();
    if (edit === undefined) { status("Nothing to undo."); return; }
    if (await write(edit.offset, edit.before, false)) {
        redoStack.push(edit);
        moveTo(edit.offset, false, false, true);
    } else {
        undoStack.push(edit);
    }
}

async function redo() {
    const edit = redoStack.pop();
    if (edit === undefined) { status("Nothing to redo."); return; }
    if (await write(edit.offset, edit.after, false)) {
        undoStack.push(edit);
        moveTo(edit.offset, false, false, true);
    } else {
        redoStack.push(edit);
    }
}

// Typing a character: a hex digit in the hex column, which writes the byte at its second digit, or a character in
// the text column, which writes it at once. Pressed is the count of the user's moves when the key was pressed.
async function typeKey(key, pressed) {
    // A key waits for the keys before it, which can wait on the debugger; one pressed before the user moved is
    // dropped rather than written where they went.
    if (moves !== pressed) return;
    // An edit goes to the byte the cursor was on when its key was pressed; should the user move while it waits on
    // the debugger, the cursor stays where they went.
    const started = pressed;
    if (pane === "text") {
        // The byte typed over decides the code written, such as normal or inverse text, so it is read first.
        const at = cursor;
        if (!await loaded(at, 1)) return;
        const value = charset === null ? typedText(key, bytes[at]) : typedText(key, bytes[at], charset.text, charset.looksSame);
        if (value === undefined) return;
        if (await write(at, [value], true) && moves === started) moveTo(at + 1, false, false, true);
        return;
    }
    const digit = parseInt(key, 16);
    if (isNaN(digit) || key.length !== 1) return;
    if (nibble === null) {
        if (!await loaded(cursor, 1)) return;
        // A first digit does not carry over to a byte the user moved to meanwhile.
        if (moves !== started || pane !== "hex") return;
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
    if (await write(at, [value], true) && moves === started) moveTo(at + 1, false, false, true);
    else render();
}

// Keys and undo run one at a time, in the order pressed, as each may wait for bytes to be read.
let typing = Promise.resolve();
function queue(action) {
    typing = typing.then(action, action);
}

// The offsets from one to another.
function range(low, high) {
    const offsets = [];
    for (let offset = low; offset <= high; offset++) offsets.push(offset);
    return offsets;
}

// Freezes bytes at values and thaws others, keeping the debugger's list.
async function freeze(items, thaw) {
    const result = await request({ type: "freeze", freeze: items, thaw });
    frozen = new Map(result.frozen.map(item => [item.address, item.value]));
    showFrozen();
    render();
}

// The most bytes the selection watches, each as its own expression.
const WATCHES = 16;

// The watch expressions for bytes: a byte as [$4100], two as the word [$4100].w, more as each byte.
function watchExpressions(low, high) {
    if (high === low + 1) return ["[" + where(low) + "].w"];
    return range(low, Math.min(high, low + WATCHES - 1)).map(offset => "[" + where(offset) + "]");
}

// Adds watch expressions to VS Code's Watch view.
async function watch(expressions) {
    try {
        // The extension says what it added, which names the machine's CPU where the machine has a coprocessor.
        const added = await request({ type: "watch", expressions });
        lastWatch = added?.expressions ?? expressions;
        status("Added " + lastWatch.join(", ") + " to the Watch view.");
    } catch (error) {
        status(String(error.message || error), true);
    }
}

// Watches the selection.
async function watchSelection() {
    const low = Math.min(cursor, anchor), high = Math.max(cursor, anchor);
    await watch(watchExpressions(low, high));
}

// Freezes the selection at its values, or thaws it when all of it is frozen.
async function toggleFreeze() {
    const low = Math.min(cursor, anchor), high = Math.max(cursor, anchor), offsets = range(low, high);
    try {
        if (offsets.every(offset => frozen.has(offset))) {
            await freeze([], offsets);
        } else {
            if (!await loaded(low, high - low + 1)) return;
            await freeze(offsets.filter(offset => !frozen.has(offset)).map(offset => ({ offset, value: bytes[offset] })), []);
        }
        status("");
    } catch (error) {
        status(String(error.message || error), true);
    }
}

// Reads every byte again, so a snapshot or search sees memory as it is now.
// Reads the whole space again, reporting whether it could; on a failure the status line says why.
// A stop or change during the read leaves its pages unread, so it reads again, a few times, until it is whole.
async function refreshAll() {
    generation++;
    pages.fill(0);
    for (let attempt = 0; attempt < 3; attempt++) {
        if (!await load(0, SIZE)) return false;
        if (pages.every(page => page === 1)) return true;
    }
    status("Memory kept changing while it was read; try again.", true);
    return false;
}

async function takeSnapshot() {
    if (!await refreshAll()) return;
    snapshot = { bytes: bytes.slice(), readable: readable.slice() };
    comparison = "snapshot";
    compareOptions();
    render();
    status("Took a snapshot; the bytes that differ from it are highlighted.");
}

function showTab(name) {
    tab = name;
    for (const button of side.querySelectorAll("[data-tab]")) button.classList.toggle("on", button.dataset.tab === name);
    inspector.hidden = name !== "inspector";
    searchPanel.hidden = name !== "search";
    frozenPanel.hidden = name !== "frozen";
    if (name === "search") showSearch();
    if (name === "frozen") showFrozen();
}

// The most hits a search lists; past that, it says to narrow further.
const HITS = 200;

function showSearch() {
    if (search === null) {
        searchPanel.innerHTML = "<p>Find the byte that holds a value, such as a game's lives, or the word that holds a score: "
            + "start with all of RAM, then let the value change and keep the values that changed the same way, until few are left.</p>"
            + '<div class="filters">Look for <select id="searchSize" aria-label="Value size"><option value="1">bytes</option>'
            + '<option value="2">words, ' + (info.bigEndian ? "high" : "low") + " byte first</option></select></div>"
            + '<button data-act="start">Start with all RAM</button>';
        return;
    }
    const unit = search.size === 2 ? "word" : "byte";
    const value = document.getElementById("searchValue");
    const typed = value === null ? "" : value.value;
    let html = '<div><span class="count">' + search.candidates.length + "</span> " + unit + (search.candidates.length === 1 ? "" : "s")
        + " left after " + search.steps.length + (search.steps.length === 1 ? " step" : " steps") + "</div>"
        + '<div class="filters">Keep the ' + unit + 's that '
        + '<button data-act="narrow" data-test="changed">changed</button><button data-act="narrow" data-test="unchanged">did not change</button>'
        + '<button data-act="narrow" data-test="increased">rose</button><button data-act="narrow" data-test="decreased">fell</button></div>'
        + '<div class="filters">or <button data-act="narrow" data-test="equal">equal</button><button data-act="narrow" data-test="notEqual">do not equal</button>'
        + '<input id="searchValue" aria-label="Value" placeholder="' + (search.size === 2 ? "$0300 or 768" : "$03 or 3") + '" value="' + escapeText(typed) + '"></div>'
        + '<div class="filters"><button data-act="back"' + (search.steps.length === 0 ? " disabled" : "") + ">Back a step</button>"
        + '<button data-act="reset" title="Start again, with bytes or words">Start over</button></div>';
    if (search.candidates.length <= HITS) {
        html += '<div class="hits">';
        for (const offset of search.candidates) {
            const name = labelOf(labels, offset);
            const digits = search.size * 2;
            const before = search.steps.length === 0 ? null : valueAt(search.steps[search.steps.length - 1].before, offset, search.size, search.bigEndian);
            const watched = "[" + where(offset) + "]" + (search.size === 2 ? ".w" : "");
            html += '<div class="hit" data-go="' + offset + '"><span class="a">' + where(offset) + (name === undefined ? "" : " " + escapeText(name)) + "</span>"
                + '<span class="v">' + (before === null ? "" : "$" + hex(before, digits) + " → ") + "$" + hex(valueAt(search.before, offset, search.size, search.bigEndian), digits) + "</span>"
                + '<button data-act="watchHit" data-o="' + offset + '" data-w="' + escapeText(watched) + '" title="Add ' + escapeText(watched) + ' to the Watch view">Watch</button></div>';
        }
        html += "</div>";
    } else {
        html += "<p>Narrow to " + HITS + " or fewer to list them.</p>";
    }
    searchPanel.innerHTML = html;
}

// Starts a RAM search for bytes or, with a size of 2, words in the CPU's byte order.
async function startSearch(size) {
    if (!await refreshAll()) return;
    search = { size, bigEndian: info.bigEndian === true, candidates: searchStart(readable, readOnly, size), before: bytes.slice(), steps: [] };
    showSearch();
    status("Searching " + search.candidates.length + (size === 2 ? " words" : " bytes") + " of RAM.");
}

async function narrowBy(test, text) {
    if (search === null) return;
    let value = 0;
    if (test === "equal" || test === "notEqual") {
        const parsed = parseValue(text, search.size);
        if (typeof parsed === "string") { status(parsed, true); return; }
        value = parsed;
    }
    // Memory is read first; a search started over or stepped back meanwhile is not narrowed by it.
    const current = search, depth = search.steps.length;
    if (!await refreshAll() || search !== current || current.steps.length !== depth) return;
    search.steps.push({ candidates: search.candidates, before: search.before });
    search.candidates = narrowSearch(search.candidates, search.before, bytes, readable, test, value, search.size, search.bigEndian);
    search.before = bytes.slice();
    showSearch();
    status(search.candidates.length + (search.size === 2 ? " word" : " byte") + (search.candidates.length === 1 ? "" : "s") + " left.");
}

function backSearch() {
    if (search === null || search.steps.length === 0) return;
    const step = search.steps.pop();
    search.candidates = step.candidates;
    search.before = step.before;
    showSearch();
}

function showFrozen() {
    document.getElementById("frozenTab").textContent = frozen.size === 0 ? "Frozen" : "Frozen (" + frozen.size + ")";
    if (tab !== "frozen") return;
    if (frozen.size === 0) {
        frozenPanel.innerHTML = "<p>Freeze bytes from the inspector to hold them at a value while the machine runs.</p>";
        return;
    }
    let html = "";
    for (const [offset, value] of Array.from(frozen).sort((first, second) => first[0] - second[0])) {
        const name = labelOf(labels, offset);
        html += '<div class="hit" data-go="' + offset + '"><span class="a">' + where(offset) + (name === undefined ? "" : " " + escapeText(name)) + "</span>"
            + '<span class="v">$' + hex(value, 2) + " " + value + "</span>"
            + '<button data-act="watchHit" data-o="' + offset + '">Watch</button>'
            + '<button data-act="thaw" data-o="' + offset + '" title="' + freezeTitle.thaw + '">Thaw</button></div>';
    }
    frozenPanel.innerHTML = html;
}

side.addEventListener("click", event => {
    const target = event.target;
    const tabButton = target.closest ? target.closest("[data-tab]") : null;
    if (tabButton !== null) { showTab(tabButton.dataset.tab); return; }
    const action = target.closest ? target.closest("[data-act]") : null;
    if (action !== null) {
        const offset = Number(action.dataset.o);
        switch (action.dataset.act) {
            case "watch": queue(watchSelection); break;
            case "freeze": queue(toggleFreeze); break;
            case "decode": decodeHere(); break;
            case "start": void startSearch(Number(document.getElementById("searchSize")?.value ?? 1)); break;
            case "reset": search = null; showSearch(); break;
            case "narrow": void narrowBy(action.dataset.test, document.getElementById("searchValue").value); break;
            case "back": backSearch(); break;
            case "watchHit": void watch([action.dataset.w ?? "[" + where(offset) + "]"]); break;
            case "thaw": void freeze([], [offset]).catch(error => status(String(error.message || error), true)); break;
        }
        return;
    }
    const hit = target.closest ? target.closest("[data-go]") : null;
    if (hit !== null) moveTo(Number(hit.dataset.go), false, true);
});
side.addEventListener("keydown", event => {
    if (event.target.id === "searchValue" && event.key === "Enter") {
        void narrowBy("equal", event.target.value);
        event.preventDefault();
        event.stopPropagation();
    }
});
document.getElementById("snapshot").addEventListener("click", () => void takeSnapshot());
compareSelect.addEventListener("change", () => {
    void compareWith(compareSelect.value);
    grid.focus();
});

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
    const pattern = parsePattern(findBox.value, charset === null ? undefined : charset.text);
    if (typeof pattern === "string") { status(pattern, true); return; }
    await ensureAll();
    const at = findPattern(bytes, readable, pattern, backward ? cursor - 1 : cursor + 1, backward);
    if (at < 0) { status("Not found.", true); return; }
    // A match is a move of the cursor, as an edit waiting on the debugger must know.
    moves++;
    anchor = at + pattern.length - 1;
    cursor = at;
    nibble = null;
    reveal(at, true);
    render();
    status("Found at " + where(at) + ".");
}

// Copies the selection as memory holds it now, reading the bytes out of view first.
async function copy() {
    const low = Math.min(cursor, anchor), high = Math.max(cursor, anchor);
    if (!await loaded(low, high - low + 1)) return;
    await request({ type: "copy", text: copyText(bytes, readable, low, high, pane === "text", charset === null ? undefined : charset.text) });
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
    if (control && (key === "z" || key === "Z")) {
        queue(event.shiftKey ? redo : undo);
    } else if (control && (key === "y" || key === "Y")) {
        queue(redo);
    } else if (control && (key === "c" || key === "C")) {
        void copy();
    } else if (control && (key === "d" || key === "D")) {
        decodeHere();
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
        moveRows(-1, event.shiftKey);
    } else if (key === "ArrowDown") {
        moveRows(1, event.shiftKey);
    } else if (key === "PageUp") {
        grid.scrollTop -= visibleRows() * LINE;
        moveRows(-visibleRows(), event.shiftKey);
    } else if (key === "PageDown") {
        grid.scrollTop += visibleRows() * LINE;
        moveRows(visibleRows(), event.shiftKey);
    } else if (key === "Home") {
        moveTo(control ? 0 : rowStart(rowOf(cursor)), event.shiftKey, false);
    } else if (key === "End") {
        moveTo(control ? SIZE - 1 : rowEnd(rowOf(cursor)), event.shiftKey, false);
    } else if (key === "Tab" && (event.shiftKey ? pane === "text" : pane === "hex")) {
        // Tab goes from the hex column to the text column and Shift+Tab back; past them, focus moves on as usual.
        moves++;
        pane = event.shiftKey ? "hex" : "text";
        nibble = null;
        render();
    } else if (key === "Escape" && nibble !== null) {
        nibble = null;
        render();
    } else if (!control && !event.altKey && key.length === 1) {
        const pressed = moves;
        queue(() => typeKey(key, pressed));
    } else {
        handled = false;
    }
    if (handled) {
        event.preventDefault();
        // VS Code sees the keys a webview does not stop, and Ctrl+G would open its own Go to Line.
        event.stopPropagation();
    }
});

alignBox.addEventListener("change", () => {
    aligned = alignBox.checked;
    remember();
    layoutRows();
    render();
    grid.focus();
});

listingBox.addEventListener("change", () => {
    showListing = listingBox.checked;
    listingPanel.hidden = !showListing;
    listingKey = "";
    narrow = null;
    remember();
    render();
    grid.focus();
});

machineBox.addEventListener("change", () => {
    machineText = machineBox.checked;
    remember();
    applyText();
    render();
    grid.focus();
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
        if (action.type !== undefined) { for (const key of action.type) await typeKey(key, moves); }
        if (action.find !== undefined) { findBox.value = action.find; await find(false); }
        if (action.undo) await undo();
        if (action.redo) await redo();
        if (action.extras) await loadExtras();
        if (action.snapshot) await takeSnapshot();
        if (action.compare !== undefined) await compareWith(action.compare === true ? "snapshot" : action.compare === false ? "" : action.compare);
        if (action.search === "start") await startSearch(action.size ?? 1);
        else if (action.search !== undefined) await narrowBy(action.search, action.value ?? "");
        if (action.watch) await watchSelection();
        if (action.freeze) await toggleFreeze();
        if (action.align !== undefined) {
            aligned = action.align;
            layoutRows();
            render();
        }
        if (action.decode) decodeHere();
        if (action.listingLine !== undefined) selectLine(listingLines[action.listingLine].address, listingLines[action.listingLine].size);
        if (action.machineText !== undefined) {
            machineText = action.machineText;
            applyText();
            render();
        }
        await loaded(cursor, 1);
    }
    return {
        cursor, anchor, pane,
        status: statusLine.textContent,
        label: labelOf(labels, cursor) ?? null,
        text: textOf(bytes[cursor], charset === null ? undefined : charset.text),
        glyphs: charset !== null,
        readOnly: readOnly[cursor] === 1,
        changed: changed[cursor] === 1,
        differs: differs(cursor),
        candidates: search === null ? null : search.candidates.length,
        lastWatch,
        frozen: frozen.has(cursor) ? frozen.get(cursor) : null,
        inspector: inspect(bytes, readable, cursor, charset === null ? undefined : charset.text),
        hex: Array.from(rows.querySelectorAll(".hex span")).map(span => span.textContent).slice(0, 64),
        row: { start: rowStart(rowOf(cursor)), end: rowEnd(rowOf(cursor)), count: rowCount() },
        listing: listingLines.map(line => hex(line.address, 4) + " " + line.text)
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
        void loadExtras();
        void loadBanks();
    } else if (message.type === "changed") {
        generation++;
        pages.fill(0);
        render();
    } else if (message.type === "frozen") {
        // Another editor on this space froze or thawed bytes.
        frozen = new Map(message.frozen.map(item => [item.address, item.value]));
        showFrozen();
        render();
    } else if (message.type === "invalidated") {
        // The machine changed while stopped, as when a card goes in: the bytes, labels, characters and frozen
        // bytes are read again. Changes still count from the stop, as between stops they do.
        generation++;
        pages.fill(0);
        render();
        void loadExtras();
        void loadBanks().then(readOther);
    } else if (message.type === "stopped") {
        // Changes count from here, and banks may have switched the labels and characters.
        stops++;
        generation++;
        pages.fill(0);
        render();
        void loadExtras();
        void readOther();
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
