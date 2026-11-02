// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import { runTests } from "@vscode/test-electron";
import * as path from "node:path";
import { mkdirSync } from "node:fs";

async function main(): Promise<void> {
    const extension = path.resolve(__dirname, "../..");
    const workspace = path.resolve(extension, "..");
    const profile = path.join(workspace, "artifacts", "vscode-m1-tests");
    mkdirSync(profile, { recursive: true });
    const executable = process.env.RETROCORE_VSCODE ?? path.join(process.env.LOCALAPPDATA ?? "", "Programs", "Microsoft VS Code", "Code.exe");
    await runTests({
        vscodeExecutablePath: executable,
        extensionDevelopmentPath: extension,
        extensionTestsPath: path.join(__dirname, "suite.js"),
        extensionTestsEnv: {
            RETROCORE_TEST_LANGUAGE_ONLY: process.argv.includes("--language-only") ? "1" : "0"
        },
        launchArgs: [
            workspace, "--user-data-dir", path.join(profile, "profile"),
            "--extensions-dir", path.join(profile, "extensions"),
            "--skip-welcome", "--skip-release-notes", "--disable-workspace-trust", "--disable-extensions"
        ]
    });
}
void main().catch(error => { console.error(error); process.exitCode = 1; });
