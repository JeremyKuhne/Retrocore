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
        "source.retrocore-business": "business.tmLanguage.json",
        "source.retrocore-colorbasic": "colorbasic.tmLanguage.json",
        "source.retrocore-mbasic": "mbasic.tmLanguage.json",
        "source.retrocore-petbasic": "petbasic.tmLanguage.json",
        "source.retrocore-bbcbasic": "bbcbasic.tmLanguage.json"
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

test("Color BASIC finds words only in capitals and never inside a name", () => {
    const line = "120 IFA=BTHEN10";
    assert.ok(has(scopes("colorbasic", line, "IF"), "keyword.control"));
    assert.ok(has(scopes("colorbasic", line, "A"), "variable.other"));
    assert.ok(has(scopes("colorbasic", line, "THEN"), "variable.other"), "THEN after B is part of the name BTHEN10");
    assert.ok(has(scopes("colorbasic", "30 IF SCORE > 5 THEN 100", "OR"), "variable.other"), "OR inside SCORE");
    assert.ok(!has(scopes("colorbasic", "40 print", "print"), "keyword"), "lowercase is not crunched");
    assert.ok(has(scopes("colorbasic", "50 GOSUB 100", "GO"), "keyword.control"));
    assert.ok(has(scopes("colorbasic", "50 GOSUB 100", "SUB"), "keyword.control"));
    assert.ok(has(scopes("colorbasic", "60 PRINT HEX$(255);STRING$(3,\"*\")", "HEX$"), "support.function"));
    assert.ok(has(scopes("colorbasic", "70 A=1 'NOTE", "NOTE"), "comment.line"));
});

test("BBC BASIC finds words only in capitals, keeps small letters in names, and runs DATA to the line's end", () => {
    assert.ok(has(scopes("bbcbasic", "10 PRINT LEFT$(A$,2)", "PRINT"), "keyword.other"));
    assert.ok(has(scopes("bbcbasic", "10 PRINT LEFT$(A$,2)", "LEFT$("), "support.function"));
    assert.ok(has(scopes("bbcbasic", "20 FOR I%=1 TO 3", "FOR"), "keyword.control"));
    assert.ok(has(scopes("bbcbasic", "30 my_name%=2", "my_name%"), "variable.other"), "a name with small letters and _");
    assert.ok(!has(scopes("bbcbasic", "40 print", "print"), "keyword"), "lowercase is not tokenised");
    assert.ok(has(scopes("bbcbasic", "50 DATA 1,2:PRINT", "PRINT"), "string.unquoted.data"), "DATA runs to the end of the line");
    assert.ok(has(scopes("bbcbasic", "60 REM a note", "note"), "comment.line"));
    for (const name of ["COUNTER", "TIMER", "ENDING"]) {
        assert.ok(has(scopes("bbcbasic", `70 ${name}=1`, name), "variable.other"), `${name} is a name: its word is conditional`);
    }
    assert.ok(has(scopes("bbcbasic", "80 PRINT COUNT", "COUNT"), "keyword"), "COUNT alone is still a word");
    // PROC and FN take the whole name after them, keywords and all.
    assert.ok(has(scopes("bbcbasic", "90 PROCREM:PRINT 1", "PRINT"), "keyword.other"), "PROCREM is a name, not a remark");
    assert.ok(has(scopes("bbcbasic", "90 PROCREM:PRINT 1", "REM"), "entity.name.function"));
    assert.ok(has(scopes("bbcbasic", "100 X=FNTIME", "TIME"), "entity.name.function"), "FNTIME names a function");
    // Abbreviations: letters and a full stop are the first word in the table's order that starts with them.
    assert.ok(has(scopes("bbcbasic", "110 P. \"HELLO\"", "P."), "keyword.other"), "P. is PRINT");
    assert.ok(has(scopes("bbcbasic", "120 D. 1,2:PRINT", "PRINT"), "string.unquoted.data"), "D. is DATA, to the line's end");
    assert.ok(has(scopes("bbcbasic", "130 PR.\"HI\"", "PR."), "keyword.other"));
    assert.ok(has(scopes("bbcbasic", "135 PRINT &DEF", "DEF"), "constant.numeric"), "&DEF is a number, not DEF");
    assert.ok(has(scopes("bbcbasic", "135 X=&BEEF", "BEEF"), "constant.numeric"), "&BEEF is a number, not a name");
    // An abbreviated PROC takes its name too, so PRO.REM calls REM rather than starting a remark.
    assert.ok(has(scopes("bbcbasic", "140 PRO.REM:PRINT 1", "PRINT"), "keyword.other"), "PRO.REM is a call, not a remark");
    assert.ok(has(scopes("bbcbasic", "140 PRO.REM:PRINT 1", "REM"), "entity.name.function"));
    // A * where a statement starts is the MOS's to the line's end, as the tokeniser leaves it; elsewhere it multiplies.
    assert.ok(has(scopes("bbcbasic", "150 *KEY 0 LIST:RUN|M", "RUN"), "string.unquoted.command"), "a * command's words are not BASIC's");
    assert.ok(has(scopes("bbcbasic", "160 *LOAD SCREEN 7C00", "LOAD"), "string.unquoted.command"));
    assert.ok(has(scopes("bbcbasic", "170 IF A THEN *CAT", "CAT"), "string.unquoted.command"), "THEN starts a statement");
    assert.ok(has(scopes("bbcbasic", "180 X=1:*FX 15", "FX"), "string.unquoted.command"), "so does a colon");
    assert.ok(has(scopes("bbcbasic", "190 PRINT 5 *LEN A$", "LEN"), "support.function"), "a * in an expression multiplies");
    assert.ok(has(scopes("bbcbasic", "195 PRINT myTHEN *LEN A$", "LEN"), "support.function"), "myTHEN is one name");
    assert.ok(has(scopes("bbcbasic", "196 IF 1 TH. *KEY 0 PRINT:RUN|M", "RUN"), "string.unquoted.command"), "TH. is THEN");
    // A conditional word's abbreviation is not taken before a name character either, and @% is a name.
    assert.ok(!has(scopes("bbcbasic", "200 PRINT COU.X", "COU."), "keyword"), "COU.X is no COUNT");
    assert.ok(has(scopes("bbcbasic", "210 @%=&90A", "@%"), "variable.other"));
});

// The scopes of the first character of the nth occurrence of value on one of several lines, tokenized in turn so a
// rule such as the assembler's carries from line to line.
function linesScopes(dialect: string, lines: string[], line: number, value: string, occurrence = 0): string[] {
    const grammar = grammars.get(dialect);
    if (grammar === undefined) throw new Error(dialect);
    let stack = INITIAL;
    for (let index = 0; index < line; index++) stack = grammar.tokenizeLine(lines[index], stack).ruleStack;
    const text = lines[line];
    let start = -1;
    for (let count = 0; count <= occurrence; count++) start = text.indexOf(value, start + 1);
    assert.notEqual(start, -1, `Missing ${value} in ${text}`);
    const token = grammar.tokenizeLine(text, stack).tokens.find(item => item.startIndex <= start && item.endIndex > start);
    return token?.scopes ?? [];
}

test("BBC BASIC's assembler, from [ to ], highlights its mnemonics, registers, labels and comments", () => {
    const program = [
        "30 [OPT pass",
        "40 .loop LDA dest,X:STA &71,Y \\ copy X: INX",
        "50 lda (dest),Y:ASL A:ROR count:ORA #1 ; set A",
        "60 EQUB 1:BNE loop",
        "65 ASL ADDR:LDX &70,XX:INY",
        "70 ]:NEXT:X=LDA+1"
    ];
    const at = (line: number, value: string, occurrence = 0) => linesScopes("bbcbasic", program, line, value, occurrence);
    assert.ok(has(at(0, "OPT"), "keyword.other.mnemonic"));
    assert.ok(has(at(0, "pass"), "variable.other"), "an operand's names are BASIC's");
    assert.ok(has(at(1, "40"), "entity.name.label.line-number"), "the assembler goes on to the next line");
    assert.ok(has(at(1, "loop"), "entity.name.label"));
    assert.ok(has(at(1, "LDA"), "keyword.other.mnemonic"), "after a label");
    assert.ok(has(at(1, "X"), "variable.language.register"));
    assert.ok(has(at(1, "Y"), "variable.language.register"));
    assert.ok(has(at(1, "copy"), "comment.line.assembler"));
    assert.ok(has(at(1, "INX"), "keyword.other.mnemonic"), "a colon ends a comment");
    assert.ok(has(at(2, "lda"), "keyword.other.mnemonic"), "in small letters too");
    assert.ok(has(at(2, "A", 1), "variable.language.register"), "ASL A is the accumulator");
    assert.ok(has(at(2, "count"), "variable.other"));
    assert.ok(has(at(2, "ORA"), "keyword.other.mnemonic"), "ORA, not OR then A");
    assert.ok(has(at(2, "set"), "comment.line.assembler"), "; after an operand");
    assert.ok(has(at(3, "EQUB"), "keyword.other.mnemonic"));
    assert.ok(has(at(3, "loop"), "variable.other"));
    assert.ok(has(at(4, "A", 1), "variable.language.register"), "ASL ADDR is ASL A");
    assert.ok(has(at(4, "DDR"), "comment.line.assembler"), "the rest of the statement is skipped");
    assert.ok(has(at(4, "XX"), "variable.language.register"));
    assert.ok(has(at(4, "X:"), "comment.line.assembler"), "after the register too");
    assert.ok(has(at(4, "INY"), "keyword.other.mnemonic"), "a colon ends what is skipped");
    assert.ok(has(at(5, "]"), "punctuation.section.assembler.end"));
    assert.ok(has(at(5, "NEXT"), "keyword.control"), "BASIC again after ]");
    assert.ok(has(at(5, "LDA"), "variable.other"), "outside the assembler LDA is a name");
    assert.ok(!has(at(5, "NEXT"), "meta") && !has(at(5, "LDA"), "keyword.other.mnemonic"));
    assert.ok(has(scopes("bbcbasic", "10 PRINT LDA", "LDA"), "variable.other"), "no [, no assembler");
});

test("MBASIC finds reserved words only set apart from names", () => {
    const line = "20 WHILE PRINTER.COUNT% MOD 2 = 0 XOR A \\ 3: PRINT FNA(2);USR1(0);MID$(B$,1,1): WEND";
    assert.ok(has(scopes("mbasic", line, "WHILE"), "keyword.control"));
    assert.ok(has(scopes("mbasic", line, "PRINTER"), "variable.other"), "PRINT inside PRINTER");
    assert.ok(!has(scopes("mbasic", line, "COUNT"), "keyword"), "the name holds a dot and ends in %");
    assert.ok(has(scopes("mbasic", line, "MOD"), "keyword.operator"));
    assert.ok(has(scopes("mbasic", line, "XOR"), "keyword.operator"));
    assert.ok(has(scopes("mbasic", "50 REMAIN=1:PRINT REMAIN", "REMAIN"), "variable.other"), "REM needs a separator after it");
    assert.ok(has(scopes("mbasic", "60 X=1 ' A NOTE", "NOTE"), "comment.line"), "an apostrophe is a remark");
    assert.ok(has(scopes("mbasic", "70 REM A NOTE", "NOTE"), "comment.line"));
    assert.ok(has(scopes("mbasic", line, "\\"), "keyword.operator"));
    assert.ok(has(scopes("mbasic", line, "PRINT", 1), "keyword.other"));
    assert.ok(has(scopes("mbasic", line, "FN"), "support.function"), "FN before its name");
    assert.ok(has(scopes("mbasic", line, "USR"), "support.function"), "USR before its number");
    assert.ok(has(scopes("mbasic", line, "MID$("), "support.function"));
    assert.ok(has(scopes("mbasic", line, "WEND"), "keyword.control"));
    assert.ok(has(scopes("mbasic", "30 FORI=1TO 9", "FORI"), "variable.other"), "FOR must be set apart");
    assert.ok(has(scopes("mbasic", "40 A=1 'NOTE", "NOTE"), "comment.line"));
});

test("PET BASIC highlights its own words, BASIC 4's disk commands too, but not in strings, DATA or REM", () => {
    assert.ok(has(scopes("petbasic", "10 INPUT#1,A$", "INPUT#"), "keyword"), "INPUT# is one word");
    assert.ok(has(scopes("petbasic", "20 DOPEN#2,\"DATA\",D0", "DOPEN"), "keyword"));
    assert.ok(has(scopes("petbasic", "30 DIRECTORY D0", "DIRECTORY"), "keyword"));
    assert.ok(has(scopes("petbasic", "40 PRINT \"DIRECTORY\"", "DIRECTORY"), "string.quoted"));
    assert.ok(has(scopes("petbasic", "50 DATA DOPEN, 2: END", "DOPEN"), "string.unquoted.data"));
    assert.ok(has(scopes("petbasic", "50 DATA DOPEN, 2: END", "END"), "keyword.control"), "a colon ends DATA");
    assert.ok(has(scopes("petbasic", "60 REM DIRECTORY", "DIRECTORY"), "comment.line"));
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
