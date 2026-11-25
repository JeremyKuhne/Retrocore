// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import { downloadAndUnzipVSCode, runTests } from "@vscode/test-electron";
import * as path from "node:path";
import { mkdirSync } from "node:fs";

// The VS Code the tests download when RETROCORE_VSCODE names none, pinned so every run tests against the same build.
// It must satisfy the "engines" field in package.json.
const vscodeVersion = "1.146.0";

async function main(): Promise<void> {
    const extension = path.resolve(__dirname, "../..");
    const workspace = path.resolve(extension, "..");
    const profile = path.join(workspace, "artifacts", "vscode-m1-tests");
    mkdirSync(profile, { recursive: true });
    // RETROCORE_VSCODE runs an installed VS Code; otherwise the pinned one is downloaded once, into .vscode-test.
    const executable = process.env.RETROCORE_VSCODE
        || await downloadAndUnzipVSCode({ version: vscodeVersion, cachePath: path.join(extension, ".vscode-test") });
    await runTests({
        vscodeExecutablePath: executable,
        extensionDevelopmentPath: extension,
        extensionTestsPath: path.join(__dirname, "suite.js"),
        extensionTestsEnv: {
            RETROCORE_TEST_LANGUAGE_ONLY: process.argv.includes("--language-only") ? "1" : "0",
            RETROCORE_TEST_MEMORY_ONLY: process.argv.includes("--memory-only") ? "1" : "0"
        },
        launchArgs: [
            workspace, "--user-data-dir", path.join(profile, "profile"),
            "--extensions-dir", path.join(profile, "extensions"),
            "--skip-welcome", "--skip-release-notes", "--disable-workspace-trust", "--disable-extensions",
            ...(process.argv.includes("--memory-only") ? ["--disable-telemetry"] : [])
        ]
    });
}
void main().catch(error => { console.error(error); process.exitCode = 1; });
