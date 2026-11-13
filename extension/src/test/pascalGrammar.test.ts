// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import * as path from "node:path";
import { after, before, test } from "node:test";
import { loadWASM, OnigScanner, OnigString } from "vscode-oniguruma";
import { IGrammar, INITIAL, parseRawGrammar, Registry, StateStack } from "vscode-textmate";

const file = path.resolve(__dirname, "../..", "syntaxes", "pascal.tmLanguage.json");
let grammar: IGrammar;
let registry: Registry;

before(async () => {
    await loadWASM(readFileSync(require.resolve("vscode-oniguruma/release/onig.wasm")));
    registry = new Registry({
        onigLib: Promise.resolve({
            createOnigScanner: patterns => new OnigScanner(patterns),
            createOnigString: text => new OnigString(text)
        }),
        loadGrammar: async name => name === "source.retrocore-pascal"
            ? parseRawGrammar(readFileSync(file, "utf8"), "pascal.tmLanguage.json")
            : null
    });
    const loaded = await registry.loadGrammar("source.retrocore-pascal");
    if (loaded === null) throw new Error("The Pascal grammar was not loaded.");
    grammar = loaded;
});

after(() => registry?.dispose());

// The scopes of the first character of the nth occurrence of value, after the lines before it.
function scopes(lines: string[], value: string, occurrence = 0): string[] {
    let state: StateStack = INITIAL;
    for (const line of lines.slice(0, -1)) state = grammar.tokenizeLine(line, state).ruleStack;
    const text = lines[lines.length - 1];
    let start = -1;
    for (let count = 0; count <= occurrence; count++) start = text.indexOf(value, start + 1);
    assert.notEqual(start, -1, `Missing ${value} in ${text}`);
    const token = grammar.tokenizeLine(text, state).tokens.find(item => item.startIndex <= start && item.endIndex > start);
    return token?.scopes ?? [];
}

function assertScope(text: string | string[], value: string, expected: string, occurrence = 0): void {
    const lines = typeof text === "string" ? [text] : text;
    const found = scopes(lines, value, occurrence);
    assert.ok(found.includes(expected), `${lines.join(" / ")}: ${value} expected ${expected}, got ${found.join(" ")}`);
}

test("Pascal's words are keywords in any case, and headings name their procedures", () => {
    assertScope("PROGRAM HELLO;", "PROGRAM", "storage.type.function.pascal.retrocore");
    assertScope("PROGRAM HELLO;", "HELLO", "entity.name.function.pascal.retrocore");
    assertScope("segment procedure Show(N: Integer);", "Show", "entity.name.function.pascal.retrocore");
    assertScope("segment procedure Show(N: Integer);", "segment", "storage.modifier.pascal.retrocore");
    assertScope("segment procedure Show(N: Integer);", "Integer", "support.type.pascal.retrocore");
    assertScope("FOR I := 1 TO 3 DO", "FOR", "keyword.control.pascal.retrocore");
    assertScope("for i := 1 to 3 do", "do", "keyword.control.pascal.retrocore");
    assertScope("IF A MOD 2 = 0 THEN", "MOD", "keyword.operator.word.pascal.retrocore");
    assertScope("WRITELN(N*7)", "WRITELN", "support.function.pascal.retrocore");
    assertScope("WRITELN(N*7)", "7", "constant.numeric.integer.pascal.retrocore");
    assertScope("X := 2.5E3;", "2.5E3", "constant.numeric.real.pascal.retrocore");
    assertScope("DONE := TRUE;", "TRUE", "constant.language.pascal.retrocore");
    assertScope("ENDING := 1;", "ENDING", "source.retrocore-pascal");
    assert.ok(!scopes(["ENDING := 1;"], "ENDING").includes("keyword.control.pascal.retrocore"), "END inside a name is no keyword");
});

test("strings double their quotes, comments span lines, and compiler options are their own", () => {
    assertScope("S := 'IT''S';", "S'", "string.quoted.single.pascal.retrocore");
    assertScope("S := 'IT''S'; X := 1", "X", "source.retrocore-pascal");
    assertScope(["(* A COMMENT", "BEGIN *) END"], "BEGIN", "comment.block.pascal.retrocore");
    assertScope(["(* A COMMENT", "BEGIN *) END"], "END", "keyword.control.pascal.retrocore");
    assertScope("{ BRACES } BEGIN", "BRACES", "comment.block.braces.pascal.retrocore");
    assertScope("(*$L APPLE1:HELLO.LST.TEXT*)", "HELLO", "meta.preprocessor.pascal.retrocore");
});
