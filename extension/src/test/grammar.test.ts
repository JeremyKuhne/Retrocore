// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import * as path from "node:path";
import { after, before, test } from "node:test";
import { loadWASM, OnigScanner, OnigString } from "vscode-oniguruma";
import { INITIAL, IGrammar, IToken, parseRawGrammar, Registry } from "vscode-textmate";

const extension = path.resolve(__dirname, "../..");
const root = path.resolve(extension, "..");
const scope = {
    opcode: "keyword.other.opcode.retrocore",
    flow: "keyword.control.flow.retrocore",
    directive: "keyword.control.directive.retrocore",
    label: "entity.name.label.retrocore",
    constant: "variable.other.constant.definition.retrocore",
    symbol: "variable.other.symbol.retrocore",
    register: "variable.language.register.retrocore",
    hex: "constant.numeric.hex.retrocore",
    binary: "constant.numeric.binary.retrocore",
    decimal: "constant.numeric.decimal.retrocore",
    string: "string.quoted.single.retrocore",
    comment: "comment.line.semicolon.retrocore"
};
let grammar: IGrammar;
let registry: Registry;

before(async () => {
    await loadWASM(readFileSync(require.resolve("vscode-oniguruma/release/onig.wasm")));
    registry = new Registry({
        onigLib: Promise.resolve({
            createOnigScanner: patterns => new OnigScanner(patterns),
            createOnigString: text => new OnigString(text)
        }),
        loadGrammar: async name => name === "source.retrocore"
            ? parseRawGrammar(readFileSync(path.join(extension, "syntaxes", "retrocore.tmLanguage.json"), "utf8"), "retrocore.json")
            : null
    });
    const loaded = await registry.loadGrammar("source.retrocore");
    if (loaded === null) throw new Error("The native assembly grammar was not loaded.");
    grammar = loaded;
});

after(() => registry?.dispose());

function tokens(text: string): IToken[] {
    const result = grammar.tokenizeLine(text, INITIAL);
    assert.equal(result.stoppedEarly, false);
    return result.tokens;
}

function assertScope(text: string, value: string, expected: string, occurrence = 0): void {
    let start = -1;
    for (let count = 0; count <= occurrence; count++) start = text.indexOf(value, start + 1);
    assert.notEqual(start, -1, `Missing token ${value} in ${text}`);
    for (let index = start; index < start + value.length; index++) {
        const token = tokens(text).find(item => item.startIndex <= index && item.endIndex > index);
        assert.ok(token?.scopes.includes(expected), `${text}: ${value} expected ${expected}, got ${token?.scopes.join(" ")}`);
    }
}

function assertNoInstruction(text: string, value: string): void {
    const start = text.indexOf(value);
    assert.notEqual(start, -1);
    const token = tokens(text).find(item => item.startIndex <= start && item.endIndex > start);
    assert.ok(!token?.scopes.some(name => name === scope.opcode || name === scope.flow),
        `${value} was incorrectly treated as an instruction in ${text}`);
}

test("native directives, processor names and ROM declarations have dedicated scopes", () => {
    for (const directive of [
        "cpu", "rom", "equ", "set", "byte", "word", "dword", "res", "org",
        "logicalorg", "align", "dum", "dend", "checksum", "assert", "export", "hiascii", "section",
        "include", "incbin", "macro", "endmacro", "local", "exitmacro", "if", "elseif", "else", "endif",
        "ifdef", "ifndef", "ifblank", "repeat", "endrepeat", "proc", "endproc", "scope", "endscope"
    ]) {
        assertScope(`  .${directive} operand`, "." + directive, scope.directive);
        assertScope(`Here: .${directive.toUpperCase()} operand`, "." + directive.toUpperCase(), scope.directive);
    }
    for (const cpu of ["Mos6502", "Wdc65C02", "Rockwell65C02", "65SC02"]) {
        assertScope(`.cpu ${cpu}`, cpu, "constant.language.processor.retrocore");
    }
    assertScope(".rom Retrocore.Machine.Firmware, $C700, $100", "Retrocore.Machine.Firmware", "entity.name.type.retrocore");
    assertScope(".rom Retrocore.Machine.Firmware, $C700, $100", "$C700", scope.hex);
});

test("every mnemonic from every CPU map, including numbered bits and undocumented names, is highlighted", () => {
    const definitions = readFileSync(path.join(root, "src", "Retrocore.Cpu.M6502", "OpcodeTables.txt"), "utf8");
    let entries = 0;
    for (const line of definitions.split(/\r\n|\r|\n/)) {
        const entry = /^([0-9A-Fa-f]{2})\s+(\w+)\s+(\w+)(?:\s+undocumented)?\s*$/.exec(line);
        if (entry === null) continue;
        const code = Number.parseInt(entry[1], 16);
        const mnemonic = ["BBR", "BBS", "RMB", "SMB"].includes(entry[2]) ? entry[2] + ((code >> 4) & 7) : entry[2];
        for (const spelling of [mnemonic, mnemonic.toLowerCase()]) {
            for (const prefix of ["    ", "Entry: "]) {
                const text = prefix + spelling + " $42";
                const token = tokens(text).find(item => item.startIndex <= prefix.length && item.endIndex > prefix.length);
                assert.ok(token?.scopes.some(name => name === scope.opcode || name === scope.flow),
                    `Opcode ${code.toString(16)} ${text} was not highlighted as an instruction.`);
            }
        }
        entries++;
    }
    assert.ok(entries >= 512, "The canonical table fixture must include both full CPU maps.");
    for (const name of ["JAM", "XAA", "AHX", "SHX", "SHY", "TAS", "LAS", "BBR7", "SMB0"]) {
        assert.ok(tokens("  " + name).some(token => token.scopes.includes(scope.opcode) || token.scopes.includes(scope.flow)), name);
    }
});

test("control flow has a distinct theme-compatible instruction scope", () => {
    for (const name of ["BNE", "BRA", "BBR3", "BBS7", "BRK", "JMP", "JSR", "RTS", "RTI", "JAM", "WAI", "STP"]) {
        assertScope(`  ${name} Target`, name, scope.flow);
    }
    assertScope("  LDA Target", "LDA", scope.opcode);
});

test("labels and assignments take priority over instruction-looking identifiers", () => {
    assertScope("LDA: LDX #1", "LDA", scope.label);
    assertScope("LDA: LDX #1", "LDX", scope.opcode);
    assertScope("JSR = $42", "JSR", scope.constant);
    assertScope("A = $10", "A", scope.constant);
    assertScope("N .set 3", "N", scope.constant);
    assertScope(".set N, 3", "N", scope.constant);
    assertScope("Byte_\u00E9: LDA Byte_\u00E9", "Byte_\u00E9", scope.label);
    assertScope("Byte_\u00E9: LDA Byte_\u00E9", "Byte_\u00E9", scope.symbol, 1);
    for (const text of ["LDA:", "LDA = 1", "LDA_LABEL:", "  JSR LDA", "  LDA LDA_LABEL", "; LDA #1", ".byte LDA, X"]) {
        assertNoInstruction(text, text.includes("JSR LDA") ? "LDA" : text.includes(".byte") ? "LDA" : text.includes("LDA LDA_LABEL") ? "LDA_LABEL" : "LDA");
    }
    assert.equal(tokens("  LDAX #1").some(token => token.scopes.includes(scope.opcode)), false);
    assertScope(".export LDA", "LDA", scope.symbol);
});

test("registers are contextual rather than arbitrary one-letter symbols", () => {
    for (const text of ["  LDA ($42,X)", "  LDA $1234,X", "  LDA ($42),Y", "  LDA $42, y"]) {
        const register = text.includes("X") ? "X" : text.includes("Y") ? "Y" : "y";
        assertScope(text, register, scope.register);
    }
    for (const mnemonic of ["ASL", "LSR", "ROL", "ROR", "INC", "DEC"]) {
        assertScope(`  ${mnemonic} A`, "A", scope.register, mnemonic.includes("A") ? 1 : 0);
    }
    for (const text of ["  LDA A", "  LDA X", "  JSR Y", "  ASL A+0", ".byte X, Y, A"]) {
        assert.equal(tokens(text).some(token => token.scopes.includes(scope.register)), false, text);
    }
});

test("lexical names, cheap locals and anonymous labels retain complete token scopes", () => {
    assertScope(".proc Entry", "Entry", scope.label);
    assertScope(".scope Inner", "Inner", "entity.name.namespace.retrocore");
    for (const name of ["@loop", "@1loop"]) {
        assertScope(`${name}: bne ${name}`, name, scope.label);
        assertScope(`${name}: bne ${name}`, name, scope.symbol, 1);
        assertScope(`.set ${name}, 1`, name, scope.constant);
    }
    for (const name of ["Outer::Inner::Value", "::Root", "a::Value", "z::Value"]) {
        assertScope(`lda ${name}`, name, scope.symbol);
        assert.equal(tokens(`lda ${name}`).some(token => token.scopes.includes("keyword.operator.width.retrocore")), false);
    }
    assert.equal(tokens("lda Outer::@loop").some(token => token.endIndex - token.startIndex === "Outer::@loop".length), false);
    assertScope(":bne :-", ":", scope.label);
    assertScope(":bne :-", "bne", scope.flow);
    for (const name of [":+", ":++", ":-", ":---"]) assertScope(`bne ${name}`, name, scope.symbol);
    assertScope("bbr0 $10,Y", "Y", scope.symbol);
    assertScope('.byte "@loop :+"', "@loop", "string.quoted.double.retrocore");
    assertScope("; ::Root", "::Root", scope.comment);
});

test("forced-width suffixes and prefixes are part of the instruction syntax", () => {
    assertScope("  LDA.W $12", "LDA.W", scope.opcode);
    assertScope("  jmp.w Target", "jmp.w", scope.flow);
    assertScope("  LDA a:$12,X", "a:", "keyword.operator.width.retrocore");
    assertScope("  LDA a:$12,X", "$12", scope.hex);
    assertScope("  LDA A:Zero", "Zero", scope.symbol);
    assertScope("  LDA z:Zero", "z:", "keyword.operator.width.retrocore");
    assertScope("  LDA !Zero", "!", "keyword.operator.width.retrocore");
    assertScope("  LDA a+0", "a", scope.symbol);
    assertScope(".assert Zero != 1", "!=", "keyword.operator.retrocore");
    assert.equal(tokens("  LDA.WX $12").some(token => token.scopes.includes(scope.opcode)), false);
});

test("named native expression operators remain distinct from symbols and literals", () => {
    for (const operator of [".not", ".and", ".or", ".xor", ".mod", ".lobyte", ".hibyte", ".bankbyte", ".paramcount", "&&", "||"]) {
        assertScope(`.byte 1 ${operator} (Value)`, operator, "keyword.operator.retrocore");
    }
    assertScope(".byte bankbyte", "bankbyte", scope.symbol);
    assertScope('.byte ".and"', ".and", "string.quoted.double.retrocore");
});

test("ca65-tagged inputs highlight the supported directives and builtins", () => {
    for (const directive of ["setcpu", "p02", "pc02", "psc02", "segment", "code", "rodata", "data", "bss", "zeropage", "addr", "endmac", "endrep"]) {
        assertScope(`.${directive} operand`, "." + directive, scope.directive);
    }
    for (const builtin of [".sizeof", ".time", ".version"]) {
        assertScope(`.dword ${builtin}`, builtin, "keyword.operator.retrocore");
    }
    assertScope('.segment "CODE"', "CODE", "string.quoted.double.retrocore");
});

test("ca65 SDK type, text and conditional directives have directive scopes", () => {
    for (const directive of ["define", "undefine", "struct", "endstruct", "union", "endunion", "enum", "endenum",
        "tag", "charmap", "asciiz", "byt", "dbyt", "faraddr", "lobytes", "hibytes",
        "ifconst", "ifnconst", "ifnblank", "ifpc02", "ifp02", "ifp816", "out", "warning", "error", "fatal",
        "global", "globalzp", "import", "importzp", "exportzp", "macpack", "reloc", "mac"]) {
        assertScope(`.${directive} operand`, "." + directive, scope.directive);
    }
    for (const builtin of [".defined", ".def", ".strlen", ".ident", ".concat", ".string"]) {
        assertScope(`.byte ${builtin}(Value)`, builtin, "keyword.operator.retrocore");
    }
});

test("Merlin pragma selects column-zero labels and undotted directive scopes", () => {
    const state = grammar.tokenizeLine("; retrocore: dialect=merlin", INITIAL).ruleStack;
    for (const [line, value, expected] of [
        ["Entry   LDA #1", "Entry", scope.label],
        ["Entry   LDA #1", "LDA", scope.opcode],
        [":loop   DEX", ":loop", scope.label],
        ["        ASC \"READY\"", "ASC", scope.directive],
        ["Emit    MAC", "MAC", scope.directive],
        ["        PMC Emit,1;2", "PMC", scope.directive],
        ["* comment", "comment", scope.comment]
    ]) {
        const start = line.indexOf(value);
        const result = grammar.tokenizeLine(line, state);
        const token = result.tokens.find(item => item.startIndex <= start && item.endIndex > start);
        assert.ok(token?.scopes.includes(expected), `${line}: expected ${expected}, got ${token?.scopes.join(" ")}`);
    }
});

test("hex, binary, decimal, character literals, operators and comments stay distinct", () => {
    assertScope("  LDA #0X1F", "0X1F", scope.hex);
    const text = "  LDA #<($ABCD + 0x10 + %1010 + 42) ; LDY #$88";
    assertScope(text, "$ABCD", scope.hex);
    assertScope(text, "0x10", scope.hex);
    assertScope(text, "%1010", scope.binary);
    assertScope(text, "42", scope.decimal);
    assertScope(text, "#", "keyword.operator.immediate.retrocore");
    assertScope(text, "+", "keyword.operator.retrocore");
    assertScope(text, "LDY", scope.comment);
    assertScope(".byte ';', 'X', '\"' ; actual comment", ";", scope.string);
    assertScope(".byte ';', 'X', '\"' ; actual comment", "X", scope.string);
    assertScope(".byte ';', 'X', '\"' ; actual comment", "actual comment", scope.comment);
    assertScope('.byte "LDA;X" ; JSR', "LDA", "string.quoted.double.retrocore");
    assertScope('.byte "LDA;X" ; JSR', "JSR", scope.comment);
    assertNoInstruction('.byte "LDA;X"', "LDA");
    assertScope("label: .byte '(', ')', ';', ','", ";", scope.string);
    assertScope("  LDA (Address+1),X", "Address", scope.symbol);
});

test("unfinished strings and comments cannot leak highlighting to the next physical line", () => {
    for (const first of ['.byte "unfinished', ".byte 'unfinished", "; comment"]) {
        const initial = grammar.tokenizeLine(first, INITIAL);
        const next = grammar.tokenizeLine("  LDA #1", initial.ruleStack);
        assert.ok(next.tokens.some(token => token.scopes.includes(scope.opcode)), first);
        assert.equal(next.tokens.some(token => token.scopes.includes(scope.comment)
            || token.scopes.includes(scope.string) || token.scopes.includes("string.quoted.double.retrocore")), false);
    }
});

test("the actual slot-seven native firmware tokenizes across lines without losing instruction positions", () => {
    const source = readFileSync(path.join(root, "src", "Retrocore.Machines.Apple2", "Roms", "Slot7.rom.asm"), "utf8");
    let state = INITIAL;
    let instructions = 0;
    for (const line of source.split(/\r\n|\r|\n/)) {
        const result = grammar.tokenizeLine(line, state);
        assert.equal(result.stoppedEarly, false);
        state = result.ruleStack;
        if (result.tokens.some(token => token.scopes.includes(scope.opcode) || token.scopes.includes(scope.flow))) instructions++;
    }
    assert.ok(instructions > 30, "The native firmware must exercise real instruction tokenization.");
});

/** The keys each JSON object repeats: JSON.parse keeps the last silently, so VS Code would see only one. */
function duplicateKeys(json: string): string[] {
    const duplicates: string[] = [];
    const objects: (Set<string> | undefined)[] = [];
    for (let index = 0; index < json.length; index++) {
        const character = json[index];
        if (character === "{") objects.push(new Set());
        else if (character === "[") objects.push(undefined);
        else if (character === "}" || character === "]") objects.pop();
        else if (character === "\"") {
            let end = index + 1;
            while (json[end] !== "\"") end += json[end] === "\\" ? 2 : 1;
            const text = json.slice(index + 1, end);
            index = end;
            let next = end + 1;
            while (/\s/.test(json[next])) next++;
            const keys = objects.at(-1);
            if (json[next] === ":" && keys !== undefined) {
                if (keys.has(text)) duplicates.push(text);
                keys.add(text);
            }
        }
    }

    return duplicates;
}

test("the manifest repeats no key in any object", () => {
    assert.deepEqual(duplicateKeys('{"a": 1, "b": {"a": 2}, "c": [{"a": 3}, {"a": 4}]}'), []);
    assert.deepEqual(duplicateKeys('{"a": 1, "b": "a:", "a": 2}'), ["a"]);
    assert.deepEqual(duplicateKeys(readFileSync(path.join(extension, "package.json"), "utf8")), []);
});

test("manifest keeps highlighting declarative and debugger-compatible, and claims .asm and .mac but not .s", () => {
    const manifest = JSON.parse(readFileSync(path.join(extension, "package.json"), "utf8"));
    const language = manifest.contributes.languages.find((item: { id: string }) => item.id === "retrocore-asm");
    assert.deepEqual(language.extensions, [".asm", ".retrocore.asm", ".rom.asm"]);
    const macro10 = manifest.contributes.languages.find((item: { id: string }) => item.id === "retrocore-macro10");
    assert.deepEqual(macro10.extensions, [".mac"]);
    assert.ok(manifest.contributes.debuggers[0].languages.includes(language.id));
    assert.ok(!manifest.activationEvents.includes("onLanguage:retrocore-asm"), "No explicit activation is needed for grammar registration.");
    assert.equal(manifest.contributes.themes, undefined, "Do not replace the user's theme.");
    const configuration = JSON.parse(readFileSync(path.join(extension, "language-configuration.json"), "utf8"));
    assert.equal(configuration.comments.lineComment, ";");
    assert.equal(configuration.comments.blockComment, undefined);
    assert.deepEqual(configuration.brackets, [["(", ")"]]);
});

test(";; documentation comments highlight sections, links, references and code", () => {
    const documentation = "comment.line.documentation.retrocore";
    assertScope(";; Plots one block; see <SCRN> and `lda`.", "Plots one block", documentation);
    assertScope(";; Plots one block; see <SCRN> and `lda`.", "<SCRN>", "markup.underline.link.retrocore");
    assertScope(";; Plots one block; see <SCRN> and `lda`.", "`lda`", "markup.inline.raw.retrocore");
    assertScope(";; In:    A = row, Y = {COLUMN}", "In", "keyword.other.documentation.retrocore");
    assertScope(";; In:    A = row, Y = {COLUMN}", "{COLUMN}", "variable.parameter.documentation.retrocore");
    assertScope("KEY_CR = $8D ;; Return, A < 10", "Return", documentation);
    assertScope("    lda #1 ; $F800 ordinary", "ordinary", scope.comment);
    assert.ok(!tokens("    lda #1 ; In: x").some(token => token.scopes.includes("keyword.other.documentation.retrocore")));
});

// Tokenizes lines in order, so a region that a .cpu line opens carries to the following lines.
function lineTokens(lines: string[]): IToken[][] {
    let state = INITIAL;
    return lines.map(line => {
        const result = grammar.tokenizeLine(line, state);
        state = result.ruleStack;
        return result.tokens;
    });
}

function scopeAt(line: string, tokensOfLine: IToken[], value: string): string[] {
    const start = line.indexOf(value);
    assert.notEqual(start, -1, `Missing token ${value} in ${line}`);
    return tokensOfLine.find(token => token.startIndex <= start && token.endIndex > start)?.scopes ?? [];
}

test("after .cpu Z80, Z80 mnemonics, registers and conditions are highlighted until another .cpu", () => {
    const lines = [
        ".cpu Z80",
        "Start:  LD A,[IX+5]",
        "        EX AF,AF' ; swap",
        "        JR NZ,Start",
        "        DJNZ Start",
        "        SLL B",
        ".cpu Mos6502",
        "        LDA B"
    ];
    const result = lineTokens(lines);
    assert.ok(scopeAt(lines[0], result[0], "Z80").includes("constant.language.processor.retrocore"));
    assert.ok(scopeAt(lines[1], result[1], "LD").includes(scope.opcode));
    assert.ok(scopeAt(lines[1], result[1], "IX").includes(scope.register));
    assert.ok(scopeAt(lines[1], result[1], "A,").includes(scope.register));
    assert.ok(scopeAt(lines[2], result[2], "AF'").includes(scope.register));
    assert.ok(scopeAt(lines[2], result[2], "swap").includes(scope.comment), "AF' does not open a string");
    assert.ok(scopeAt(lines[3], result[3], "JR").includes(scope.flow));
    assert.ok(scopeAt(lines[3], result[3], "NZ").includes("constant.language.condition.retrocore"));
    assert.ok(scopeAt(lines[4], result[4], "DJNZ").includes(scope.flow));
    assert.ok(scopeAt(lines[5], result[5], "SLL").includes(scope.opcode));
    assert.ok(scopeAt(lines[7], result[7], "LDA").includes(scope.opcode));
    assert.ok(!scopeAt(lines[7], result[7], "B").includes(scope.register), "6502 operands keep their own rules");
});

test("after .cpu I8080 or I8085, Intel mnemonics and registers are highlighted until another .cpu", () => {
    const lines = [
        ".cpu I8080",
        "Entry:  INR M",
        "        LXI SP,$F000",
        "        PUSH PSW",
        "        JNZ Entry",
        ".cpu I8085",
        "        RIM",
        "        CC Entry",
        ".cpu Mos6502",
        "        LDA M"
    ];
    const result = lineTokens(lines);
    assert.ok(scopeAt(lines[0], result[0], "I8080").includes("constant.language.processor.retrocore"));
    assert.ok(scopeAt(lines[1], result[1], "INR").includes(scope.opcode));
    assert.ok(scopeAt(lines[1], result[1], "M").includes(scope.register));
    assert.ok(scopeAt(lines[2], result[2], "SP").includes(scope.register));
    assert.ok(scopeAt(lines[3], result[3], "PSW").includes(scope.register));
    assert.ok(scopeAt(lines[4], result[4], "JNZ").includes(scope.flow));
    assert.ok(scopeAt(lines[6], result[6], "RIM").includes(scope.opcode));
    assert.ok(scopeAt(lines[7], result[7], "CC").includes(scope.flow));
    assert.ok(!scopeAt(lines[9], result[9], "M").includes(scope.register));
});

test("after .cpu M6809, M6809 mnemonics, aliases and registers are highlighted until another .cpu", () => {
    const lines = [
        ".cpu M6809",
        "Entry:  LDS #$2000",
        "        LEAX -2,U",
        "        LDA [D,PCR]",
        "        PSHS CC,A,B,DP,X,Y,U,PC",
        "        LBHS Entry",
        ".cpu Mos6502",
        "        LDA U"
    ];
    const result = lineTokens(lines);
    assert.ok(scopeAt(lines[0], result[0], "M6809").includes("constant.language.processor.retrocore"));
    assert.ok(scopeAt(lines[1], result[1], "LDS").includes(scope.opcode));
    assert.ok(scopeAt(lines[2], result[2], "LEAX").includes(scope.opcode));
    assert.ok(scopeAt(lines[2], result[2], "U").includes(scope.register));
    assert.ok(scopeAt(lines[3], result[3], "D,").includes(scope.register));
    assert.ok(scopeAt(lines[3], result[3], "PCR").includes(scope.register));
    assert.ok(scopeAt(lines[4], result[4], "PSHS").includes(scope.opcode));
    assert.ok(scopeAt(lines[4], result[4], "DP").includes(scope.register));
    assert.ok(scopeAt(lines[5], result[5], "LBHS").includes(scope.flow));
    assert.ok(!scopeAt(lines[7], result[7], "U").includes(scope.register));
});
