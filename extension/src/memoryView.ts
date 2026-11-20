// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Retrocore Memory's page: a hex and text grid over a whole 64K space, with labels, rows aligned to them, the
// machine's own characters, read-only shading, changes since the last stop or differences from a snapshot or another
// bank, go to, following an expression, back and forward, bookmarks, find, copy, editing with undo, an inspector, RAM search of bytes or words, watching in VS Code's Watch
// view and frozen bytes. The page asks the extension for bytes, labels,
// characters, writes, freezes and watches; the extension asks the debugger, or VS Code for watches.

import { copyFormats, pageFunctions } from "./memoryModel";

/** The memory editor's page, with its script allowed by the nonce. */
export function memoryEditorHtml(nonce: string, assets?: { cspSource: string; codicons: string }): string {
    // The icons are VS Code's codicons, which the extension ships, as a webview cannot reach the workbench's.
    const source = assets === undefined ? "" : " " + assets.cspSource;
    return `<!doctype html><html><head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'${source}; font-src${source || " 'none'"}; img-src data:; script-src 'nonce-${nonce}'">
${assets === undefined ? "" : `<link rel="stylesheet" href="${assets.codicons}">`}
<style>
[hidden]{display:none!important}
html,body{height:100%}
body{margin:0;display:flex;flex-direction:column;background:var(--vscode-editor-background);color:var(--vscode-editor-foreground);font-family:var(--vscode-font-family);font-size:var(--vscode-font-size);overflow:hidden}
.bar{display:flex;flex-wrap:wrap;gap:4px;align-items:center;padding:4px 8px;border-bottom:1px solid var(--vscode-panel-border)}
.bar .spacer{flex:1}
#space{max-width:280px}
input{font-family:var(--vscode-font-family);font-size:var(--vscode-font-size);padding:3px 6px;border-radius:2px;width:150px;background:var(--vscode-input-background);color:var(--vscode-input-foreground);border:1px solid var(--vscode-input-border,transparent)}
input::placeholder{color:var(--vscode-input-placeholderForeground)}
select{font-family:var(--vscode-font-family);font-size:var(--vscode-font-size);height:24px;padding:0 4px;border-radius:2px;background:var(--vscode-dropdown-background);color:var(--vscode-dropdown-foreground);border:1px solid var(--vscode-dropdown-border,transparent)}
select:focus{outline:1px solid var(--vscode-focusBorder);outline-offset:-1px}
input:focus{outline:1px solid var(--vscode-focusBorder);outline-offset:-1px}
button{font-family:var(--vscode-font-family);font-size:var(--vscode-font-size);line-height:18px;padding:2px 10px;border-radius:2px;cursor:pointer;color:var(--vscode-button-secondaryForeground);background:var(--vscode-button-secondaryBackground);border:1px solid var(--vscode-button-border,transparent)}
button:hover{background:var(--vscode-button-secondaryHoverBackground)}
button:focus-visible{outline:1px solid var(--vscode-focusBorder);outline-offset:1px}
button:disabled{opacity:.5;cursor:default}
button.action{display:inline-flex;align-items:center;justify-content:center;flex:none;width:24px;height:24px;padding:0;border:1px solid transparent;border-radius:5px;background:none;color:var(--vscode-icon-foreground,var(--vscode-foreground))}
button.action:hover{background:var(--vscode-toolbar-hoverBackground)}
button.action:disabled{opacity:.4;background:none}
button.action[aria-pressed=true]{background:var(--vscode-inputOption-activeBackground);border-color:var(--vscode-inputOption-activeBorder,transparent);color:var(--vscode-inputOption-activeForeground,inherit)}
button.action:focus-visible{outline-offset:-1px}
.box{display:flex;align-items:center;gap:1px;padding-right:2px;background:var(--vscode-input-background);border:1px solid var(--vscode-input-border,transparent);border-radius:2px}
.box:focus-within{border-color:var(--vscode-focusBorder)}
.box input{border:none;background:none;width:220px}
.box input:focus{outline:none}
.box button.action{width:20px;height:20px;border-radius:3px}
.box select{height:22px;border:none;background:none}
.box select:focus{outline:none}
.box option{background:var(--vscode-dropdown-background);color:var(--vscode-dropdown-foreground)}
.bar .nav button{padding:2px 6px}
.main{flex:1;display:flex;min-height:0;min-width:0}
#bytes{flex:0 1 auto;min-width:120px;position:relative;display:flex;flex-direction:column;min-height:0;overflow:hidden}
.fold{display:inline-block;width:22px;margin-right:1ch;vertical-align:top}
#head [data-fold]{cursor:pointer}
.strip{position:absolute;top:0;bottom:0;width:22px;display:flex;align-items:center;justify-content:center;gap:6px;padding:8px 0;border:none;border-left:1px solid var(--vscode-panel-border);border-right:1px solid var(--vscode-panel-border);border-radius:0;background:var(--vscode-sideBarSectionHeader-background,var(--vscode-editor-background));color:var(--vscode-descriptionForeground);font-family:var(--vscode-font-family);font-size:11px;writing-mode:vertical-rl;white-space:nowrap;overflow:hidden;cursor:pointer}
.strip:hover{color:var(--vscode-foreground);background:var(--vscode-toolbar-hoverBackground)}
.strip.ccw{transform:rotate(180deg)}
.strip .codicon{font-size:14px;text-orientation:sideways}
#listingPane .strip{position:static;flex:1;width:auto;border:none}
#head{flex:none;height:24px;line-height:24px;color:var(--vscode-descriptionForeground);border-bottom:1px solid var(--vscode-panel-border);font-family:var(--vscode-editor-font-family);font-size:var(--vscode-editor-font-size);white-space:pre;user-select:none}
#head span{cursor:help}
#head .lab{color:inherit}
#head .txt span{width:auto}
#head .hex span{cursor:help}
#grid{flex:1;min-height:0;overflow:auto;position:relative;outline:none;font-family:var(--vscode-editor-font-family);font-size:var(--vscode-editor-font-size);white-space:pre;user-select:none;cursor:text}
#spacer{position:absolute;top:0;left:0;width:1px}
#rows{position:absolute;top:0;left:0;right:0}
.row{height:20px;line-height:20px;padding:0 10px;width:max-content}
.addr{display:inline-block;width:6ch;color:var(--vscode-editorLineNumber-foreground)}
.lab{display:inline-block;overflow:hidden;text-overflow:ellipsis;vertical-align:top;margin-right:1ch;color:var(--vscode-symbolIcon-functionForeground,var(--vscode-editor-foreground))}
.lab.in{opacity:.6}
.lab[data-a]{cursor:pointer}
#head button.tog{display:inline-flex;align-items:center;justify-content:center;width:20px;height:20px;margin-left:4px;padding:0;font-size:14px;vertical-align:middle;border:1px solid transparent;border-radius:3px;background:none;color:var(--vscode-icon-foreground,inherit);cursor:pointer}
#head button.tog:hover{background:var(--vscode-toolbar-hoverBackground)}
#head button.tog[aria-pressed=true]{border-color:var(--vscode-inputOption-activeBorder,var(--vscode-focusBorder));background:var(--vscode-inputOption-activeBackground);color:var(--vscode-inputOption-activeForeground,inherit)}
.lab .nm{display:inline-block;max-width:calc(100% - 4ch);overflow:hidden;text-overflow:ellipsis;vertical-align:top}
.dt{background-color:color-mix(in srgb,var(--vscode-symbolIcon-arrayForeground,#cca700) 10%,transparent)}
.dt2{background-color:color-mix(in srgb,var(--vscode-symbolIcon-arrayForeground,#cca700) 20%,transparent)}
.lab .more{margin-left:4px;padding:0 4px;border-radius:7px;font-size:85%;color:var(--vscode-badge-foreground,var(--vscode-foreground));background:var(--vscode-badge-background,color-mix(in srgb,var(--vscode-descriptionForeground) 25%,transparent))}
.hl{outline:1px dashed var(--vscode-symbolIcon-functionForeground,var(--vscode-focusBorder));outline-offset:-1px;background-color:color-mix(in srgb,var(--vscode-symbolIcon-functionForeground,var(--vscode-focusBorder)) 25%,transparent)}
.hex span.bm{box-shadow:inset 0 -2px var(--vscode-charts-yellow,#cca700)}
.hex span.lb{background-image:linear-gradient(135deg,color-mix(in srgb,var(--vscode-symbolIcon-functionForeground,var(--vscode-focusBorder)) 55%,transparent) 3.5px,transparent 3.5px)}
body.nomarks .hex span.lb{background-image:none}
.ro{background-color:color-mix(in srgb,var(--vscode-editor-foreground) 8%,transparent)}
.chg{background-color:var(--vscode-debugView-valueChangedHighlight,rgba(86,156,214,.35))}
.frz{color:var(--vscode-charts-blue,#3794ff);font-weight:600}
.txt.g{position:relative;display:inline-block;vertical-align:top}
.txt.g span{height:16px;vertical-align:middle}
.txt.g canvas{position:absolute;left:0;top:2px;height:16px;pointer-events:none}
.hex span{display:inline-block;width:3ch;text-align:center}
.hex span.mid{margin-left:1ch}
.txt{margin-left:2ch}
.txt span{display:inline-block;width:1ch}
.hi{color:var(--vscode-debugTokenExpression-string,var(--vscode-editor-foreground))}
.gap{color:var(--vscode-disabledForeground)}
.sel{background:var(--vscode-editor-inactiveSelectionBackground)}
.cur{outline:1px solid var(--vscode-editorCursor-foreground,var(--vscode-focusBorder));outline-offset:-1px}
#grid:focus .cur.on{background:var(--vscode-editor-selectionBackground)}
.pending{color:var(--vscode-editorWarning-foreground)}
#side{flex:none;min-width:0;display:flex;flex-direction:column;background:var(--vscode-panel-background,var(--vscode-editor-background));font-size:var(--vscode-font-size)}
.tabs{display:flex;flex:none;gap:0;height:35px;align-items:stretch;padding:0 8px}
.tablist{display:flex;align-items:stretch;min-width:0;overflow:hidden}
.docks{display:flex;align-items:center;gap:2px;margin-left:auto}
.docks button.action[aria-pressed=true]:disabled{opacity:1;cursor:default}
#sash{flex:none;width:4px;margin:0 -2px;position:relative;z-index:5;cursor:col-resize;background:none;border-left:1px solid var(--vscode-panel-border);background-clip:content-box;transition:background-color .1s .3s}
#sash:hover,#sash.dragging,#sash:focus-visible{background-color:var(--vscode-sash-hoverBorder,var(--vscode-focusBorder));outline:none}
.tablist button{display:flex;align-items:center;align-self:center;height:27px;margin:0 2px;padding:0 8px;background:none;border:none;border-radius:0;font-size:11px;text-transform:uppercase;letter-spacing:.02em;line-height:27px;color:var(--vscode-panelTitle-inactiveForeground,var(--vscode-descriptionForeground))}
.tablist button:hover{background:none;color:var(--vscode-panelTitle-activeForeground,var(--vscode-foreground))}
.tablist button.on{color:var(--vscode-panelTitle-activeForeground,var(--vscode-foreground));box-shadow:inset 0 -1px var(--vscode-panelTitle-activeBorder,var(--vscode-focusBorder))}
.tablist button:focus-visible{outline:1px solid var(--vscode-focusBorder);outline-offset:-1px}
.panel{flex:1;min-height:0;overflow-y:auto;padding:4px 20px 12px}
.acts{display:flex;gap:6px;margin-bottom:10px;flex-wrap:wrap}
.menu{position:fixed;z-index:10;display:flex;flex-direction:column;min-width:12em;padding:4px;background:var(--vscode-menu-background,var(--vscode-editorWidget-background));color:var(--vscode-menu-foreground,var(--vscode-foreground));border:1px solid var(--vscode-menu-border,var(--vscode-panel-border));border-radius:4px;box-shadow:0 2px 8px var(--vscode-widget-shadow,rgba(0,0,0,.36));font-size:12px}
.menu[hidden]{display:none}
.menu button{background:none;border:none;border-radius:3px;padding:3px 10px;text-align:left;white-space:nowrap;color:inherit}
.menu button:hover,.menu button:focus{background:var(--vscode-menu-selectionBackground,var(--vscode-list-activeSelectionBackground));color:var(--vscode-menu-selectionForeground,inherit);outline:none}
.menu .sep{height:1px;margin:4px 6px;background:var(--vscode-menu-separatorBackground,var(--vscode-panel-border))}
.group{margin-bottom:10px}
.group h3{margin:0 0 4px;font-size:12px;font-weight:normal;color:var(--vscode-descriptionForeground)}
.acts .gap{width:8px}
.line{padding:1px 0;font-family:var(--vscode-editor-font-family)}
.line .meta,.where .meta{font-family:var(--vscode-font-family);color:var(--vscode-descriptionForeground)}
.values button.link,.values .plain{margin-right:2ch}
#inspector button.order{font-size:11px;margin:2px 0 4px}
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
.item{display:flex;gap:8px;padding:2px 0;align-items:baseline}
.item .k{width:9em;flex:none;color:var(--vscode-descriptionForeground);white-space:nowrap}
.item .v{font-family:var(--vscode-editor-font-family);white-space:pre}
#inspector .doc{margin:2px 0 6px;color:var(--vscode-descriptionForeground)}
#inspector button.link{background:none;border:none;padding:0;color:var(--vscode-textLink-foreground);font:inherit;cursor:pointer}
#inspector button.link:focus-visible{outline:1px solid var(--vscode-focusBorder)}
#inspector button.ref{width:100%;background:none;border:none;color:inherit;font:inherit;text-align:left}
#inspector button.ref:focus-visible{outline:1px solid var(--vscode-focusBorder);outline-offset:-1px}
#listingPane{flex:1 1 auto;min-width:0;display:flex;flex-direction:column;min-height:0;border-left:1px solid var(--vscode-panel-border)}
#listingHead{flex:none;height:24px;line-height:24px;padding:0 8px;color:var(--vscode-descriptionForeground);border-bottom:1px solid var(--vscode-panel-border);font-family:var(--vscode-editor-font-family);font-size:var(--vscode-editor-font-size);user-select:none}
button.heading{all:unset;cursor:pointer;white-space:pre}
button.heading:focus-visible{outline:1px solid var(--vscode-focusBorder);outline-offset:1px}
#head button.hex.heading span{display:inline-block}
#listingPane.folded{flex:none;width:22px}
body.nolist:not(.narrow) #side{flex:1 0 auto}
#listingPane.folded #listingHead,#listingPane.folded #listing{display:none}
#listing{flex:1;min-height:0;overflow:auto;display:grid;align-content:start;font-family:var(--vscode-editor-font-family);font-size:var(--vscode-editor-font-size);white-space:pre}
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
body.narrow .main{display:grid;grid-template-columns:auto minmax(0,1fr);grid-template-rows:minmax(0,1fr) 4px auto}
body.narrow #sash{grid-row:2;grid-column:1/-1;width:auto;height:4px;margin:-2px 0;cursor:row-resize;border-left:none;border-top:1px solid var(--vscode-panel-border)}
body.narrow #bytes{grid-row:1;grid-column:1}
body.narrow #listingPane{grid-row:1;grid-column:2;width:auto}
body.narrow #listingPane.folded{width:22px}
body.narrow.nolist .main{grid-template-columns:minmax(0,1fr)}
body.cramped #listingPane{display:none}
body.narrow #side{grid-row:3;grid-column:1/-1}
body.narrow #inspector .acts{margin:0 0 6px}
body.narrow #inspector .where{margin:0;padding:2px 0}
body.narrow .group{display:flex;gap:12px;align-items:baseline;margin-bottom:4px}
body.narrow .group h3{flex:none;width:6.5em;margin:0}
body.narrow .group .items{flex:1;min-width:0;display:flex;flex-wrap:wrap;gap:2px 20px;align-items:baseline}
body.narrow .group .doc,body.narrow .group .hit{flex-basis:100%;margin:0}
body.narrow .item .k{width:auto}
#map{position:relative;height:10px;margin:8px 10px 6px;cursor:pointer;background:var(--vscode-editorWidget-background,transparent);outline:1px solid var(--vscode-panel-border)}
#map[hidden]{display:none}
#map .seg{position:absolute;top:0;bottom:0}
#map .ram{background:var(--vscode-charts-blue,#3794ff)}
#map .rom{background:var(--vscode-charts-purple,#b180d7)}
#map .io{background:var(--vscode-charts-orange,#d18616)}
#map .video{background:var(--vscode-charts-green,#89d185)}
#map .none{background:transparent}
#map .off{opacity:.3}
#map .wo{background-image:repeating-linear-gradient(135deg,transparent 0 3px,var(--vscode-editor-background) 3px 6px)}
#map .edge{position:absolute;top:0;bottom:0;width:1px;background:var(--vscode-editor-background)}
#mapView{position:absolute;top:-3px;bottom:-3px;min-width:2px;box-sizing:border-box;border:1px solid var(--vscode-focusBorder);pointer-events:none}
#status{padding:3px 20px;border-top:1px solid var(--vscode-panel-border);background:var(--vscode-panel-background,var(--vscode-editor-background));font-size:12px;color:var(--vscode-descriptionForeground);min-height:16px}
#status.error{color:var(--vscode-errorForeground)}
.tip{position:fixed;z-index:20;max-width:420px;padding:4px 8px;border-radius:3px;font-family:var(--vscode-font-family);font-size:var(--vscode-font-size);line-height:1.4;white-space:pre-line;pointer-events:none;color:var(--vscode-editorHoverWidget-foreground,var(--vscode-foreground));background:var(--vscode-editorHoverWidget-background,var(--vscode-editorWidget-background));border:1px solid var(--vscode-editorHoverWidget-border,var(--vscode-panel-border));box-shadow:0 2px 8px var(--vscode-widget-shadow,rgba(0,0,0,.36))}
.ended{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;background:color-mix(in srgb,var(--vscode-editor-background) 80%,transparent);font-size:14px}
</style></head>
<body>
<div class="bar" role="toolbar" aria-label="Memory">
<button id="back" class="action codicon codicon-arrow-left" disabled aria-label="Back" title="Back to where the view was before a go-to (Alt+Left, or the mouse's back button)"></button>
<button id="forward" class="action codicon codicon-arrow-right" disabled aria-label="Forward" title="Forward again (Alt+Right, or the mouse's forward button)"></button>
<div class="box" title="An address, label or expression, such as $0400, TEXT_PAGE or HL+2 (Ctrl+G)"><input id="goto" aria-label="Go to address" placeholder="Go to address or expression">
<button id="follow" class="action codicon codicon-eye" aria-pressed="false" aria-label="Follow" title="Follow: go to the Go to expression again at each stop, such as PC, S+$100 or [$06].w"></button></div>
<div class="box" title="Hex bytes with ?? for any byte, such as A9 ?? 20; text in quotes; a number after =, such as =1000 or =-2.5, as a byte, a word either way round or the BASIC's float; or an instruction, with ? for any character and * for any run, such as STA $C0?? or JSR COUT (Ctrl+F)"><input id="find" aria-label="Find" placeholder="Find bytes, &quot;text&quot;, =number or instruction">
<button id="findPrevious" class="action codicon codicon-arrow-up" aria-label="Find previous" title="Previous match (Shift+Enter, Shift+F3)"></button>
<button id="findNext" class="action codicon codicon-arrow-down" aria-label="Find next" title="Next match (Enter, F3)"></button></div>
<span class="spacer"></span>
<select id="space" aria-label="Memory space" title="Which memory this editor shows: memory as the CPU maps it now, or one bank on its own, whether the CPU sees it now or not" hidden></select>
<div class="box compare"><select id="compareWith" aria-label="Compare with" title="What the highlighted bytes differ from: what they held at the stop before, the snapshot, or another bank's bytes at the same addresses"><option value="">Changed since the last stop</option></select>
<button id="highlight" class="action codicon codicon-diff" aria-pressed="true" aria-label="Highlight differences" title="Highlight the bytes that differ from what the list names"></button></div>
<button id="snapshot" class="action codicon codicon-device-camera" aria-label="Snapshot" title="Snapshot: keep a copy of every byte now, to compare with"></button>
<button id="bookmarks" class="action codicon codicon-bookmark" aria-label="Bookmarks" title="Bookmarks: go to one, or remove one; the Mark menu in the inspector adds one"></button>
</div>
<div id="map" hidden aria-hidden="true"></div>
<div class="main"><div id="bytes"><div id="head"></div><div id="grid" tabindex="0" role="grid" aria-label="Memory bytes"><div id="spacer"></div><div id="rows"></div></div><div id="strips"></div></div>
<div id="listingPane"><div id="listingHead"><button class="heading" data-fold="listing" aria-label="Collapse the Disassembly column" title="The bytes as instructions and data, with labels, source lines and breakpoints. Click to collapse the column.">Disassembly</button></div>
<div id="listing" role="list" aria-label="Disassembly"></div>
<button class="strip cw" data-fold="listing" title="Expand the Disassembly column" hidden><span class="codicon codicon-triangle-down"></span>Disassembly<span class="codicon codicon-triangle-down"></span></button></div>
<div id="sash" role="separator" aria-label="Resize the inspector" tabindex="0"></div>
<div id="side"><div class="tabs"><div class="tablist" role="tablist"><button role="tab" data-tab="inspector" class="on">Inspector</button><button role="tab" data-tab="search">RAM search</button><button role="tab" data-tab="frozen" id="frozenTab">Frozen</button></div><span class="docks" id="docks"></span></div>
<div id="inspector" class="panel" aria-live="polite"></div><div id="actionMenu" class="menu" role="menu" hidden></div><div id="search" class="panel" hidden></div><div id="frozen" class="panel" hidden></div></div></div>
<div id="status" role="status"></div>
<div class="tip" id="tip" role="tooltip" hidden></div>
<div class="ended" id="ended" hidden>The debug session ended.</div>
<script nonce="${nonce}">
${pageFunctions.map(fn => fn.toString()).join("\n")}
const copyFormats = ${JSON.stringify(copyFormats)};
const vscode = acquireVsCodeApi();
const SIZE = 0x10000, ROW = 16, ROWS = SIZE / ROW, LINE = 20, PAGE = 256;
const bytes = new Uint8Array(SIZE);
// 0 not read yet, 1 readable, 2 unreadable.
const readable = new Uint8Array(SIZE);
// 0 to read, 1 read and current, 2 being read.
const pages = new Uint8Array(SIZE / PAGE);
const grid = document.getElementById("grid"), rows = document.getElementById("rows"), inspector = document.getElementById("inspector");
const head = document.getElementById("head"), actionMenu = document.getElementById("actionMenu");
const bytesPane = document.getElementById("bytes"), sash = document.getElementById("sash");
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
// The bytes of each label on data, 1 and 2 by turns so that one table next to another shows where it starts.
let labelData = new Uint8Array(SIZE);
// The machine's character set as the debugger gave it, whether the text column uses it (the page remembers), and the set in effect.
let machineSet = null, machineText = true, charset = null, glyphStyle = null, flashTimer = null;
// The machine's characters, one small canvas per code in each phase of flashing, and a text cell's width in pixels.
let glyphImages = [], flashImages = [], glyphCell = 0;
// Whether rows start where labels do; then each row's first address, else every row is ROW bytes from a multiple of ROW.
let aligned = false, rowStarts = null;
// Whether the grid highlights the bytes that differ from what Compare with names, and marks the bytes labels start at.
let highlight = true, labelMarks = true;
// Where the inspector is, beside the bytes or under them, and its sizes there, which the splitter sets.
let dock = "right", sideWidth = 360, sideHeight = 220;
// Whether the listing shows (the page remembers), the lines it shows, which request they answer, its width, and the
// addresses Decode from here started an instruction at.
let showListing = true, listingLines = [], listingKey = "";
// The columns collapsed into vertical strips, which a click on their heading or strip toggles.
let folded = { label: false, bytes: false, text: false, listing: false };
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
    if (saved && saved.folded && typeof saved.folded === "object") folded = { ...folded, ...saved.folded };
    if (folded.bytes && folded.text) folded.text = false;
    if (saved && (saved.dock === "right" || saved.dock === "bottom")) dock = saved.dock;
    if (saved && typeof saved.sideWidth === "number") sideWidth = saved.sideWidth;
    if (saved && typeof saved.sideHeight === "number") sideHeight = saved.sideHeight;
    showListing = !folded.listing;
    if (saved && typeof saved.machineText === "boolean") machineText = saved.machineText;
    if (saved && typeof saved.aligned === "boolean") aligned = saved.aligned;
    if (saved && typeof saved.highlight === "boolean") highlight = saved.highlight;
    if (saved && typeof saved.labelMarks === "boolean") labelMarks = saved.labelMarks;
} catch {
    // A page without saved state uses the machine's characters, in rows of ROW bytes.
}

// Remembers the page's choices, which are conveniences.
function remember() {
    try {
        vscode.setState({ machineText, aligned, showListing, following, highlight, labelMarks, folded, dock, sideWidth, sideHeight });
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
// Puts the machine's characters in effect, or ASCII, as the Text heading's toggle says; the toggle shows when
// there is a set.
function applyText() {
    charset = machineText ? machineSet : null;
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
const listingPanel = document.getElementById("listing"), listingPane = document.getElementById("listingPane");
const strips = document.getElementById("strips");
listingPane.classList.toggle("folded", folded.listing);
for (const strip of listingPane.querySelectorAll ? listingPane.querySelectorAll(".strip") : []) strip.hidden = !folded.listing;
const side = document.getElementById("side"), searchPanel = document.getElementById("search"), frozenPanel = document.getElementById("frozen");
const compareSelect = document.getElementById("compareWith");
let tab = "inspector";
let info = { bank: null, label: "", readOnly: false, bigEndian: false };
let cursor = 0, anchor = 0, pane = visiblePane("hex"), nibble = null, ended = false, dragging = false, generation = 0;

// The column the cursor edits: the one asked for, unless it is collapsed and the other shows.
function visiblePane(wanted) {
    if (folded.bytes && !folded.text) return "text";
    if (folded.text && !folded.bytes) return "hex";
    return wanted;
}
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
        labelData = new Uint8Array(SIZE);
        let turn = 1;
        for (const label of labels) {
            if (!(label.size > 0)) continue;
            labelData.fill(turn, label.address, Math.min(SIZE, label.address + label.size));
            turn = 3 - turn;
        }
        const crowded = labels.some((label, index) => index > 0 && Math.floor(labels[index - 1].address / ROW) === Math.floor(label.address / ROW));
        labelWidth = labels.length === 0 ? 0 : Math.max(10, Math.min(16, labels.reduce((widest, label) => Math.max(widest, label.name.length), 0)) + (crowded ? 4 : 0));
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
        // In a bank's view: bright where the CPU reads the bank now, striped where it only writes it, dim where neither.
        const access = area.mapped ? "" : area.written ? " wo" : " off";
        html += '<div class="seg ' + area.kind + access + '" style="left:' + percent(area.start) + ";width:" + percent(area.length) + '"></div>';
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

// The bar's hover follows the mouse along it, saying what is at the address under it.
mapBar.addEventListener("mousemove", event => {
    setTip(mapBar, mapTitle(mapAddress(event)));
    // Its text is first known here, after the mouse came over it, so its tip starts here too.
    if (tipFor !== mapBar) startTip(mapBar);
    if (tipFor === mapBar && !tip.hidden) {
        tip.textContent = mapBar.dataset.tip;
        tip.style.left = Math.max(4, Math.min(event.clientX, window.innerWidth - tip.offsetWidth - 4)) + "px";
    }
});
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
    const image = (data, code) => {
        const canvas = document.createElement("canvas");
        canvas.width = width;
        canvas.height = height;
        const context = canvas.getContext("2d");
        context.fillStyle = ink;
        for (let line = 0; line < height; line++) {
            for (let pixel = 0; pixel < width; pixel++) {
                if (data[code * height + line] & (0x80 >> pixel)) context.fillRect(pixel, line, 1, 1);
            }
        }
        return canvas;
    };
    glyphCell = Math.round(width * GLYPH / height);
    const css = ".txt.g span{width:" + glyphCell + "px}";
    let flashing = false;
    glyphImages = [];
    flashImages = [];
    for (let code = 0; code < 256; code++) {
        glyphImages.push(image(glyphs, code));
        flashImages.push(null);
        if (flashed === null) continue;
        const rows = flashed.subarray(code * height, (code + 1) * height);
        if (rows.every((row, line) => row === glyphs[code * height + line])) continue;
        flashImages[code] = image(flashed, code);
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
    if (flashing && flashTimer === null) {
        flashTimer = setInterval(() => {
            document.body.classList.toggle("flash");
            paintGlyphs();
        }, 270);
    }
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
    const codes = [];
    for (let index = 0; index < ROW; index++) {
        const offset = base + index;
        let classes = index === 8 ? "mid" : "";
        // A row aligned to a label leaves the columns before it, and after the next, empty.
        if (offset < start || offset > end) {
            hexPart += '<span class="' + classes + '"> </span>';
            textPart += "<span> </span>";
            codes.push(-1);
            continue;
        }
        if (labelData[offset] !== 0) classes += labelData[offset] === 1 ? " dt" : " dt2";
        if (low !== high && offset >= low && offset <= high) classes += " sel";
        if (highlight && readable[offset] === 1 && differs(offset)) classes += " chg";
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
        const drawn = / k([0-9]+)/.exec(textClasses);
        codes.push(drawn === null ? -1 : Number(drawn[1]));
    }
    let gutter = "";
    if (labelWidth > 0) {
        // The first label starting in the row, dimmed where it starts after the row's first byte, and how many more
        // start in it, which its tooltip lists.
        const starting = [];
        for (let offset = start; offset <= end; offset++) {
            if (labelAt.has(offset)) starting.push(offset);
        }
        if (starting.length === 0) {
            gutter = '<span class="lab" style="width:' + labelWidth + 'ch"></span>';
        } else {
            const first = starting[0], name = labelAt.get(first);
            const tip = starting.map(labelTip).join("&#10;") + "&#10;Click to go to " + where(first) + ".";
            const shown = starting.length === 1 ? escapeText(name)
                : '<span class="nm">' + escapeText(name) + '</span><span class="more" aria-label="' + (starting.length - 1) + ' more labels">&#8943;' + (starting.length - 1) + "</span>";
            gutter = '<span class="lab' + (first > start ? " in" : "") + '" style="width:' + labelWidth + 'ch" data-a="' + first + '" title="'
                + tip + '">' + shown + "</span>";
        }
    }
    return '<div class="row"><span class="addr">' + hex(start, 4) + "</span>"
        + (labelWidth > 0 && folded.label ? '<span class="fold"></span>' : gutter)
        + (folded.bytes ? '<span class="fold"></span>' : '<span class="hex">' + hexPart + "</span>")
        + (folded.text ? '<span class="fold"></span>' : '<span class="txt' + (charset !== null ? " g" : "") + '">' + textPart
            + (charset !== null ? '<canvas class="glyphs" aria-hidden="true" data-codes="' + codes.join(",") + '"></canvas>' : "") + "</span>")
        + "</div>";
}

// A label's name, address, kind and, on data, how many bytes its data takes, for a tooltip.
function labelTip(offset) {
    const label = labels.find(item => item.address === offset);
    const kind = label && label.kind ? ", " + label.kind : "";
    const size = label && label.size > 0 ? ", " + label.size + (label.size === 1 ? " byte" : " bytes") : "";
    return escapeText(labelAt.get(offset)) + " at " + where(offset) + escapeText(kind) + size;
}

// The column headings over the bytes, which name what each column is; they follow the bytes' horizontal scroll.
let headHtml = "";
function renderHead() {
    const offsets = [];
    for (let index = 0; index < ROW; index++) {
        offsets.push('<span class="' + (index === 8 ? "mid" : "") + '" title="The byte at offset ' + hex(index, 2) + ' in each row. Click to collapse the Bytes column.">' + hex(index, 2) + "</span>");
    }
    const toggle = (name, on, icon, title) => '<button class="tog codicon codicon-' + icon + '" data-toggle="' + name + '" aria-pressed="' + on + '" aria-label="' + title.split(":")[0] + '" title="' + title + '"></button>';
    const strip = name => '<span class="fold" data-strip="' + name + '"></span>';
    const html = '<div class="row"><span class="addr" title="The address of each row&#39;s first byte">Addr</span>'
        + (labelWidth === 0 ? "" : folded.label ? strip("label")
            : '<span class="lab" style="width:' + labelWidth + 'ch"><button class="heading" data-fold="label" aria-label="Collapse the Label column" title="The first label starting in each row: bright where it starts the row, dimmed where it starts later in it, with a count where more start there. Its tooltip says what each names: a routine or code, data, or a named address. A corner marks each label&#39;s byte, and the bytes of a label on data are shaded; hover a name to see its byte, and click it to go there. Click the heading to collapse the column.">Label</button>'
            + toggle("align", aligned, "list-tree", "Align to labels: start a row at each label, so a label&#39;s bytes begin a row of their own")
            + toggle("marks", labelMarks, "tag", "Label marks: mark the byte each label starts at with a corner") + "</span>")
        + (folded.bytes ? strip("bytes") : '<button class="hex heading" data-fold="bytes" aria-label="Collapse the Bytes column">' + offsets.join("") + "</button>")
        + (folded.text ? strip("text") : '<span class="txt"><button class="heading" data-fold="text" aria-label="Collapse the Text column" title="The bytes as text. Click to collapse the column.">Text</button>'
            + (machineSet === null ? "" : toggle("ascii", !machineText, "symbol-key", "ASCII: show the text as ASCII instead of the machine&#39;s own characters")) + "</span>") + "</div>";
    if (html !== headHtml) {
        headHtml = html;
        head.innerHTML = html;
    }
    head.style.transform = "translateX(" + (-grid.scrollLeft) + "px)";
    placeStrips();
}

// The collapsed columns' strips, over the room their headings and rows leave, from the top of the headings to the
// bottom of the bytes, each its name between two triangles, turned to read upward.
const stripNames = { label: "Label", bytes: "Bytes", text: "Text" };
let stripsHtml = "";
function placeStrips() {
    if (!head.querySelectorAll) return;
    let html = "";
    for (const room of head.querySelectorAll("[data-strip]")) {
        const name = room.dataset.strip;
        html += '<button class="strip ccw" data-fold="' + name + '" title="Expand the ' + stripNames[name] + ' column" style="left:' + (room.offsetLeft - grid.scrollLeft) + 'px">'
            + '<span class="codicon codicon-triangle-down"></span>' + stripNames[name] + '<span class="codicon codicon-triangle-down"></span></button>';
    }
    if (html !== stripsHtml) {
        stripsHtml = html;
        strips.innerHTML = html;
    }
}

// Draws each row's machine characters on its canvas at the screen's own pixels, each glyph filling its cell to the
// pixel, so neighbors meet without the seams that images scaled into cells leave at fractional display scales.
function paintGlyphs() {
    if (charset === null || glyphImages.length === 0 || !rows.querySelectorAll) return;
    const scale = window.devicePixelRatio || 1;
    const flashing = document.body.classList.contains("flash");
    for (const canvas of rows.querySelectorAll("canvas.glyphs")) {
        const codes = canvas.dataset.codes.split(",").map(Number);
        canvas.style.width = codes.length * glyphCell + "px";
        canvas.width = Math.round(codes.length * glyphCell * scale);
        canvas.height = Math.round(GLYPH * scale);
        const context = canvas.getContext("2d");
        context.imageSmoothingEnabled = false;
        codes.forEach((code, index) => {
            if (code < 0) return;
            const image = flashing && flashImages[code] !== null ? flashImages[code] : glyphImages[code];
            const left = Math.round(index * glyphCell * scale), right = Math.round((index + 1) * glyphCell * scale);
            context.drawImage(image, left, 0, right - left, canvas.height);
        });
    }
}

function render() {
    renderHead();
    const top = Math.floor(grid.scrollTop / LINE);
    const count = visibleRows() + 2;
    let html = "";
    for (let row = top; row < Math.min(rowCount(), top + count); row++) html += rowHtml(row);
    rows.style.transform = "translateY(" + (top * LINE) + "px)";
    rows.innerHTML = html;
    paintGlyphs();
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
    if (!showListing || ended || cramped) return;
    const top = Math.min(Math.floor(grid.scrollTop / LINE), rowCount() - 1);
    const start = rowStart(top), end = rowEnd(Math.min(rowCount() - 1, top + visibleRows() + 1));
    const key = start + ":" + end + ":" + generation + ":" + writes + ":" + marks + ":" + breakpointChanges + ":" + labels.length + ":" + forcedStarts.size;
    if (key === listingKey) return;
    listingKey = key;
    if (!listingBusy) void loadListing(start, Math.min(0x1000, end - start + 1), key);
}

let listingBusy = false;
async function loadListing(start, count, key) {
    listingBusy = true;
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
    } finally {
        listingBusy = false;
        if (key !== listingKey) {
            listingKey = "";
            wantListing();
        }
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
        html += '<div class="' + classes + '" role="listitem" aria-keyshortcuts="F9 F2"' + (line.guess ? ' title="A guess: no source describes these bytes, and analysis takes them for ' + line.kind + '"' : "") + ' tabindex="' + (index === stop ? 0 : -1) + '" data-a="' + line.address + '" data-s="' + line.size + '">' + breakpointHtml(line) + '<span class="a">' + hex(line.address, 4) + "</span>"
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
function listingShown() { return showListing && !ended && !cramped; }
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

// Assembling in place: F2, Assemble in the inspector or a double-click on a listing line asks for an instruction to
// type over the line, as the Monitor's mini-assembler takes one, which the debugger assembles with the session's
// labels. A shorter instruction leaves the rest of the old one, or pads it with NOPs, as the user says; a longer one
// says what it overwrites first. The write is one edit, which undo takes back.
async function assembleAtCursor() {
    const shown = listingShown();
    const current = listingCurrent();
    const line = current ? listingLines.find(item => cursor >= item.address && cursor < item.address + item.size) : undefined;
    if (line === undefined) {
        status(!shown ? "Show the listing to assemble an instruction." : !current ? "The listing is being read; press F2 again." : "No listing line is at the cursor.", true);
        return;
    }
    await assembleLine(line);
}

async function assembleLine(line) {
    // Only the listing as last read says how long the line is and what follows it; it may change while the user
    // types, as at a stop or a write, so it is checked again before writing.
    if (!listingCurrent()) { status(!listingShown() ? "Show the listing to assemble an instruction." : "The listing is being read; press F2 again.", true); return; }
    const key = listingKey;
    const problem = writeProblem(line.address, 1);
    if (problem !== null) { status(problem, true); return; }
    let result;
    try {
        result = await request({ type: "assemble", address: line.address, text: line.kind === "data" ? "" : line.text });
    } catch (error) {
        status(String(error.message || error), true);
        return;
    }
    if (!result || result.cancelled) return;
    // The line's own text, accepted as it was, leaves its bytes alone: assembled again it may take another
    // encoding, as LDA $0024 written with an absolute address assembles to zero page.
    // The mnemonic in any case, and its spacing, but the operand as spelled, as names are case-sensitive.
    const same = text => {
        const parts = String(text ?? "").split(" ").join(String.fromCharCode(9)).split(String.fromCharCode(9)).filter(part => part !== "");
        return parts.length === 0 ? "" : [parts[0].toUpperCase(), ...parts.slice(1)].join(" ");
    };
    if (line.kind !== "data" && same(result.line) === same(line.text)) {
        status(line.text + " is unchanged.");
        return;
    }
    const values = Array.from(result.bytes);
    const typed = result.text ?? result.line;
    const end = line.address + values.length;
    if (end > SIZE) { status(typed + " runs past " + where(SIZE - 1) + ".", true); return; }
    const sized = count => count + (count === 1 ? " byte" : " bytes");
    if (values.length < line.size) {
        const left = line.size - values.length;
        const answer = await request({
            type: "confirm",
            message: typed + " is " + sized(values.length) + ", " + left + " fewer than " + line.text + ". Pad the rest with NOP?",
            actions: ["Pad with NOP", "Leave the rest"]
        });
        if (!answer || !answer.choice) return;
        if (answer.choice === "Pad with NOP") {
            const nop = Array.from(result.nop ?? []);
            while (nop.length > 0 && values.length + nop.length <= line.size) values.push(...nop);
            if (values.length < line.size) {
                status("A NOP does not fit the " + sized(line.size - values.length) + " left; they are left as they were.", true);
            }
        }
    } else if (values.length > line.size) {
        // What the longer instruction writes over: the lines after, as listed, and any bytes past the listing.
        const covered = listingLines.filter(item => item.address > line.address && item.address < end);
        const named = covered.map(item => item.text + " at " + where(item.address) + (item.address + item.size > end ? " (in part)" : ""));
        const listedTo = covered.length === 0 ? line.address + line.size : covered[covered.length - 1].address + covered[covered.length - 1].size;
        if (listedTo < end) named.push(where(listedTo) + "-" + where(end - 1));
        const answer = await request({
            type: "confirm",
            message: typed + " is " + sized(values.length) + ", " + (values.length - line.size) + " more than " + line.text + ": it overwrites " + named.join(", ") + ".",
            actions: ["Write"]
        });
        if (!answer || answer.choice !== "Write") return;
    }
    if (listingKey !== key || !listingCurrent()) {
        status("The listing changed while you typed; press F2 again.", true);
        return;
    }
    // In turn with typing, undo and redo, so the write is on the undo stack before either can run.
    let written = false;
    await new Promise(resolve => queue(async () => {
        // An edit or undo before it in the queue, or a stop while the bytes are read, may change the listing while
        // it waits; the write is checked again after each wait, up to sending it.
        const current = () => listingKey === key && listingCurrent();
        if (current()) written = await write(line.address, values, true, current);
        if (!written && !current()) status("The listing changed while you typed; press F2 again.", true);
        resolve(undefined);
    }));
    if (written) status("Assembled " + typed + " at " + where(line.address) + ".");
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

// A double-click on a line types over it. Its first click selected the line and drew the listing again, so the
// element under the pointer may be new, or the event may come to the listing itself: the cursor's line is the one.
listingPanel.addEventListener("dblclick", event => {
    const target = event.target;
    if (target && target.closest && (target.closest("[data-go]") || target.closest("[data-src]") || target.closest("[data-bp]"))) return;
    void assembleAtCursor();
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
    } else if (event.key === "F2") {
        const listed = listingLines.find(item => item.address === Number(line.dataset.a));
        if (listed !== undefined) void assembleLine(listed);
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
    let html = '<option value="">Changed since the last stop</option>';
    if (snapshot !== null) html += '<option value="snapshot">the snapshot</option>';
    for (const bank of otherBanks) html += '<option value="' + escapeText(bank.memoryReference) + '">' + escapeText(bank.label) + "</option>";
    compareSelect.innerHTML = html;
    compareSelect.value = comparison;
}

// Asks for the other banks, which a card going in or out changes; a bank compared with that has gone is no longer.
async function loadBanks() {
    let spaces = [];
    try {
        const result = await request({ type: "banks" });
        otherBanks = result.banks;
        spaces = result.spaces ?? [];
    } catch {
        otherBanks = [];
    }
    // The spaces this editor can show instead, where the machine has more than one.
    spaceSelect.innerHTML = spaces.map(space => '<option value="' + escapeText(space.name ?? "") + '"' + ((space.name ?? null) === info.bank ? " selected" : "") + ">"
        + escapeText(space.label) + "</option>").join("");
    spaceSelect.hidden = spaces.length < 2;
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
    freeze: "Freeze: keep these bytes at their values now while the machine runs, as for a game's lives. A write the "
        + "program makes to one is undone as its instruction ends, so the program never reads its own value there. "
        + "Typing a new value changes what they are held at; the Frozen tab lists them, and Thaw lets them go.",
    thaw: "Thaw: let the program change these bytes again."
};

// The actions on the selection, by what they are for: the ones used most while debugging as buttons, and the rest
// in menus, Mark, Edit and Export, which the bytes' right-click menu lists after them.
function actions() {
    const low = Math.min(cursor, anchor), high = Math.max(cursor, anchor);
    const allFrozen = range(low, high).every(offset => frozen.has(offset));
    const count = high > low ? " " + (high - low + 1) + " bytes" : "";
    const watchTitle = "Add to VS Code's Watch view as " + watchExpressions(low, high).join(", ");
    const main = [
        { act: "watch", label: high === low + 1 ? "Watch word" : "Watch" + count, title: watchTitle },
        { act: "freeze", label: (allFrozen ? "Thaw" : "Freeze") + count, title: allFrozen ? freezeTitle.thaw : freezeTitle.freeze },
        { act: "name", label: "Name", title: "Name this address, kept in the hints file" },
        { act: "comment", label: "Comment", title: "Comment on this address, kept in the hints file" }
    ];
    const menus = {
        mark: { label: "Mark", items: [
            { act: "markCode", label: "Mark code", title: "Mark code as starting here, kept in the hints file" },
            { act: "markData", label: "Mark data" + count, title: "Mark the selection as data, kept in the hints file" },
            showListing ? { act: "decode", label: "Decode from here", title: "Start an instruction at the cursor in the listing, where it decodes from the wrong byte (Ctrl+D)" } : null,
            { act: "unmark", label: "Unmark", title: "Take the code and data marks off the selection" },
            { act: "bookmark", label: "Bookmark", title: bookmarkAt.has(cursor) ? "Rename or remove this bookmark" : "Bookmark this address with a name, kept for this launch configuration" }
        ].filter(entry => entry !== null) },
        edit: { label: "Edit", items: [
            showListing ? { act: "assemble", label: "Assemble", title: "Type an instruction over the listing line at the cursor, which is assembled and written (F2)" } : null,
            { act: "fill", label: "Fill" + count, title: "Fill the selection with a byte, bytes or text, repeated" },
            { act: "load", label: "Load", title: "Load a binary at the cursor, or Intel HEX at its addresses" }
        ].filter(entry => entry !== null) },
        export: { label: "Export", items: [
            { act: "copyAs", label: "Copy as", title: "Copy the selection as Monitor lines, .byte lines, BASIC DATA, a C array or base64" },
            { act: "save", label: "Save" + count, title: "Save the selection as a binary, Intel HEX or native assembly" }
        ] }
    };
    return { main, menus };
}

function actionButton(entry, menu) {
    return "<button " + (menu ? 'role="menuitem" ' : "") + 'data-act="' + entry.act + '" title="' + escapeText(entry.title) + '">' + escapeText(entry.label) + "</button>";
}

function menuHtml(entries) {
    return entries.map(entry => entry === null ? '<div class="sep" role="separator"></div>' : actionButton(entry, true)).join("");
}

// Whether the number section shows the word in both byte orders.
let bothOrders = false;

function group(name, body) {
    return body === "" ? "" : '<section class="group" aria-label="' + name + '"><h3>' + name + '</h3><div class="items">' + body + "</div></section>";
}

function line(html) {
    return '<div class="line">' + html + "</div>";
}

// A value that can be written, as a button that asks for a new one; what it is shows on hover.
function valueButton(label, value) {
    return '<button class="link" data-edit="' + escapeText(label) + '" title="' + escapeText(label) + ": click to write a new value at " + where(cursor) + '">' + escapeText(value) + "</button>";
}

function showInspector() {
    const low = Math.min(cursor, anchor), high = Math.max(cursor, anchor);
    const { main, menus } = actions();
    let html = '<div class="acts">' + main.map(entry => actionButton(entry, false)).join("") + '<span class="gap"></span>'
        + Object.entries(menus).map(([key, menu]) => '<button data-act="menu" data-menu="' + key + '" aria-haspopup="menu" title="' + menu.items.map(entry => entry.label).join(", ") + '">'
            + menu.label + " &#9662;</button>").join("") + "</div>";
    html += group("Where", whereHtml(low, high));
    html += group("Value", valueHtml());
    html += group("Code", codeHtml());
    html += group("Used by", usedByHtml());
    html += group("As a number", numberHtml());
    inspector.innerHTML = html;
}

// What a label's kind means to a reader: an equate naming RAM is a named address.
function kindText(label) {
    if (label === undefined || !label.kind) return "";
    const kind = label.kind === "constant" ? "named address" : label.kind;
    return label.size > 0 ? kind + ", " + label.size + (label.size === 1 ? " byte" : " bytes") : kind;
}

// The address and its name, what kind of name, the selection, where in the machine it is and what the memory map does
// there, the label it is inside with its documentation, and the source line that made it.
function whereHtml(low, high) {
    const known = inspected !== null && inspected.address === cursor ? inspected : null;
    let html = '<div class="where">' + where(cursor);
    const name = labelOf(labels, cursor);
    if (name !== undefined) html += "  " + escapeText(name);
    const kind = kindText(labels.find(entry => entry.address === cursor));
    if (kind !== "") html += ' <span class="meta">' + escapeText(kind) + "</span>";
    if (high > low) html += ' <span class="meta">· selected ' + (high - low + 1) + " bytes, " + where(low) + "-$" + hex(high, 4) + "</span>";
    html += "</div>";
    if (known === null) return html;
    if (known.label && known.offset > 0) html += line('<span class="meta">Inside</span> ' + escapeText(known.label + "+" + known.offset));
    if (known.region) html += line('<span class="meta">In</span> ' + escapeText(known.region + (known.detail ? ", " + known.detail : "")));
    if (known.mapped) html += line(escapeText(known.mapped));
    if (known.summary) html += '<div class="doc">' + escapeText((known.offset > 0 ? known.label + ": " : "") + known.summary) + "</div>";
    if (known.path) {
        html += line('<span class="meta">From</span> <button class="link" data-src="' + escapeText(known.path) + '" data-line="' + known.line + '" title="Open ' + escapeText(known.path) + ", line " + known.line + '">'
            + escapeText(fileName(known.path) + ":" + known.line) + "</button>");
    }
    return html;
}

// The byte as hex, unsigned, signed and binary, each written when clicked; its character, where it is one; how it
// differs from a snapshot or the last stop; whether it is frozen or cannot be written; and the bits its documentation
// names.
function valueHtml() {
    const rows = inspect(bytes, readable, cursor, charset === null ? undefined : charset.text);
    const byRow = new Map(rows.map(row => [row.label, row.value]));
    let html;
    if (readable[cursor] !== 1) {
        html = line("Unreadable here");
    } else {
        html = '<div class="line values">' + byteRows.map(label => valueButton(label, byRow.get(label))).join("");
        const text = byRow.get("Text");
        if (text !== undefined && text !== "none" && text !== "graphics") html += ' <span class="meta">shows</span> ' + escapeText(text);
        html += "</div>";
    }
    if (comparison !== "" && differs(cursor)) html += line('<span class="meta">Was</span> $' + hex(compared().bytes[cursor], 2) + ' <span class="meta">' + (comparison === "snapshot" ? "in the snapshot" : "in " + escapeText(comparedName())) + "</span>");
    else if (readable[cursor] === 1 && changed[cursor]) html += line('<span class="meta">Was</span> $' + hex(was[cursor], 2) + ' <span class="meta">at the last stop</span>');
    if (frozen.has(cursor)) html += line('<span class="meta">Frozen at</span> $' + hex(frozen.get(cursor), 2));
    if (readable[cursor] === 1 && readOnly[cursor]) html += line('<span class="meta">Not RAM now, so writes are refused</span>');
    const known = inspected !== null && inspected.address === cursor ? inspected : null;
    for (const bit of known === null ? [] : known.bits ?? []) {
        const value = readable[cursor] === 1 ? String((bytes[cursor] >> bit.bit) & 1) : "?";
        html += line('<span class="meta">Bit ' + bit.bit + (bit.name ? " " + escapeText(bit.name) : "") + "</span> " + value + ' <span class="meta">' + escapeText(bit.meaning) + "</span>");
    }
    return html;
}

// The instruction starting at the cursor, where code is known to start: its size, cycles and the flags it changes,
// and what it does.
function codeHtml() {
    const known = inspected !== null && inspected.address === cursor ? inspected : null;
    const instruction = known === null ? null : known.instruction;
    if (!instruction) return "";
    const facts = [instruction.size + (instruction.size === 1 ? " byte" : " bytes")];
    if (typeof instruction.cycles === "number") {
        facts.push(instruction.cycles + " cycles" + (typeof instruction.cyclesTaken === "number" ? ", " + instruction.cyclesTaken + " taken" : ""));
    }
    if (instruction.flags) facts.push(instruction.flags === "none" ? "leaves the flags alone" : "changes " + instruction.flags);
    let html = line('<span class="v">' + escapeText(instruction.text) + '</span> <span class="meta">' + escapeText(facts.join(" · ")) + "</span>");
    if (instruction.summary) html += '<div class="doc">' + escapeText(instruction.summary) + "</div>";
    return html;
}

// The instructions that read, write or jump to the address, each going there.
function usedByHtml() {
    const known = inspected !== null && inspected.address === cursor ? inspected : null;
    if (known === null || !(known.referenceCount > 0)) return "";
    let html = "";
    for (const reference of known.references) {
        // A button, so Tab reaches it and Enter or Space goes there.
        html += '<button class="hit ref" data-go="' + reference.address + '" title="' + escapeText(reference.kind) + " here; go to " + where(reference.address) + '"><span class="a">' + where(reference.address)
            + (reference.label ? " " + escapeText(reference.label) : "") + "</span><span>" + escapeText(reference.text ?? "") + "</span></button>";
    }
    if (known.referenceCount > known.references.length) html += '<div class="doc">and ' + (known.referenceCount - known.references.length) + " more</div>";
    return html;
}

// The word in the CPU's byte order, and the other with Both byte orders, and the BASIC's floats: none where an
// instruction starts, as its bytes are no number.
function numberHtml() {
    const known = inspected !== null && inspected.address === cursor ? inspected : null;
    if (readable[cursor] !== 1 || (known !== null && known.instruction)) return "";
    const rows = inspect(bytes, readable, cursor);
    const own = info.bigEndian ? "Word, high first" : "Word, low first", other = info.bigEndian ? "Word, low first" : "Word, high first";
    let html = "";
    for (const row of rows) {
        if (row.label !== own && !(bothOrders && row.label === other)) continue;
        const forms = row.value.split("  ");
        html += '<div class="line values"><span class="meta">' + (row.label === "Word, low first" ? "Word, low byte first" : "Word, high byte first") + "</span> "
            + forms.map((form, index) => index === 0 ? valueButton(row.label, form) : '<span class="plain">' + escapeText(form) + "</span>").join("") + "</div>";
    }
    if (html !== "") {
        html += '<button class="link order" data-act="orders" title="' + (bothOrders ? "Show the word in the CPU&#39;s byte order only" : "Show the word in the other byte order too") + '">'
            + (bothOrders ? "One byte order" : "Both byte orders") + "</button>";
    }
    for (const row of known === null ? [] : known.values ?? []) html += '<div class="line values"><span class="meta">' + escapeText(row.label) + "</span> " + valueButton(row.label, row.value) + "</div>";
    return html;
}

// A menu of actions at a place in the window, kept inside it: one of the inspector's, under its button, or the
// bytes' right-click menu, at the mouse, with every action on the selection, a group at a time.
function openMenu(which, x, y) {
    const { main, menus } = actions();
    const all = [...main.slice(0, 2), null, ...main.slice(2), ...menus.mark.items, null, ...menus.edit.items, null, ...menus.export.items];
    actionMenu.innerHTML = menuHtml(which === "all" ? all : menus[which].items);
    actionMenu.hidden = false;
    const width = actionMenu.offsetWidth || 0, height = actionMenu.offsetHeight || 0;
    const right = window.innerWidth || x + width, bottom = window.innerHeight || y + height;
    actionMenu.style.left = Math.max(0, Math.min(x, right - width)) + "px";
    actionMenu.style.top = Math.max(0, Math.min(y, bottom - height)) + "px";
    const first = actionMenu.querySelector ? actionMenu.querySelector("button") : null;
    if (first) first.focus();
}

function closeMenu() {
    actionMenu.hidden = true;
}

// What the debugger says about the cursor's address: its region and where in it, what the memory map does with it,
// the label it is in with its documentation, and its source line. Asked for again when the cursor, memory, the
// marks or the stop change.
let inspected = null, inspectKey = "", inspectBusy = false;

function wantInspection() {
    if (ended) return;
    const key = cursor + ":" + generation + ":" + writes + ":" + marks + ":" + Array.from(forcedStarts).join(",");
    if (key === inspectKey) return;
    inspectKey = key;
    if (!inspectBusy) void loadInspection(cursor, key);
}

async function loadInspection(address, key) {
    inspectBusy = true;
    let result = null;
    try {
        result = await request({ type: "inspect", address, starts: Array.from(forcedStarts) });
    } catch {
        // The inspector shows what the page knows without it.
    } finally {
        inspectBusy = false;
        if (key !== inspectKey) {
            inspectKey = "";
            wantInspection();
        }
    }
    if (key !== inspectKey) return;
    inspected = result;
    showInspector();
}

// The narrowest the listing gets beside the bytes; narrower than that, it is left out until the editor is wider. And
// the inspector's sizes beside the bytes and under them, which the splitter sets.
const LISTING = 280, SASH = 4;
let narrow = null, cramped = false;

// Fits the bytes' column to its rows and gives the listing and inspector the rest, or docks the inspector under the
// bytes and the listing when they do not all fit, and leaves the listing out when even it does not fit beside the
// bytes. Returns whether that changed, which changes how many rows show.
function layout() {
    const first = rows.firstElementChild;
    if (!first || !document.body) return false;
    const content = first.offsetWidth + (grid.offsetWidth - grid.clientWidth);
    const width = document.body.clientWidth;
    const docked = dock === "bottom";
    // The bytes keep their width as the inspector grows, scrolling sideways when it takes the room; the listing
    // fills what is left.
    sideWidth = Math.max(200, Math.min(sideWidth, width - 160));
    sideHeight = Math.max(80, Math.min(sideHeight, (window.innerHeight || 600) - 160));
    side.style.width = docked ? "" : sideWidth + "px";
    side.style.height = docked ? sideHeight + "px" : "";
    const tight = showListing && width - content - (docked ? 0 : sideWidth + SASH) < LISTING;
    bytesPane.style.width = content + "px";
    grid.style.width = "100%";
    showDocks();
    if (docked === narrow && tight === cramped) return false;
    narrow = docked;
    cramped = tight;
    document.body.classList.toggle("narrow", docked);
    document.body.classList.toggle("cramped", tight);
    document.body.classList.toggle("nolist", !showListing || tight);
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

// still, when given, says whether what the write was decided from holds after reading the bytes, which waits.
async function write(offset, values, record, still) {
    // Undo puts back the bytes from before, so they must be what memory held.
    if (!await loaded(offset, values.length)) return false;
    if (still && !still()) return false;
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

// Writes an edit's bytes from before, to undo it, or after, to redo it; a group's pieces in turn, the last first
// when undoing.
async function rewrite(edit, undoing) {
    if (edit.group === undefined) return write(edit.offset, undoing ? edit.before : edit.after, false);
    const pieces = undoing ? edit.group.slice().reverse() : edit.group;
    for (const piece of pieces) {
        if (!await write(piece.offset, undoing ? piece.before : piece.after, false)) return false;
    }
    return true;
}

async function undo() {
    const edit = undoStack.pop();
    if (edit === undefined) { status("Nothing to undo."); return; }
    if (await rewrite(edit, true)) {
        redoStack.push(edit);
        moveTo(edit.offset, false, false, true);
    } else {
        undoStack.push(edit);
    }
}

async function redo() {
    const edit = redoStack.pop();
    if (edit === undefined) { status("Nothing to redo."); return; }
    if (await rewrite(edit, false)) {
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
    const docking = target.closest ? target.closest("[data-dock]") : null;
    if (docking !== null) { moveInspector(docking.dataset.dock); return; }
    const tabButton = target.closest ? target.closest("[data-tab]") : null;
    if (tabButton !== null) { showTab(tabButton.dataset.tab); return; }
    const action = target.closest ? target.closest("[data-act]") : null;
    if (action !== null) {
        const offset = Number(action.dataset.o);
        if (action.dataset.act === "menu") {
            const box = action.getBoundingClientRect ? action.getBoundingClientRect() : { left: 0, bottom: 0 };
            openMenu(action.dataset.menu, box.left, box.bottom + 2);
            return;
        }
        closeMenu();
        switch (action.dataset.act) {
            case "orders": bothOrders = !bothOrders; showInspector(); break;
            case "watch": queue(watchSelection); break;
            case "freeze": queue(toggleFreeze); break;
            case "decode": decodeHere(); break;
            case "assemble": void assembleAtCursor(); break;
            case "markCode": void mark({ kind: "code" }); break;
            case "markData": void mark({ kind: "data" }); break;
            case "unmark": void mark({ kind: "clear" }); break;
            case "name": void mark({ what: "name" }); break;
            case "comment": void mark({ what: "comment" }); break;
            case "bookmark": void addBookmark(); break;
            // The grid has the focus while the box is up and after, so keys and undo reach it.
            case "fill": grid.focus(); void fill(); break;
            case "copyAs": grid.focus(); void copySelectionAs(); break;
            case "save": grid.focus(); void saveSelection(); break;
            case "load": grid.focus(); void loadIntoMemory(); break;
            case "start": void startSearch(Number(document.getElementById("searchSize")?.value ?? 1)); break;
            case "reset": search = null; showSearch(); break;
            case "narrow": void narrowBy(action.dataset.test, document.getElementById("searchValue").value); break;
            case "back": backSearch(); break;
            case "watchHit": void watch([action.dataset.w ?? "[" + where(offset) + "]"]); break;
            case "thaw": void freeze([], [offset]).catch(error => status(String(error.message || error), true)); break;
        }
        return;
    }
    const edited = target.closest ? target.closest("[data-edit]") : null;
    if (edited !== null) { grid.focus(); void editValue(edited.dataset.edit); return; }
    const source = target.closest ? target.closest("[data-src]") : null;
    if (source !== null) {
        void request({ type: "open", path: source.dataset.src, line: Number(source.dataset.line) }).catch(error => status(String(error.message || error), true));
        return;
    }
    const hit = target.closest ? target.closest("[data-go]") : null;
    if (hit !== null) jump(Number(hit.dataset.go));
});
side.addEventListener("keydown", event => {
    // The menu moves through its actions with the arrow keys, and Escape closes it.
    if (!actionMenu.hidden && (event.key === "Escape" || event.key === "ArrowDown" || event.key === "ArrowUp")) {
        if (event.key === "Escape") {
            closeMenu();
            grid.focus();
        } else {
            const items = Array.from(actionMenu.querySelectorAll ? actionMenu.querySelectorAll("button") : []);
            const at = items.indexOf(document.activeElement);
            const next = items[(at + (event.key === "ArrowDown" ? 1 : items.length - 1)) % items.length];
            if (next) next.focus();
        }
        event.preventDefault();
        event.stopPropagation();
        return;
    }
    if (event.target.id === "searchValue" && event.key === "Enter") {
        void narrowBy("equal", event.target.value);
        event.preventDefault();
        event.stopPropagation();
    }
});
document.getElementById("snapshot").addEventListener("click", () => void takeSnapshot());
// The space list opens the space picked in this editor's place, at the cursor's address.
const spaceSelect = document.getElementById("space");
spaceSelect.addEventListener("change", () => {
    const bank = spaceSelect.value === "" ? null : spaceSelect.value;
    if (bank === info.bank) return;
    void request({ type: "switch", bank, address: cursor }).catch(error => status(String(error.message || error), true));
});
if (document.body) document.body.classList.toggle("nomarks", !labelMarks);
const highlightButton = document.getElementById("highlight");
highlightButton.ariaPressed = String(highlight);
highlightButton.addEventListener("click", () => {
    highlight = !highlight;
    highlightButton.ariaPressed = String(highlight);
    remember();
    render();
});
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
    followBox.ariaPressed = String(following !== "");
    setTip(followBox, following === ""
        ? "Follow: go to the Go to expression again at each stop, such as PC, S+$100 or [$06].w"
        : "Following " + following + ": the view goes there again at each stop. Click to stay put.");
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
        followBox.ariaPressed = "false";
        status("Type what to follow in Go to, such as PC, then turn on Follow.", true);
        gotoBox.focus();
        return Promise.resolve();
    }
    setFollowing(text);
    status("Following " + text + ".");
    return follow();
}

// Goes where the followed expression points now, as at a stop. Only the latest request's answer counts, as an
// earlier stop's is out of date, and a move made while the debugger answered, such as Back, wins over it.
let followAsked = 0;
async function follow() {
    const text = following, started = moves, asked = ++followAsked;
    if (text === "") return;
    try {
        const result = await request({ type: "goto", text });
        if (asked === followAsked && following === text && moves === started) jump(result.address);
    } catch (error) {
        if (asked === followAsked && following === text) status("Following " + text + ": " + String(error.message || error), true);
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
    // Matches only in memory as it is now: a read that fails says why, and finds nothing.
    if (!await loaded(0, SIZE)) return;
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
    // Matches only in memory as it is now: a read that fails says why, and finds nothing.
    if (!await loaded(0, SIZE)) return;
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
    // A match is a go-to, which Back returns from, and a move of the cursor, as an edit waiting on the debugger must know.
    jump(at);
    anchor = at + size - 1;
    render();
    status(message);
}

// Writing values: an inspector row's value typed anew, the selection filled with a pattern, or the clipboard pasted
// at the cursor. Each is one edit, which undo takes back, written in turn with typing, undo and redo.
const byteRows = ["Byte", "Unsigned", "Signed", "Binary"];

// Whether an inspector row's value can be typed anew: the byte's forms, the words and the BASIC's floats.
function editable(label) {
    return byteRows.includes(label) || label === "Word, low first" || label === "Word, high first"
        || (inspected !== null && inspected.address === cursor && (inspected.values ?? []).some(value => value.label === label));
}

// The bytes a row's value is written as, or why the text is not one.
async function valueBytes(label, text) {
    if (byteRows.includes(label)) {
        // The Binary row shows its bits in two groups, as %1010 1001, which it takes back.
        const value = parseByte(label === "Binary" ? text.split(" ").join("") : text);
        return typeof value === "string" ? value : [value];
    }
    if (label === "Word, low first" || label === "Word, high first") {
        const value = parseValue(text, 2);
        if (typeof value === "string") return value;
        return label === "Word, low first" ? [value & 0xFF, value >> 8] : [value >> 8, value & 0xFF];
    }
    // A float, encoded by the debugger from the text as typed.
    let result;
    try {
        result = await request({ type: "numbers", value: text.trim() });
    } catch (error) {
        return String(error.message || error);
    }
    const format = (result.formats ?? []).find(item => item.label === label);
    return format === undefined ? text.trim() + " is too large for " + label.toLowerCase() + "." : Array.from(format.bytes);
}

async function editValue(label) {
    const at = cursor;
    const row = inspect(bytes, readable, at, charset === null ? undefined : charset.text).concat(inspected !== null && inspected.address === at ? inspected.values ?? [] : [])
        .find(item => item.label === label);
    if (row === undefined) return;
    const shown = row.value.split("  ")[0];
    const answer = await request({ type: "input", title: label + " at " + where(at), prompt: "A new value, written to memory.", value: shown });
    if (!answer || answer.cancelled) return;
    // The value as shown, accepted as it was, writes nothing: a float shows rounded, so written again it may not be
    // the bytes it came from.
    if (answer.text.trim() === shown.trim()) { status(label + " at " + where(at) + " is unchanged."); return; }
    await inTurn(async () => {
        const values = await valueBytes(label, answer.text);
        if (typeof values === "string") { status(values, true); return; }
        if (at + values.length > SIZE) { status(label + " at " + where(at) + " runs past " + where(SIZE - 1) + ".", true); return; }
        if (await writeNow(at, values)) status(label + " at " + where(at) + " written.");
    });
}

// Runs an edit in turn with typing, undo and redo, from what it reads or asks for to its write, so that neither can
// run between them, and its write is on the undo stack before the next runs.
function inTurn(action) {
    return new Promise(resolve => queue(async () => {
        try {
            await action();
        } finally {
            resolve(undefined);
        }
    }));
}

// Writes as one edit, from within its turn. A hex digit typed and waiting for its second is dropped, so the next key
// starts a byte of its own.
async function writeNow(offset, values) {
    nibble = null;
    render();
    return write(offset, values, true);
}

// Bytes or text for a range: text is the machine's characters, each chosen to keep what it can of the byte it
// replaces, as typing does; or null and a message for a character the machine does not have.
function dataAt(data, offset, count) {
    if (Array.isArray(data)) return data;
    const values = [];
    const characters = Array.from(data.text);
    for (let index = 0; index < Math.min(count, characters.length); index++) {
        const old = bytes[offset + index];
        const value = charset === null ? typedText(characters[index], old) : typedText(characters[index], old, charset.text, charset.looksSame);
        if (value === undefined) { status("The machine has no " + characters[index] + " character.", true); return null; }
        values.push(value);
    }
    return values;
}

async function fill() {
    const low = Math.min(cursor, anchor), high = Math.max(cursor, anchor), count = high - low + 1;
    const span = where(low) + (count > 1 ? "-" + where(high) + " (" + count + " bytes)" : "");
    const answer = await request({ type: "input", title: "Fill " + span, prompt: 'A byte, bytes or text in quotes, repeated to fill, such as EA, 01 02 or "*".' });
    if (!answer || answer.cancelled) return;
    const data = parseData(answer.text);
    if (typeof data === "string") { status(data, true); return; }
    await inTurn(async () => {
        let values;
        if (Array.isArray(data)) {
            values = Array.from({ length: count }, (_, index) => data[index % data.length]);
        } else {
            // Text repeats as characters, each chosen against the byte it replaces.
            if (!await loaded(low, count)) return;
            const text = Array.from(data.text);
            values = dataAt({ text: Array.from({ length: count }, (_, index) => text[index % text.length]).join("") }, low, count);
            if (values === null) return;
        }
        if (await writeNow(low, values)) status("Filled " + span + ".");
    });
}

// Pastes the clipboard at the cursor: in the text pane as the machine's characters, else as hex bytes, which may
// be the Monitor's lines with their addresses. It takes its turn when Ctrl+V is pressed, so an undo or a key pressed
// while the clipboard is read comes after it.
async function paste() {
    // The column Ctrl+V was pressed in, and where: a key typed before it moves the cursor on when its write comes
    // back, so where the paste goes is decided when its turn comes, unless the user has moved since.
    const column = pane, pressed = moves, wasAt = cursor;
    await inTurn(async () => {
        const at = moves === pressed ? cursor : wasAt;
        let clipboard;
        try {
            clipboard = String((await request({ type: "paste" })).text ?? "");
        } catch (error) {
            status(String(error.message || error), true);
            return;
        }
        if (clipboard.length === 0) { status("The clipboard is empty.", true); return; }
        const data = column === "text" ? { text: clipboard.split(String.fromCharCode(13)).join("").split(String.fromCharCode(10)).join("") } : parseData(clipboard);
        if (typeof data === "string") { status("The clipboard does not hold hex bytes: " + data, true); return; }
        const length = Array.isArray(data) ? data.length : Array.from(data.text).length;
        const count = Math.min(length, SIZE - at);
        if (!await loaded(at, count)) return;
        const values = Array.isArray(data) ? data.slice(0, count) : dataAt(data, at, count);
        if (values === null) return;
        const cut = length > count ? "; " + (length - count) + " more ran past " + where(SIZE - 1) : "";
        if (await writeNow(at, values)) status("Pasted " + count + (count === 1 ? " byte" : " bytes") + " at " + where(at) + cut + ".");
    });
}

// Copies the selection as memory holds it now, reading the bytes out of view first.
async function copy() {
    const low = Math.min(cursor, anchor), high = Math.max(cursor, anchor);
    if (!await loaded(low, high - low + 1)) return;
    await request({ type: "copy", text: copyText(bytes, readable, low, high, pane === "text", charset === null ? undefined : charset.text) });
}

// The selection's bytes, read first, or null and a message where one cannot be read.
async function selectionBytes(doing) {
    const low = Math.min(cursor, anchor), high = Math.max(cursor, anchor), count = high - low + 1;
    if (!await loaded(low, count)) return null;
    for (let offset = low; offset <= high; offset++) {
        if (readable[offset] !== 1) { status("There is no byte at " + where(offset) + " to " + doing + ".", true); return null; }
    }
    return { low, values: Array.from(bytes.slice(low, high + 1)) };
}

function bytesCount(count) {
    return count + (count === 1 ? " byte" : " bytes");
}

// Copies the selection in a form chosen from copyFormats, such as the Monitor's lines or a C array.
async function copySelectionAs() {
    const picked = await request({ type: "pick", title: "Copy as", items: copyFormats.map(item => ({ label: item.label, detail: item.detail })) });
    if (!picked || picked.cancelled) return;
    const selection = await selectionBytes("copy");
    if (selection === null) return;
    const format = copyFormats[picked.index];
    await request({ type: "copy", text: copyAs(selection.values, selection.low, format.format) });
    status("Copied " + bytesCount(selection.values.length) + " from " + where(selection.low) + " as " + format.label + ".");
}

// Saves the selection to a file, whose extension says how: binary, Intel HEX or native assembly.
async function saveSelection() {
    const selection = await selectionBytes("save");
    if (selection === null) return;
    let saved;
    try {
        saved = await request({ type: "save", offset: selection.low, data: selection.values, starts: Array.from(forcedStarts) });
    } catch (error) {
        status(String(error.message || error), true);
        return;
    }
    if (!saved || saved.cancelled) return;
    const what = "Saved " + bytesCount(selection.values.length) + " from " + where(selection.low) + " to " + saved.path;
    if (saved.form !== "assembly") status(what + " as " + saved.form + ".");
    else if (saved.exact) status(what + ", which assembles back to the same bytes.");
    else status(what + " as .byte lines, as its instructions would not assemble back to the same bytes.");
}

// Loads a file: a binary's bytes at the cursor, or Intel HEX's at the addresses it gives, as one edit.
async function loadIntoMemory() {
    const at = cursor;
    let file;
    try {
        file = await request({ type: "load" });
    } catch (error) {
        status(String(error.message || error), true);
        return;
    }
    if (!file || file.cancelled) return;
    await inTurn(async () => {
        let runs = file.runs, cut = "";
        if (runs === undefined) {
            if (file.data.length === 0) { status(file.name + " is empty.", true); return; }
            const count = Math.min(file.data.length, SIZE - at);
            if (count < file.data.length) cut = "; " + (file.data.length - count) + " more ran past " + where(SIZE - 1);
            runs = [{ address: at, data: file.data.slice(0, count) }];
        }
        nibble = null;
        render();
        const before = undoStack.length;
        let written = 0;
        for (const run of runs) {
            if (!await write(run.address, run.data, true)) break;
            written += run.data.length;
        }
        // One undo takes back the whole file.
        const pieces = undoStack.splice(before);
        if (pieces.length === 1) undoStack.push(pieces[0]);
        else if (pieces.length > 1) undoStack.push({ offset: pieces[0].offset, group: pieces });
        if (written < runs.reduce((total, run) => total + run.data.length, 0)) return;
        const places = runs.length === 1 ? " at " + where(runs[0].address) : " in " + runs.length + " runs from " + where(runs[0].address);
        status("Loaded " + bytesCount(written) + " from " + file.name + places + cut + ".");
        moveTo(runs[0].address, false, false, true);
    });
}

grid.addEventListener("scroll", render);
window.addEventListener("resize", render);

function offsetAt(event) {
    const target = event.target.closest ? event.target.closest("[data-o]") : null;
    return target === null ? null : { offset: Number(target.dataset.o), text: target.dataset.t === "1" };
}

grid.addEventListener("contextmenu", event => {
    const hit = offsetAt(event);
    if (hit !== null) {
        const low = Math.min(cursor, anchor), high = Math.max(cursor, anchor);
        // A click outside the selection selects the byte clicked, as an editor's does.
        if (hit.offset < low || hit.offset > high) {
            pane = hit.text ? "text" : "hex";
            moveTo(hit.offset, false, false);
        }
    }
    openMenu("all", event.clientX, event.clientY);
    event.preventDefault();
});
window.addEventListener("mousedown", event => {
    if (actionMenu.hidden) return;
    const inside = event.target && event.target.closest ? event.target.closest("#actionMenu, [data-act=menu]") : null;
    if (inside === null) closeMenu();
});
grid.addEventListener("scroll", closeMenu);

// The label a gutter name stands for, under the mouse.
function gutterLabel(event) {
    const target = event.target && event.target.closest ? event.target.closest(".lab[data-a]") : null;
    return target === null ? null : Number(target.dataset.a);
}

// Marks a label's byte, in the bytes and the text, while the mouse is over its name.
let hoveredLabel = null;
function markLabel(address) {
    if (address === hoveredLabel) return;
    for (const element of rows.querySelectorAll(".hl")) element.classList.remove("hl");
    hoveredLabel = address;
    if (address !== null) for (const element of rows.querySelectorAll('[data-o="' + address + '"]')) element.classList.add("hl");
}
rows.addEventListener("mouseover", event => markLabel(gutterLabel(event)));
rows.addEventListener("mouseleave", () => markLabel(null));

grid.addEventListener("mousedown", event => {
    // The mouse's back and forward buttons go back and forward, from where the cursor is, and the right button's menu
    // keeps the selection it opens over; only the main button selects.
    if (event.button !== undefined && event.button !== 0) return;
    const label = gutterLabel(event);
    if (label !== null) {
        pane = visiblePane("hex");
        moveTo(label, event.shiftKey, false);
        grid.focus();
        event.preventDefault();
        return;
    }
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
    } else if (control && (key === "v" || key === "V")) {
        void paste();
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
    } else if (key === "F2") {
        void assembleAtCursor();
    } else if (key === "ContextMenu" || (key === "F10" && event.shiftKey)) {
        // The right-click menu, at the cursor's byte.
        const at = rows.querySelector ? rows.querySelector(".cur") : null;
        const box = at && at.getBoundingClientRect ? at.getBoundingClientRect() : { left: 0, bottom: 0 };
        openMenu("all", box.left, box.bottom);
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
    } else if (key === "Tab" && !folded.bytes && !folded.text && (event.shiftKey ? pane === "text" : pane === "hex")) {
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

// Tooltips drawn in the page, in VS Code's hover colors and font size, which grow with VS Code's zoom as the
// browser's own do not. An element's title becomes its tip as the mouse first reaches it, so the browser shows none;
// its text stays the element's accessible description.
const tip = document.getElementById("tip");
let tipFor = null, tipTimer = null;
// Sets an element's hover text where the page changes it as it runs, which a title would show as the browser's own.
function setTip(element, text) {
    element.dataset.tip = text;
    if (element.removeAttribute) element.removeAttribute("title");
    if (element.setAttribute) element.setAttribute("aria-description", text);
}

function hideTip() {
    clearTimeout(tipTimer);
    tipFor = null;
    tip.hidden = true;
}
window.addEventListener("mouseover", event => {
    const target = event.target && event.target.closest ? event.target.closest("[title], [data-tip]") : null;
    startTip(target);
});

// Shows an element's tip after a moment, taking over its title.
function startTip(target) {
    if (target === tipFor) return;
    hideTip();
    if (target === null) return;
    if (target.hasAttribute && target.hasAttribute("title")) {
        target.dataset.tip = target.getAttribute("title");
        target.setAttribute("aria-description", target.dataset.tip);
        target.removeAttribute("title");
    }
    if (!target.dataset.tip) return;
    tipFor = target;
    tipTimer = setTimeout(() => {
        if (tipFor !== target || !target.isConnected) return;
        tip.textContent = target.dataset.tip;
        tip.hidden = false;
        const box = target.getBoundingClientRect();
        const width = tip.offsetWidth, height = tip.offsetHeight;
        const below = box.bottom + 4 + height <= window.innerHeight;
        tip.style.left = Math.max(4, Math.min(box.left, window.innerWidth - width - 4)) + "px";
        tip.style.top = (below ? box.bottom + 4 : Math.max(4, box.top - height - 4)) + "px";
    }, 500);
}
window.addEventListener("mousedown", hideTip, true);
window.addEventListener("keydown", hideTip, true);
window.addEventListener("wheel", hideTip, true);
document.documentElement?.addEventListener("mouseleave", hideTip);

// The headings' toggles: Align to labels in the Label heading, and the machine's characters in the Text heading.
head.addEventListener("click", event => {
    const toggle = event.target && event.target.closest ? event.target.closest("[data-toggle]") : null;
    if (toggle === null) return;
    if (toggle.dataset.toggle === "align") {
        aligned = !aligned;
        remember();
        layoutRows();
    } else if (toggle.dataset.toggle === "marks") {
        labelMarks = !labelMarks;
        if (document.body) document.body.classList.toggle("nomarks", !labelMarks);
        remember();
    } else {
        machineText = !machineText;
        remember();
        applyText();
    }
    render();
    grid.focus();
});

// The inspector's places, beside the bytes or under them: the one it is in shows pressed, and the other moves it there.
function showDocks() {
    const docks = document.getElementById("docks");
    const right = dock === "right";
    const html = (right
        ? '<button class="action codicon codicon-layout-sidebar-right" disabled aria-pressed="true" aria-label="The inspector is beside the bytes" title="The inspector is beside the bytes"></button>'
            + '<button class="action codicon codicon-layout-panel-dock" data-dock="bottom" aria-label="Move the inspector under the bytes" title="Move the inspector under the bytes"></button>'
        : '<button class="action codicon codicon-layout-sidebar-right-dock" data-dock="right" aria-label="Move the inspector beside the bytes" title="Move the inspector beside the bytes"></button>'
            + '<button class="action codicon codicon-layout-panel" disabled aria-pressed="true" aria-label="The inspector is under the bytes" title="The inspector is under the bytes"></button>');
    if (docks.innerHTML !== html) docks.innerHTML = html;
    sash.ariaOrientation = right ? "vertical" : "horizontal";
}

function moveInspector(place) {
    if (place === dock) return;
    dock = place;
    narrow = null;
    showDocks();
    remember();
    render();
}
showDocks();

// The splitter between the bytes and the inspector: dragging it sizes the inspector, and the arrow keys move it too.
let sashDrag = null;
sash.addEventListener("pointerdown", event => {
    sashDrag = { x: event.clientX, y: event.clientY, width: sideWidth, height: sideHeight };
    if (sash.setPointerCapture) sash.setPointerCapture(event.pointerId);
    sash.classList.add("dragging");
    event.preventDefault();
});
sash.addEventListener("pointermove", event => {
    if (sashDrag === null) return;
    if (dock === "right") sideWidth = sashDrag.width - (event.clientX - sashDrag.x);
    else sideHeight = sashDrag.height - (event.clientY - sashDrag.y);
    narrow = null;
    render();
});
const endDrag = () => {
    if (sashDrag === null) return;
    sashDrag = null;
    sash.classList.remove("dragging");
    remember();
};
sash.addEventListener("pointerup", endDrag);
sash.addEventListener("pointercancel", endDrag);
sash.addEventListener("keydown", event => {
    const step = event.shiftKey ? 40 : 10;
    const grow = dock === "right" ? { ArrowLeft: step, ArrowRight: -step } : { ArrowUp: step, ArrowDown: -step };
    if (!(event.key in grow)) return;
    if (dock === "right") sideWidth += grow[event.key];
    else sideHeight += grow[event.key];
    narrow = null;
    remember();
    render();
    event.preventDefault();
});

// Collapses a column into a vertical strip, or expands it again.
function toggleFold(name) {
    // The cursor edits in the bytes or the text, so one of them stays.
    const other = name === "bytes" ? "text" : name === "text" ? "bytes" : null;
    if (other !== null && !folded[name] && folded[other]) {
        status("Keep the bytes or the text showing, to see and edit the byte at the cursor.", true);
        return;
    }
    folded[name] = !folded[name];
    if (name === "listing") {
        showListing = !folded.listing;
        listingPane.classList.toggle("folded", folded.listing);
        for (const strip of listingPane.querySelectorAll ? listingPane.querySelectorAll(".strip") : []) strip.hidden = !folded.listing;
        listingKey = "";
    }
    // The cursor's column goes to the one that shows, where the bytes or the text collapse.
    pane = visiblePane(pane);
    narrow = null;
    remember();
    render();
    grid.focus();
}
window.addEventListener("click", event => {
    const fold = event.target && event.target.closest ? event.target.closest("[data-fold]") : null;
    if (fold !== null) toggleFold(fold.dataset.fold);
});


const backButton = document.getElementById("back"), forwardButton = document.getElementById("forward");
const followBox = document.getElementById("follow");
backButton.addEventListener("click", () => { goBack(false); grid.focus(); });
forwardButton.addEventListener("click", () => { goBack(true); grid.focus(); });
document.getElementById("bookmarks").addEventListener("click", () => void pickBookmark());
followBox.addEventListener("click", () => void useFollow(following === ""));
document.getElementById("findPrevious").addEventListener("click", () => void find(true));
document.getElementById("findNext").addEventListener("click", () => void find(false));
// Alt+Left and Alt+Right go back and forward wherever focus is, ahead of the boxes and the listing, which use the
// arrows themselves.
window.addEventListener("keydown", event => {
    if (!event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;
    if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
    event.preventDefault();
    event.stopPropagation();
    goBack(event.key === "ArrowRight");
}, true);
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
        if (action.follow !== undefined) await useFollow(action.follow);
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
        if (action.assemble) await assembleAtCursor();
        if (action.edit !== undefined) await editValue(action.edit);
        if (action.fill) await fill();
        if (action.paste) await paste();
        if (action.copyAs) await copySelectionAs();
        if (action.save) await saveSelection();
        if (action.load) await loadIntoMemory();
        if (action.space !== undefined) await request({ type: "switch", bank: action.space, address: cursor });
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
        ended,
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
    } else if (message.type === "restarted") {
        // VS Code restarted the session: a new machine, so nothing is frozen and there is nothing to undo, and the
        // bytes, labels, characters and banks are read again.
        ended = false;
        document.getElementById("ended").hidden = true;
        frozen = new Map();
        undoStack.length = 0;
        redoStack.length = 0;
        stops++;
        generation++;
        pages.fill(0);
        showFrozen();
        render();
        void loadExtras();
        void loadBanks().then(readOther);
    } else if (message.type === "test") {
        test(message.actions).then(
            state => vscode.postMessage({ type: "testDone", id: message.id, state }),
            error => vscode.postMessage({ type: "testDone", id: message.id, error: String(error) }));
    }
});

vscode.postMessage({ type: "ready" });
</script></body></html>`;
}
