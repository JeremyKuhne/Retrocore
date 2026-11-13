// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using System.Diagnostics;
using System.Globalization;
using System.Text.RegularExpressions;
using Touki.Text;

namespace Retrocore.Debug;

// Breakpoints of every kind: source lines, functions (labels and addresses), instructions and data, each with a
// condition, a hit count condition and a log message.
internal sealed partial class DebugSession
{
    private const string FunctionGroup = "function";
    private const string InstructionGroup = "instruction";
    private const string DataGroup = "data";

    // Every breakpoint by its group and key, so setting a group again keeps the ids and hits of those that stay.
    private readonly Dictionary<string, BreakpointState> _states = [];
    private readonly Dictionary<ushort, List<BreakpointSite>> _breakpoints = [];

    // Scanline breakpoints, each at a beam position as a cycle within the video frame.
    private readonly List<(int Position, BreakpointState State)> _beamBreakpoints = [];

    // The positions the scanline filter stops at while it is ticked, from its condition.
    private int[] _scanlinePositions = [192 * 65];
    private readonly List<DataWatch> _watches = [];

    // Logpoints write at most this many lines a second, so one in a loop cannot flood the Debug Console; the launch
    // configuration's logpointLimit changes it, and 0 lifts it.
    private const int DefaultLogpointLimit = 100;
    private int _logpointLimit = DefaultLogpointLimit;
    private long _logWindow;
    private int _logged;
    private int _dropped;

    // Data breakpoints the current instruction has hit, checked when it finishes.
    private readonly List<(BreakpointState Breakpoint, string Description)> _dataHits = [];
    private JsonObject? _functionRequest;
    private JsonObject? _instructionRequest;
    private JsonObject? _dataRequest;

    // The exception filters on in the Breakpoints view; BRK stops until VS Code says otherwise.
    private HashSet<string> _exceptionFilters = [BrkFilter];

    // What the last exception stop was, for exceptionInfo.
    private (string Id, string Description)? _exception;

    private const string BrkFilter = "brk";
    private const string ContractsFilter = "contracts";
    private const string ScanlineFilter = "scanline";
    private const string MachineResetFilter = "machineReset";

    // SOS call breakpoints, such as sos OPEN: each with its call's number, or null for every call.
    private readonly List<(byte? Number, BreakpointState State)> _systemCallBreakpoints = [];

    // The sites at an address with none, so checking each instruction allocates nothing.
    private static readonly List<BreakpointSite> s_noSites = [];

    /// <summary>
    ///  Gets the exception filters the Breakpoints view lists for a machine.
    /// </summary>
    /// <param name="machine">The launched machine, or null for every machine's.</param>
    /// <param name="contracts">Whether any routine's <c>;; Keeps:</c> contract is checked, as the filter needs.</param>
    /// <returns>The filters.</returns>
    internal static (string Filter, string Label, string Description, bool Default)[] ExceptionFilters(
        string? machine,
        bool contracts = true)
    {
        (string, string, string, bool) reset = (
            MachineResetFilter,
            "Machine reset",
            "Stops when the machine resets: as it powers on, and at each reset after.",
            true);

        (string, string, string, bool) brk = (
            BrkFilter,
            "BRK instructions",
            "Stops before a 6502 BRK runs.",
            true);

        // SOS calls are BRKs, so on the Apple III the BRK filter stops at the rest; an sos function breakpoint stops
        // at calls.
        (string, string, string, bool) sosBrk = (
            BrkFilter,
            "BRK instructions",
            "Stops before a 6502 BRK runs that is not an SOS call, and at SOS's debug call, BRK $FE.",
            true);

        (string, string, string, bool) scanline = (
            ScanlineFilter,
            "Video beam reaches a scanline",
            "Stops each frame when the video beam reaches a scanline. The default is 192, where vertical blanking starts.",
            false);

        (string, string, string, bool) keeps = (
            ContractsFilter,
            "Routine broke its Keeps: promise",
            "Stops where a call returns with a register, flag or memory location changed that the routine's ;; Keeps: "
                + "comment promises to keep. The Debug Console reports these either way.",
            false);

        (string, string, string, bool)[] checks = contracts ? [keeps] : [];
        return machine switch
        {
            DebugMachines.Trs80Model1 => [reset, .. checks, .. BasicFilters],

            // The Apple III has no BASIC in ROM to stop in, nor a beam position to stop at yet.
            DebugMachines.Apple3 => [reset, sosBrk, .. checks],
            DebugMachines.Apple1 => [reset, brk, .. checks],
            _ => [reset, brk, scanline, .. checks, .. BasicFilters]
        };
    }

    /// <summary>
    ///  Gets the hint the Breakpoints view shows for an exception filter's condition.
    /// </summary>
    /// <param name="filter">The filter.</param>
    /// <returns>The hint, or null for a filter without a condition.</returns>
    internal static string? FilterConditionDescription(string filter) =>
        filter == ScanlineFilter ? "Scanline:column positions, such as 192:0 or 0:25, 100:25" : null;

    // Answers setExceptionBreakpoints: the ticked filters, and those with a condition. A scanline condition that
    // does not read leaves the filter unverified, saying why.
    private JsonObject ExceptionBreakpoints(JsonObject args)
    {
        HashSet<string> on = [];
        List<JsonNode?> responses = [];
        foreach (JsonNode? filter in args["filters"] as JsonArray ?? [])
        {
            string id = (filter as JsonValue)?.GetValue<string>() ?? "";
            on.Add(id);
            responses.Add(FilterResponse(id, condition: null));
        }

        foreach (JsonObject option in (args["filterOptions"] as JsonArray ?? []).OfType<JsonObject>())
        {
            string id = option.String("filterId") ?? "";
            on.Add(id);
            responses.Add(FilterResponse(id, option.String("condition")));
        }

        _exceptionFilters = on;
        ApplyBeamBreaks();
        return new JsonObject { ["breakpoints"] = responses.ToJsonArray() };
    }

    private JsonObject FilterResponse(string id, string? condition)
    {
        if (id != ScanlineFilter) { return new JsonObject { ["verified"] = true }; }
        string? problem = _target is not null && !Target.HasBeam ? "Only the IIe has a video beam to stop on." : null;
        List<int> positions = [];
        string[] items = (condition ?? "").Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        foreach (string item in items)
        {
            if (BeamPosition($"scanline {item}") is not { } beam)
            {
                problem ??= $"'{item}' is not a position: use scanline:column, such as 192:0.";
            }
            else if (beam.Problem is { } invalid)
            {
                problem ??= invalid;
            }
            else
            {
                positions.Add(beam.Position);
            }
        }

        _scanlinePositions = problem is not null ? [] : positions.Count == 0 ? [192 * 65] : [.. positions];
        return problem is null ? new JsonObject
        {
            ["verified"] = true
        } : new JsonObject { ["verified"] = false, ["message"] = problem };
    }

    // Gives the target every beam position to stop at: the scanline function breakpoints', and the filter's while
    // it is ticked.
    private void ApplyBeamBreaks()
    {
        if (_target is null || !Target.HasBeam) { return; }
        IEnumerable<int> filter = BreaksOn(ScanlineFilter) ? _scanlinePositions : [];
        Target.SetBeamBreaks([.. _beamBreakpoints.Select(beam => beam.Position).Concat(filter)]);
    }

    private bool BreaksOn(string filter) => _exceptionFilters.Contains(filter);

    // Adds modules for code the machine has loaded, such as SOS's drivers, and binds the source breakpoints again so
    // lines in that code stop; each binding the editor shows is updated.
    private void AddLoadedModules()
    {
        if (_target is null) { return; }
        ScanPascal();
        if (!Target.AddLoadedModules(_debug)) { return; }
        foreach (JsonObject request in _requested.Values.ToArray())
        {
            JsonObject response = Breakpoints(request);
            foreach (JsonObject breakpoint in (response["breakpoints"] as JsonArray ?? []).OfType<JsonObject>())
            {
                Notify("breakpoint", new JsonObject
                {
                    ["reason"] = "changed",
                    ["breakpoint"] = breakpoint.DeepClone()
                });
            }
        }
    }

    // Binds every breakpoint again for a new launch, with no hits.
    private void RebindBreakpoints()
    {
        _beamBreakpoints.Clear();
        _systemCallBreakpoints.Clear();
        _pascalBreakpoints.Clear();
        _states.Clear();
        _breakpoints.Clear();
        _basicSites.Clear();
        _watches.Clear();
        _dataHits.Clear();
        foreach (JsonObject request in _requested.Values.ToArray())
        {
            Breakpoints(request);
        }

        if (_functionRequest is { } functions) { FunctionBreakpoints(functions); }
        if (_instructionRequest is { } instructions) { InstructionBreakpoints(instructions); }
        if (_dataRequest is { } data) { DataBreakpoints(data); }
        if (_basicBreakpoints is { } basic) { BasicBreakpoints(basic); }
        foreach ((string path, JsonObject request) in _basicFileBreakpoints.ToArray())
        {
            BasicFileBreakpoints(request, path);
        }

        ApplyBeamBreaks();

    }

    private JsonObject Breakpoints(JsonObject args)
    {
        string requested = Required(args["source"] as JsonObject ?? throw new ArgumentException("source is required."), "path");
        if (IsBasicDocument(requested)) { return BasicBreakpoints(args); }
        if (IsBasicFile(requested)) { return BasicFileBreakpoints(args, requested); }
        string path = Path.GetFullPath(requested);

        _requested[path] = args;
        string group = $"source\n{path.ToUpperInvariant()}";
        RemoveSites(group);
        HashSet<string> kept = [];
        List<JsonObject> responses = [];
        foreach (JsonObject breakpoint in (args["breakpoints"] as JsonArray ?? []).OfType<JsonObject>())
        {
            int line = (breakpoint.Int("line") ?? 0);
            BreakpointState state = State(group, line.ToString(CultureInfo.InvariantCulture), breakpoint, kept);
            state.Kind = "breakpoint";
            state.Line = new(path, line);
            state.Location = $"{Path.GetFileName(path)}:{line}";
            int count = 0;

            // A breakpoint belongs to each module that has code on the line, and stops only where that module applies.
            foreach (IDebugModule module in _debug.Modules)
            {
                foreach (ushort address in module.Entries(path, line))
                {
                    AddSite(address, new(module, state.Line, state));
                    count++;
                }
            }

            if (count == 0) { state.Problem ??= "No executable debug span on this line."; }
            state.Response = new JsonObject
            {
                ["id"] = state.Id,
                ["verified"] = state.Problem is null,
                ["line"] = line,
                ["source"] = new JsonObject { ["name"] = Path.GetFileName(path), ["path"] = path }
            };

            responses.Add(Describe(state, changed: false));
        }

        Forget(group, kept);
        return new JsonObject { ["breakpoints"] = responses.ToJsonArray() };
    }

    // Function breakpoints name a label or an address expression, and stop whenever the PC reaches it; or name a
    // scanline, and stop whenever the video beam reaches it.
    private JsonObject FunctionBreakpoints(JsonObject args)
    {
        _functionRequest = args;
        RemoveSites(FunctionGroup);
        _beamBreakpoints.Clear();
        _systemCallBreakpoints.Clear();
        _pascalBreakpoints.Clear();
        HashSet<string> kept = [];
        List<JsonObject> responses = [];
        foreach (JsonObject breakpoint in (args["breakpoints"] as JsonArray ?? []).OfType<JsonObject>())
        {
            string name = breakpoint.String("name") ?? throw new ArgumentException("name is required.");
            BreakpointState state = State(FunctionGroup, name.Trim(), breakpoint, kept);
            state.Kind = "function breakpoint";
            state.Location = name;
            if (BeamPosition(name) is { } beam)
            {
                BindBeam(state, beam.Position, beam.Problem);
                responses.Add(Describe(state, changed: false));
                continue;
            }

            if (PascalBreakpointName().Match(name.Trim()) is { Success: true } pascal)
            {
                BindPascal(state, pascal);
                responses.Add(Describe(state, changed: false));
                continue;
            }

            if (SystemCallBreakpoint().Match(name.Trim()) is { Success: true } call)
            {
                BindSystemCall(state, call.Groups["call"].Success ? call.Groups["call"].Value : null);
                responses.Add(Describe(state, changed: false));
                continue;
            }

            ushort? address = null;
            DebugMemoryBank? bank = null;
            if (_target is null)
            {
                state.Problem ??= "Binds when the machine launches.";
            }
            else if (state.Problem is null)
            {
                // A name such as bank1:$D000 stops only while the CPU runs that bank's code there.
                try
                {
                    address = checked((ushort)Evaluate(ExpressionEvaluator.SplitBank(Target, name.Trim(), out bank)));
                    if (bank is not null && bank.Peek(address.Value) is null)
                    {
                        state.Problem = $"{bank.Label} has no byte at ${address:X4}.";
                        address = null;
                    }
                }
                catch (Exception exception) when (IsEvaluationError(exception))
                {
                    state.Problem = $"'{name}' is not a label or an address: {exception.Message}";
                }
            }

            if (address is { } value)
            {
                AddSite(value, new(Module: null, Line: null, state, bank));
                state.Location = $"{name} ({(bank is null ? "" : $"{bank.Name}:")}${value:X4})";
                state.Address = value;
            }

            state.Response = new JsonObject
            {
                ["id"] = state.Id,
                ["verified"] = state.Problem is null,
                ["instructionReference"] = address is { } bound ? $"0x{bound:X4}" : null
            };

            responses.Add(Describe(state, changed: false));
        }

        ApplyBeamBreaks();
        Forget(FunctionGroup, kept);
        return new JsonObject { ["breakpoints"] = responses.ToJsonArray() };
    }

    // A scanline breakpoint stops when the IIe's beam reaches a scanline and column, between any two cycles: mid-
    // instruction, if need be.
    private void BindBeam(BreakpointState state, int position, string? problem)
    {
        if (_target is null)
        {
            state.Problem ??= "Binds when the machine launches.";
        }
        else if (!Target.HasBeam)
        {
            state.Problem ??= "Only the IIe has a video beam to stop on.";
        }
        else
        {
            state.Problem ??= problem;
        }

        if (state.Problem is null) { _beamBreakpoints.Add((position, state)); }
        state.Location = $"scanline {position / 65}:{position % 65} (video beam)";
        state.Response = new JsonObject { ["id"] = state.Id, ["verified"] = state.Problem is null };
    }

    // An SOS call breakpoint, sos OPEN or sos $C8, stops before a program makes that call; sos alone, before any.
    private void BindSystemCall(BreakpointState state, string? call)
    {
        byte? number = null;
        if (call is not null)
        {
            number = SosCalls.Parse(call);
            if (number is null)
            {
                state.Problem ??= $"'{call.Trim()}' is not an SOS call: use a name or number, such as OPEN or $C8.";
            }
        }

        if (_target is null)
        {
            state.Problem ??= "Binds when the machine launches.";
        }
        else if (Target is not Apple3DebugTarget)
        {
            state.Problem ??= "Only the Apple III makes SOS calls.";
        }

        if (state.Problem is null) { _systemCallBreakpoints.Add((number, state)); }
        state.Location = number is { } known ? $"sos {SosCalls.Name(known)} (SOS call ${known:X2})" : "sos (every SOS call)";
        state.Response = new JsonObject { ["id"] = state.Id, ["verified"] = state.Problem is null };
    }

    /// <summary>
    ///  Reads a scanline breakpoint's name: <c>scanline S:C</c>, <c>scanline S</c> (column 0) or <c>scanline vbl</c>
    ///  (192:0, where vertical blanking starts). Scanlines run 0-261 and columns 0-64; visible fetches start at
    ///  column 25.
    /// </summary>
    /// <param name="name">The function breakpoint's name.</param>
    /// <returns>The beam position as a cycle within the frame and why it is invalid, or null when not one.</returns>
    private static (int Position, string? Problem)? BeamPosition(string name)
    {
        Match match = ScanlineBreakpoint().Match(name.Trim());
        if (!match.Success) { return null; }
        if (match.Groups["vbl"].Success) { return (192 * 65, null); }
        int scanline = int.Parse(match.Groups["scanline"].Value, CultureInfo.InvariantCulture);
        int column = match.Groups["column"].Success ? int.Parse(match.Groups["column"].Value, CultureInfo.InvariantCulture) : 0;
        return scanline < 262 && column < 65
            ? ((scanline * 65) + column, null)
            : (0, "A scanline is 0-261 and a column 0-64.");
    }

    // Stops for the scanline breakpoints at the beam's position, if their conditions and hit counts say to.
    private BreakpointStop? BeamStop(int position)
    {
        List<BreakpointState> stops = [];
        string? description = null;
        foreach ((int at, BreakpointState state) in _beamBreakpoints)
        {
            if (at != position || !Triggers(state, access: null, out string? error)) { continue; }
            stops.Add(state);
            description ??= error;
        }

        string reached = $"The video beam reached scanline {position / 65}, column {position % 65}.";
        if (stops.Count != 0)
        {
            return new("function breakpoint", [.. stops.Select(state => state.Id)], Hidden: null, description ?? reached);
        }

        return BreaksOn(ScanlineFilter) && _scanlinePositions.Contains(position)
            ? new("breakpoint", [], Hidden: null, reached)
            : null;
    }

    // Instruction breakpoints are set in the Disassembly view, by address.
    private JsonObject InstructionBreakpoints(JsonObject args)
    {
        _instructionRequest = args;
        RemoveSites(InstructionGroup);
        HashSet<string> kept = [];
        List<JsonObject> responses = [];
        foreach (JsonObject breakpoint in (args["breakpoints"] as JsonArray ?? []).OfType<JsonObject>())
        {
            string reference = breakpoint.String("instructionReference")
                ?? throw new ArgumentException("instructionReference is required.");

            // A reference may name a bank, such as bank1:0xD000, to stop only while the CPU runs that bank's code.
            DebugMemoryBank? bank = null;
            string? problem = null;
            long address = 0;
            try
            {
                address = (_target is null ? Address(reference) : MemoryReference(reference, out bank))
                    + (breakpoint.Int("offset") ?? 0);
            }
            catch (Exception exception) when (IsEvaluationError(exception))
            {
                problem = exception.Message;
            }

            string prefix = bank is null ? "" : $"{bank.Name}:";
            BreakpointState state = State(
                InstructionGroup,
                $"{prefix}{address.ToString(CultureInfo.InvariantCulture)}",
                breakpoint,
                kept);

            state.Kind = "instruction breakpoint";
            state.Location = $"{prefix}${address:X4}";
            if (problem is not null)
            {
                state.Problem ??= problem;
            }
            else if (address is < 0 or > 0xFFFF)
            {
                state.Problem ??= "The address is outside the CPU's 64K.";
            }
            else if (bank is not null && bank.Peek((ushort)address) is null)
            {
                state.Problem ??= $"{bank.Label} has no byte at ${address:X4}.";
            }
            else
            {
                AddSite((ushort)address, new(Module: null, Line: null, state, bank));
                state.Address = (int)address;
            }

            state.Response = new JsonObject
            {
                ["id"] = state.Id,
                ["verified"] = state.Problem is null,
                ["instructionReference"] = $"0x{address:X4}"
            };

            responses.Add(Describe(state, changed: false));
        }

        Forget(InstructionGroup, kept);
        return new JsonObject { ["breakpoints"] = responses.ToJsonArray() };
    }

    // Data breakpoints watch memory, or a Z80's I/O ports, for reads, writes or both.
    private JsonObject DataBreakpoints(JsonObject args)
    {
        _dataRequest = args;
        _watches.Clear();
        _basicWatches.Clear();
        _basicWatchValues.Clear();
        _dataHits.Clear();
        HashSet<string> kept = [];
        List<JsonObject> responses = [];
        foreach (JsonObject breakpoint in (args["breakpoints"] as JsonArray ?? []).OfType<JsonObject>())
        {
            string id = breakpoint.String("dataId") ?? throw new ArgumentException("dataId is required.");
            string access = breakpoint.String("accessType") ?? "write";
            BreakpointState state = State(DataGroup, $"{id}\n{access}", breakpoint, kept);
            state.Kind = "data breakpoint";
            if (id.StartsWith(BasicDataPrefix, StringComparison.Ordinal))
            {
                WatchBasic(state, id);
            }
            else if (DataId().Match(id) is not { Success: true } match)
            {
                state.Problem ??= $"'{id}' is not a Retrocore data breakpoint.";
            }
            else
            {
                bool port = match.Groups["kind"].Value == "port";
                string? name = match.Groups["bank"].Success ? match.Groups["bank"].Value : null;
                DebugMemoryBank? bank = name is null ? null
                    : _target?.Banks.FirstOrDefault(bank => string.Equals(bank.Name, name, StringComparison.OrdinalIgnoreCase));

                int start = int.Parse(match.Groups["start"].Value, NumberStyles.HexNumber, CultureInfo.InvariantCulture);
                int length = int.Parse(match.Groups["length"].Value, NumberStyles.None, CultureInfo.InvariantCulture);
                state.Location = $"{Describe(port, start, length, bank?.Name ?? name)} ({Access(access)})";
                if (port && _target is { HasPorts: false })
                {
                    state.Problem ??= "This CPU has no I/O ports.";
                }
                else if (name is not null && bank is null)
                {
                    // Before launch there is no machine to name the bank; launch sets the breakpoints again.
                    if (_target is not null) { state.Problem ??= $"This machine has no memory bank '{name}'."; }
                }
                else if (state.Problem is null)
                {
                    _watches.Add(new(start, length, port, access != "write", access != "read", state, bank));
                }
            }

            state.Response = new JsonObject { ["id"] = state.Id, ["verified"] = state.Problem is null };
            responses.Add(Describe(state, changed: false));
        }

        Forget(DataGroup, kept);
        return new JsonObject { ["breakpoints"] = responses.ToJsonArray() };
    }

    private static string Access(string access) => access switch
    {
        "read" => "read",
        "readWrite" => "read or write",
        _ => "write"
    };

    private static string Describe(bool port, int start, int length, string? bank = null)
    {
        string prefix = port ? "port " : bank is null ? "" : $"{bank}:";
        string digits = port && start + length <= 0x100 ? "X2" : "X4";
        string first = start.ToString(digits, CultureInfo.InvariantCulture);
        if (length == 1) { return $"{prefix}${first}"; }
        string last = (start + length - 1).ToString(digits, CultureInfo.InvariantCulture);
        return $"{prefix}${first}-${last}";
    }

    /// <summary>
    ///  Answers dataBreakpointInfo: what a variable, watch expression or address can watch.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A memory variable watches its byte, and registers cannot be watched. An expression watches the bytes
    ///   <c>[address]</c> or <c>[address].w</c> read, the byte at a label, or <c>port N</c>'s I/O port; an address
    ///   from Add Data Breakpoint at Address watches the bytes it asks for.
    ///  </para>
    /// </remarks>
    private JsonObject DataBreakpointInfo(JsonObject args)
    {
        string name = Required(args, "name").Trim();
        int reference = args.Int("variablesReference") ?? 0;
        bool basic = (reference >= BasicReferences && reference < PascalReferences) || (reference == 0 && args.Int("frameId") >= BasicFrameBase);
        if (basic && HasBasicThread)
        {
            string description = $"'{name}' is not a BASIC variable or array element.";
            return BasicDataBreakpointInfo(reference, name) ?? new JsonObject
            {
                ["dataId"] = (string?)null,
                ["description"] = description
            };
        }

        string[] accessTypes = ["write", "read", "readWrite"];
        string? reason = null;
        (bool Port, DebugMemoryBank? Bank, int Start, int Length)? watch = null;
        try
        {
            watch = reference != 0
                ? Variable(reference, name, out reason)
                : args.Bool("asAddress") == true
                    ? AddressWatch(name, args.Int("bytes") ?? 1)
                    : Expression(name, out reason);
        }
        catch (Exception exception) when (IsEvaluationError(exception))
        {
            reason = exception.Message;
        }

        if (watch is { } value && (value.Length < 1 || value.Start + value.Length > 0x10000))
        {
            reason = "The bytes watched must be within the CPU's 64K.";
            watch = null;
        }
        else if (watch is { Bank: { } bank } banked && Missing(bank, banked.Start, banked.Length) is { } missing)
        {
            reason = $"{bank.Label} has no byte at ${missing:X4}.";
            watch = null;
        }

        if (watch is not { } found)
        {
            return new JsonObject
            {
                ["dataId"] = (string?)null,
                ["description"] = reason ?? $"'{name}' cannot be watched."
            };
        }

        string place = Describe(found.Port, found.Start, found.Length, found.Bank?.Name);
        bool named = found.Bank is null
            && !name.StartsWith('$')
            && !name.StartsWith("0x", StringComparison.OrdinalIgnoreCase);

        string kind = found.Port ? "port" : found.Bank is { } watched ? $"bank:{watched.Name}" : "mem";
        return new JsonObject
        {
            ["dataId"] = $"{kind}:{found.Start:X4}:{found.Length}",
            ["description"] = named && reference == 0 ? $"{name} ({place})" : place,
            ["accessTypes"] = accessTypes.ToJsonArray(),
            ["canPersist"] = true
        };
    }

    // A variable in the Variables view: the memory scope's bytes can be watched, and registers cannot.
    private static (bool, DebugMemoryBank?, int, int)? Variable(int reference, string name, out string? reason)
    {
        reason = null;
        if (reference == BanksScope)
        {
            reason = "Watch a byte of a bank instead, such as [aux:$0400].";
            return null;
        }

        if (reference > DocumentationScope || (reference & 1) != 0)
        {
            reason = "Only memory can be watched; registers and documentation cannot.";
            return null;
        }

        return (false, null, Address(name), 1);
    }

    // Add Data Breakpoint at Address: an address expression, which may name a bank, such as aux:$0400.
    private (bool, DebugMemoryBank?, int, int) AddressWatch(string name, int bytes)
    {
        long address = MemoryReference(name, out DebugMemoryBank? bank);
        return (false, bank, checked((ushort)address), bytes);
    }

    // The first address of a range a bank has no byte for, or null when it has them all.
    private static int? Missing(DebugMemoryBank bank, int start, int length)
    {
        for (int address = start; address < start + length; address++)
        {
            if (bank.Peek((ushort)address) is null) { return address; }
        }

        return null;
    }

    private (bool, DebugMemoryBank?, int, int)? Expression(string name, out string? reason)
    {
        reason = null;
        if (PortExpression().Match(name) is { Success: true } port)
        {
            if (!Target.HasPorts)
            {
                reason = "This CPU has no I/O ports.";
                return null;
            }

            int value = checked((ushort)Evaluate(port.Groups[1].Value));
            return (true, null, value, 1);
        }

        if (MemoryExpression().Match(name) is { Success: true } memory)
        {
            long address = MemoryReference(memory.Groups[1].Value, out DebugMemoryBank? bank);
            return (false, bank, checked((ushort)address), memory.Groups[2].Success ? 2 : 1);
        }

        if (Target.Registers.Value(Target.Frame, name) is not null)
        {
            reason = "Registers cannot be watched; watch memory, such as [$0400].";
            return null;
        }

        return (false, null, checked((ushort)Evaluate(name)), 1);
    }

    /// <summary>
    ///  Answers retro/breakpoints: every breakpoint with its hits, after zeroing them when asked.
    /// </summary>
    private JsonObject BreakpointList(JsonObject args)
    {
        if (args.Bool("reset") == true)
        {
            foreach (BreakpointState state in _states.Values) { state.Hits = 0; }
            NotifyHits();
        }

        return new JsonObject
        {
            ["breakpoints"] = _states.Values.OrderBy(state => state.Id).Select(state => new JsonObject
{
                ["id"] = state.Id,
                ["kind"] = state.Kind,
                ["location"] = state.Location,
                ["path"] = state.Line?.Path,
                ["line"] = state.Line?.Line,
                ["address"] = state.Address is { } address ? $"0x{address:X4}" : null,
                ["verified"] = state.Problem is null,
                ["hits"] = state.Hits,
                ["condition"] = state.Condition,
                ["hitCondition"] = state.HitText,
                ["logMessage"] = state.LogMessage,
                ["message"] = state.Problem
}).ToJsonArray()
        };
    }

    // Finds or creates a group's breakpoint and takes its condition, hit count and log message from the request.
    private BreakpointState State(string group, string key, JsonNode request, HashSet<string> kept)
    {
        string full = $"{group}\n{key}";
        kept.Add(full);
        if (!_states.TryGetValue(full, out BreakpointState? state))
        {
            state = new(_nextBreakpoint++, group);
            _states.Add(full, state);
        }

        state.Condition = Text(request, "condition");
        state.HitText = Text(request, "hitCondition");
        state.LogMessage = Text(request, "logMessage");
        state.Problem = null;
        state.HitTest = null;
        if (state.HitText is { } hits)
        {
            try
            {
                state.HitTest = HitCondition.Parse(hits);
            }
            catch (FormatException exception)
            {
                state.Problem = exception.Message;
            }
        }

        return state;
    }

    private static string? Text(JsonNode request, string name) =>
        request.String(name) is { } text && !string.IsNullOrWhiteSpace(text) ? text.Trim() : null;

    // Forgets a group's breakpoints that its latest request no longer lists.
    private void Forget(string group, HashSet<string> kept)
    {
        foreach (string key in _states.Keys.ToArray())
        {
            if (_states[key].Group == group && !kept.Contains(key)) { _states.Remove(key); }
        }
    }

    private void RemoveSites(string group)
    {
        foreach (List<BreakpointSite> sites in _breakpoints.Values)
        {
            sites.RemoveAll(site => site.Breakpoint.Group == group);
        }
    }

    private void AddSite(ushort address, BreakpointSite site)
    {
        if (!_breakpoints.TryGetValue(address, out List<BreakpointSite>? sites))
        {
            sites = [];
            _breakpoints.Add(address, sites);
        }

        sites.Add(site);
    }

    // A breakpoint as DAP reports it, with its problem or its hits as the message.
    private static JsonObject Describe(BreakpointState state, bool changed)
    {
        JsonObject breakpoint = (JsonObject)state.Response.DeepClone();
        string? message = state.Problem ?? state.Hits switch
        {
            0 => changed ? "Not hit" : null,
            1 => "Hit once",
            int hits => $"Hit {hits} times"
        };

        if (message is not null) { breakpoint["message"] = message; }
        return breakpoint;
    }

    // Sends a changed breakpoint event for each breakpoint whose hits have changed since they were last sent.
    private void NotifyHits()
    {
        foreach (BreakpointState state in _states.Values)
        {
            if (state.Hits == state.Reported) { continue; }
            state.Reported = state.Hits;
            Notify("breakpoint", new JsonObject
            {
                ["reason"] = "changed",
                ["breakpoint"] = Describe(state, changed: true)
            });
        }
    }

    private void Stopped(BreakpointStop stop) => Stopped(stop.Reason, stop.Ids, stop.Description, stop.Hidden);

    /// <summary>
    ///  Finds the breakpoints that stop at an address: each counts a hit where its module applies and its
    ///  condition holds, logs instead of stopping when it has a log message, and stops when its hit count does.
    /// </summary>
    /// <param name="pc">The instruction address.</param>
    /// <returns>The stop, or null.</returns>
    private BreakpointStop? Hit(ushort pc)
    {
        List<BreakpointSite> sites = _breakpoints.GetValueOrDefault(pc) ?? s_noSites;
        if (sites.Count == 0 && _systemCallBreakpoints.Count == 0) { return null; }
        List<BreakpointState> stops = [];
        HashSet<BreakpointState> seen = [];
        int? hidden = null;
        string? description = null;
        foreach (BreakpointSite site in sites)
        {
            if (site.Bank is { } bank && !bank.Areas.Contains(Target.ReadArea(pc))) { continue; }
            int? levels = null;
            if (site.Module is { } module)
            {
                if (!DebugInfo.Active(module, Target, pc) || module.Position(Target, pc) is not { } position)
                {
                    continue;
                }

                // Show the breakpoint's own line: the outermost level that is that line.
                levels = 0;
                for (int level = 0; level < position.Chain.Count; level++)
                {
                    if (site.Line is { } line && position.Chain[level].Is(line.Path, line.Line)) { levels = level; }
                }
            }

            if (!seen.Add(site.Breakpoint) || !Triggers(site.Breakpoint, access: null, out string? error)) { continue; }
            stops.Add(site.Breakpoint);
            hidden ??= levels;
            description ??= error;
        }

        if (_systemCallBreakpoints.Count != 0 && Target.SystemCall(pc) is { } call)
        {
            foreach ((byte? number, BreakpointState state) in _systemCallBreakpoints)
            {
                if ((number is { } only && only != call.Number)
                    || !seen.Add(state)
                    || !Triggers(state, access: null, out string? error))
                {
                    continue;
                }

                stops.Add(state);
                description ??= error ?? $"SOS call {call.Name} (${call.Number:X2}) at ${pc:X4}.";
            }
        }

        return stops.Count == 0 ? null : new(stops[0].Kind, [.. stops.Select(state => state.Id)], hidden, description);
    }

    // Notes the data breakpoints a bus cycle hits, for when its instruction finishes.
    private void Watch(in ProcessorCycle cycle)
    {
        foreach (DataWatch watch in _watches)
        {
            if (!watch.Matches(cycle, out bool write) || _dataHits.Exists(hit => hit.Breakpoint == watch.Breakpoint))
            {
                continue;
            }

            // A bank's watch sees only the accesses the memory map sends to it; the map has not changed since, as
            // only accesses to soft switches change it.
            if (watch.Bank is { } bank
                && !bank.Areas.Contains(write ? Target.WriteArea(cycle.Address) : Target.ReadArea(cycle.Address)))
            {
                continue;
            }

            int address = watch.Port && watch.Start + watch.Length <= 0x100 ? cycle.Address & 0xFF : cycle.Address;
            string place = Describe(watch.Port, address, length: 1, watch.Bank?.Name);
            string description = write ? $"Wrote ${cycle.Value:X2} to {place}." : $"Read ${cycle.Value:X2} from {place}.";
            _dataHits.Add((watch.Breakpoint, description));
        }
    }

    // Stops for the data breakpoints the instruction that just finished hit, if their conditions and hit counts say
    // to. Returns false when it stops.
    private bool DataStop()
    {
        List<BreakpointState> stops = [];
        string? description = null;
        foreach ((BreakpointState state, string seen) in _dataHits)
        {
            if (!Triggers(state, seen, out string? error)) { continue; }
            stops.Add(state);
            description ??= error ?? seen;
        }

        _dataHits.Clear();
        if (stops.Count == 0) { return true; }
        Stopped("data breakpoint", [.. stops.Select(state => state.Id)], description);
        _unchecked = true;
        return false;
    }

    /// <summary>
    ///  Applies a breakpoint's condition, hit count and log message where it is reached.
    /// </summary>
    /// <param name="state">The breakpoint.</param>
    /// <param name="access">What a data breakpoint saw, for its log message.</param>
    /// <param name="error">Why the condition could not be evaluated, which stops.</param>
    /// <returns>Whether it stops.</returns>
    private bool Triggers(BreakpointState state, string? access, out string? error)
    {
        error = null;
        if (state.Condition is { } condition)
        {
            try
            {
                if (Evaluate(condition) == 0) { return false; }
            }
            catch (Exception exception) when (IsEvaluationError(exception))
            {
                error = $"The breakpoint condition '{condition}' failed: {exception.Message}";
                state.Hits++;
                return true;
            }
        }

        state.Hits++;
        if (state.HitTest is { } test && !test.Matches(state.Hits)) { return false; }
        if (state.LogMessage is not { } message) { return true; }
        string text = access is null ? Interpolate(message) : $"{Interpolate(message)} ({access})";
        // A source breakpoint's message links to its line; the others have no line to link to.
        JsonObject output = new JsonObject { ["category"] = "console", ["output"] = $"{text}\n" };
        if (state.Line is { } line)
        {
            output["source"] = new JsonObject { ["name"] = Path.GetFileName(line.Path), ["path"] = line.Path };
            output["line"] = line.Line;
        }

        Log(output);
        return false;
    }

    /// <summary>
    ///  Writes a logpoint's line, unless logpoints have written their limit in the last second; the lines dropped
    ///  are counted, and reported when the next second starts or the machine stops.
    /// </summary>
    private void Log(JsonObject output)
    {
        long now = Stopwatch.GetTimestamp();
        if (Stopwatch.GetElapsedTime(_logWindow, now).TotalSeconds >= 1)
        {
            ReportDropped();
            _logWindow = now;
            _logged = 0;
        }

        if (_logpointLimit != 0 && _logged >= _logpointLimit)
        {
            _dropped++;
            return;
        }

        _logged++;
        Notify("output", output);
    }

    // Reports dropped logpoint lines once their second has passed, for a running machine that logs no more.
    private void FlushLog()
    {
        if (_dropped != 0 && Stopwatch.GetElapsedTime(_logWindow).TotalSeconds >= 1) { ReportDropped(); }
    }

    // Reports the logpoint lines the limit dropped, if any.
    private void ReportDropped()
    {
        if (_dropped == 0) { return; }
        string lines = _dropped == 1 ? "1 logpoint line" : $"{_dropped} logpoint lines";
        Notify("output", new JsonObject
        {
            ["category"] = "important",
            ["output"] = $"Retrocore dropped {lines}: logpoints write at most {_logpointLimit} a second. Set "
                + "logpointLimit in the launch configuration to change it, or 0 for no limit.\n"
        });

        _dropped = 0;
    }

    /// <summary>
    ///  Fills a log message's <c>{expression}</c> placeholders, with <c>{{</c> and <c>}}</c> for braces. A value
    ///  shows as hex like <c>$1F</c>; <c>{expression,d}</c> shows decimal, <c>,x</c> bare hex, <c>,b</c> binary
    ///  and <c>,c</c> the ASCII character. <c>{sos}</c> describes the SOS call about to be made, such as
    ///  <c>OPEN ".CONSOLE"</c>.
    /// </summary>
    /// <param name="message">The log message.</param>
    /// <returns>The text.</returns>
    private string Interpolate(string message)
    {
        using ValueStringBuilder text = new(stackalloc char[256]);
        for (int index = 0; index < message.Length; index++)
        {
            char character = message[index];
            if (character is '{' or '}' && index + 1 < message.Length && message[index + 1] == character)
            {
                text.Append(character);
                index++;
                continue;
            }

            int end = character == '{' ? message.IndexOf('}', index + 1) : -1;
            if (end < 0)
            {
                text.Append(character);
                continue;
            }

            text.Append(Placeholder(message[(index + 1)..end]));
            index = end;
        }

        return text.ToString();
    }

    private string Placeholder(string placeholder)
    {
        if (placeholder.Trim().Equals("sos", StringComparison.OrdinalIgnoreCase))
        {
            return Target.DescribeSystemCall(Target.ProgramCounter) ?? "{sos: no SOS call is made here}";
        }

        int comma = placeholder.LastIndexOf(',');
        string format = comma < 0 ? "" : placeholder[(comma + 1)..].Trim().ToLowerInvariant();
        if (format is not ("d" or "x" or "b" or "c")) { format = ""; }
        string expression = format.Length == 0 ? placeholder : placeholder[..comma];
        try
        {
            long value = Evaluate(expression);
            return format switch
            {
                "d" => value.ToString(CultureInfo.InvariantCulture),
                "x" => value.ToString("X", CultureInfo.InvariantCulture),
                "b" => $"%{Convert.ToString(value, toBase: 2)}",
                "c" => ((char)(value & 0x7F)).ToString(),
                _ => $"${value:X}"
            };
        }
        catch (Exception exception) when (IsEvaluationError(exception))
        {
            return $"{{{expression.Trim()}: {exception.Message}}}";
        }
    }

    private long Evaluate(string expression) => new ExpressionEvaluator(Target, _debug, expression).Evaluate();

    private static bool IsEvaluationError(Exception exception) =>
        exception is FormatException or OverflowException or DivideByZeroException or ArgumentException;

    [GeneratedRegex(@"^(?:(?<kind>mem|port)|bank:(?<bank>[a-zA-Z][a-zA-Z0-9]*)):(?<start>[0-9A-F]{1,4}):(?<length>\d{1,5})$")]
    private static partial Regex DataId();

    [GeneratedRegex(@"^port\s+(.+)$", RegexOptions.IgnoreCase)]
    private static partial Regex PortExpression();

    [GeneratedRegex(@"^scanline\s+(?:(?<vbl>vbl)|(?<scanline>\d{1,3})(?::(?<column>\d{1,2}))?)$",
        RegexOptions.IgnoreCase)]
    private static partial Regex ScanlineBreakpoint();

    [GeneratedRegex(@"^sos(?:\s+(?<call>.+))?$", RegexOptions.IgnoreCase)]
    private static partial Regex SystemCallBreakpoint();

    [GeneratedRegex(@"^\[(.+)\](\.w)?$")]
    private static partial Regex MemoryExpression();
}
