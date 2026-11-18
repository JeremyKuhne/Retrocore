// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Generates the BASIC grammars from the reserved word tables in Retrocore.Basic, which a test checks against the
// ROMs. Each dialect's words are tried in token order at every position, as the ROM's tokenizer tries them, so a
// word inside a name (OR in SCORE) is highlighted where BASIC finds it. Business BASIC takes a word only between
// separators, so its words are highlighted only there, as are MBASIC's, which must be set apart from names.

import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { writeGenerated } from "./generated-file.mjs";

const extension = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const library = resolve(extension, "..", "src", "Retrocore.Basic");

// A table's words, without the placeholders Business BASIC's and MBASIC's lists keep empty, and C#'s escapes undone.
function keywords(file, field = "s_keywords") {
    const source = readFileSync(resolve(library, file), "utf8");
    const table = new RegExp(`${field}\\s*=\\s*\\[([\\s\\S]*?)\\];`).exec(source);
    if (table === null) throw new Error(`No ${field} table in ${file}.`);
    return [...table[1].matchAll(/"((?:[^"\\]|\\.)*)"/g)].map(match => match[1].replace(/\\(.)/g, "$1"))
        .filter(word => word.length > 0);
}

const flow = new Set(["END", "FOR", "NEXT", "GOTO", "RUN", "IF", "GOSUB", "RETURN", "STOP", "ON", "THEN", "TO", "STEP",
    "ELSE", "ONERR", "RESUME", "POP", "CONT", "ERROR", "GO", "SUB", "WHILE", "WEND"]);
const operators = new Set(["+", "-", "*", "/", "^", "[", "AND", "OR", "NOT", ">", "=", "<", "MOD", "DIV", "#", "<>", ">=",
    "<=", "XOR", "EQV", "IMP", "\\"]);
const functions = new Set(["SGN", "INT", "ABS", "USR", "FRE", "PDL", "POS", "SQR", "RND", "LOG", "EXP", "COS", "SIN",
    "TAN", "ATN", "PEEK", "LEN", "VAL", "ASC", "INP", "CVI", "CVS", "CVD", "EOF", "LOC", "LOF", "CINT", "CSNG", "CDBL",
    "FIX", "ERL", "ERR", "MEM", "POINT", "VARPTR", "INSTR", "FN", "SCRN", "RNDX", "HPOS", "VPOS", "ERRLIN", "KBD",
    "EXFN.", "EXFN%.", "LPOS"]);

const escape = text => text.replace(/[\\^$.*+?()[\]{}|]/g, "\\$&");

// A word as the tokenizer matches it: GOTO may have spaces between GO and TO; AppleSoft's AT is not taken before N
// (ATN) or O (A TO).
function pattern(word) {
    if (word === "GOTO") return "G\\s*O\\s*T\\s*O";
    if (word === "AT") return "AT(?![NnOo])";
    return escape(word);
}

// A Business BASIC or MBASIC word, which needs a separator before it, and after it too unless it ends in one, as ( or
// . does; FN is taken before its function's name, as in FNA(2), and MBASIC's USR before its number, as in USR1(X).
// An operator needs no separator.
const before = "(?<![A-Za-z0-9.])";
const after = "(?![A-Za-z0-9.])";
function separated(word) {
    if (!/^[A-Za-z]/.test(word)) return pattern(word);
    return /[A-Za-z0-9$]$/.test(word) && word !== "FN" && word !== "USR" ? `${before}${pattern(word)}${after}` : `${before}${pattern(word)}`;
}

// BBC BASIC's keyword table: each word in the order the tokeniser searches it, which a test checks against the ROM,
// the conditional ones, which are not words when a name character follows, as in COUNTER or TIMER, and those a
// name follows, PROC and FN, which take the whole name after them, as in PROCREM.
function bbcKeywords() {
    const source = readFileSync(resolve(library, "BbcBasicDialect.cs"), "utf8");
    const table = /s_table\s*=\s*\[([\s\S]*?)\];/.exec(source);
    if (table === null) throw new Error("No s_table in BbcBasicDialect.cs.");
    const entries = [...table[1].matchAll(/\("([^"]+)", [^,]+, ([^)]+)\)/g)];
    return {
        words: entries.map(match => match[1]),
        conditional: new Set(entries.filter(match => /\bConditional\b/.test(match[2])).map(match => match[1])),
        nameFollows: new Set(entries.filter(match => /\bNameFollows\b/.test(match[2])).map(match => match[1])),
        abbreviations: abbreviations(entries.map(match => match[1]))
    };
}

// BBC BASIC's abbreviations, as its tokeniser finds them: letters then a full stop stand for the first word in the
// table's order that starts with those letters, so P. is PRINT's only if no word before it starts with P. Each word
// gets the prefixes shorter than itself that no word before it took.
function abbreviations(words) {
    const taken = new Set();
    const result = new Map();
    for (const word of words) {
        const prefixes = [];
        for (let length = 1; length < word.length; length++) {
            const prefix = word.slice(0, length);
            if (taken.has(prefix)) continue;
            taken.add(prefix);
            prefixes.push(prefix);
        }

        if (prefixes.length !== 0) result.set(word, prefixes);
    }

    return result;
}

// Integer BASIC's names are any length, letters then letters and digits, and Business BASIC's may also hold dots and
// end in & for a long integer; MBASIC's are letters, digits and dots, 40 of them significant; the other Microsoft
// BASICs' are read by two. Color BASIC finds words only in capitals and never inside a name, which runs from a
// capital through letters and digits. BBC BASIC also finds words only in capitals; its names are whole, with _
// and small letters, and its DATA, like its REM, runs to the end of the line.
function grammar(dialect, name, words, { names = "[A-Za-z][0-9]*[$%!#]?", ignoreCase = true, business = false, wholeLineData = false, conditional = new Set(), nameFollows = new Set(), abbreviated = new Map() } = {}) {
    const matching = text => ignoreCase ? `(?i:${text})` : `(?:${text})`;
    const scope = `retrocore-${dialect}`;
    // One alternation in token order, as the tokenizer tries the words, with a group per word for its scope.
    const reserved = words.filter(word => word !== "REM" && word !== "'" && word !== "DATA");
    // A word as written in full, or as one of its abbreviations, a prefix and a full stop.
    const written = (word, full) => abbreviated.has(word)
        ? `(?:${full}|(?:${abbreviated.get(word).map(escape).join("|")})\\.)`
        : full;
    // MBASIC sets REM apart from names, as Business BASIC does, so REMAIN is a variable; its remark may also be '.
    const remark = words.includes("'") && business ? `(?i:${before}(REM)${after}|(')).*$`
        : words.includes("'") ? `${matching("(REM)|(')")}.*$`
            : business ? `(?i:${before}(REM)${after}|(!)).*$`
                : `${matching(`(${written("REM", "REM")})`)}.*$`;
    const kind = word => flow.has(word) ? "keyword.control"
        : operators.has(word) ? "keyword.operator"
            : functions.has(word) || /[$(]$/.test(word) ? "support.function"
                : "keyword.other";
    const captures = Object.fromEntries(reserved.map((word, index) => [String(index + 1), { name: `${kind(word)}.${scope}` }]));
    return {
        $schema: "https://raw.githubusercontent.com/martinring/tmlanguage/master/tmlanguage.json",
        name,
        scopeName: `source.${scope}`,
        patterns: [
            { include: "#pragma" },
            { match: "^\\s*(?:@[A-Za-z_][A-Za-z0-9_]*|[A-Za-z_][A-Za-z0-9_]*:)\\s*$", name: `entity.name.label.${scope}` },
            { match: "^\\s*(\\d+)", captures: { "1": { name: `entity.name.label.line-number.${scope}` } } },
            { include: "#statements" }
        ],
        repository: {
            pragma: { match: "^\\s*(?:REM|')\\s*retrocore\\s+\\S+.*$", name: `comment.line.pragma.${scope}` },
            statements: {
                patterns: [
                    { include: "#remark" },
                    { include: "#data" },
                    { include: "#string" },
                    { include: "#escape" },
                    { match: "@[A-Za-z_][A-Za-z0-9_]*", name: `entity.name.label.${scope}` },
                    ...[...nameFollows].map(word => ({
                        match: matching(`(${pattern(word)})([A-Za-z0-9_\`]*)`),
                        captures: { "1": { name: `${kind(word)}.${scope}` }, "2": { name: `entity.name.function.${scope}` } }
                    })),
                    { match: matching(reserved.map(word => `(${business ? separated(word) : written(word, conditional.has(word) ? `${pattern(word)}(?![A-Za-z0-9_\`])` : pattern(word))})`).join("|")), captures },
                    { match: "\\?", name: `keyword.other.${scope}` },
                    { match: "(?:\\d+\\.?\\d*|\\.\\d+)(?:[EeDd][+-]?\\d+)?", name: `constant.numeric.${scope}` },
                    { match: names, name: `variable.other.${scope}` },
                    { match: ":", name: `punctuation.separator.statement.${scope}` },
                    { match: "[;,]", name: `punctuation.separator.${scope}` }
                ]
            },
            remark: {
                match: remark,
                name: `comment.line.${scope}`,
                captures: { "1": { name: `keyword.other.remark.${scope}` }, "2": { name: `keyword.other.remark.${scope}` } }
            },
            data: {
                begin: business ? `(?i:${before}(DATA)${after})` : matching(`(${written("DATA", "DATA")})`),
                beginCaptures: { "1": { name: `keyword.other.${scope}` } },
                end: wholeLineData ? "(?=$)" : "(?=:|$)",
                contentName: `string.unquoted.data.${scope}`,
                patterns: [{ include: "#string" }, { include: "#escape" }]
            },
            string: {
                begin: "\"",
                end: "\"|$",
                name: `string.quoted.double.${scope}`,
                patterns: [{ include: "#escape" }]
            },
            escape: { match: "\\{(?:\\{|\\$[0-9A-Fa-f]{2}|CTRL-.)\\}", name: `constant.character.escape.${scope}` }
        }
    };
}

const appleSoft = keywords("AppleSoftDialect.cs");
const level2 = keywords("Level2Dialect.cs");
const integer = keywords("IntegerBasicDialect.cs");
const business = [...keywords("BusinessBasicDialect.cs", "s_statements"), ...keywords("BusinessBasicDialect.cs", "s_functions")];
const mbasic = [...keywords("MbasicDialect.cs"), ...keywords("MbasicDialect.cs", "s_functions")];
const colorBasic = [...keywords("ColorBasicDialect.cs", "s_commands"), ...keywords("ColorBasicDialect.cs", "s_functions")];
const bbcBasic = bbcKeywords();
const petBasic = keywords("PetBasicDialect.cs");
const union = [...appleSoft, ...level2.filter(word => !appleSoft.includes(word))];
const outputs = [
    ["applesoft.tmLanguage.json", grammar("applesoft", "AppleSoft BASIC", appleSoft)],
    ["level2.tmLanguage.json", grammar("level2", "Level II BASIC", level2)],
    ["integer.tmLanguage.json", grammar("integer", "Integer BASIC", integer, { names: "[A-Za-z][A-Za-z0-9]*\\$?" })],
    ["business.tmLanguage.json", grammar("business", "Business BASIC", business, { names: "[A-Za-z][A-Za-z0-9.]*[$%&]?", business: true })],
    ["colorbasic.tmLanguage.json", grammar("colorbasic", "Color BASIC", colorBasic, { names: "[A-Z][A-Z0-9]*\\$?", ignoreCase: false })],
    ["mbasic.tmLanguage.json", grammar("mbasic", "MBASIC", mbasic, { names: "[A-Za-z][A-Za-z0-9.]*[$%!#]?", business: true })],
    ["bbcbasic.tmLanguage.json", grammar("bbcbasic", "BBC BASIC", bbcBasic.words, { names: "[A-Za-z_`][A-Za-z0-9_`]*[$%]?", ignoreCase: false, wholeLineData: true, conditional: bbcBasic.conditional, nameFollows: bbcBasic.nameFollows, abbreviated: bbcBasic.abbreviations })],
    ["petbasic.tmLanguage.json", grammar("petbasic", "Commodore BASIC (PET)", petBasic)],
    ["basic.tmLanguage.json", grammar("basic", "Retrocore BASIC", union)]
];
for (const [file, content] of outputs) {
    const output = resolve(extension, "syntaxes", file);
    writeGenerated(output, JSON.stringify(content, null, 2) + "\n", `${file} is stale. Run npm run generate:grammar.`);
}
console.log(`BASIC grammars: ${appleSoft.length} AppleSoft, ${level2.length} Level II, ${integer.length} Integer BASIC, `
    + `${business.length} Business BASIC, ${colorBasic.length} Color BASIC, ${mbasic.length} MBASIC, ${petBasic.length} PET BASIC and ${bbcBasic.words.length} BBC BASIC reserved words.`);
