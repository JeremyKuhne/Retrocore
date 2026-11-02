// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import { createRequire } from "node:module";
import { readFileSync, mkdirSync } from "node:fs";
import { join, resolve } from "node:path";

const require = createRequire(new URL("../extension/package.json", import.meta.url));
const { build } = require("esbuild");
const root = join(process.env.RETROCORE_CACHE ?? join(process.env.USERPROFILE ?? "", "Retrocore"), "m1-dependencies", "apple2ts");
const output = resolve(import.meta.dirname, "..", "artifacts", "apple2ts-oracle");
mkdirSync(output, { recursive: true });
const entry = `
import * as mem from ${JSON.stringify(join(root, "src/worker/memory.ts"))};
import * as cpu from ${JSON.stringify(join(root, "src/worker/cpu6502.ts"))};
import * as ins from ${JSON.stringify(join(root, "src/worker/instructions.ts"))};
import * as sw from ${JSON.stringify(join(root, "src/worker/softswitches.ts"))};
export { mem, cpu, ins, sw };
`;
await build({
    stdin: { contents: entry, resolveDir: root, loader: "ts" },
    bundle: true, platform: "node", format: "cjs",
    outfile: join(output, "oracle.cjs"),
    plugins: [{
        name: "external-roms-and-ui",
        setup(plugin) {
            plugin.onLoad({ filter: /[\\/]devices[\\/]videoterm\.ts$/ }, () => ({
                contents: "export const videoTerm={enabled:false,active:false,readMemory(){throw new Error('Videx is not installed in the M1 oracle.')}};",
                loader: "ts"
            }));
            plugin.onResolve({ filter: /^@fortawesome\// }, args => ({ path: args.path, namespace: "icons" }));
            plugin.onLoad({ filter: /.*/, namespace: "icons" }, () => ({ contents: "export const faCircle={}; export const faCircleHalfStroke={};", loader: "ts" }));
            plugin.onResolve({ filter: /[\\/]roms[\\/]/ }, args => ({ path: args.path, namespace: "rom" }));
            plugin.onLoad({ filter: /.*/, namespace: "rom" }, args => {
                const original = args.path.includes("unenhanced");
                const code = `
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
const dir = process.env.RETROCORE_IIE_ROMS;
if(!dir) throw new Error('External ROM directory is required');
const variant=${JSON.stringify(original ? "UNENHANCED" : "ENHANCED")};
const cd=${JSON.stringify(original ? "342-0135 - B" : "342-0304 - A")};
const ef=${JSON.stringify(original ? "342-0134 - A" : "342-0303 - A")};
export const romBase64=Buffer.concat([
readFileSync(join(dir,'APPLE IIe - CD '+variant+' - '+cd+' - 2764.bin')),
readFileSync(join(dir,'APPLE IIe - EF '+variant+' - '+ef+' - 2764.bin'))
]).toString('base64');`;
                return { contents: code, loader: "ts" };
            });
            plugin.onLoad({ filter: /[\\/](worker2main|motherboard)\.ts$/ }, args => {
                const source = readFileSync(args.path, "utf8");
                const names = [...source.matchAll(/export\s+(?:const|let|function|class)\s+(\w+)/g)].map(match => match[1]);
                return { contents: names.map(name => `export const ${name}=${name === "isDebugging" ? "false" : name === "runOnlyMode" ? "()=>true" : "()=>{}"};`).join("\n"), loader: "ts" };
            });
        }
    }]
});
console.log(`Pinned Apple2TS oracle bundled without ROM assets: ${join(output, "oracle.cjs")}`);
