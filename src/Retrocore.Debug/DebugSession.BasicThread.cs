// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text.Json.Nodes;
using Retrocore.Basic;

namespace Retrocore.Debug;

// The BASIC thread: the program's statements, GOSUBs, breakpoints, steps and stops, beside the CPU's.
//
// Every statement starts at the ROM's GONE, with the current line set and the text pointer before the statement, or
// where the target says it starts one otherwise (AppleSoft under ProDOS's BASIC.SYSTEM, which skips GONE). The run
// looks at BASIC only there and at the ROM's error and stop routines, so a program without BASIC breakpoints or
// steps runs as before. Frames come from BASIC's own stack, as saved when the statement began.
internal sealed partial class DebugSession
{
    private const int BasicThread = 2;
    private const int BasicFrameBase = 50000;
    private const int MaximumStackEntries = 128;
    private const double PauseSeconds = 0.5;
    private const string BasicGroup = "basic";
    private const string BasicErrorsFilter = "basicErrors";
    private const string BasicHandledFilter = "basicHandledErrors";
    private const string BasicStopFilter = "basicStop";
    private const string BasicStartFilter = "basicStart";

    // A RUN or CONT on its way to its first statement: "RUN starts" or "CONT resumes".
    private string? _basicStarting;

    private const string NotAtStatement =
        "Set Next Statement works when BASIC is at the start of a statement: step on the BASIC thread first.";

    private static readonly HashSet<string> s_machineCalls = ["CALL", "&", "USR", "SYSTEM", "PERFORM", "EXFN.", "EXFN%."];


    // Where the machine-program documents live, which the extension gives at the session's start.
    private string? _basicDocumentBase;

    // The machine-program document's URI. Its name follows the BASIC in memory now, as DOS's INT and FP switch it.
    private string? BasicDocument => _basicDocumentBase is null || Target.Basic is not { } dialect
        ? null
        : $"{_basicDocumentBase}Program.{dialect.Name}.bas";

    // The line, address and BASIC stack of the statement that started last, recorded at GONE.
    private (int Line, int Address, int Stack)? _basicStatement;
    private BasicGoal? _basicGoal;
    private BasicView? _basicView;
    private JsonObject? _basicBreakpoints;
    private readonly Dictionary<int, List<(int Line, BreakpointState State)>> _basicSites = [];

    // The BASIC line and statement each of the document's breakpoints is on, by its place in the request, and the
    // text of every line of the program they were set in, which tell a program edited from one replaced.
    private readonly Dictionary<int, (int Number, int Statement)> _basicAnchors = [];
    private HashSet<string> _basicBoundLines = [];

    // AppleSoft's STOP and END run into ENDCON, which also ends a program that runs off its last line.
    private bool _basicEnded;

    /// <summary>
    ///  Registers the BASIC thread's own requests.
    /// </summary>
    /// <param name="transport">The protocol's wire.</param>
    private void RegisterBasicThread(DapTransport transport)
    {
        transport.On("retro/basic/document", args => Reply(() =>
        {
            _basicDocumentBase = Required(args, "base");
            _ = Basic;
            return new JsonObject { ["uri"] = BasicDocument };
        }));

        transport.On("breakpointLocations", args => Reply(() => BreakpointLocations(args)));
        transport.On("gotoTargets", args => Reply(() => GotoTargets(args)));
        transport.On("goto", args => Reply(() => GotoStatement((args.Int("targetId") ?? 0))));
    }

    /// <summary>
    ///  Gets the BASIC filters the Breakpoints view lists.
    /// </summary>
    private static (string Filter, string Label, string Description, bool Default)[] BasicFilters =>
    [
        (BasicStartFilter, "BASIC program start", "Stops at the first statement RUN runs, and where CONT resumes.", true),
        (BasicErrorsFilter, "BASIC errors", "Stops at the statement that fails when no ONERR GOTO or ON ERROR GOTO will take the error.", true),
        (BasicHandledFilter, "Handled BASIC errors", "Stops even when an error handler will take the error.", false),
        (BasicStopFilter, "BASIC program end", "Stops at STOP, END, the end of the program, and Ctrl-C or BREAK.", false)
    ];

    // The BASIC ROM's addresses, when its source applies to the ROM mapped now.
    private BasicRom? ActiveBasic => Target.BasicRom is { } rom && _debug.Position(Target, rom.Gone) is not null ? rom : null;

    private bool BasicDirect => Target.Basic is not { } dialect || dialect.InDirectMode(new TargetBasicMemory(Target));

    private int CurrentLine => Target.BasicCurrentLine;

    private bool HasBasicThread => _target is { Basic: not null, BasicRom: not null };

    // The threads: the CPU's, and BASIC's on a machine with a BASIC the debugger knows.
    // Pascal's too once its interpreter is found, and the coprocessor's while the machine has one.
    private JsonArray Threads()
    {
        JsonArray threads = [new JsonObject { ["id"] = 1, ["name"] = _target?.ThreadName ?? "CPU" }];
        if (_target is not null && HasBasicThread)
        {
            threads.Add((JsonNode)new JsonObject
            {
                ["id"] = BasicThread, ["name"] = "BASIC"
            });
        }

        if (_target is not null && HasPascalThread)
        {
            threads.Add((JsonNode)new JsonObject
            {
                ["id"] = PascalThread, ["name"] = "Pascal"
            });
        }

        if (_target?.Coprocessor is { } coprocessor)
        {
            threads.Add((JsonNode)new JsonObject
            {
                ["id"] = SoftCardThread, ["name"] = coprocessor.ThreadName
            });
        }

        return threads;
    }

    // Records the statement that starts at GONE, for the BASIC thread's top frame.
    private void ObserveBasic(ushort pc)
    {
        if (Target.BasicRom is null || Target.BasicStatementStart(pc) is not { } start || BasicDirect) { return; }
        _basicStatement = (start.Line, start.Address, Target.BasicLiveStack);
        _basicEnded = false;
    }

    /// <summary>
    ///  Checks where BASIC is before an instruction runs: a statement's start, an error, a stop, the prompt, or a
    ///  step leaving BASIC for machine code.
    /// </summary>
    /// <param name="pc">The instruction's address.</param>
    /// <returns>Whether the run stopped.</returns>
    private bool BasicStops(ushort pc)
    {
        if (Target.BasicRom is not { } rom) { return false; }
        if (_basicGoal is { } goal)
        {
            if (goal.Step == BasicStep.Into && goal.CallsMachine && !Target.InRom(pc))
            {
                Stopped("step", description: $"Machine code at ${pc:X4}");
                return true;
            }

            if (goal.Step == BasicStep.Pause && Target.CycleCount >= goal.Deadline)
            {
                Stopped("pause", threadId: BasicThread);
                return true;
            }
        }

        if (Target.BasicStatementStart(pc) is { } start) { return StatementStops(start.Line, start.Address); }
        if (pc == rom.Run) { _basicStarting = "RUN starts"; }
        if (pc == rom.Continue) { _basicStarting = "CONT resumes"; }
        if (pc == rom.Prompt) { _basicStarting = null; }
        if (pc == rom.Prompt && _basicGoal is not null && ActiveBasic is not null)
        {
            Stopped("step", description: "BASIC is at its prompt.", threadId: BasicThread);
            return true;
        }

        if (pc == rom.Error)
        {
            // An error stops the program by its own route, which passes the stop routines after it.
            _basicEnded = true;
            return ErrorStops();
        }

        if (!rom.Stops.TryGetValue(pc, out string? kind)) { return false; }
        if (kind == BasicRom.IntegerRanOff)
        {
            // Running off the last line is an error, reported once BASIC has left the program: stop for it here.
            _basicEnded = true;
            return ErrorStops();
        }

        return EndStops(kind);
    }

    private bool StatementStops(int line, int address)
    {
        bool idle = _basicSites.Count == 0 && _basicGoal is null && _basicWatches.Count == 0 && _basicStarting is null;
        if (idle || ActiveBasic is null || BasicDirect) { return false; }

        // The program's first statement after RUN or CONT; a breakpoint or step stopping there is its one stop.
        string? starting = _basicStarting;
        _basicStarting = null;
        _basicStatement = (line, address, Target.BasicLiveStack);
        _basicEnded = false;
        if (_basicSites.TryGetValue(address, out List<(int Line, BreakpointState State)>? sites))
        {
            List<int> ids = [];
            string? error = null;
            foreach ((int number, BreakpointState state) in sites)
            {
                if (number != line || !BasicTriggers(state, out string? failed)) { continue; }
                ids.Add(state.Id);
                error ??= failed;
            }

            if (ids.Count != 0)
            {
                Stopped("breakpoint", [.. ids], description: error, threadId: BasicThread);
                return true;
            }
        }

        if (_basicWatches.Count != 0 && BasicWatchStops()) { return true; }

        if (starting is not null && BreaksOn(BasicStartFilter) && _basicGoal?.Step is not BasicStep.Entry)
        {
            Stopped("breakpoint", description: $"{starting} at {line}.", threadId: BasicThread);
            return true;
        }

        if (_basicGoal is not { } goal) { return false; }
        bool done = goal.Step switch
        {
            BasicStep.Over => BasicDepth() <= goal.Depth,
            BasicStep.Out => BasicDepth() < goal.Depth,
            _ => true
        };

        string reason = goal.Step switch
        {
            BasicStep.Pause => "pause",
            BasicStep.Entry => "entry",
            _ => "step"
        };

        if (done) { Stopped(reason, threadId: BasicThread); }
        return done;
    }

    private bool ErrorStops()
    {
        if (!BreaksOn(BasicErrorsFilter) && !BreaksOn(BasicHandledFilter)) { return false; }
        if (ActiveBasic is null || BasicDirect) { return false; }
        (int code, string message, bool handled) = Target.BasicError();
        if (!BreaksOn(handled ? BasicHandledFilter : BasicErrorsFilter)) { return false; }
        string description = handled
            ? $"{message} in {CurrentLine} (code {code}); the error handler will take it."
            : $"{message} in {CurrentLine} (code {code}).";

        Stopped("exception", description: description, exception: "basic-error", threadId: BasicThread);
        return true;
    }

    private bool EndStops(string kind)
    {
        if (ActiveBasic is null || BasicDirect) { return false; }
        if (kind is BasicRom.IntegerStop or BasicRom.Apple1Stop or BasicRom.IntegerEnd)
        {
            // Integer BASIC's errors and Control-C, and Apple-1 BASIC's errors and keys, stop at STOPPED AT, which
            // runs into END: only the first says why.
            bool reported = _basicEnded;
            _basicEnded = true;
            if (reported || !BreaksOn(BasicStopFilter)) { return false; }
            string why = kind switch
            {
                BasicRom.IntegerStop => "Ctrl-C",
                BasicRom.Apple1Stop => "A key",
                _ => "END"
            };

            Stopped("exception", description: $"{why} in {CurrentLine}.", exception: "basic-stop", threadId: BasicThread);
            return true;
        }

        string? what = kind switch
        {
            "STOP" => StatementWord() is "STOP" or "END" ? StatementWord() : "Ctrl-C",
            BasicRom.StopOrBreak => StatementWord() == "STOP" ? "STOP" : "BREAK",
            "END" => "END",
            "ENDCON" or "PRGEND" => _basicEnded ? null : "the end of the program",
            _ => StatementWord() is "STOP" or "END" ? StatementWord() : "BREAK"
        };

        _basicEnded = kind is "STOP" or "END" or BasicRom.StopOrBreak;
        if (what is null)
        {
            _basicEnded = false;
            return false;
        }

        if (!BreaksOn(BasicStopFilter)) { return false; }
        Stopped("exception", description: $"{what} in {CurrentLine}.", exception: "basic-stop", threadId: BasicThread);
        return true;
    }

    // Starts a step on the BASIC thread, which the run finishes at the next statement it is for.
    private void StepBasic(BasicStep step)
    {
        int depth = BasicDepth();
        if (step == BasicStep.Out && depth == 0) { throw new InvalidOperationException("BASIC is not in a GOSUB."); }
        _basicGoal = new(step, depth, step == BasicStep.Into && CallsMachine(), ulong.MaxValue);
        Continue();
    }

    // Pauses the BASIC thread at the next statement, or now when BASIC is not running a program.
    private void PauseBasic()
    {
        if (ActiveBasic is null || BasicDirect || _run is not { IsCancellationRequested: false })
        {
            _run?.Cancel();
            Stopped("pause", threadId: BasicThread);
            return;
        }

        ulong deadline = Target.CycleCount + (ulong)(Target.ClockHertz * PauseSeconds);
        _basicGoal = new(BasicStep.Pause, Depth: 0, CallsMachine: false, deadline);
    }

    // The GOSUBs in progress, from BASIC's stack as the statement began.
    private int BasicDepth() => BasicStackEntries().Count;

    // The GOSUB entries on BASIC's stack, most recent first: the line each was in and its text pointer.
    private List<(int Line, int TextPointer)> BasicStackEntries()
    {
        List<(int, int)> entries = [];
        if (Target.Basic is not { } dialect) { return entries; }
        if (Target.BasicGosubs is { } gosubs) { return [.. gosubs]; }
        int gosub = dialect.StackGosubToken;
        int forToken = dialect.StackForToken;
        int at = BasicStackTop;
        for (int count = 0; count < MaximumStackEntries && at < 0xFFFB; count++)
        {
            int token = Target.Peek((ushort)at);
            if (token == forToken)
            {
                at += Target.BasicForSize;
            }
            else if (token == gosub)
            {
                entries.Add((Word(at + 1), Word(at + 3)));
                at += Target.BasicGosubSize;
            }
            else
            {
                break;
            }
        }

        return entries;
    }

    // BASIC's most recent stack entry: as the current statement began, else as BASIC saved it.
    private int BasicStackTop => _basicStatement is { } last && last.Line == CurrentLine ? last.Stack : Target.BasicStack;

    // The program as the machine-program document shows it, made again when the program changes.
    private BasicView? View()
    {
        string version = BasicVersion();
        if (_basicView?.Version == version) { return _basicView; }
        BasicDialect dialect = Basic;
        try
        {
            BasicProgram program = BasicProgram.Read(dialect, new TargetBasicMemory(Target));
            Dictionary<int, int> addresses = [];
            int address = dialect.ProgramBounds(new TargetBasicMemory(Target)).Start;
            foreach (BasicLine line in program.Lines)
            {
                addresses.TryAdd(line.Number, address);
                address += line.Tokens.Length + dialect.LineOverhead;
            }

            _basicView = new(version, BasicSource.Analyze(program.ToText(), dialect), addresses);
        }
        catch (InvalidDataException)
        {
            _basicView = null;
        }

        return _basicView;
    }

    // The line, statement and text of an address in the program.
    private static (BasicSourceLine Line, int Statement)? Locate(BasicView view, int number, int address)
    {
        if (view.Line(number) is not { } line || !view.Addresses.TryGetValue(number, out int start)) { return null; }
        return (line, line.StatementAt(address - start - (view.Source.Dialect?.LineHeader ?? 4)));
    }

    // The first reserved word of the statement that started last.
    private string? StatementWord()
    {
        if (_basicStatement is not { } statement || Target.Basic is not { } dialect) { return null; }
        IBasicMemory text = TextMemory;
        int at = statement.Address;
        while (text.Read(at) == ' ' && at < statement.Address + 8) { at++; }
        ReadOnlySpan<byte> token = [text.Read(at), text.Read(at + 1)];
        return dialect.KeywordAt(token, 0, out _);
    }

    // Whether the statement that started last calls machine code: CALL, &, USR or SYSTEM, Business BASIC's PERFORM
    // and EXFN., or Color BASIC's EXEC.
    private bool CallsMachine()
    {
        if (_basicStatement is not { } statement || Target.Basic is not { } dialect) { return false; }
        if (dialect is IntegerBasicDialect)
        {
            byte[] tokens = new byte[256];
            for (int index = 0; index < tokens.Length; index++)
            {
                tokens[index] = TextMemory.Read(statement.Address + index);
            }

            return IntegerBasic.CallsMachine(tokens);
        }

        bool inString = false;
        IBasicMemory text = TextMemory;
        for (int at = statement.Address; at < statement.Address + 256; at++)
        {
            byte value = text.Read(at);
            if (value == 0 || (value == ':' && !inString)) { break; }
            if (value == '"') { inString = !inString; }

            // A function after a prefix, such as Business BASIC's $FF, is read with it: REC('s token alone would be
            // EXFN.
            ReadOnlySpan<byte> token = [value, text.Read(at + 1)];
            if (!inString && dialect.KeywordAt(token, 0, out int length) is { } word)
            {
                // Color BASIC's EXEC runs machine code; Business BASIC's reads a file as typed input.
                if (s_machineCalls.Contains(word) || (word == "EXEC" && dialect.Name == "colorbasic")) { return true; }
                at += length - 1;
            }
        }

        return false;
    }

    // The BASIC thread's frames: the current statement, then each GOSUB's.
    private JsonObject BasicStackTrace()
    {
        List<JsonNode?> frames = [];
        BasicView? view = ActiveBasic is null ? null : View();
        BasicFile? file = view is null ? null : InSyncFile();
        if (ActiveBasic is null)
        {
            frames.Add(new JsonObject
            {
                ["id"] = BasicFrameBase,
                ["name"] = "BASIC: not running",
                ["line"] = 0,
                ["column"] = 0
            });
        }
        else if (BasicDirect)
        {
            frames.Add(new JsonObject
            {
                ["id"] = BasicFrameBase,
                ["name"] = "BASIC: ready",
                ["line"] = 0,
                ["column"] = 0
            });
        }
        else
        {
            int line = CurrentLine;
            int address = _basicStatement is { } last && last.Line == line
                ? last.Address
                : view?.Addresses.GetValueOrDefault(line) + Basic.LineHeader ?? 0;

            string note = Target.InRom(Target.ProgramCounter) ? "" : $" (in machine code at ${Target.ProgramCounter:X4})";
            frames.Add(BasicFrame(view, file, frames.Count, line, address, note));
            foreach ((int caller, int pointer) in BasicStackEntries())
            {
                frames.Add(BasicFrame(view, file, frames.Count, caller, pointer + 1, " (GOSUB)"));
            }
        }

        return new JsonObject { ["stackFrames"] = frames.ToJsonArray(), ["totalFrames"] = frames.Count };
    }

    private JsonObject BasicFrame(BasicView? view, BasicFile? file, int index, int number, int address, string note)
    {
        string name = number.ToString(CultureInfo.InvariantCulture);
        if (view is null || Locate(view, number, address) is not { } at)
        {
            return new JsonObject
            {
                ["id"] = BasicFrameBase + index,
                ["name"] = name + note,
                ["line"] = 0,
                ["column"] = 0
            };
        }

        name = $"{number}: {view.Text(at.Line, at.Statement)}{note}";
        if (file is not null && FilePlace(file, number, at.Statement) is { } place)
        {
            return new JsonObject
            {
                ["id"] = BasicFrameBase + index,
                ["name"] = name,
                ["source"] = new JsonObject { ["name"] = Path.GetFileName(file.Path), ["path"] = file.Path },
                ["line"] = place.Line,
                ["column"] = place.Column
            };
        }

        string? path = BasicDocument;
        return new JsonObject
        {
            ["id"] = BasicFrameBase + index,
            ["name"] = name,
            ["source"] = path is null ? null : new JsonObject
            {
                ["name"] = path[(path.LastIndexOf('/') + 1)..],
                ["path"] = path
            },
            ["line"] = at.Line.Line + 1,
            ["column"] = at.Line.Statements[at.Statement].Column + 1
        };
    }

    private static bool IsBasicDocument(string? path) => path?.StartsWith("retrocore-basic:", StringComparison.OrdinalIgnoreCase) == true;

    // Breakpoints in the machine-program document: each on a statement, the line's first unless a column says.
    private JsonObject BasicBreakpoints(JsonObject args)
    {
        _basicBreakpoints = args;
        string path = Required((JsonObject)(args["source"] ?? new JsonObject()), "path");
        RemoveBasicSites(BasicGroup);
        HashSet<string> kept = [];
        List<JsonObject> responses = [];
        BasicView? view = _target is null || Target.Basic is null ? null : View();
        _basicAnchors.Clear();
        _basicBoundLines = view is null ? [] : [.. view.Source.NumberedLines.Select(line => view.Source.Lines[line.Line])];
        JsonArray requested = args["breakpoints"] as JsonArray ?? [];
        for (int index = 0; index < requested.Count; index++)
        {
            if (requested[index] is not JsonObject breakpoint) { continue; }
            int line = (breakpoint.Int("line") ?? 0);
            int? column = breakpoint.Int("column");
            BreakpointState state = State(BasicGroup, $"{line}:{column}", breakpoint, kept);
            state.Kind = "breakpoint";
            state.Line = new(path, line);
            state.Location = $"BASIC line {line}";
            int? at = null;
            if (view is null || line < 1 || line > view.Source.NumberedLines.Count)
            {
                state.Problem ??= "There is no BASIC line here.";
            }
            else
            {
                BasicSourceLine source = view.Source.NumberedLines[line - 1];
                int statement = column is { } value ? source.StatementAtColumn(value - 1) : 0;
                at = source.Statements[statement].Column + 1;
                int address = view.Addresses[source.Number] + Basic.LineHeader + source.Statements[statement].Offset;
                state.Location = $"BASIC {view.Text(source, statement)} (line {source.Number})";
                if (!_basicSites.TryGetValue(address, out List<(int, BreakpointState)>? sites))
                {
                    sites = [];
                    _basicSites.Add(address, sites);
                }

                sites.Add((source.Number, state));
                _basicAnchors[index] = (source.Number, statement);
            }

            state.Response = new JsonObject
            {
                ["id"] = state.Id,
                ["verified"] = state.Problem is null,
                ["line"] = line,
                ["column"] = at,
                ["source"] = new JsonObject { ["name"] = path[(path.LastIndexOf('/') + 1)..], ["path"] = path }
            };

            responses.Add(Describe(state, changed: false));
        }

        Forget(BasicGroup, kept);
        return new JsonObject { ["breakpoints"] = responses.ToJsonArray() };
    }

    // Binds the BASIC breakpoints again after the program changes, and tells VS Code where each is now. A breakpoint
    // follows its BASIC line as the program is edited, and goes with it when the line is deleted. When the program is
    // gone, erased or replaced by another that keeps none of its lines, or BASIC itself changed, they all go.
    // retro/basic/breakpointsMoved tells the extension, which moves them in VS Code's list.
    private void RebindBasicBreakpoints()
    {
        if (_basicBreakpoints is not { } request) { return; }
        string path = Required((JsonObject)(request["source"] ?? new JsonObject()), "path");
        BasicView? view = Target.Basic is null ? null : View();
        bool gone = view is null
            || view.Source.NumberedLines.Count == 0
            || !string.Equals(path, BasicDocument, StringComparison.OrdinalIgnoreCase)
            || (_basicBoundLines.Count > 0
                && !view.Source.NumberedLines.Any(line => _basicBoundLines.Contains(view.Source.Lines[line.Line])));

        JsonArray requested = request["breakpoints"] as JsonArray ?? [];
        List<JsonObject> kept = [];
        List<JsonObject> moves = [];
        for (int index = 0; index < requested.Count; index++)
        {
            if (requested[index] is not JsonObject breakpoint) { continue; }
            (int Line, int? Column) from = ((breakpoint.Int("line") ?? 0), breakpoint.Int("column"));
            (int Line, int? Column)? to = from;
            if (gone || view is null)
            {
                to = null;
            }
            else if (_basicAnchors.TryGetValue(index, out (int Number, int Statement) anchor))
            {
                to = Follow(view, anchor, from.Column);
            }

            if (to is { } place)
            {
                JsonObject copy = (JsonObject)breakpoint.DeepClone();
                copy["line"] = place.Line;
                if (place.Column is { } column) { copy["column"] = column; }
                kept.Add(copy);
            }

            if (to == from) { continue; }
            JsonObject move = new() { ["line"] = from.Line, ["column"] = from.Column };
            if (to is { } moved)
            {
                move["toLine"] = moved.Line;
                move["toColumn"] = moved.Column;
            }

            moves.Add(move);
        }

        if (moves.Count > 0)
        {
            Notify("retro/basic/breakpointsMoved", new JsonObject { ["path"] = path, ["moves"] = moves.ToJsonArray() });
        }

        JsonObject rebound = (JsonObject)request.DeepClone();
        rebound["breakpoints"] = kept.ToJsonArray();
        foreach (JsonObject breakpoint in (BasicBreakpoints(rebound)["breakpoints"] as JsonArray ?? []).OfType<JsonObject>())
        {
            Notify("breakpoint", new JsonObject
            {
                ["reason"] = "changed",
                ["breakpoint"] = breakpoint.DeepClone()
            });
        }
    }

    // Where a breakpoint on a BASIC line's statement is in the document now: the line's place, and the statement's
    // column when the breakpoint has one; null when the line is gone.
    private static (int Line, int? Column)? Follow(BasicView view, (int Number, int Statement) anchor, int? column)
    {
        if (view.Line(anchor.Number) is not { } line) { return null; }
        int statement = Math.Min(anchor.Statement, line.Statements.Count - 1);
        return (line.Line + 1, column is null ? null : line.Statements[statement].Column + 1);
    }

    // The statements on a line of the machine-program document, where inline breakpoints can go.
    private JsonObject BreakpointLocations(JsonObject args)
    {
        string? path = (args["source"] as JsonObject)?.String("path");
        int line = (args.Int("line") ?? 0);
        if (path is not null && IsBasicFile(path) && InSyncFile() is { } file && Same(file.Path, Path.GetFullPath(path)))
        {
            BasicSourceLine? statementLine = file.Source.NumberedLines.FirstOrDefault(found => found.Line == line - 1);
            IReadOnlyList<BasicStatement> starts = statementLine?.Statements ?? [];
            JsonArray places = starts.Select(statement => new JsonObject
            {
                ["line"] = line,
                ["column"] = statement.Column + 1
            }).ToJsonArray();

            return new JsonObject { ["breakpoints"] = places };
        }

        if (!IsBasicDocument(path))
        {
            return new JsonObject { ["breakpoints"] = new JsonArray(new JsonObject { ["line"] = line }) };
        }

        if (View() is not { } view || line < 1 || line > view.Source.NumberedLines.Count)
        {
            return new JsonObject { ["breakpoints"] = new JsonArray() };
        }

        IEnumerable<BasicStatement> statements = view.Source.NumberedLines[line - 1].Statements;
        JsonArray locations = statements.Select(statement => new JsonObject
        {
            ["line"] = line,
            ["column"] = statement.Column + 1
        }).ToJsonArray();

        return new JsonObject { ["breakpoints"] = locations };
    }

    // Where Set Next Statement can go on a line of the machine-program document: its statements.
    private JsonObject GotoTargets(JsonObject args)
    {
        string? path = (args["source"] as JsonObject)?.String("path");
        int line = (args.Int("line") ?? 0);
        int? column = args.Int("column");
        if (View() is not { } view) { return new JsonObject { ["targets"] = new JsonArray() }; }

        // A workspace file's line is its program line in the machine-program document, whose index the target names.
        BasicSourceLine? place = null;
        int machineLine = line;
        if (path is not null && IsBasicFile(path) && InSyncFile() is { } file && Same(file.Path, Path.GetFullPath(path)))
        {
            place = file.Source.NumberedLines.FirstOrDefault(found => found.Line == line - 1);
            machineLine = place is null ? 0 : view.Source.NumberedLines.ToList().FindIndex(found => found.Number == place.Number) + 1;
        }
        else if (!IsBasicDocument(path))
        {
            return new JsonObject { ["targets"] = new JsonArray() };
        }

        if (machineLine < 1 || machineLine > view.Source.NumberedLines.Count)
        {
            return new JsonObject { ["targets"] = new JsonArray() };
        }

        BasicSourceLine source = view.Source.NumberedLines[machineLine - 1];
        BasicSourceLine shown = place ?? source;
        int first = column is { } value ? shown.StatementAtColumn(value - 1) : 0;
        int count = column is null ? Math.Min(source.Statements.Count, shown.Statements.Count) : 1;
        return new JsonObject
        {
            ["targets"] = Enumerable.Range(first, count).Select(statement => new JsonObject
{
                ["id"] = (machineLine << 8) | statement,
                ["label"] = $"{source.Number}: {view.Text(source, statement)}",
                ["line"] = line,
                ["column"] = shown.Statements[statement].Column + 1
}).ToJsonArray()
        };
    }

    // Set Next Statement: BASIC continues at another statement, as a GOTO would, keeping its GOSUBs and FORs.
    private JsonObject GotoStatement(int target)
    {
        if (ActiveBasic is null
            || !Target.IsInstructionBoundary
            || Target.BasicStatementStart(Target.ProgramCounter) is null
            || BasicDirect)
        {
            throw new InvalidOperationException(NotAtStatement);
        }

        BasicView view = View() ?? throw new InvalidOperationException("BASIC has no program.");
        int line = target >> 8;
        int statement = target & 0xFF;
        BasicSourceLine source = view.Source.NumberedLines[line - 1];
        int address = view.Addresses[source.Number] + Basic.LineHeader + source.Statements[statement].Offset;
        Target.SetBasicStatement(source.Number, address - 1);
        _basicStatement = (source.Number, address, Target.BasicLiveStack);
        Stopped("goto", threadId: BasicThread);
        return [];
    }
}
