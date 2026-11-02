// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Each machine in the Run and Debug dropdown, so one starts with no launch.json: VS Code asks for these dynamic
// configurations when the dropdown or Debug: Select and Start Debugging lists Retrocore's. Their names are stable, so
// each machine keeps the cards and disks it last ran with (savedMachine.ts).

import * as vscode from "vscode";
import { launchConfiguration, machines } from "./machines";

/** One launch configuration per machine, booting it as it is. */
export function machineConfigurations(): vscode.DebugConfiguration[] {
    return machines.map(machine => launchConfiguration(machine) as vscode.DebugConfiguration);
}

/** Registers the machines' dynamic configurations. */
export function registerMachineMenu(context: vscode.ExtensionContext): void {
    context.subscriptions.push(vscode.debug.registerDebugConfigurationProvider(
        "retrocore",
        { provideDebugConfigurations: () => machineConfigurations() },
        vscode.DebugConfigurationProviderTriggerKind.Dynamic));

    // What the dropdown lists, for the editor tests, which cannot read it from VS Code.
    context.subscriptions.push(vscode.commands.registerCommand("retrocore.machine.configurations", () => machineConfigurations()));
}
