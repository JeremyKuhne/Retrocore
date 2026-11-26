// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Reads Retrocore projects (retrocore.json) as far as the extension needs them: their targets, the machine each runs
// and the launch configuration that debugs one. The debug host builds and checks them (src/Retrocore.Debug/Project);
// this only finds names, so a file it cannot read is left for the host's launch to report. Free of the vscode module,
// so the unit tests walk it.

import * as fs from "node:fs";
import * as path from "node:path";
import { machineById } from "./machines";

/** A project's file name. */
export const projectFileName = "retrocore.json";

/** A target of a project, as a launch names it. */
export interface ProjectTarget {
    /** The project's retrocore.json, a full path. */
    file: string;
    /** The project's name. */
    project: string;
    /** The target's name. */
    name: string;
    /** The target's catalog machine id, such as apple2-iiplus, as the file gives it. */
    machine: string;
    /** The target as the file gives it, which decides what the launch builds and starts. */
    definition: Record<string, unknown>;
}

/** The name that picks a target among every project of a root file: project/target. */
export function qualifiedName(target: ProjectTarget): string {
    return `${target.project}/${target.name}`;
}

/**
 * Parses JSON with comments and trailing commas, as the host reads a project file.
 * @throws SyntaxError when the text is not JSON once comments and trailing commas are left out.
 */
export function parseJsonc(text: string): unknown {
    let output = "";
    let index = 0;
    while (index < text.length) {
        const character = text[index];
        if (character === "\"") {
            // A string, kept whole with its escapes.
            const start = index++;
            while (index < text.length && text[index] !== "\"") index += text[index] === "\\" ? 2 : 1;
            output += text.slice(start, ++index);
        } else if (character === "/" && text[index + 1] === "/") {
            while (index < text.length && text[index] !== "\n") index++;
        } else if (character === "/" && text[index + 1] === "*") {
            const end = text.indexOf("*/", index + 2);
            index = end < 0 ? text.length : end + 2;
        } else {
            output += character;
            index++;
        }
    }
    // A comma before a closing bracket, with only white space between, is a trailing comma. Strings were kept whole
    // above, but a string may hold ",]" itself, so the commas are found outside strings only.
    let result = "";
    let inString = false;
    for (let at = 0; at < output.length; at++) {
        const character = output[at];
        if (inString) {
            result += character;
            if (character === "\\") result += output[++at] ?? "";
            else if (character === "\"") inString = false;
            continue;
        }
        if (character === "\"") inString = true;
        if (character === ",") {
            let next = at + 1;
            while (next < output.length && /\s/.test(output[next])) next++;
            if (output[next] === "}" || output[next] === "]") continue;
        }
        result += character;
    }
    return JSON.parse(result);
}

/** The retrocore.json a launch's project names: the file, or the one in the folder it names. */
export function projectFile(project: string): string {
    const full = path.resolve(project);
    try {
        if (fs.statSync(full).isDirectory()) return path.join(full, projectFileName);
    } catch {
        // Neither a file nor a folder: the host's launch says so.
    }
    return full;
}

function read(file: string): Record<string, unknown> {
    const value = parseJsonc(fs.readFileSync(file, "utf8"));
    if (typeof value !== "object" || value === null || Array.isArray(value)) throw new Error(`${file} is not a JSON object.`);
    return value as Record<string, unknown>;
}

function targetsOf(file: string, root: Record<string, unknown>): ProjectTarget[] {
    const project = typeof root.name === "string" ? root.name : path.basename(path.dirname(file));
    const targets = root.targets;
    if (typeof targets !== "object" || targets === null || Array.isArray(targets)) return [];
    return Object.entries(targets as Record<string, unknown>).flatMap(([name, value]) => {
        if (typeof value !== "object" || value === null || Array.isArray(value)) return [];
        const definition = value as Record<string, unknown>;
        return [{ file, project, name, machine: typeof definition.machine === "string" ? definition.machine : "", definition }];
    });
}

/** Whether a project file is a root file, which lists other projects' folders. */
export function isRootFile(file: string): boolean {
    try {
        return "projects" in read(file);
    } catch {
        return false;
    }
}

/**
 * The targets a launch's project names: a project's, or each of a root file's projects' in the order it lists them.
 * A project's are in its file's order, as the host lists them, except that here names that are whole numbers come
 * first, as JSON.parse orders them.
 * @throws Error when a file cannot be read or is not JSON.
 */
export function loadTargets(project: string): ProjectTarget[] {
    const file = projectFile(project);
    const root = read(file);
    if (!("projects" in root)) return targetsOf(file, root);
    // The host refuses a root whose projects are not a list of folders, or an empty one.
    if (!Array.isArray(root.projects)) return [];
    return root.projects.flatMap(folder => {
        if (typeof folder !== "string") return [];
        const member = path.join(path.resolve(path.dirname(file), folder), projectFileName);
        return targetsOf(member, read(member));
    });
}

/** The one target a launch's target names, by its name or as project/target, as the host chooses it; none when no target, or more than one, has that name. */
export function findTarget(targets: readonly ProjectTarget[], name: string): ProjectTarget | undefined {
    const named = targets.filter(target => target.name === name || qualifiedName(target) === name);
    return named.length === 1 ? named[0] : undefined;
}

/** The launch configuration that builds and debugs a target: F5's, in a workspace with no launch.json. */
export function projectLaunch(target: ProjectTarget): { type: string; request: string; name: string; project: string; target: string } {
    return {
        type: "retrocore", request: "launch", name: `${target.project} · ${target.name} (Retrocore)`,
        project: target.file, target: qualifiedName(target)
    };
}

/**
 * The retrocore/activeTarget notification's parameters: the active target's retrocore.json and name, so the server
 * assembles the open sources with that target's settings (its SDK paths, defines, CPU and platform folders); both
 * null without one, when the server uses each source's first target that assembles it.
 */
export function activeTargetParams(target: ProjectTarget | undefined): { project: string | null; target: string | null } {
    return { project: target?.file ?? null, target: target?.name ?? null };
}

/** The target a project launch configuration names, if the extension can read it; else the host's launch reports why. */
export function launchTarget(configuration: Record<string, unknown>): ProjectTarget | undefined {
    if (typeof configuration.project !== "string" || typeof configuration.target !== "string") return undefined;
    try {
        return findTarget(loadTargets(configuration.project), configuration.target);
    } catch {
        return undefined;
    }
}

/**
 * The launch property a project launch's resolved target goes in: its file, its qualified name and what the file
 * gives it, so the saved machine follows the target and changes with it. The debug host ignores it.
 */
export const projectTargetKey = "retrocoreTarget";

/**
 * A project launch configuration with the machine its target runs filled in, as the catalog configures it, so what
 * reads a session's machine reads the target's (the host sets the same from the target, replacing these), and its
 * saved machine is kept for that target. A configuration that is not a project launch, or names no target the
 * extension can find, is returned as it is.
 */
export function withProjectMachine(configuration: Record<string, unknown>): Record<string, unknown> {
    const target = launchTarget(configuration);
    if (target === undefined) return configuration;
    const machine = machineById(target.machine);
    const { machine: _machine, model: _model, rom: _rom, ...rest } = configuration;
    return {
        ...rest,
        ...(machine?.configuration ?? {}),
        [projectTargetKey]: { file: target.file, target: qualifiedName(target), definition: target.definition }
    };
}

/** What separates a project launch's name from its target's in the name its saved machine is kept under. */
export const targetSeparator = "";

/**
 * The name a launch configuration's saved machine and recovery journal are kept under: its own name, or for a project
 * launch its name and its target's as project/target (separated by targetSeparator), so each target of a launch
 * whose target is a variable keeps its own, whether the launch names it by name or as project/target.
 */
export function savedName(configuration: Record<string, unknown>): string | undefined {
    const name = configuration.name;
    if (typeof name !== "string") return undefined;
    const resolved = configuration[projectTargetKey];
    if (typeof resolved === "object" && resolved !== null && "target" in resolved && typeof resolved.target === "string") {
        return `${name}${targetSeparator}${resolved.target}`;
    }
    if (typeof configuration.project !== "string" || typeof configuration.target !== "string") return name;
    // A target the extension cannot find keeps the name it is given, as the host reports it.
    const target = launchTarget(configuration);
    return `${name}${targetSeparator}${target === undefined ? configuration.target : qualifiedName(target)}`;
}

/** A saved name as it is shown: a project launch's as its name · project/target. */
export function savedLabel(saved: string): string {
    return saved.replace(targetSeparator, " · ");
}

/** A saved name's launch configuration name and, for a project launch, its target as project/target. */
export function splitSavedName(saved: string): { name: string; target: string | undefined } {
    const at = saved.indexOf(targetSeparator);
    return at < 0 ? { name: saved, target: undefined } : { name: saved.slice(0, at), target: saved.slice(at + 1) };
}
