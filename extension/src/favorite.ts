// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// A favorite: a whole machine kept under a name, with a description, in the retrocore.favorites setting. It is a
// Start Machine setup (the catalog machine, its settings and what it runs) with the saved machine (its cards and
// media), so loading one sets it up off and booting one starts it as Start Machine would. Paths inside the workspace
// are written as ${workspaceFolder}/..., so a favorite shared through the workspace's settings works elsewhere. Free
// of the vscode module, so the unit tests load it.

import * as os from "node:os";
import { machineById } from "./machines";
import type { RunKind, Setup } from "./startFlow";

/** A favorite as the retrocore.favorites setting keeps it. */
export interface Favorite {
    name: string;
    description?: string;
    /** The catalog machine, such as apple2-iiplus. */
    machine: string;
    /** Its settings that differ from their defaults, by launch option. */
    options?: Record<string, string | number | boolean>;
    /** What it runs, when not just the machine. */
    run?: { kind: RunKind; path?: string; basicDisk?: string };
    /** Its cards and media, as the debug host's retro/devices gives them. */
    machineState?: unknown;
}

/** Whether a value read from the setting is a favorite this version can use. */
export function isFavorite(value: unknown): value is Favorite {
    if (typeof value !== "object" || value === null) return false;
    const favorite = value as Partial<Favorite>;
    return typeof favorite.name === "string" && favorite.name.trim() !== ""
        && typeof favorite.machine === "string" && machineById(favorite.machine) !== undefined;
}

/** The setup that starts a favorite, named for it. */
export function favoriteSetup(favorite: Favorite): Setup {
    const setup: Setup = { name: favorite.name, machineId: favorite.machine, kind: favorite.run?.kind ?? "machine", options: { ...favorite.options } };
    if (favorite.run?.path !== undefined) setup.path = favorite.run.path;
    if (favorite.run?.basicDisk !== undefined) setup.basicDisk = favorite.run.basicDisk;
    return setup;
}

/** A favorite of a setup and its saved machine, leaving out what is empty. */
export function favoriteFrom(setup: Setup, name: string, description: string | undefined, machineState: unknown): Favorite {
    const favorite: Favorite = { name, machine: setup.machineId };
    if (description !== undefined && description.trim() !== "") favorite.description = description.trim();
    if (Object.keys(setup.options).length !== 0) favorite.options = { ...setup.options };
    if (setup.kind !== "machine") {
        favorite.run = { kind: setup.kind };
        if (setup.path !== undefined) favorite.run.path = setup.path;
        if (setup.basicDisk !== undefined) favorite.run.basicDisk = setup.basicDisk;
    }
    if (machineState !== undefined) favorite.machineState = machineState;
    return favorite;
}

// A path's separators, for comparing it with the workspace's.
const slashes = (path: string): string => path.replace(/\\/g, "/");

/**
 * Writes paths inside the workspace as ${workspaceFolder}/..., anywhere in a value, so it works from another
 * computer's copy of the workspace. Windows paths compare without case.
 */
export function portable<T>(value: T, workspace: string | undefined): T {
    if (workspace === undefined) return value;
    const root = slashes(workspace).replace(/\/+$/, "");
    const caseless = /^[a-z]:/i.test(root);
    const within = (path: string): string | undefined => {
        const candidate = slashes(path);
        const head = candidate.slice(0, root.length);
        const same = caseless ? head.toLowerCase() === root.toLowerCase() : head === root;
        if (!same || (candidate.length > root.length && candidate[root.length] !== "/")) return undefined;
        return "${workspaceFolder}" + candidate.slice(root.length);
    };
    const walk = (item: unknown): unknown => {
        if (typeof item === "string") return within(item) ?? item;
        if (Array.isArray(item)) return item.map(walk);
        if (typeof item === "object" && item !== null) {
            return Object.fromEntries(Object.entries(item).map(([key, entry]) => [key, walk(entry)]));
        }
        return item;
    };
    return walk(value) as T;
}

/**
 * Substitutes the variables a launch configuration in launch.json or a favorite uses, as VS Code does when it starts
 * one: ${workspaceFolder}, ${workspaceFolderBasename}, ${userHome} and ${env:NAME}. Anything else is left as it is.
 */
export function resolveVariables<T>(value: T, workspace: string | undefined, env: NodeJS.ProcessEnv = process.env): T {
    if (typeof value === "string") {
        return value.replace(/\$\{([^}]+)\}/g, (whole, name: string) => {
            if (name === "workspaceFolder" && workspace !== undefined) return workspace;
            if (name === "workspaceFolderBasename" && workspace !== undefined) return workspace.split(/[\\/]/).pop() ?? whole;
            if (name === "userHome") return os.homedir();
            if (name.startsWith("env:")) return env[name.slice(4)] ?? "";
            return whole;
        }) as T;
    }
    if (Array.isArray(value)) return value.map(item => resolveVariables(item, workspace, env)) as T;
    if (typeof value === "object" && value !== null) {
        return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, resolveVariables(item, workspace, env)])) as T;
    }
    return value;
}

/**
 * The reverse of portable: paths written as ${workspaceFolder}/... become the workspace's own, with its separators,
 * as they are when a favorite moves from the workspace's settings to the user's.
 */
export function local<T>(value: T, workspace: string | undefined): T {
    if (workspace === undefined) return value;
    const separator = workspace.includes("\\") ? "\\" : "/";
    const walk = (item: unknown): unknown => {
        if (typeof item === "string" && item.startsWith("${workspaceFolder}")) {
            return workspace.replace(/[\/]+$/, "") + item.slice("${workspaceFolder}".length).replace(/[\/]/g, separator);
        }
        if (Array.isArray(item)) return item.map(walk);
        if (typeof item === "object" && item !== null) {
            return Object.fromEntries(Object.entries(item).map(([key, entry]) => [key, walk(entry)]));
        }
        return item;
    };
    return walk(value) as T;
}

// A value as JSON with its keys in order, so two saved machines compare by what they hold.
function canonical(value: unknown): string {
    if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
    if (typeof value === "object" && value !== null) {
        return `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical((value as Record<string, unknown>)[key])}`).join(",")}}`;
    }
    return JSON.stringify(value) ?? "null";
}

/**
 * What differs between a favorite as kept and the machine it was saved from, as it is now: its settings, what it runs,
 * its cards, and its disks and tapes. An empty drive holds nothing, so drives that come and go with a card do not count.
 */
export function differences(kept: Favorite, now: Favorite): string[] {
    const found: string[] = [];
    if (kept.machine !== now.machine || canonical(kept.options ?? {}) !== canonical(now.options ?? {})) found.push("its settings");
    if (canonical(kept.run ?? null) !== canonical(now.run ?? null)) found.push("what it runs");
    const part = (favorite: Favorite, name: string): string => {
        const entries = (favorite.machineState as Record<string, unknown> | undefined)?.[name];
        const held = typeof entries === "object" && entries !== null
            ? Object.fromEntries(Object.entries(entries).filter(([, value]) => value !== null && value !== "empty"))
            : {};
        return canonical(held);
    };
    // A favorite that records no cards and media is the machine its launch gives, whatever that holds.
    if (kept.machineState === undefined) return found;
    if (part(kept, "cards") !== part(now, "cards")) found.push("its cards");
    if (part(kept, "media") !== part(now, "media")) found.push("its disks and tapes");
    return found;
}
