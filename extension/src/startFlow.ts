// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// What Retrocore: Start Machine builds from its quick picks: the things a machine can run, the setup chosen, and the
// launch configuration that starts it. Free of the vscode module, so the unit tests walk it. startMachine.ts shows the
// quick picks.

import { launchConfiguration, machineById, type Machine } from "./machines";

/** What a machine is started with. */
export type RunKind = "machine" | "source" | "program" | "basic" | "disk" | "tape" | "dosSource";

/** A thing a machine can run, as the second quick pick lists it. */
export interface RunChoice {
    kind: RunKind;
    label: string;
    detail: string;
    /** The file extensions the open dialog offers, without the dot; none for the bare machine. */
    extensions: string[];
}

/** A setup chosen in Start Machine, kept to start it again. */
export interface Setup {
    machineId: string;
    kind: RunKind;
    /** The file run, for every kind but the bare machine. */
    path?: string;
    /** For a basic launch, the disk the machine's BASIC boots from, when it is not in ROM. */
    basicDisk?: string;
    /** The machine's choices changed from their defaults, by launch option. */
    options: Record<string, string | number | boolean>;
}

/** The source files Retrocore assembles: native, ca65, Merlin and MACRO-10. */
export const sourceExtensions = ["asm", "s", "mac"];

/** What a machine can run: itself, a source or binary, and what its BASIC, drives and DOS take. */
export function runChoices(machine: Machine): RunChoice[] {
    const choices: RunChoice[] = [
        { kind: "machine", label: "Just the machine", detail: "Boots it as it is", extensions: [] },
        { kind: "source", label: "A source file", detail: "Assembles it, loads it and stops at its start", extensions: sourceExtensions },
        { kind: "program", label: "A binary program", detail: "Loads it at the machine's usual address and stops at its start", extensions: ["bin"] }
    ];

    if (machine.basicDialects.length !== 0) {
        choices.push({
            kind: "basic",
            label: "A BASIC file",
            detail: `Loads it into ${machine.basicDialects.map(dialectName).join(" or ")} and runs it`,
            extensions: ["bas"]
        });
    }

    if (machine.diskFormats.length !== 0) {
        choices.push({ kind: "disk", label: "A disk image", detail: "Boots it from the first drive", extensions: machine.diskFormats });
    }

    if (machine.tapeFormats.length !== 0) {
        choices.push({ kind: "tape", label: "A tape", detail: "Puts it in the cassette player", extensions: machine.tapeFormats });
    }

    if (machine.dos) {
        choices.push({
            kind: "dosSource",
            label: "A source file on a DOS 3.3 disk",
            detail: "Assembles it onto a fresh DOS disk, which boots and runs it",
            extensions: sourceExtensions
        });
    }

    return choices;
}

function dialectName(dialect: string): string {
    switch (dialect) {
        case "applesoft": return "AppleSoft";
        case "integer": return "Integer BASIC";
        case "apple1": return "Apple-1 BASIC";
        case "level2": return "Level II BASIC";
        case "business": return "Business BASIC";
        case "colorbasic": return "Color BASIC";
        default: return dialect;
    }
}

function fileName(path: string): string {
    return path.split(/[\\/]/).pop() ?? path;
}

/** How a setup is named: in the dropdown, the saved machine and the last-setup item. */
export function setupName(machine: Machine, setup: Setup): string {
    return setup.path === undefined ? `${machine.label} (Retrocore)` : `${machine.label}: ${fileName(setup.path)}`;
}

/** The launch configuration that starts a setup. */
export function setupConfiguration(setup: Setup): Record<string, unknown> {
    const machine = machineById(setup.machineId);
    if (machine === undefined) throw new Error(`There is no machine '${setup.machineId}'.`);
    const configuration: Record<string, unknown> = { ...launchConfiguration(machine, setupName(machine, setup)), ...setup.options };
    const path = setup.path;
    switch (setup.kind) {
        case "source":
            Object.assign(configuration, { source: path, stopOnEntry: true });
            break;
        case "program":
            Object.assign(configuration, { program: path, stopOnEntry: true });
            break;
        case "basic":
            Object.assign(configuration, { basic: path, stopOnEntry: true });
            if (setup.basicDisk !== undefined) configuration.disks = [setup.basicDisk];
            break;
        case "disk":
            Object.assign(configuration, machine.configuration.machine === "apple2" ? { diskImage: path } : { disks: [path] });
            break;
        case "tape":
            Object.assign(configuration, { cassette: path });
            break;
        case "dosSource":
            Object.assign(configuration, { source: path, dos: "3.3", stopOnEntry: false });
            break;
        default:
            break;
    }

    return configuration;
}

/** The setup's options with one changed, dropping it when it is back to the machine's default. */
export function withOption(machine: Machine, setup: Setup, option: string, value: string | number | boolean): Setup {
    const choice = machine.choices.find(candidate => candidate.option === option);
    if (choice === undefined) throw new Error(`${machine.label} has no ${option}.`);
    const options = { ...setup.options };
    if (value === choice.default) delete options[option];
    else options[option] = value;
    return { ...setup, options };
}

/** The value a setup gives one of the machine's choices: its own, or the default. */
export function optionValue(machine: Machine, setup: Setup, option: string): string | number | boolean | undefined {
    return setup.options[option] ?? machine.choices.find(choice => choice.option === option)?.default;
}

/** A one-line description of a setup, for the last-setup item: the machine, what it runs, and changed options. */
export function describeSetup(setup: Setup): string {
    const machine = machineById(setup.machineId);
    if (machine === undefined) return setup.machineId;
    const parts = [machine.label];
    if (setup.path !== undefined) parts.push(fileName(setup.path));
    for (const [option, value] of Object.entries(setup.options)) {
        const choice = machine.choices.find(candidate => candidate.option === option);
        const label = choice?.values.find(candidate => candidate.value === value)?.label ?? String(value);
        parts.push(`${choice?.label ?? option}: ${label}`);
    }

    return parts.join(" · ");
}

/** Whether a kept setup still names a machine and a kind it can run, as one saved by an older version might not. */
export function isUsable(setup: Setup | undefined): setup is Setup {
    const machine = setup === undefined ? undefined : machineById(setup.machineId);
    return machine !== undefined && runChoices(machine).some(choice => choice.kind === setup?.kind)
        && (setup?.kind === "machine" || typeof setup?.path === "string");
}
