// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import * as vscode from "vscode";

interface Variable { name: string; value: string; variablesReference: number; evaluateName?: string }

const program = [
    "10 A=1.5:B$=\"HI\":DIM E(2,3):E(1,2)=7",
    "20 FOR I=1 TO 3",
    "30 C=I*2",
    "40 NEXT",
    "50 STOP",
    ""
].join("\n");

/** Drives BASIC variables on a running Level II machine at its prompt: scopes, watches, edits, conditions and data breakpoints. */
export async function testBasicVariables(session: vscode.DebugSession, stop: () => Promise<string>): Promise<void> {
    const basic = 2;
    {
        assert.equal((await session.customRequest("retro/basic/write", { text: program })).success, true);
        const uri = await vscode.commands.executeCommand<vscode.Uri>("retrocore.basic.open");
        const conditional = new vscode.SourceBreakpoint(new vscode.Location(uri, new vscode.Position(2, 0)), true, "I=2");
        vscode.debug.addBreakpoints([conditional]);
        await new Promise(resolve => setTimeout(resolve, 500));
        for (const character of "RUN\r") await session.customRequest("retro/key", { code: character.charCodeAt(0) });
        assert.equal(await stop(), "breakpoint");
        const frameId: number = (await session.customRequest("stackTrace", { threadId: basic })).stackFrames[0].id;
        const evaluate = async (expression: string): Promise<string> =>
            (await session.customRequest("evaluate", { expression, frameId, context: "watch" })).result;
        assert.equal(await evaluate("I"), "2", "the condition held on the second pass");
        assert.equal(await evaluate("A*2"), "3");
        assert.equal(await evaluate("B$+\"!\""), "\"HI!\"");
        assert.equal(await evaluate("E(1,2)+LEN(B$)"), "9");

        // The scopes: the variables, the arrays with their elements, the loop and the program's memory.
        const scopes = (await session.customRequest("scopes", { frameId })).scopes as { name: string; variablesReference: number }[];
        assert.deepEqual(scopes.map(scope => scope.name), ["Variables", "Arrays", "Loops", "Program"]);
        const list = async (reference: number): Promise<Variable[]> =>
            (await session.customRequest("variables", { variablesReference: reference })).variables;
        const simple = await list(scopes[0].variablesReference);
        assert.deepEqual(simple.map(variable => `${variable.name}=${variable.value}`).slice(0, 4), ["A=1.5", "B$=\"HI\"", "I=2", "C=2"]);
        const arrays = await list(scopes[1].variablesReference);
        assert.equal(arrays[0].value, "E(2,3): 12 elements");
        const elements = await list(arrays[0].variablesReference);
        assert.equal(elements.find(element => element.name === "(1,2)")?.value, "7");
        const loops = await list(scopes[2].variablesReference);
        assert.equal(`${loops[0].name}: ${loops[0].value}`, "I: 2 TO 3 STEP 1 (FOR in line 20)");

        // Setting values: from the Variables view, from a watch, a new variable, and a string.
        assert.equal((await session.customRequest("setVariable", { variablesReference: scopes[0].variablesReference, name: "A", value: "A*10" })).value, "15");
        assert.equal(await evaluate("A"), "15");
        await session.customRequest("setExpression", { expression: "E(1,2)", value: "8", frameId });
        assert.equal(await evaluate("E(1,2)"), "8");
        await session.customRequest("setExpression", { expression: "Z", value: "5", frameId });
        assert.equal(await evaluate("Z"), "5");
        await session.customRequest("setExpression", { expression: "B$", value: "\"BYE\"", frameId });
        assert.equal(await evaluate("B$"), "\"BYE\"");

        // A logpoint writes BASIC values; a data breakpoint stops after the statement that changes its variable.
        vscode.debug.removeBreakpoints([conditional]);
        const logpoint = new vscode.SourceBreakpoint(new vscode.Location(uri, new vscode.Position(3, 0)), true, undefined, undefined, "C={C} B$={B$}");
        vscode.debug.addBreakpoints([logpoint]);
        await new Promise(resolve => setTimeout(resolve, 500));
        const info = await session.customRequest("dataBreakpointInfo", { variablesReference: scopes[0].variablesReference, name: "C" });
        assert.equal(info.dataId, "basic:C");
        await session.customRequest("setDataBreakpoints", { breakpoints: [{ dataId: info.dataId }] });
        await session.customRequest("continue", { threadId: basic });
        assert.equal(await stop(), "data breakpoint");
        assert.equal(await evaluate("C"), "4", "C changed from 2 to 4 in line 30");
        // The logpoint counted its hit and did not stop.
        const hits = (await session.customRequest("retro/breakpoints")).breakpoints as { location: string; hits: number; logMessage?: string }[];
        assert.equal(hits.find(breakpoint => breakpoint.logMessage === "C={C} B$={B$}")?.hits, 1);
        await session.customRequest("setDataBreakpoints", { breakpoints: [] });
        vscode.debug.removeBreakpoints([logpoint]);
        await new Promise(resolve => setTimeout(resolve, 300));
        await session.customRequest("continue", { threadId: basic });
    }
    await vscode.commands.executeCommand("workbench.action.closeAllEditors");
}
