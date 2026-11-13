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

    // Looks for the interpreter about once a second until it is found, and tells VS Code of the thread then. Once
    // something else replaces the interpreter, the thread ends, and a step on it is given up.
    private void ScanPascal()
    {
        if (Pascal is not { } pascal) { return; }
        if (pascal.Interpreter is null && Stopwatch.GetElapsedTime(_pascalScanned).TotalSeconds < 1) { return; }
        _pascalScanned = Stopwatch.GetTimestamp();
        bool known = pascal.Scan();
        if (known) { RefreshPascalSources(); }
        if (known == _pascalAnnounced) { return; }

        _pascalAnnounced = known;
        _pascalFrames = null;
        Notify("thread", new JsonObject { ["reason"] = known ? "started" : "exited", ["threadId"] = PascalThread });
        if (!known && _pascalGoal is not null)
        {
            _pascalGoal = null;
            Notify("output", new JsonObject
            {
                ["category"] = "console",
                ["output"] = "Apple Pascal's interpreter is no longer in memory, so the Pascal thread's step ended.\n"
            });
        }
    }

    // Starts a launch with no Pascal thread, step or frames from the one before.
    private void ForgetPascal()
    {
        _pascalGoal = null;
        _pascalFrames = null;
        _pascalAnnounced = false;
        _pascalScanned = 0;
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
            // MSCWs are made below their callers', so a higher MP is a caller.
            bool done = goal.Step switch
            {
                PascalStep.Over => top.Mark.Address > goal.Mark || (top.Mark.Address == goal.Mark && goal.LeftLine(top)),
                PascalStep.Into => top.Mark.Address != goal.Mark || goal.LeftLine(top),
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

    // A step by line where the procedure's listing is known, unless the Disassembly view steps by instruction; by
    // p-code otherwise.
    private void StepPascal(PascalStep step, bool instruction = false)
    {
        ushort mark = Pascal?.Registers?.Mark.Address ?? 0;
        (PascalListing Listing, PascalListingLine Line, string? Path)? place =
            instruction || step is PascalStep.Pause or PascalStep.Out || PascalFrames() is not [PascalFrame top, ..] ? null : PascalPlace(top);

        string? segment = place?.Listing.SegmentName(place.Value.Line.Segment) is { } named ? PascalListing.CodeName(named) : null;
        int start = place is { } at && Pascal is { } pascal ? FirstPcode(pascal, segment, at.Line) : 0;
        _pascalGoal = new PascalGoal(step, mark, Target.CycleCount + 2_000_000, place?.Listing, place?.Line, start);
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
                (PascalListing Listing, PascalListingLine Line, string? Path)? place = PascalPlace(frame);
                if (place?.Listing.ProcedureName(frame.SegmentNumber, frame.Procedure) is { } procedure)
                {
                    name = $"{procedure} ({name})";
                }

                if (index == 0 && pascal.Instruction(frame) is { } instruction) { name += $": {instruction}"; }
                if (place is { Path: null } unsourced) { name += $" (line {unsourced.Line.Line})"; }
                JsonObject entry = new()
                {
                    ["id"] = PascalFrameBase + index,
                    ["name"] = name,
                    ["line"] = place is { Path: not null } sourced ? sourced.Line.Line : 0,
                    ["column"] = place is { Path: not null } ? 1 : 0,
                    ["presentationHint"] = index == 0 ? "normal" : "subtle"
                };

                if (place is { Path: { } path })
                {
                    entry["source"] = new JsonObject { ["name"] = Path.GetFileName(path), ["path"] = path };
                }

                frames.Add(entry);
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
                // The listing names what it declares; the words it does not cover keep their numbers.
                IReadOnlyList<PascalVariable> named = PascalPlace(frame) is { } place
                    ? place.Listing.Variables(frame.SegmentNumber, frame.Procedure)
                    : [];

                foreach (PascalVariable variable in named.Where(variable => variable.Word <= frame.Words))
                {
                    PascalPointer at = PascalVariableAt(pascal.Memory, frame, variable);
                    variables.Add(new JsonObject
                    {
                        ["name"] = variable.Name,
                        ["value"] = PascalValue(pascal.Memory, at, variable),
                        ["type"] = variable.Type,
                        ["variablesReference"] = 0,
                        ["memoryReference"] = PascalReference(at)
                    });
                }

                for (int number = 1; number <= Math.Min(frame.Words, 512); number++)
                {
                    if (named.Any(variable => number >= variable.Word && number < variable.Word + Math.Max(variable.Words, 1)))
                    {
                        continue;
                    }

                    PascalPointer at = frame.Local(number);
                    ushort value = PascalMachine.Word(pascal.Memory, at);
                    variables.Add(new JsonObject
                    {
                        ["name"] = number.ToString(CultureInfo.InvariantCulture),
                        ["value"] = $"{(short)value} (${value:X4})",
                        ["variablesReference"] = 0,
                        ["memoryReference"] = PascalReference(at)
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
            ["memoryReference"] = PascalReference(pointer)
        };
    }

    // Where a Pascal pointer is, for the memory view. On the Apple II, RAM below $C000 is named by its bank, main or
    // auxiliary, as Apple Pascal 1.3 keeps its code in the auxiliary 64K and reads it with RAMRD on, so memory as the
    // CPU maps it at a fetch is not where the variables are. Elsewhere it is memory as the CPU maps it, and an Apple III
    // pointer through an X-byte has none.
    private string? PascalReference(PascalPointer pointer)
    {
        if (Pascal?.Memory is Apple2PascalMemory
            && pointer.Address is >= 0x200 and < 0xC000
            && Target.Banks.FirstOrDefault(bank => bank.Name == (pointer.Bank == 1 ? "aux" : "main")) is { } named)
        {
            return Reference(named, pointer.Address);
        }

        return pointer.Bank == 0 ? Reference(bank: null, pointer.Address) : null;
    }

    // A variable's value as its declared type shows it: an integer, a character, a boolean, a string, or words.
    private static string PascalValue(IPascalMemory memory, PascalPointer at, PascalVariable variable)
    {
        string type = variable.Type.ToUpperInvariant().Replace(" ", "", StringComparison.Ordinal);
        ushort word = PascalMachine.Word(memory, at);
        int size = variable.Reference ? PascalListing.WordsOf(variable.Type) : variable.Words;
        if (PascalListing.IsOrdinal(variable.Type))
        {
            return ((short)word).ToString(CultureInfo.InvariantCulture);
        }

        if (type == "BOOLEAN") { return (word & 1) != 0 ? "TRUE" : "FALSE"; }
        if (type == "CHAR")
        {
            char character = (char)(word & 0x7F);
            return character is >= ' ' and < (char)0x7F ? $"'{character}' ({word & 0xFF})" : $"CHR({word & 0xFF})";
        }

        if (type.StartsWith("STRING", StringComparison.Ordinal) && size > 0)
        {
            int length = Math.Min(memory.Read(at.Address, at.Bank), (size * 2) - 1);
            char[] text = new char[length];
            for (int index = 0; index < length; index++)
            {
                char character = (char)(memory.Read((ushort)(at.Address + 1 + index), at.Bank) & 0x7F);
                text[index] = character is >= ' ' and < (char)0x7F ? character : '?';
            }

            return $"'{new string(text).Replace("'", "''", StringComparison.Ordinal)}'";
        }

        int words = Math.Clamp(size, 1, 4);
        return string.Join(' ', Enumerable.Range(0, words).Select(index => $"${PascalMachine.Word(memory, at.Plus(index * 2)):X4}"));
    }

    // Where a variable is: its word in the frame, or for a VAR parameter the address that word holds, in the frame's
    // banks on the Apple III.
    private static PascalPointer PascalVariableAt(IPascalMemory? memory, PascalFrame frame, PascalVariable variable)
    {
        PascalPointer slot = frame.Local(variable.Word);
        return variable.Reference && memory is not null ? new PascalPointer(PascalMachine.Word(memory, slot), slot.Bank) : slot;
    }

    // A variable a Pascal frame's listing names, and where it is: in the frame, or in the program's globals.
    private (PascalVariable Variable, PascalPointer At)? PascalVariableNamed(int frameId, string name)
    {
        IReadOnlyList<PascalFrame> stack = PascalFrames();
        int index = frameId - PascalFrameBase;
        if ((uint)index >= (uint)stack.Count) { return null; }

        foreach (PascalFrame? frame in (PascalFrame?[])[stack[index], Globals()])
        {
            if (frame is not null
                && PascalPlace(frame)?.Listing.Variables(frame.SegmentNumber, frame.Procedure)
                    .FirstOrDefault(variable => string.Equals(variable.Name, name, StringComparison.OrdinalIgnoreCase)) is { } variable)
            {
                return (variable, PascalVariableAt(Pascal?.Memory, frame, variable));
            }
        }

        return null;
    }

    // The outer block's frame, whose locals are the program's globals: the one BASE names.
    private PascalFrame? Globals() =>
        Pascal?.Registers is { } registers ? PascalFrames().FirstOrDefault(frame => frame.Mark.Address == registers.Base.Address) : null;

    [GeneratedRegex(@"^pascal\s+(?<segment>[A-Za-z_][A-Za-z0-9_]*|\d+)\.(?<procedure>\d+)(?:\s*\+\s*(?<offset>\$[0-9A-Fa-f]+|\d+))?$", RegexOptions.IgnoreCase)]
    private static partial Regex PascalBreakpointName();
}
