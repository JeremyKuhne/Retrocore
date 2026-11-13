// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Generates the BASIC grammars from the reserved word tables in Retrocore.Basic, which a test checks against the
// ROMs. Each dialect's words are tried in token order at every position, as the ROM's tokenizer tries them, so a
// word inside a name (OR in SCORE) is highlighted where BASIC finds it. Business BASIC takes a word only between
// separators, so its words are highlighted only there.

import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { writeGenerated } from "./generated-file.mjs";

const extension = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const library = resolve(extension, "..", "src", "Retrocore.Basic");

// A table's words, without the placeholders Business BASIC's lists keep empty.
function keywords(file, field = "s_keywords") {
    const source = readFileSync(resolve(library, file), "utf8");
    const table = new RegExp(`${field}\\s*=\\s*\\[([\\s\\S]*?)\\];`).exec(source);
    if (table === null) throw new Error(`No ${field} table in ${file}.`);
    return [...table[1].matchAll(/"((?:[^"\\]|\\.)*)"/g)].map(match => match[1]).filter(word => word.length > 0);
}

const flow = new Set(["END", "FOR", "NEXT", "GOTO", "RUN", "IF", "GOSUB", "RETURN", "STOP", "ON", "THEN", "TO", "STEP",
    "ELSE", "ONERR", "RESUME", "POP", "CONT", "ERROR"]);
const operators = new Set(["+", "-", "*", "/", "^", "[", "AND", "OR", "NOT", ">", "=", "<", "MOD", "DIV", "#", "<>", ">=",
    "<="]);
const functions = new Set(["SGN", "INT", "ABS", "USR", "FRE", "PDL", "POS", "SQR", "RND", "LOG", "EXP", "COS", "SIN",
    "TAN", "ATN", "PEEK", "LEN", "VAL", "ASC", "INP", "CVI", "CVS", "CVD", "EOF", "LOC", "LOF", "CINT", "CSNG", "CDBL",
    "FIX", "ERL", "ERR", "MEM", "POINT", "VARPTR", "INSTR", "FN", "SCRN", "RNDX", "HPOS", "VPOS", "ERRLIN", "KBD",
    "EXFN.", "EXFN%."]);

const escape = text => text.replace(/[\\^$.*+?()[\]{}|]/g, "\\$&");

// A word as the tokenizer matches it: GOTO may have spaces between GO and TO; AppleSoft's AT is not taken before N
// (ATN) or O (A TO).
function pattern(word) {
    if (word === "GOTO") return "G\\s*O\\s*T\\s*O";
    if (word === "AT") return "AT(?![NnOo])";
    return escape(word);
}

// A Business BASIC word, which needs a separator before it, and after it too unless it ends in one, as ( or . does;
// FN is taken before its function's name, as in FNA(2).
const before = "(?<![A-Za-z0-9.])";
const after = "(?![A-Za-z0-9.])";
function separated(word) {
    return /[A-Za-z0-9$]$/.test(word) && word !== "FN" ? `${before}${pattern(word)}${after}` : `${before}${pattern(word)}`;
}

// Integer BASIC's names are any length, letters then letters and digits, and Business BASIC's may also hold dots and
// end in & for a long integer; the Microsoft BASICs' are read by two.
function grammar(dialect, name, words, { longNames = false, business = false } = {}) {
    const scope = `retrocore-${dialect}`;
    // One alternation in token order, as the tokenizer tries the words, with a group per word for its scope.
    const reserved = words.filter(word => word !== "REM" && word !== "'" && word !== "DATA");
    const variable = business ? "[A-Za-z][A-Za-z0-9.]*[$%&]?" : longNames ? "[A-Za-z][A-Za-z0-9]*\\$?" : "[A-Za-z][0-9]*[$%!#]?";
    const remark = words.includes("'") ? "(?i:(REM)|(')).*$"
        : business ? `(?i:${before}(REM)${after}|(!)).*$`
            : "(?i:(REM)).*$";
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
                    { match: `(?i:${reserved.map(word => `(${business ? separated(word) : pattern(word)})`).join("|")})`, captures },
                    { match: "\\?", name: `keyword.other.${scope}` },
                    { match: "(?:\\d+\\.?\\d*|\\.\\d+)(?:[EeDd][+-]?\\d+)?", name: `constant.numeric.${scope}` },
                    { match: variable, name: `variable.other.${scope}` },
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
                begin: business ? `(?i:${before}(DATA)${after})` : "(?i:(DATA))",
                beginCaptures: { "1": { name: `keyword.other.${scope}` } },
                end: "(?=:|$)",
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
const union = [...appleSoft, ...level2.filter(word => !appleSoft.includes(word))];
const outputs = [
    ["applesoft.tmLanguage.json", grammar("applesoft", "AppleSoft BASIC", appleSoft)],
    ["level2.tmLanguage.json", grammar("level2", "Level II BASIC", level2)],
    ["integer.tmLanguage.json", grammar("integer", "Integer BASIC", integer, { longNames: true })],
    ["business.tmLanguage.json", grammar("business", "Business BASIC", business, { business: true })],
    ["basic.tmLanguage.json", grammar("basic", "Retrocore BASIC", union)]
];
for (const [file, content] of outputs) {
    const output = resolve(extension, "syntaxes", file);
    writeGenerated(output, JSON.stringify(content, null, 2) + "\n", `${file} is stale. Run npm run generate:grammar.`);
}
console.log(`BASIC grammars: ${appleSoft.length} AppleSoft, ${level2.length} Level II, ${integer.length} Integer BASIC and `
    + `${business.length} Business BASIC reserved words.`);
