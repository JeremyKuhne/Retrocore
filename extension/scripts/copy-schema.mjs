// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Copies the project file's schema, which the debug host ships as Schemas/project-1.schema.json, into out/schemas,
// where package.json's jsonValidation names it: the VSIX packages out/, and a self-hosted extension has no packaged
// host to read it from. The copy also says, in VS Code's own schema keywords, that the file takes comments and
// trailing commas, as the host reads it.

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const extension = join(dirname(fileURLToPath(import.meta.url)), "..");
const source = join(extension, "..", "src", "Retrocore.Debug", "Project", "project-1.schema.json");
const output = join(extension, "out", "schemas", "project-1.schema.json");
mkdirSync(dirname(output), { recursive: true });
const schema = JSON.parse(readFileSync(source, "utf8"));
writeFileSync(output, JSON.stringify({ ...schema, allowComments: true, allowTrailingCommas: true }, undefined, 2) + "\n");
