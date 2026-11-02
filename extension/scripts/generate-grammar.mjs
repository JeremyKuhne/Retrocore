// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { writeGenerated } from "./generated-file.mjs";

const extension = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const definitions = readFileSync(resolve(extension, "..", "src", "Retrocore.Cpu.M6502", "OpcodeTables.txt"), "utf8");
const variants = new Map();
const flowInstructions = new Set();
let current;
let overridden;
let description = false;
for (const original of definitions.split(/\r\n|\r|\n/)) {
    // [isa] and [forms] describe the family; only their flow classes matter here. Their patterns quote "#",
    // so their lines are not stripped of comments like opcode lines.
    if (description && /^flow\s/.test(original.trim())) {
        for (const name of original.replace(/#.*/, "").trim().split(/\s+/).slice(2)) flowInstructions.add(name.split(":")[0]);
        continue;
    }
    const line = original.replace(/#.*/, "").trim();
    if (line.length === 0) continue;
    const section = /^\[\s*(\w+)\s*(?::\s*(\w+)\s*)?\]$/.exec(line);
    if (section !== null) description = section[1] === "isa" || section[1] === "forms";
    if (description) continue;
    if (section !== null) {
        if (variants.has(section[1])) throw new Error(`Duplicate CPU section: ${line}`);
        const inherited = section[2] === undefined ? undefined : variants.get(section[2]);
        if (section[2] !== undefined && inherited?.size !== 256) throw new Error(`Incomplete base CPU: ${line}`);
        current = new Map(inherited);
        overridden = new Set();
        variants.set(section[1], current);
        continue;
    }
    const entry = /^([0-9A-Fa-f]{2})\s+(\w+)\s+(\w+)(?:\s+undocumented)?$/.exec(line);
    if (entry === null || current === undefined || overridden === undefined) throw new Error(`Invalid opcode entry: ${line}`);
    const code = Number.parseInt(entry[1], 16);
    if (overridden.has(code)) throw new Error(`Duplicate opcode entry: ${line}`);
    overridden.add(code);
    const mnemonic = /^(BBR|BBS|RMB|SMB)$/.test(entry[2]) ? entry[2] + ((code >> 4) & 7) : entry[2];
    current.set(code, { mnemonic, instruction: entry[2], mode: entry[3] });
}
for (const [variant, entries] of variants) {
    if (entries.size !== 256) throw new Error(`CPU ${variant} does not define all 256 opcodes.`);
}
if (variants.size === 0) throw new Error("No CPU definitions were found.");

const instructions = new Set();
const accumulator = new Set();
const flowMnemonics = new Set();
for (const entries of variants.values()) {
    for (const { mnemonic, instruction, mode } of entries.values()) {
        instructions.add(mnemonic);
        if (mode === "Accumulator") accumulator.add(mnemonic);
        if (flowInstructions.has(instruction)) flowMnemonics.add(mnemonic);
    }
}
// The instructions the description gives a flow class: branches, jumps, calls, returns, breaks and halts.
const flow = [...instructions].filter(name => flowMnemonics.has(name));
const ordinary = [...instructions].filter(name => !flow.includes(name) && !accumulator.has(name));

// The Z80's description lists opcodes with prefixes, split operands, literal forms and cycles; only its
// mnemonics and flow classes matter here.
const z80Definitions = readFileSync(resolve(extension, "..", "src", "Retrocore.Cpu.Z80", "Z80Isa.txt"), "utf8");
const z80Instructions = new Set();
const z80FlowInstructions = new Set();
let z80Section = "";
for (const original of z80Definitions.split(/\r\n|\r|\n/)) {
    const line = original.replace(/#.*/, "").trim();
    if (/^\[[^\]"]*\]$/.test(line)) {
        z80Section = line.slice(1, -1).trim();
        continue;
    }
    if (z80Section === "isa" && /^flow\s/.test(line)) {
        for (const name of line.split(/\s+/).slice(2)) z80FlowInstructions.add(name.split(":")[0]);
        continue;
    }
    if (z80Section === "isa" || z80Section === "forms" || line.length === 0) continue;
    const entry = /^(?:(?:[0-9A-F]{2}|\*)\s+)+([A-Z]+)\s+\S+(?:\s+(?:undocumented|t=[0-9/]+))*$/.exec(line);
    if (entry === null) throw new Error(`Invalid Z80 opcode entry: ${line}`);
    z80Instructions.add(entry[1]);
}
if (z80Instructions.size < 60) throw new Error("The Z80 description lists too few instructions.");
const z80Flow = [...z80Instructions].filter(name => z80FlowInstructions.has(name));
const z80Ordinary = [...z80Instructions].filter(name => !z80FlowInstructions.has(name));
const z80Registers = ["AF'", "AF", "BC", "DE", "HL", "IX", "IY", "IXH", "IXL", "IYH", "IYL", "SP", "A", "B", "C", "D", "E", "H", "L", "I", "R"];
const z80Conditions = ["NZ", "Z", "NC", "C", "PO", "PE", "P", "M"];
const alternatives = values => `(?i:${[...values].sort().join("|")})`;
const identifier = "[A-Za-z_][\\p{L}\\p{Mn}\\p{Nd}\\p{Pc}]*";
const cheapLocal = "@[\\p{L}\\p{Mn}\\p{Nd}\\p{Pc}]+";
const definition = `(?:${identifier}|${cheapLocal})`;
// Cheap locals cannot be qualified, so only ordinary identifiers follow ::.
const reference = `(?:(?:::)?${identifier}(?:::${identifier})*|${cheapLocal})`;
const boundary = "(?=[\\s;]|$)";
const operands = [{ include: "#comments" }, { include: "#literals" }, { include: "#anonymous-labels" }, { include: "#operators" }, { include: "#symbols" }];
const instructionRule = (names, scope, extra = [], registers = true) => ({
    begin: `\\G[ \\t]*(${alternatives(names)}(?:\\.[wW])?)${boundary}`,
    beginCaptures: { "1": { name: scope } },
    end: "$",
    patterns: [...extra, ...(registers ? [{ include: "#registers" }] : []), ...operands]
});
const z80InstructionRule = (names, scope, conditions) => ({
    begin: `\\G[ \\t]*(${alternatives(names)})${boundary}`,
    beginCaptures: { "1": { name: scope } },
    end: "$",
    patterns: [
        ...(conditions ? [{
            match: `\\G[ \\t]+(${alternatives(z80Conditions)})(?=[ \\t]*(?:,|;|$))`,
            captures: { "1": { name: "constant.language.condition.retrocore" } }
        }] : []),
        { include: "#z80-registers" },
        ...operands
    ]
});
const grammar = {
    $schema: "https://raw.githubusercontent.com/martinring/tmlanguage/master/tmlanguage.json",
    $comment: "Generated by scripts/generate-grammar.mjs from src/Retrocore.Cpu.M6502/OpcodeTables.txt and src/Retrocore.Cpu.Z80/Z80Isa.txt. Do not edit this file directly.",
    name: "Retrocore Assembly",
    scopeName: "source.retrocore",
    patterns: [{ include: "#merlin" }, { include: "#z80" }, { include: "#constant-definition" }, { include: "#statement" }],
    repository: {
        // From a .cpu Z80 line to the next .cpu of another CPU, statements use the Z80's mnemonics and registers.
        z80: {
            begin: `^(?=[ \\t]*(?i:\\.cpu)[ \\t]+(?i:Z80)${boundary})`,
            end: `^(?=[ \\t]*(?i:\\.cpu)[ \\t]+(?!(?i:Z80)${boundary}))`,
            patterns: [{ include: "#constant-definition" }, { include: "#z80-statement" }]
        },
        "z80-statement": {
            begin: `^(?=[ \\t]*\\S)[ \\t]*(?:(?:(${definition})(:)(?!:)|(:)(?![:+-]))[ \\t]*)?`,
            beginCaptures: {
                "1": { name: "entity.name.label.retrocore" },
                "2": { name: "punctuation.separator.label.retrocore" },
                "3": { name: "entity.name.label.retrocore" }
            },
            end: "$",
            patterns: [
                { include: "#directives" },
                z80InstructionRule(z80Flow, "keyword.control.flow.retrocore", true),
                z80InstructionRule(z80Ordinary, "keyword.other.opcode.retrocore", false),
                ...operands
            ]
        },
        "z80-registers": {
            patterns: [
                {
                    match: `(?<![\\w$.@'])(${alternatives(z80Registers)})(?![\\w'])`,
                    captures: { "1": { name: "variable.language.register.retrocore" } }
                },
                { match: "[\\[\\]]", name: "punctuation.section.brackets.retrocore" }
            ]
        },
        merlin: {
            begin: "\\A[ \\t]*;[ \\t]*(?i:retrocore:[ \\t]*dialect=merlin)[ \\t]*$",
            beginCaptures: { "0": { name: "comment.line.semicolon.retrocore" } },
            end: "(?!)",
            patterns: [
                { match: "^[*;].*$", name: "comment.line.semicolon.retrocore" },
                {
                    begin: "^(?=[ \\t]*\\S)(?:([^\\s;*]+)[ \\t]+|([^\\s;*]+)$)?[ \\t]*",
                    beginCaptures: {
                        "1": { name: "entity.name.label.retrocore" },
                        "2": { name: "entity.name.label.retrocore" }
                    },
                    end: "$",
                    patterns: [
                        {
                            begin: "\\G((?i:ASC|DCI|INV|FLS|REV|STR|HEX|DFB|DB|DA|DW|DDB|ADR|ADRL|DS|ORG|EQU|DUM|DEND|CHK|ERR|XC|MX|MAC|EOM|PMC|DO|ELSE|FIN|IF|LUP|PUT|USE|SAV|DSK|TYP|ENT|EXT)|<<<|>>>|--\\^|=)(?=[\\s;]|$)",
                            beginCaptures: { "1": { name: "keyword.control.directive.retrocore" } },
                            end: "$",
                            patterns: [{ include: "#literals" }, { include: "#operators" }, { include: "#symbols" }]
                        },
                        instructionRule(flow, "keyword.control.flow.retrocore"),
                        instructionRule(accumulator, "keyword.other.opcode.retrocore"),
                        instructionRule(ordinary, "keyword.other.opcode.retrocore"),
                        ...operands
                    ]
                }
            ]
        },
        "constant-definition": {
            begin: `^[ \\t]*(${definition})[ \\t]*(=|(?i:\\.set)${boundary})`,
            beginCaptures: {
                "1": { name: "variable.other.constant.definition.retrocore" },
                "2": { name: "keyword.operator.assignment.retrocore" }
            },
            end: "$",
            patterns: operands
        },
        statement: {
            begin: `^(?=[ \\t]*\\S)[ \\t]*(?:(?:(${definition})(:)(?!:)|(:)(?![:+-]))[ \\t]*)?`,
            beginCaptures: {
                "1": { name: "entity.name.label.retrocore" },
                "2": { name: "punctuation.separator.label.retrocore" },
                "3": { name: "entity.name.label.retrocore" }
            },
            end: "$",
            patterns: [
                { include: "#directives" },
                instructionRule(flow.filter(name => !/^BB[RS]/.test(name)), "keyword.control.flow.retrocore"),
                instructionRule(flow.filter(name => /^BB[RS]/.test(name)), "keyword.control.flow.retrocore", [], false),
                instructionRule(accumulator, "keyword.other.opcode.retrocore", [{
                    match: "\\G[ \\t]+([aA])(?=[ \\t]*(?:;|$))",
                    captures: { "1": { name: "variable.language.register.retrocore" } }
                }]),
                instructionRule(ordinary, "keyword.other.opcode.retrocore"),
                ...operands
            ]
        },
        directives: {
            patterns: [
                {
                    begin: `\\G[ \\t]*((?i:\\.cpu))${boundary}`,
                    beginCaptures: { "1": { name: "keyword.control.directive.retrocore" } },
                    end: "$",
                    patterns: [
                        { include: "#comments" },
                        { match: `\\b${alternatives([...variants.keys(), "65SC02", "Z80"])}\\b`, name: "constant.language.processor.retrocore" },
                        ...operands
                    ]
                },
                {
                    begin: `\\G[ \\t]*((?i:\\.rom))${boundary}`,
                    beginCaptures: { "1": { name: "keyword.control.directive.retrocore" } },
                    end: "$",
                    patterns: [
                        { match: `\\G[ \\t]+(${identifier}(?:\\.${identifier})+)`, captures: { "1": { name: "entity.name.type.retrocore" } } },
                        ...operands
                    ]
                },
                {
                    begin: `\\G[ \\t]*((?i:\\.set))${boundary}[ \\t]+(${definition})(?=[ \\t]*,)`,
                    beginCaptures: {
                        "1": { name: "keyword.control.directive.retrocore" },
                        "2": { name: "variable.other.constant.definition.retrocore" }
                    },
                    end: "$",
                    patterns: operands
                },
                ...["proc", "scope"].map(directive => ({
                    begin: `\\G[ \\t]*((?i:\\.${directive}))${boundary}[ \\t]+(${identifier})${boundary}`,
                    beginCaptures: {
                        "1": { name: "keyword.control.directive.retrocore" },
                        "2": { name: directive === "proc" ? "entity.name.label.retrocore" : "entity.name.namespace.retrocore" }
                    },
                    end: "$",
                    patterns: operands
                })),
                {
                    begin: `\\G[ \\t]*((?i:\\.(?:equ|set|byte|word|dword|res|org|logicalorg|align|dum|dend|checksum|assert|export|hiascii|section|include|incbin|macro|endmacro|local|exitmacro|if|elseif|else|endif|ifdef|ifndef|ifblank|repeat|endrepeat|proc|endproc|scope|endscope|setcpu|p02|pc02|psc02|segment|code|rodata|data|bss|zeropage|addr|endmac|endrep|define|undefine|struct|endstruct|union|endunion|enum|endenum|tag|charmap|asciiz|byt|dbyt|faraddr|lobytes|hibytes|ifconst|ifnconst|ifnblank|ifp02|ifp02x|ifpsc02|ifpc02|ifpwc02|ifpce02|ifp816|ifp4510|ifp45gs02|ifp6280|ifpdtv|ifpm740|ifpsweet16|ifref|ifnref|feature|debuginfo|list|smart|out|warning|error|fatal|global|globalzp|import|importzp|exportzp|macpack|reloc|mac)))${boundary}`,
                    beginCaptures: { "1": { name: "keyword.control.directive.retrocore" } },
                    end: "$",
                    patterns: operands
                }
            ]
        },
        comments: {
            patterns: [
                {
                    // ;; documentation comments (docs/DocComments.md): sections, links, references and code.
                    begin: "(;;)",
                    beginCaptures: { "1": { name: "punctuation.definition.comment.retrocore" } },
                    end: "$",
                    name: "comment.line.documentation.retrocore",
                    patterns: [
                        {
                            match: "\\G[ \\t]*((?i:In|Out|Flags|Errors|Uses|Keeps|Entry|Calls|Cycles|Stack|Model|Parameters|Members|Example|See(?: also)?|Deprecated|Inherit|Include)):",
                            captures: { "1": { name: "keyword.other.documentation.retrocore" } }
                        },
                        { match: "<(?![\\s=\\d])[^<>]+>", name: "markup.underline.link.retrocore" },
                        { match: "\\{[\\w@.:]+\\}", name: "variable.parameter.documentation.retrocore" },
                        { match: "`[^`]*`", name: "markup.inline.raw.retrocore" }
                    ]
                },
                {
                    match: "(;).*$",
                    name: "comment.line.semicolon.retrocore",
                    captures: { "1": { name: "punctuation.definition.comment.retrocore" } }
                }
            ]
        },
        literals: {
            patterns: [
                {
                    begin: "'",
                    end: "'|(?=$)",
                    name: "string.quoted.single.retrocore",
                    beginCaptures: { "0": { name: "punctuation.definition.string.begin.retrocore" } },
                    endCaptures: { "0": { name: "punctuation.definition.string.end.retrocore" } }
                },
                {
                    begin: "\"",
                    end: "\"|(?=$)",
                    name: "string.quoted.double.retrocore",
                    beginCaptures: { "0": { name: "punctuation.definition.string.begin.retrocore" } },
                    endCaptures: { "0": { name: "punctuation.definition.string.end.retrocore" } }
                },
                { match: "(?<![\\w$])(?:\\$[0-9A-Fa-f]+|0[xX][0-9A-Fa-f]+)\\b", name: "constant.numeric.hex.retrocore" },
                { match: "(?<!\\w)%[01]+\\b", name: "constant.numeric.binary.retrocore" },
                { match: "(?<!\\w)[0-9]+\\b", name: "constant.numeric.decimal.retrocore" }
            ]
        },
        operators: {
            patterns: [
                { match: "#", name: "keyword.operator.immediate.retrocore" },
                { match: "(?<![\\w$.])(?:[aAzZ]:(?!:)|!(?!=))", name: "keyword.operator.width.retrocore" },
                { match: "(?i:\\.(?:not|and|or|xor|mod|lobyte|hibyte|bankbyte|paramcount|sizeof|time|version|defined|def|definedmacro|strlen|strat|ident|concat|string|sprintf|min|max|loword|hiword|match|xmatch|tcount|blank|left|right|mid|const|cpu))\\b", name: "keyword.operator.retrocore" },
                { match: "==|!=|<=|>=|<<|>>|&&|\\|\\||[=+*/&|^~<>-]", name: "keyword.operator.retrocore" },
                { match: "[()]", name: "punctuation.section.parens.retrocore" },
                { match: ",", name: "punctuation.separator.operand.retrocore" }
            ]
        },
        registers: {
            match: "(?<=,)[ \\t]*([XxYy])(?=[ \\t]*(?:\\)|;|$))",
            captures: { "1": { name: "variable.language.register.retrocore" } }
        },
        "anonymous-labels": {
            match: ":(?:\\++|-+)",
            name: "variable.other.symbol.retrocore"
        },
        symbols: {
            match: reference,
            name: "variable.other.symbol.retrocore"
        }
    }
};

const output = resolve(extension, "syntaxes", "retrocore.tmLanguage.json");
writeGenerated(output, JSON.stringify(grammar, null, 2) + "\n", "Assembly grammar is stale. Run npm run generate:grammar.");
console.log(`Retrocore grammar: ${instructions.size} 6502 family mnemonics from ${variants.size} complete CPU maps and ${z80Instructions.size} Z80 mnemonics.`);
