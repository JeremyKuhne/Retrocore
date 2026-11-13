// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import * as path from "node:path";
import { after, before, test } from "node:test";
import { loadWASM, OnigScanner, OnigString } from "vscode-oniguruma";
import { INITIAL, IGrammar, parseRawGrammar, Registry } from "vscode-textmate";

const syntaxes = path.resolve(__dirname, "../..", "syntaxes");
const grammars = new Map<string, IGrammar>();
let registry: Registry;

before(async () => {
    await loadWASM(readFileSync(require.resolve("vscode-oniguruma/release/onig.wasm")));
    const files: Record<string, string> = {
        "source.retrocore-applesoft": "applesoft.tmLanguage.json",
        "source.retrocore-level2": "level2.tmLanguage.json",
        "source.retrocore-integer": "integer.tmLanguage.json",
        "source.retrocore-business": "business.tmLanguage.json"
    };
    registry = new Registry({
        onigLib: Promise.resolve({
            createOnigScanner: patterns => new OnigScanner(patterns),
            createOnigString: text => new OnigString(text)
        }),
        loadGrammar: async name => name in files
            ? parseRawGrammar(readFileSync(path.join(syntaxes, files[name]), "utf8"), files[name])
            : null
    });
    for (const name of Object.keys(files)) {
        const loaded = await registry.loadGrammar(name);
        if (loaded === null) throw new Error(`${name} was not loaded.`);
        grammars.set(name.replace("source.retrocore-", ""), loaded);
    }
});

after(() => registry?.dispose());

// The scopes of the first character of the nth occurrence of value.
function scopes(dialect: string, text: string, value: string, occurrence = 0): string[] {
    let start = -1;
    for (let count = 0; count <= occurrence; count++) start = text.indexOf(value, start + 1);
    assert.notEqual(start, -1, `Missing ${value} in ${text}`);
    const grammar = grammars.get(dialect);
    if (grammar === undefined) throw new Error(dialect);
    const token = grammar.tokenizeLine(text, INITIAL).tokens.find(item => item.startIndex <= start && item.endIndex > start);
    return token?.scopes ?? [];
}

const has = (list: string[], prefix: string): boolean => list.some(scope => scope.startsWith(prefix));

test("BASIC finds reserved words where the ROM does, inside names too", () => {
    const line = "30 IF SCORE > 5 THEN 100";
    assert.ok(has(scopes("applesoft", line, "30"), "entity.name.label.line-number"));
    assert.ok(has(scopes("applesoft", line, "IF"), "keyword.control"));
    assert.ok(has(scopes("applesoft", line, "OR"), "keyword.operator"), "OR inside SCORE");
    assert.ok(has(scopes("applesoft", line, "S"), "variable.other"));
    assert.ok(has(scopes("level2", "10 INPUT A", "INPUT"), "keyword.other"), "INPUT, not INP then UT");
    assert.ok(has(scopes("level2", "10 GO TO 20", "GO"), "keyword.control"));
    assert.ok(has(scopes("applesoft", "10 X = ATN(1) + A TO B", "ATN"), "support.function"));
});

test("Integer BASIC's names run to any length, and MOD and # are operators", () => {
    const line = "20 IF COUNT MOD 2 # 0 THEN GOSUB 100";
    assert.ok(has(scopes("integer", line, "IF"), "keyword.control"));
    assert.ok(has(scopes("integer", line, "MOD"), "keyword.operator"));
    assert.ok(has(scopes("integer", line, "#"), "keyword.operator"));
    assert.ok(has(scopes("integer", line, "GOSUB"), "keyword.control"));
    assert.ok(has(scopes("integer", "30 SCORE=SCORE+1", "SC"), "variable.other"));
    assert.ok(has(scopes("integer", "40 A$(1,3)=\"XYZ\"", "A$"), "variable.other"));
});

test("Business BASIC finds reserved words only between separators", () => {
    const line = "20 IF PRINTER.COUNT& DIV 2 THEN GOSUB 100 ELSE PRINT FNA(2);MID$(B$,1,1)";
    assert.ok(has(scopes("business", line, "IF"), "keyword.control"));
    assert.ok(has(scopes("business", line, "PRINTER"), "variable.other"), "PRINT inside PRINTER");
    assert.ok(!has(scopes("business", line, "COUNT"), "keyword"), "the name holds a dot and ends in &");
    assert.ok(has(scopes("business", line, "DIV"), "keyword.operator"));
    assert.ok(has(scopes("business", line, "THEN"), "keyword.control"));
    assert.ok(has(scopes("business", line, "ELSE"), "keyword.control"));
    assert.ok(has(scopes("business", line, "PRINT", 1), "keyword.other"));
    assert.ok(has(scopes("business", line, "FN"), "support.function"), "FN before its name");
    assert.ok(has(scopes("business", line, "MID$("), "support.function"));
    assert.ok(has(scopes("business", "30 X=EXFN.SUM(1)", "EXFN."), "support.function"));
    assert.ok(has(scopes("business", "40 ! A NOTE", "NOTE"), "comment.line"));
    assert.ok(has(scopes("business", "50 REMARK=1", "REMARK"), "variable.other"), "REM needs a separator after it");
});

test("BASIC labels have label scopes", () => {
    assert.ok(has(scopes("applesoft", "loop:", "loop"), "entity.name.label"));
    assert.ok(has(scopes("level2", "  @done", "@done"), "entity.name.label"));
    assert.ok(has(scopes("applesoft", "    GOSUB @done", "@done"), "entity.name.label"));
});

test("BASIC remarks, strings, DATA and escapes have their scopes", () => {
    assert.ok(has(scopes("applesoft", "10 REM HELLO: PRINT", "PRINT"), "comment.line"), "REM runs to the end of the line");
    assert.ok(has(scopes("level2", "10 A=1 'note", "note"), "comment.line"));
    assert.ok(has(scopes("applesoft", "10 PRINT \"GOTO {CTRL-D}\"", "GOTO"), "string.quoted"));
    assert.ok(has(scopes("applesoft", "10 PRINT \"{CTRL-D}CATALOG\"", "{CTRL-D}"), "constant.character.escape"));
    assert.ok(has(scopes("applesoft", "10 DATA 1, PRINT: END", "PRINT"), "string.unquoted.data"));
    assert.ok(has(scopes("applesoft", "10 DATA 1, PRINT: END", "END"), "keyword.control"), "a colon ends DATA");
});
