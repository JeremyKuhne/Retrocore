// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Diagnostics;
using System.Globalization;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Retrocore.Pascal;

namespace Retrocore.Debug;

// The Pascal thread: the p-machine's procedures, breakpoints on p-code and steps, beside the CPU's.
//
// The run looks at the p-machine only at its interpreter's fetch of each p-code, and only once the interpreter has
// been found in memory. Frames come from the mark stack, as it was at the last fetch.
internal sealed partial class DebugSession
{
    private const int PascalThread = 3;
    private const int PascalFrameBase = 40000;
    private const int PascalReferences = 2_000_000;
    private const int PascalScopes = 4;
    private const int PascalLocalsScope = 1;
    private const int PascalGlobalsScope = 2;
    private const int PascalRegistersScope = 3;

    // Pascal breakpoints, such as pascal HELLO.2+$5: a segment named or numbered, a procedure, and an offset.
    private readonly List<(PascalBreakpoint Where, BreakpointState State)> _pascalBreakpoints = [];
    private PascalGoal? _pascalGoal;
    private IReadOnlyList<PascalFrame>? _pascalFrames;
    private long _pascalScanned;
    private bool _pascalAnnounced;

    private PascalRuntime? Pascal => _target?.Pascal;

    private bool HasPascalThread => Pascal?.Interpreter is not null;

    private bool OnPascal(JsonObject args) => args.Int("threadId") == PascalThread && _target is not null && HasPascalThread;

    // Looks for the interpreter about once a second until it is found, and tells VS Code of the thread then.
    private void ScanPascal()
    {
        if (Pascal is not { } pascal) { return; }
        if (pascal.Interpreter is null && Stopwatch.GetElapsedTime(_pascalScanned).TotalSeconds < 1) { return; }
        _pascalScanned = Stopwatch.GetTimestamp();
        if (!pascal.Scan() || _pascalAnnounced) { return; }
        _pascalAnnounced = true;
        Notify("thread", new JsonObject { ["reason"] = "started", ["threadId"] = PascalThread });
    }

    // Notes the p-machine's registers at each fetch, for the Pascal thread's frames.
    private void ObservePascal(ushort pc)
    {
        if (Pascal is { } pascal && pascal.AtFetch(pc)) { pascal.ObserveFetch(); }
    }

    /// <summary>
    ///  Checks the p-machine at its fetch of a p-code: a step's end, or a Pascal breakpoint.
    /// </summary>
    /// <param name="pc">The instruction's address.</param>
    /// <returns>Whether the run stopped.</returns>
    private bool PascalStops(ushort pc)
    {
        if ((_pascalBreakpoints.Count == 0 && _pascalGoal is null) || Pascal is not { } pascal) { return false; }
        if (_pascalGoal is { Step: PascalStep.Pause } pause && Target.CycleCount >= pause.Deadline)
        {
            Stopped("pause", description: "The p-machine ran no p-code.", threadId: PascalThread);
            return true;
        }

        if (!pascal.AtFetch(pc) || pascal.ObserveFetch() is not { } top) { return false; }
        if (_pascalGoal is { } goal)
        {
            bool done = goal.Step switch
            {
                PascalStep.Over => top.Mark.Address >= goal.Mark,
                PascalStep.Out => top.Mark.Address > goal.Mark,
                _ => true
            };

            if (done)
            {
                Stopped(goal.Step == PascalStep.Pause ? "pause" : "step", threadId: PascalThread);
                return true;
            }
        }

        List<BreakpointState> stops = [];
        string? description = null;
        foreach ((PascalBreakpoint where, BreakpointState state) in _pascalBreakpoints)
        {
            if (!where.Matches(top, pascal) || !Triggers(state, access: null, out string? error)) { continue; }
            stops.Add(state);
            description ??= error ?? $"{pascal.Describe(top)}+${top.Offset:X4}";
        }

        if (stops.Count == 0) { return false; }
        Stopped(stops[0].Kind, [.. stops.Select(state => state.Id)], description, threadId: PascalThread);
        return true;
    }

    private void StepPascal(PascalStep step)
    {
        ushort mark = Pascal?.Registers?.Mark.Address ?? 0;
        _pascalGoal = new PascalGoal(step, mark, Target.CycleCount + 2_000_000);
        if (step == PascalStep.Pause) { return; }
        Continue();
    }

    // A Pascal breakpoint, pascal HELLO.2 or pascal 1.2+$12, stops before the p-code at that offset of the procedure.
    private void BindPascal(BreakpointState state, Match match)
    {
        string segment = match.Groups["segment"].Value;
        int procedure = int.Parse(match.Groups["procedure"].Value, CultureInfo.InvariantCulture);
        string offsetText = match.Groups["offset"].Success ? match.Groups["offset"].Value : "0";
        int offset = offsetText.StartsWith('$')
            ? int.Parse(offsetText.AsSpan(1), NumberStyles.HexNumber, CultureInfo.InvariantCulture)
            : int.Parse(offsetText, CultureInfo.InvariantCulture);

        bool numbered = int.TryParse(segment, NumberStyles.None, CultureInfo.InvariantCulture, out int number);
        PascalBreakpoint where = new(numbered ? null : segment, numbered ? number : null, procedure, offset);

        if (_target is null)
        {
            state.Problem ??= "Binds when the machine launches.";
        }
        else if (Target.Pascal is null)
        {
            state.Problem ??= "Only the Apple II and the Apple III run Apple Pascal.";
        }

        if (state.Problem is null) { _pascalBreakpoints.Add((where, state)); }
        state.Location = $"pascal {segment}.{procedure}{(offset == 0 ? "" : $"+${offset:X4}")} (p-code)";
        state.Response = new JsonObject { ["id"] = state.Id, ["verified"] = state.Problem is null };
    }

    private IReadOnlyList<PascalFrame> PascalFrames() => _pascalFrames ??= Pascal?.Frames() ?? [];

    private JsonObject PascalStackTrace()
    {
        List<JsonNode?> frames = [];
        IReadOnlyList<PascalFrame> stack = PascalFrames();
        if (stack.Count == 0 || Pascal is not { } pascal)
        {
            frames.Add(new JsonObject
            {
                ["id"] = PascalFrameBase, ["name"] = "Pascal: not running", ["line"] = 0, ["column"] = 0
            });
        }
        else
        {
            for (int index = 0; index < stack.Count; index++)
            {
                PascalFrame frame = stack[index];
                string name = $"{pascal.Describe(frame)}+${frame.Offset:X4}";
                if (index == 0 && pascal.Instruction(frame) is { } instruction) { name += $": {instruction}"; }
                frames.Add(new JsonObject
                {
                    ["id"] = PascalFrameBase + index,
                    ["name"] = name,
                    ["line"] = 0,
                    ["column"] = 0,
                    ["presentationHint"] = index == 0 ? "normal" : "subtle"
                });
            }
        }

        return new JsonObject { ["stackFrames"] = frames.ToJsonArray(), ["totalFrames"] = frames.Count };
    }

    private JsonObject PascalScopesOf(int frameId)
    {
        int index = frameId - PascalFrameBase;
        IReadOnlyList<PascalFrame> stack = PascalFrames();
        List<JsonNode?> scopes = [];
        if ((uint)index < (uint)stack.Count)
        {
            int reference = PascalReferences + (index * PascalScopes);
            scopes.Add(Scope("Locals", reference + PascalLocalsScope, stack[index].Words));
            if (Globals() is { } globals)
            {
                scopes.Add(Scope("Globals", reference + PascalGlobalsScope, globals.Words));
            }

            if (index == 0) { scopes.Add(Scope("P-machine", reference + PascalRegistersScope, 5)); }
        }

        return new JsonObject { ["scopes"] = scopes.ToJsonArray() };

        static JsonObject Scope(string name, int reference, int count) => new()
        {
            ["name"] = name,
            ["variablesReference"] = reference,
            ["namedVariables"] = count,
            ["expensive"] = false
        };
    }

    private JsonObject PascalVariablesOf(int reference)
    {
        int index = (reference - PascalReferences) / PascalScopes;
        int scope = (reference - PascalReferences) % PascalScopes;
        IReadOnlyList<PascalFrame> stack = PascalFrames();
        List<JsonNode?> variables = [];
        if ((uint)index < (uint)stack.Count && Pascal is { } pascal)
        {
            if (scope == PascalRegistersScope)
            {
                if (pascal.Registers is { } registers)
                {
                    variables.Add(Pointer("IPC", registers.Code));
                    variables.Add(Pointer("MP", registers.Mark));
                    variables.Add(Pointer("BASE", registers.Base));
                    variables.Add(Pointer("JTAB", registers.JumpTable));
                    variables.Add(Pointer("SEG", registers.Segment));
                }
            }
            else if ((scope == PascalLocalsScope ? stack[index] : Globals()) is { } frame)
            {
                for (int number = 1; number <= Math.Min(frame.Words, 512); number++)
                {
                    PascalPointer at = frame.Local(number);
                    ushort value = PascalMachine.Word(pascal.Memory, at);
                    variables.Add(new JsonObject
                    {
                        ["name"] = number.ToString(CultureInfo.InvariantCulture),
                        ["value"] = $"{(short)value} (${value:X4})",
                        ["variablesReference"] = 0,
                        ["memoryReference"] = at.Bank == 0 ? Reference(bank: null, at.Address) : null
                    });
                }
            }
        }

        return new JsonObject { ["variables"] = variables.ToJsonArray() };

        JsonObject Pointer(string name, PascalPointer pointer) => new()
        {
            ["name"] = name,
            ["value"] = pointer.ToString(),
            ["variablesReference"] = 0,
            ["memoryReference"] = pointer.Bank == 0 ? Reference(bank: null, pointer.Address) : null
        };
    }

    // The outer block's frame, whose locals are the program's globals: the one BASE names.
    private PascalFrame? Globals() =>
        Pascal?.Registers is { } registers ? PascalFrames().FirstOrDefault(frame => frame.Mark.Address == registers.Base.Address) : null;

    [GeneratedRegex(@"^pascal\s+(?<segment>[A-Za-z_][A-Za-z0-9_]*|\d+)\.(?<procedure>\d+)(?:\s*\+\s*(?<offset>\$[0-9A-Fa-f]+|\d+))?$", RegexOptions.IgnoreCase)]
    private static partial Regex PascalBreakpointName();
}
