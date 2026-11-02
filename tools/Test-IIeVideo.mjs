// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Compile the unchanged DHGR lookup function from the externally cached, pinned MIT oracle.
// Input: 192 rows of 80 interleaved auxiliary/main bytes. Output: base64 560x192 RGBA.
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { execFileSync } from "node:child_process";

const require = createRequire(new URL("../extension/package.json", import.meta.url));
const ts = require("typescript");
const { build } = require("esbuild");
const root = join(process.env.RETROCORE_CACHE ?? join(process.env.USERPROFILE ?? "", "Retrocore"), "m1-dependencies", "apple2ts");
const pin = "ca16c7f487d5980003a2fa87ffc60bbbf3fc8ee3";
if (execFileSync("git", ["--no-pager", "-C", root, "rev-parse", "HEAD"], { encoding: "utf8" }).trim() !== pin) {
    throw new Error("The Apple2TS cache does not match the M1 pin. Run tools\\Fetch-M1Dependencies.ps1.");
}
const filename = join(root, "src", "ui", "graphics.ts");
const source = ts.createSourceFile(filename, readFileSync(filename, "utf8"), ts.ScriptTarget.Latest, true);
const declaration = source.statements.find(statement => ts.isVariableStatement(statement)
    && statement.declarationList.declarations.some(value => value.name.getText(source) === "getDoubleHiresColors"));
if (!declaration) throw new Error("Pinned Apple2TS DHGR lookup function was not found.");
const implementation = ts.createPrinter().printNode(ts.EmitHint.Unspecified, declaration, source);
const result = await build({
    stdin: {
        contents: `import {loresColors,translateDHGR} from ${JSON.stringify(join(root, "src", "ui", "graphicscolors.ts"))};
const BLACK=0;const COLOR_MODE={COLOR:0,NOFRINGE:1};
${implementation}
export function render(bytes){const colors=getDoubleHiresColors(bytes,0,false);const rgba=new Uint8Array(colors.length*4);
for(let i=0;i<colors.length;i++){rgba.set(loresColors[colors[i]],i*4);rgba[i*4+3]=255;}return rgba;}`,
        resolveDir: root, loader: "ts"
    },
    bundle: true, platform: "node", format: "esm", write: false
});
const oracle = await import("data:text/javascript;base64," + Buffer.from(result.outputFiles[0].text).toString("base64"));
let input = "";
for await (const chunk of process.stdin) input += chunk;
const values = JSON.parse(input);
if (!Array.isArray(values) || values.length !== 192 * 80 || !values.every(value => Number.isInteger(value) && value >= 0 && value <= 255)) {
    throw new Error("Expected 192 rows of 80 byte values.");
}
process.stdout.write(Buffer.from(oracle.render(Uint8Array.from(values))).toString("base64"));
