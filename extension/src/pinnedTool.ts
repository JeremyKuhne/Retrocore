// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The retrocore tool a repository pins in its .NET tool manifest, and which host the extension runs for it. A
// repository pins the tool so that everyone, CI included, builds with the same tool and SDK headers, so the extension
// runs the pinned tool once `dotnet tool restore` has put it in the NuGet packages folder and it runs as the version
// pinned. Otherwise the extension runs its own host and says so, offering to restore: its own host builds a project of
// any SDK major it carries, and refuses one it does not, with the host's own message. No VS Code here, so node's tests
// run it.

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

/** The tool's package id and command, as the manifest names it. */
export const toolName = "retrocore";

const hostName = "Retrocore.Debug.dll";

/** A repository's pin of the tool. */
export interface ToolPin {
    /** The manifest that pins it. */
    manifest: string;
    /** The folder `dotnet tool restore` runs in: the manifest's repository folder. */
    folder: string;
    /** The version pinned. */
    version: string;
}

/** Whether two NuGet versions are the same, as NuGet compares them: without regard to case. */
export function sameVersion(a: string | undefined, b: string | undefined): boolean {
    return a !== undefined && b !== undefined && a.toLowerCase() === b.toLowerCase();
}

/**
 * The pin of the tool that `dotnet retrocore` in a folder would run: the nearest manifest at or above it,
 * `.config/dotnet-tools.json` or `dotnet-tools.json`, that lists the tool (its id compared without regard to case, as
 * NuGet's are), searching no higher than a manifest that says it is the root. Undefined when none pins it, or a
 * manifest cannot be read.
 */
export function findPin(folder: string): ToolPin | undefined {
    for (let directory = path.resolve(folder); ; directory = path.dirname(directory)) {
        for (const manifest of [path.join(directory, ".config", "dotnet-tools.json"), path.join(directory, "dotnet-tools.json")]) {
            if (!fs.existsSync(manifest)) continue;
            let json: unknown;
            try {
                json = JSON.parse(fs.readFileSync(manifest, "utf8"));
            } catch {
                return undefined;
            }
            if (typeof json !== "object" || json === null) return undefined;
            const record = json as { isRoot?: unknown; tools?: Record<string, { version?: unknown } | undefined> };
            const tools = typeof record.tools === "object" && record.tools !== null ? record.tools : {};
            const entry = Object.entries(tools).find(([name]) => name.toLowerCase() === toolName)?.[1];
            const version = entry?.version;
            if (typeof version === "string" && version !== "") return { manifest, folder: directory, version };
            if (record.isRoot === true) return undefined;
        }
        if (path.dirname(directory) === directory) return undefined;
    }
}

/**
 * The NuGet packages folder `dotnet tool restore` restores into: NUGET_PACKAGES, or the user's ~/.nuget/packages. A
 * globalPackagesFolder that a NuGet.Config sets instead is not read.
 */
export function packagesFolder(environment: NodeJS.ProcessEnv = process.env): string {
    return environment.NUGET_PACKAGES || path.join(os.homedir(), ".nuget", "packages");
}

/**
 * The host a restored pinned tool runs, in the NuGet packages folder: `retrocore/<version>/tools/<framework>/any/`,
 * the newest framework first. Undefined when that version is not restored.
 */
export function restoredHost(version: string, packages: string = packagesFolder()): string | undefined {
    const tools = path.join(packages, toolName, version.toLowerCase(), "tools");
    if (!fs.existsSync(tools)) return undefined;
    const frameworks = fs.readdirSync(tools).sort((a, b) => b.localeCompare(a, "en", { numeric: true }));
    for (const framework of frameworks) {
        const candidate = path.join(tools, framework, "any", hostName);
        if (fs.existsSync(candidate)) return candidate;
    }
    return undefined;
}

/** What the extension runs for a folder, and what it tells the user about it. */
export interface HostChoice {
    /** The host to run, or undefined when there is none. */
    host: string | undefined;
    /** The pin it followed or could not, if the folder has one. */
    pin?: ToolPin;
    /** Whether the host is the pinned tool itself. */
    pinned: boolean;
    /** A warning to show: the pinned tool is not restored or does not run, and another host runs instead. */
    warning?: string;
}

/**
 * Chooses the host for a folder. A host the settings name always runs, with no warning. Otherwise a pinned tool that
 * is restored and runs as its version runs, and one that is not gives way to the extension's own host, with a warning
 * unless that host is of the pinned version, so the same tool.
 */
export function chooseHost(options: {
    configured?: string;
    pin?: ToolPin;
    restored?: string;
    /** Whether the pinned version is restored but did not run, or ran as another version. */
    unrunnable?: boolean;
    fallback?: string;
    fallbackVersion?: string;
}): HostChoice {
    const { configured, pin, restored, unrunnable, fallback, fallbackVersion } = options;
    if (configured) return { host: configured, pin, pinned: false };
    if (pin === undefined) return { host: fallback, pinned: false };
    if (restored !== undefined) return { host: restored, pin, pinned: true };
    if (sameVersion(fallbackVersion, pin.version)) return { host: fallback, pin, pinned: false };
    const state = unrunnable
        ? "which is restored but does not run as that version (is the .NET runtime it needs installed?)"
        : "which is not restored";
    const running = fallback === undefined
        ? "and Retrocore has no host of its own to run instead"
        : `so Retrocore runs its own${fallbackVersion === undefined ? "" : ` ${fallbackVersion}`} instead; a project whose SDK it does not carry fails to build`;
    return {
        host: fallback,
        pin,
        pinned: false,
        warning: `This repository pins ${toolName} ${pin.version} (${pin.manifest}), ${state}, ${running}. Run dotnet tool restore to use the pinned tool.`
    };
}
