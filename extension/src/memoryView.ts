// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Retrocore Memory's page: a hex and text grid over a whole 64K space, with labels, rows aligned to them, the
// machine's own characters, read-only shading, changes since the last stop or differences from a snapshot or another
// bank, go to, following an expression, back and forward, bookmarks, find, copy, editing with undo, an inspector, RAM search of bytes or words, watching in VS Code's Watch
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
.bar .nav{display:flex;gap:2px}
.bar .nav button{padding:2px 6px}
.main{flex:1;display:flex;min-height:0}
#grid{flex:none;overflow:auto;position:relative;outline:none;font-family:var(--vscode-editor-font-family);font-size:var(--vscode-editor-font-size);white-space:pre;user-select:none;cursor:text}
#spacer{position:absolute;top:0;left:0;width:1px}
#rows{position:absolute;top:0;left:0;right:0}
.row{height:20px;line-height:20px;padding:0 10px;width:max-content}
.addr{display:inline-block;width:6ch;color:var(--vscode-editorLineNumber-foreground)}
.lab{display:inline-block;overflow:hidden;text-overflow:ellipsis;vertical-align:top;margin-right:1ch;color:var(--vscode-symbolIcon-functionForeground,var(--vscode-editor-foreground))}
.lab.in{opacity:.6}
.hex span.bm{box-shadow:inset 0 -2px var(--vscode-charts-yellow,#cca700)}
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
#inspector .doc{margin:2px 0 6px;color:var(--vscode-descriptionForeground)}
#inspector button.link{background:none;border:none;padding:0;color:var(--vscode-textLink-foreground);font:inherit;cursor:pointer}
#inspector button.link:focus-visible{outline:1px solid var(--vscode-focusBorder)}
#listing{flex:none;width:46ch;overflow:auto;display:grid;align-content:start;border-left:1px solid var(--vscode-panel-border);font-family:var(--vscode-editor-font-family);font-size:var(--vscode-editor-font-size);white-space:pre}
#listing[hidden]{display:none}
#listing .ln{height:20px;line-height:20px;padding:0 8px;cursor:pointer;display:flex;gap:1ch}
#listing .ln:hover{background:var(--vscode-list-hoverBackground)}
#listing .ln:focus,#listing a:focus{outline:1px solid var(--vscode-focusBorder);outline-offset:-1px}
#listing .ln.sel{background:var(--vscode-editor-inactiveSelectionBackground)}
#listing .ln.cur{outline:1px solid var(--vscode-editorCursor-foreground,var(--vscode-focusBorder));outline-offset:-1px}
#listing .a{color:var(--vscode-editorLineNumber-foreground)}
#listing .bp{width:1.5ch;flex:none;margin-left:-4px;text-align:center;color:transparent;cursor:default}
#listing .ln:hover .bp{color:var(--vscode-debugIcon-breakpointDisabledForeground,var(--vscode-disabledForeground))}
#listing .ln .bp.on{color:var(--vscode-debugIcon-breakpointForeground,#e51400)}
.sr{position:absolute;width:1px;height:1px;overflow:hidden;clip-path:inset(50%);white-space:nowrap}
#listing .l{width:10ch;flex:none;overflow:hidden;text-overflow:ellipsis;color:var(--vscode-symbolIcon-functionForeground,var(--vscode-editor-foreground))}
#listing .unknown .t{opacity:.7}
#listing .guess .t{font-style:italic}
#listing .cm{color:var(--vscode-descriptionForeground);font-style:italic}
#listing .data .t{color:var(--vscode-debugTokenExpression-number,var(--vscode-editor-foreground))}
#listing a{color:var(--vscode-textLink-foreground);text-decoration:none;cursor:pointer}
#listing a:hover{text-decoration:underline}
#listing .src{flex:none;margin-left:auto;padding-left:1ch;color:var(--vscode-descriptionForeground)}
#listing p{margin:8px;white-space:normal;color:var(--vscode-descriptionForeground);font-family:var(--vscode-font-family);font-size:12px}
body.narrow #listing{display:none}
body.narrow .main{flex-direction:column}
body.narrow #grid{flex:1}
body.narrow #side{flex:none;max-height:40%;border-left:none;border-top:1px solid var(--vscode-panel-border)}
body.narrow #inspector{display:flex;flex-wrap:wrap;gap:2px 24px;align-items:baseline}
body.narrow #inspector .acts{margin:0}
body.narrow #inspector .where{margin:0;padding:2px 0}
body.narrow .item .k{width:auto}
#map{position:relative;height:10px;margin:2px 10px 6px;cursor:pointer;background:var(--vscode-editorWidget-background,transparent);outline:1px solid var(--vscode-panel-border)}
#map[hidden]{display:none}
#map .seg{position:absolute;top:0;bottom:0}
#map .ram{background:var(--vscode-charts-blue,#3794ff)}
#map .rom{background:var(--vscode-charts-purple,#b180d7)}
#map .io{background:var(--vscode-charts-orange,#d18616)}
#map .video{background:var(--vscode-charts-green,#89d185)}
#map .none{background:transparent}
#map .off{opacity:.3}
#map .edge{position:absolute;top:0;bottom:0;width:1px;background:var(--vscode-editor-background)}
#mapView{position:absolute;top:-3px;bottom:-3px;min-width:2px;box-sizing:border-box;border:1px solid var(--vscode-focusBorder);pointer-events:none}
#status{padding:3px 10px;border-top:1px solid var(--vscode-panel-border);font-size:12px;color:var(--vscode-descriptionForeground);min-height:16px}
#status.error{color:var(--vscode-errorForeground)}
.ended{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;background:color-mix(in srgb,var(--vscode-editor-background) 80%,transparent);font-size:14px}
</style></head>
<body>
<div class="bar"><span class="title" id="title">Memory</span>
<span class="nav"><button id="back" disabled aria-label="Back" title="Back to where the view was before a go-to (Alt+Left, or the mouse's back button)">&#8592;</button><button id="forward" disabled aria-label="Forward" title="Forward again (Alt+Right, or the mouse's forward button)">&#8594;</button></span>
<button id="bookmarks" title="Go to a bookmark, or remove one; Bookmark in the inspector adds one">Bookmarks</button>
<label title="Show the bytes as instructions and data beside them"><input type="checkbox" id="listingBox" checked> Listing</label>
<label id="alignLabel" title="Start a row where each label starts, so a label's bytes begin a row of their own" hidden><input type="checkbox" id="align"> Align to labels</label>
<label id="machineLabel" title="Draw the text column in the machine's own characters, or as ASCII" hidden><input type="checkbox" id="machineText" checked> Machine text</label>
<button id="snapshot" title="Keep a copy of every byte now, to compare with">Snapshot</button>
<label title="Highlight the bytes that differ from what they held at the stop before, from the snapshot, or from another bank's bytes at the same addresses">Compare with <select id="compareWith" aria-label="Compare with"><option value="">the last stop</option></select></label>
<label title="An address, label or expression, such as $0400, TEXT_PAGE or HL+2 (Ctrl+G)">Go to <input id="goto" aria-label="Go to address" placeholder="$0400"></label>
<label id="followLabel" title="Go to the Go to expression again at each stop, such as PC, S+$100 or [$06].w; a view that does not follow stays where it is"><input type="checkbox" id="follow"> Follow</label>
<label title="Hex bytes with ?? for any byte, such as A9 ?? 20; text in quotes; a number after =, such as =1000 or =-2.5, as a byte, a word either way round or the BASIC's float; or an instruction, with ? for any character and * for any run, such as STA $C0?? or JSR COUT. Enter finds the next, Shift+Enter the one before (Ctrl+F, F3)">Find <input id="find" aria-label="Find" placeholder="A9 ?? 20, &quot;TEXT&quot;, =1000 or STA $C0??"></label>
</div>
<div id="map" hidden aria-hidden="true"></div>
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
// The key of the listing the lines are, which is listingKey once the one asked for last has come.
let listingLoaded = "";
// The writes the page made, which change what the listing shows, and the cursor the listing last scrolled to.
let writes = 0, listingCursor = -1;
// The marks, names and comments made, which change what the listing shows.
let marks = 0;
// Breakpoints set or taken away anywhere, which change the listing's gutter.
let breakpointChanges = 0;
// Why the last listing request failed, which shows in place of lines; empty when it did not.
let listingError = "";
const forcedStarts = new Set();
// The expression the view follows, gone to again at each stop; empty for a view that stays put (the page remembers).
let following = "";
// Where go-tos left from, for Back, and where Back left from, for Forward.
const backStack = [], forwardStack = [];
const HISTORY = 100;
// The bookmarks in this view's space, by address.
let bookmarkAt = new Map();
try {
    const saved = vscode.getState();
    if (saved && typeof saved.following === "string") following = saved.following;
    if (saved && typeof saved.showListing === "boolean") showListing = saved.showListing;
    if (saved && typeof saved.machineText === "boolean") machineText = saved.machineText;
    if (saved && typeof saved.aligned === "boolean") aligned = saved.aligned;
} catch {
    // A page without saved state uses the machine's characters, in rows of ROW bytes.
}

// Remembers the page's choices, which are conveniences.
function remember() {
    try {
        vscode.setState({ machineText, aligned, showListing, following });
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
    void loadMap();
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

// The bar across the top: the whole space, colored by what memory reads there now, dimmed where a bank is not what
// the CPU reads, with a line where each of the machine's regions starts and a box around the bytes in view. Hovering
// names the address under the pointer, and a click goes there. The keyboard has Go to instead, so it is hidden from
// screen readers.
let map = null;
const mapBar = document.getElementById("map");

// Read at the start and at each stop, apart from the other extras, which do not wait for it.
async function loadMap() {
    try {
        map = await request({ type: "map" });
    } catch {
        // The bytes show without it.
        map = null;
    }
    showMap();
}

function percent(address) { return (address / SIZE * 100) + "%"; }

function showMap() {
    const areas = map === null ? [] : map.areas;
    mapBar.hidden = areas.length === 0;
    let html = "";
    for (const area of areas) {
        html += '<div class="seg ' + area.kind + (area.mapped ? "" : " off") + '" style="left:' + percent(area.start) + ";width:" + percent(area.length) + '"></div>';
    }
    for (const region of map === null ? [] : map.regions) {
        if (region.start > 0) html += '<div class="edge" style="left:' + percent(region.start) + '"></div>';
    }
    mapBar.innerHTML = html + '<div id="mapView"></div>';
    showMapView();
}

function showMapView() {
    const view = document.getElementById("mapView");
    if (view === null || mapBar.hidden) return;
    const top = Math.floor(grid.scrollTop / LINE);
    const start = rowStart(Math.min(top, rowCount() - 1)), end = rowEnd(Math.min(rowCount() - 1, top + visibleRows() - 1));
    view.style.left = percent(start);
    view.style.width = percent(end - start + 1);
}

// The address under a point on the bar.
function mapAddress(event) {
    const box = mapBar.getBoundingClientRect();
    return Math.min(SIZE - 1, Math.max(0, Math.floor((event.clientX - box.left) / Math.max(1, box.width) * SIZE)));
}

// What the bar says of an address: its region and what memory reads there.
function mapTitle(address) {
    if (map === null) return where(address);
    const region = map.regions.filter(item => address >= item.start && address < item.start + item.length).sort((a, b) => a.length - b.length)[0];
    const area = map.areas.find(item => address >= item.start && address < item.start + item.length);
    return [where(address), region?.name, area?.name].filter(Boolean).join(" · ");
}

mapBar.addEventListener("mousemove", event => { mapBar.title = mapTitle(mapAddress(event)); });
mapBar.addEventListener("click", event => {
    jump(mapAddress(event));
    grid.focus();
});

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
        const names = [];
        if (labelAt.has(offset)) {
            classes += " lb";
            names.push(labelAt.get(offset));
        }
        if (bookmarkAt.has(offset)) {
            classes += " bm";
            names.push("Bookmark: " + bookmarkAt.get(offset));
        }
        if (names.length > 0) title = ' title="' + escapeText(names.join("; ")) + '"';
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
    showMapView();
    wantListing();
    wantInspection();
    showListingLines();
    if (tab === "frozen") showFrozen();
}

// Asks for the listing of the bytes in view, when they, memory, the labels or the starts Decode from here made
// have changed since it was last asked for.
function wantListing() {
    if (!showListing || ended || narrow === true) return;
    const top = Math.min(Math.floor(grid.scrollTop / LINE), rowCount() - 1);
    const start = rowStart(top), end = rowEnd(Math.min(rowCount() - 1, top + visibleRows() + 1));
    const key = start + ":" + end + ":" + generation + ":" + writes + ":" + marks + ":" + breakpointChanges + ":" + labels.length + ":" + forcedStarts.size;
    if (key === listingKey) return;
    listingKey = key;
    void loadListing(start, Math.min(0x1000, end - start + 1), key);
}

async function loadListing(start, count, key) {
    try {
        const result = await request({ type: "listing", address: start, count, starts: Array.from(forcedStarts) });
        if (key !== listingKey) return;
        listingLines = result.lines;
        listingLoaded = key;
        listingError = "";
        // New lines can move the cursor's, as when Decode from here or a write changes the instructions' sizes,
        // so its line is brought into view again.
        listingCursor = -1;
    } catch (error) {
        if (key !== listingKey) return;
        listingLines = [];
        listingError = String(error.message || error);
    }
    showListingLines();
}

// The file's name in a path, for the listing's source column.
function fileName(path) {
    return path.substring(Math.max(path.lastIndexOf("/"), path.lastIndexOf(String.fromCharCode(92))) + 1);
}

// Shows the listing's lines, marking those in the selection and the one the cursor is in.
function showListingLines() {
    if (!showListing) return;
    if (listingLines.length === 0) {
        // Nothing lists where the space has no bytes, such as past a bank's end, so no old lines stay.
        listingPanel.innerHTML = listingError === "" ? "" : "<p>" + escapeText(listingError) + "</p>";
        return;
    }
    const low = Math.min(cursor, anchor), high = Math.max(cursor, anchor);
    // The line that takes the listing's one tab stop: the cursor's, or the first.
    const stop = Math.max(0, listingLines.findIndex(line => cursor >= line.address && cursor < line.address + line.size));
    const focused = focusedListing();
    let html = "";
    for (const [index, line] of listingLines.entries()) {
        const last = line.address + line.size - 1;
        let classes = "ln " + line.kind + (line.guess ? " guess" : "");
        if (high > low && line.address <= high && last >= low) classes += " sel";
        if (cursor >= line.address && cursor <= last) classes += " cur";
        const space = line.text.indexOf(" ");
        const mnemonic = space < 0 ? line.text : line.text.substring(0, space), operand = space < 0 ? "" : line.text.substring(space + 1);
        let text = escapeText(mnemonic);
        if (operand !== "") {
            text += " " + (line.target === null || line.target === undefined
                ? escapeText(operand)
                : '<a role="link" tabindex="-1" data-go="' + line.target + '" title="Go to ' + where(line.target) + '">' + escapeText(operand) + "</a>");
        }
        const source = line.path === null || line.path === undefined ? ""
            : '<a class="src" role="link" tabindex="-1" data-src="' + escapeText(line.path) + '" data-line="' + line.line + '" title="Open ' + escapeText(line.path) + ", line " + line.line + '">'
                + escapeText(fileName(line.path)) + ":" + line.line + "</a>";
        const label = line.label === null || line.label === undefined ? "" : line.label;
        html += '<div class="' + classes + '" role="listitem" aria-keyshortcuts="F9"' + (line.guess ? ' title="A guess: no source describes these bytes, and analysis takes them for ' + line.kind + '"' : "") + ' tabindex="' + (index === stop ? 0 : -1) + '" data-a="' + line.address + '" data-s="' + line.size + '">' + breakpointHtml(line) + '<span class="a">' + hex(line.address, 4) + "</span>"
            + '<span class="l"' + (label === "" ? "" : ' title="' + escapeText(label) + '"') + ">" + escapeText(label) + '</span><span class="t">' + text + "</span>"
            + (line.comment ? '<span class="cm">; ' + escapeText(line.comment) + "</span>" : "") + source + "</div>";
    }
    listingPanel.innerHTML = html;
    if (!listingPanel.querySelector) return;
    if (focused !== null) {
        // Drawing the lines again keeps the focus where it was, on a line or one of its links.
        // Without scrolling to it, so the listing stays where the user scrolled it; where the line has left the
        // listing, as when the bytes scroll, the listing's tab stop takes it, so keys still reach the listing.
        const line = listingPanel.querySelector('[data-a="' + focused.address + '"]');
        const target = line === null ? listingPanel.querySelector('[tabindex="0"]')
            : focused.link < 0 ? line : line.querySelectorAll("a")[focused.link] || line;
        if (target !== null) target.focus({ preventScroll: true });
    }
    if (cursor !== listingCursor) {
        // The cursor's line scrolls into view as the cursor moves, not as the listing scrolls; until the listing
        // has the line, which may come with the next listing, it tries again.
        const current = listingPanel.querySelector(".ln.cur");
        if (current !== null) {
            current.scrollIntoView({ block: "nearest" });
            listingCursor = cursor;
        }
    }
}

// Where the focus is in the listing: the address of its line, and which of the line's links has it, or -1 for the
// line; null when the listing does not have it.
function focusedListing() {
    const active = document.activeElement;
    if (!active || !listingPanel.contains || !listingPanel.contains(active) || !active.closest) return null;
    const line = active.closest("[data-a]");
    if (line === null) return null;
    return { address: Number(line.dataset.a), link: active === line ? -1 : Array.from(line.querySelectorAll("a")).indexOf(active) };
}

// The gutter's breakpoint dot, filled where one stops at the line's address; clicking it, or F9, sets or takes it away.
function breakpointHtml(line) {
    const on = Array.isArray(line.breakpoints) && line.breakpoints.length > 0;
    // The dot is hidden from screen readers, which hear "Breakpoint" at the line's start instead, and F9 as its shortcut.
    return '<span class="bp' + (on ? " on" : "") + '" data-bp="1" aria-hidden="true" title="'
        + (on ? "Take the breakpoint at " + where(line.address) + " away" : "Stop at " + where(line.address)) + ' (F9)">&#9679;</span>'
        + (on ? '<span class="sr">Breakpoint, </span>' : "");
}

// Sets or takes away a breakpoint at a listing line's address: a function breakpoint VS Code keeps, named by the
// address, such as $0300 or aux:$0400, so it shows in the Breakpoints view.
async function toggleBreakpoint(line) {
    try {
        const result = await request({ type: "breakpoint", address: line.address, ids: line.breakpoints ?? null });
        status(result.status);
    } catch (error) {
        status(String(error.message || error), true);
    }
}

// F9 in the bytes: a breakpoint at the line the cursor is in.
// Only the listing on show, as last asked for, says where a line starts and what stops there: while it is hidden or
// being read again, its lines may be of other bytes, or name breakpoints that have moved since.
function listingShown() { return showListing && !ended && narrow !== true; }
function listingCurrent() { return listingShown() && listingLoaded === listingKey; }

async function toggleAtCursor() {
    const shown = listingShown();
    const current = listingCurrent();
    const line = current ? listingLines.find(item => cursor >= item.address && cursor < item.address + item.size) : undefined;
    if (line === undefined) {
        status(!shown ? "Show the listing to set a breakpoint." : !current ? "The listing is being read; press F9 again." : "No listing line is at the cursor.", true);
        return;
    }
    await toggleBreakpoint(line);
}

// Selects a line's bytes, the cursor on its first.
function selectLine(address, size) {
    moveTo(address + size - 1, false, false);
    moveTo(address, true, false);
}

// Marks the selection as data or neither, or starts code, names or comments at the cursor, in the hints file: the
// extension asks for a name's or comment's text, and the labels and listing are read again.
async function mark(fields) {
    const ranged = fields.kind === "data" || fields.kind === "clear";
    const low = ranged ? Math.min(cursor, anchor) : cursor, high = ranged ? Math.max(cursor, anchor) : cursor;
    try {
        const result = await request({ type: "mark", address: low, count: high - low + 1, ...fields });
        if (result && result.cancelled) return;
        if (fields.kind !== undefined) await reconcile(result.address, result.count, fields.kind === "code" ? result.address : undefined);
        marks++;
        await loadExtras();
        render();
        status("Kept in " + fileName(String(result.path)) + ".");
    } catch (error) {
        status(String(error.message || error), true);
    }
}

// Decode from here's starts give way to a code or data mark, as the hints file's do: each whose instruction is in
// the marked bytes or runs into them goes, except a code mark's own. Only the starts asked about can go, so one
// added while the request was out stays.
async function reconcile(address, count, keep) {
    if (forcedStarts.size === 0) return;
    const sent = Array.from(forcedStarts);
    const result = await request({ type: "starts", address, count, starts: sent, keep });
    const left = new Set(result.starts);
    for (const start of sent) if (!left.has(start)) forcedStarts.delete(start);
}

// Starts an instruction at the cursor, where the listing decoded from the wrong byte.
function decodeHere() {
    forcedStarts.add(cursor);
    render();
    status("The listing decodes an instruction from " + where(cursor) + ".");
}

// A listing line or link clicked, or Enter or Space on one: a source opens, an operand goes to its address, and a
// line selects its bytes. Reports whether it was one of those.
function activateListing(target) {
    if (!target || !target.closest) return false;
    const source = target.closest("[data-src]");
    if (source !== null) {
        void request({ type: "open", path: source.dataset.src, line: Number(source.dataset.line) }).catch(error => status(String(error.message || error), true));
        return true;
    }
    const go = target.closest("[data-go]");
    if (go !== null) {
        jump(Number(go.dataset.go));
        grid.focus();
        return true;
    }
    const line = target.closest("[data-a]");
    if (line === null) return false;
    selectLine(Number(line.dataset.a), Number(line.dataset.s));
    grid.focus();
    return true;
}

listingPanel.addEventListener("click", event => {
    const target = event.target;
    const dot = target && target.closest ? target.closest("[data-bp]") : null;
    const line = dot === null ? null : dot.closest("[data-a]");
    if (line !== null && !listingCurrent()) { status("The listing is being read; click again.", true); return; }
    const listed = line === null ? undefined : listingLines.find(item => item.address === Number(line.dataset.a));
    if (listed !== undefined) { void toggleBreakpoint(listed); return; }
    activateListing(target);
});

// Up and Down move between lines, Left and Right between a line and its links, Home and End to the first and last
// line, Enter or Space does what a click does, and Escape goes back to the bytes.
listingPanel.addEventListener("keydown", event => {
    const target = event.target;
    if (!target || !target.closest) return;
    const line = target.closest("[data-a]");
    if (line === null) return;
    const stops = [line, ...Array.from(line.querySelectorAll("a"))];
    let next = null;
    if (event.key === "Enter" || event.key === " ") {
        if (!activateListing(target)) return;
    } else if (event.key === "F9") {
        if (!listingCurrent()) { status("The listing is being read; press F9 again.", true); event.preventDefault(); return; }
        const listed = listingLines.find(item => item.address === Number(line.dataset.a));
        if (listed !== undefined) void toggleBreakpoint(listed);
    } else if (event.key === "ArrowDown") next = line.nextElementSibling;
    else if (event.key === "ArrowUp") next = line.previousElementSibling;
    else if (event.key === "Home") next = listingPanel.firstElementChild;
    else if (event.key === "End") next = listingPanel.lastElementChild;
    else if (event.key === "ArrowRight") next = stops[Math.min(stops.length - 1, stops.indexOf(target) + 1)];
    else if (event.key === "ArrowLeft") next = stops[Math.max(0, stops.indexOf(target) - 1)];
    else if (event.key === "Escape") grid.focus();
    else return;
    if (next) next.focus();
    event.preventDefault();
    event.stopPropagation();
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
        + (showListing ? '<button data-act="decode" title="Start an instruction at the cursor in the listing, where it decodes from the wrong byte (Ctrl+D)">Decode from here</button>' : "") + "</div>"
        + '<div class="acts"><button data-act="markCode" title="Mark code as starting here, kept in the hints file">Mark code</button>'
        + '<button data-act="markData" title="Mark the selection as data, kept in the hints file">Mark data' + count + "</button>"
        + '<button data-act="unmark" title="Take the code and data marks off the selection">Unmark</button>'
        + '<button data-act="name" title="Name this address, kept in the hints file">Name</button>'
        + '<button data-act="comment" title="Comment on this address, kept in the hints file">Comment</button>'
        + '<button data-act="bookmark" title="' + (bookmarkAt.has(cursor) ? "Rename or remove this bookmark" : "Bookmark this address with a name, kept for this launch configuration") + '">Bookmark</button></div>';
    html += '<div class="where">' + where(cursor);
    const name = labelOf(labels, cursor);
    if (name !== undefined) html += " · " + escapeText(name);
    if (high > low) html += " · " + (high - low + 1) + " bytes, " + where(low) + "-$" + hex(high, 4);
    html += "</div>";
    html += inspectionHtml();
    const rows = inspect(bytes, readable, cursor, charset === null ? undefined : charset.text);
    if (inspected !== null && inspected.address === cursor) rows.push(...(inspected.values ?? []));
    if (comparison !== "" && differs(cursor)) rows.push({ label: comparison === "snapshot" ? "In the snapshot" : "In " + comparedName(), value: "$" + hex(compared().bytes[cursor], 2) });
    else if (readable[cursor] === 1 && changed[cursor]) rows.push({ label: "At the last stop", value: "$" + hex(was[cursor], 2) });
    if (frozen.has(cursor)) rows.push({ label: "Frozen at", value: "$" + hex(frozen.get(cursor), 2) });
    if (readable[cursor] === 1 && readOnly[cursor]) rows.push({ label: "Writes", value: "refused: not RAM now" });
    for (const row of rows) {
        html += '<div class="item"><span class="k">' + escapeText(row.label) + '</span><span class="v">' + escapeText(row.value) + "</span></div>";
    }
    inspector.innerHTML = html;
}

// What the debugger says about the cursor's address: its region and where in it, what the memory map does with it,
// the label it is in with its documentation, and its source line. Asked for again when the cursor, memory, the
// marks or the stop change.
let inspected = null, inspectKey = "";

function wantInspection() {
    if (ended) return;
    const key = cursor + ":" + generation + ":" + writes + ":" + marks;
    if (key === inspectKey) return;
    inspectKey = key;
    void loadInspection(cursor, key);
}

async function loadInspection(address, key) {
    let result = null;
    try {
        result = await request({ type: "inspect", address });
    } catch {
        // The inspector shows what the page knows without it.
    }
    if (key !== inspectKey) return;
    inspected = result;
    showInspector();
}

function inspectionHtml() {
    const known = inspected !== null && inspected.address === cursor ? inspected : null;
    if (known === null) return "";
    const row = (label, value) => '<div class="item"><span class="k">' + label + '</span><span class="v">' + value + "</span></div>";
    let html = "";
    if (known.region) html += row("Region", escapeText(known.region + (known.detail ? ", " + known.detail : "")));
    if (known.mapped) html += row("Map", escapeText(known.mapped));
    if (known.label && known.offset > 0) html += row("In", escapeText(known.label + "+" + known.offset));
    if (known.summary) html += '<div class="doc">' + escapeText((known.offset > 0 ? known.label + ": " : "") + known.summary) + "</div>";
    if (known.path) {
        html += row("Source", '<button class="link" data-src="' + escapeText(known.path) + '" data-line="' + known.line + '" title="Open ' + escapeText(known.path) + ", line " + known.line + '">'
            + escapeText(fileName(known.path) + ":" + known.line) + "</button>");
    }
    return html;
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
        // The listing decodes what memory holds now.
        writes++;
        wantListing();
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
            case "markCode": void mark({ kind: "code" }); break;
            case "markData": void mark({ kind: "data" }); break;
            case "unmark": void mark({ kind: "clear" }); break;
            case "name": void mark({ what: "name" }); break;
            case "comment": void mark({ what: "comment" }); break;
            case "bookmark": void addBookmark(); break;
            case "start": void startSearch(Number(document.getElementById("searchSize")?.value ?? 1)); break;
            case "reset": search = null; showSearch(); break;
            case "narrow": void narrowBy(action.dataset.test, document.getElementById("searchValue").value); break;
            case "back": backSearch(); break;
            case "watchHit": void watch([action.dataset.w ?? "[" + where(offset) + "]"]); break;
            case "thaw": void freeze([], [offset]).catch(error => status(String(error.message || error), true)); break;
        }
        return;
    }
    const source = target.closest ? target.closest("[data-src]") : null;
    if (source !== null) {
        void request({ type: "open", path: source.dataset.src, line: Number(source.dataset.line) }).catch(error => status(String(error.message || error), true));
        return;
    }
    const hit = target.closest ? target.closest("[data-go]") : null;
    if (hit !== null) jump(Number(hit.dataset.go));
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
        // A view that follows follows what was gone to last.
        if (following !== "") setFollowing(text.trim());
        jump(result.address);
        status(following === "" ? "" : "Following " + following + ".");
        grid.focus();
    } catch (error) {
        status(String(error.message || error), true);
    }
}

// Goes to an address, remembering where the cursor was for Back.
function jump(offset) {
    const to = Math.min(SIZE - 1, Math.max(0, offset));
    if (to !== cursor) {
        backStack.push(cursor);
        if (backStack.length > HISTORY) backStack.shift();
        forwardStack.length = 0;
    }
    moveTo(to, false, true);
    showHistory();
}

// Back to where a go-to left from, or with forward, on to where Back left from.
function goBack(forward) {
    const from = forward ? forwardStack : backStack, to = forward ? backStack : forwardStack;
    if (from.length === 0) return;
    to.push(cursor);
    moveTo(from.pop(), false, true);
    showHistory();
}

function showHistory() {
    backButton.disabled = backStack.length === 0;
    forwardButton.disabled = forwardStack.length === 0;
}

// Follows an expression, or with none stays put.
function setFollowing(text) {
    following = text;
    followBox.checked = following !== "";
    followLabel.title = following === ""
        ? "Go to the Go to expression again at each stop, such as PC, S+$100 or [$06].w; a view that does not follow stays where it is"
        : "Following " + following + ": the view goes there again at each stop. Clear to stay put.";
    remember();
}

// Turns following on with Go to's text, or off.
function useFollow(on) {
    if (!on) {
        setFollowing("");
        status("The view stays where it is.");
        return Promise.resolve();
    }
    const text = gotoBox.value.trim();
    if (text === "") {
        followBox.checked = false;
        status("Type what to follow in Go to, such as PC, then check Follow.", true);
        gotoBox.focus();
        return Promise.resolve();
    }
    setFollowing(text);
    status("Following " + text + ".");
    return follow();
}

// Goes where the followed expression points now, as at a stop.
async function follow() {
    const text = following;
    if (text === "") return;
    try {
        const result = await request({ type: "goto", text });
        if (following === text) jump(result.address);
    } catch (error) {
        if (following === text) status("Following " + text + ": " + String(error.message || error), true);
    }
}

// Bookmarks the cursor's address, or renames or removes its bookmark, through the extension, which asks the name.
async function addBookmark() {
    try {
        const name = labelOf(labels, cursor);
        const result = await request({ type: "bookmark", address: cursor, name: name ?? null });
        if (result.cancelled) return;
        useBookmarks(result.bookmarks);
        render();
    } catch (error) {
        status(String(error.message || error), true);
    }
}

// Lists the bookmarks to go to one; one in another space opens there.
async function pickBookmark() {
    try {
        const result = await request({ type: "bookmarks" });
        if (result.none) { status("No bookmarks yet: Bookmark in the inspector adds one."); return; }
        if (result.bookmarks !== undefined) useBookmarks(result.bookmarks);
        if (typeof result.address === "number") {
            jump(result.address);
            status("Bookmark " + result.name + " at " + where(result.address) + ".");
            grid.focus();
        }
        render();
    } catch (error) {
        status(String(error.message || error), true);
    }
}

function useBookmarks(list) {
    bookmarkAt = new Map((list ?? []).map(item => [item.address, item.name]));
}

// Finds a number, as a byte, a word either way round or the BASIC's floats, whichever comes first from the cursor.
async function findValue(text, backward) {
    const read = valueForms(text);
    if (typeof read === "string") { status(read, true); return; }
    const forms = read.forms.slice();
    try {
        const floats = await request({ type: "numbers", value: read.decimal });
        for (const format of floats.formats ?? []) forms.push({ label: "a " + String(format.label).toLowerCase(), bytes: format.bytes });
    } catch (error) {
        status(String(error.message || error), true);
        return;
    }
    if (forms.length === 0) { status(read.decimal + " does not fit a byte, a word or the BASIC's numbers.", true); return; }
    await ensureAll();
    const from = backward ? cursor - 1 : cursor + 1;
    let best = -1, bestForm = null, bestDistance = SIZE + 1;
    for (const form of forms) {
        const at = findPattern(bytes, readable, form.bytes.map(value => ({ value, mask: 0xFF })), from, backward);
        if (at < 0) continue;
        const distance = backward ? (from - at + 2 * SIZE) % SIZE : (at - from + 2 * SIZE) % SIZE;
        if (distance < bestDistance) { best = at; bestForm = form; bestDistance = distance; }
    }
    if (best < 0) { status(read.decimal + " is not in memory as " + forms.map(form => form.label).join(", or ") + ".", true); return; }
    found(best, bestForm.bytes.length, "Found " + read.decimal + " as " + bestForm.label + " at " + where(best) + ".");
}

async function find(backward) {
    const text = findBox.value;
    if (text.trim().startsWith("=")) { await findValue(text.trim().substring(1), backward); return; }
    const pattern = parsePattern(text, charset === null ? undefined : charset.text);
    if (typeof pattern === "string") {
        // What is neither bytes nor quoted text is an instruction, which the debugger decodes.
        const trimmed = text.trim();
        if (trimmed.length === 0 || trimmed.startsWith('"') || trimmed.startsWith("'")) { status(pattern, true); return; }
        await findInstruction(text, backward);
        return;
    }
    await ensureAll();
    const at = findPattern(bytes, readable, pattern, backward ? cursor - 1 : cursor + 1, backward);
    if (at < 0) { status("Not found.", true); return; }
    found(at, pattern.length, "Found at " + where(at) + ".");
}

// Finds an instruction such as STA $C0?? from the cursor, as the listing would show it.
async function findInstruction(text, backward) {
    try {
        const result = await request({ type: "find", pattern: text, from: backward ? cursor - 1 : cursor + 1, backward });
        if (result.address === null || result.address === undefined) { status("No instruction matches " + text.trim() + ".", true); return; }
        found(result.address, result.size, "Found " + result.text + " at " + where(result.address) + ".");
    } catch (error) {
        status(String(error.message || error), true);
    }
}

// Selects a match, the cursor on its first byte.
function found(at, size, message) {
    // A match is a move of the cursor, as an edit waiting on the debugger must know.
    moves++;
    anchor = at + size - 1;
    cursor = at;
    nibble = null;
    reveal(at, true);
    render();
    status(message);
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
    // The mouse's back and forward buttons go back and forward, from where the cursor is.
    if (event.button === 3 || event.button === 4) return;
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
    } else if (key === "F9") {
        void toggleAtCursor();
    } else if (event.altKey && (key === "ArrowLeft" || key === "ArrowRight")) {
        goBack(key === "ArrowRight");
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

const backButton = document.getElementById("back"), forwardButton = document.getElementById("forward");
const followBox = document.getElementById("follow"), followLabel = document.getElementById("followLabel");
backButton.addEventListener("click", () => { goBack(false); grid.focus(); });
forwardButton.addEventListener("click", () => { goBack(true); grid.focus(); });
document.getElementById("bookmarks").addEventListener("click", () => void pickBookmark());
followBox.addEventListener("change", () => void useFollow(followBox.checked));
// The mouse's back and forward buttons.
window.addEventListener("mouseup", event => {
    if (event.button !== 3 && event.button !== 4) return;
    goBack(event.button === 4);
    event.preventDefault();
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
        if (action.jump !== undefined) jump(action.jump);
        if (action.back) goBack(false);
        if (action.forward) goBack(true);
        if (action.gotoText !== undefined) { gotoBox.value = action.gotoText; await goTo(action.gotoText); }
        if (action.follow !== undefined) { followBox.checked = action.follow; await useFollow(action.follow); }
        if (action.findValue !== undefined) { findBox.value = action.findValue; await find(action.backward === true); }
        if (action.bookmark) await addBookmark();
        if (action.bookmarks) await pickBookmark();
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
        if (action.mark !== undefined) await mark(action.mark);
        if (action.breakpoint) await toggleAtCursor();
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
        listing: listingLines.map(line => hex(line.address, 4) + " " + line.text),
        breakpoints: listingLines.filter(line => Array.isArray(line.breakpoints) && line.breakpoints.length > 0).map(line => line.address),
        following,
        back: backStack.slice(),
        forward: forwardStack.slice(),
        bookmarks: Array.from(bookmarkAt, ([address, name]) => ({ address, name }))
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
        useBookmarks(message.bookmarks);
        if (following !== "") gotoBox.value = following;
        setFollowing(following);
        reveal(cursor, true);
        render();
        grid.focus();
        void loadExtras();
        void loadBanks();
        void follow();
    } else if (message.type === "changed") {
        generation++;
        pages.fill(0);
        render();
    } else if (message.type === "marked") {
        // Another editor on this space marked, named or commented on memory.
        marks++;
        const reconciled = message.kind === undefined ? Promise.resolve() : reconcile(message.address, message.count, message.kind === "code" ? message.address : undefined);
        void reconciled.then(loadExtras).then(() => render(), error => status(String(error.message || error), true));
    } else if (message.type === "bookmarks") {
        // Bookmarks were added, renamed or removed here or in another editor.
        useBookmarks(message.bookmarks);
        render();
    } else if (message.type === "goto") {
        // A bookmark in this space picked from another editor's list.
        jump(message.address);
        grid.focus();
    } else if (message.type === "breakpoints") {
        // Breakpoints were set or taken away, here or anywhere else.
        breakpointChanges++;
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
        void follow();
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
