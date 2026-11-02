// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text.Json.Nodes;
using Retrocore.Basic;

namespace Retrocore.Debug;

// BASIC files in the workspace: the basic launch, which loads and runs one, and debugging a file in place while the
// program in memory is what it compiles to. Its frames and breakpoints map through its line map, so a file with
// labels and no line numbers debugs as written.
internal sealed partial class DebugSession
{
    private const double BootSeconds = 10;
    private const string NoBasicSource = "The debugger has no source for this machine's BASIC ROM, so it cannot load a BASIC file.";

    private readonly Dictionary<string, BasicFile> _basicFiles = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, JsonObject> _basicFileBreakpoints = new(StringComparer.OrdinalIgnoreCase);
    private string? _basicLaunched;

    // Whether the frames last showed the launched file, to say once when the program stops matching it.
    private bool _basicLaunchedInSync;

    // Whether running from launch stops at the first statement, for a basic launch with stopOnEntry.
    private bool _basicEntry;

    private const string MachineFrames = "BASIC frames show the machine's program.";

    private static bool Same(string? left, string? right) => string.Equals(left, right, StringComparison.OrdinalIgnoreCase);

    private static bool IsBasicFile(string path) => path.EndsWith(".bas", StringComparison.OrdinalIgnoreCase);

    // An Integer BASIC file: its first line's pragma says so, its name ends in .integer.bas, or the II runs Integer BASIC.
    private static bool IsIntegerBasic(Apple2DebugTarget target, string path)
    {
        string? first = File.ReadLines(path).FirstOrDefault(line => line.Trim().Length != 0);
        System.Text.RegularExpressions.Match pragma = Pragma().Match(first ?? "");

        return pragma.Success
            ? pragma.Groups[1].Value.Equals("integer", StringComparison.OrdinalIgnoreCase)
            : path.EndsWith(".integer.bas", StringComparison.OrdinalIgnoreCase) || target.RunsIntegerBasic;
    }

    // Starts Integer BASIC at its cold start for an Integer BASIC file, which LaunchBasic then puts in, on a machine
    // whose Integer BASIC is in ROM: a II, or a II Plus's firmware card.
    private static void StartIntegerBasic(Apple2DebugTarget target, string path)
    {
        if (!target.RunsIntegerBasic)
        {
            string name = Path.GetFileName(Path.GetFullPath(path));
            string needs = "which needs a II running it (model ii), or a II Plus with its firmware card";
            throw new ArgumentException($"{name} is Integer BASIC, {needs}.");
        }

        target.StartIntegerBasic();
    }

    [System.Text.RegularExpressions.GeneratedRegex(@"^\s*(?:\d+\s*)?(?:REM|')\s*retrocore\s+(\S+)", System.Text.RegularExpressions.RegexOptions.IgnoreCase)]
    private static partial System.Text.RegularExpressions.Regex Pragma();

    /// <summary>
    ///  Loads a BASIC file for a launch: boots the machine to BASIC's prompt, answering the Model I's MEMORY SIZE?,
    ///  writes the program, and types RUN unless told not to.
    /// </summary>
    /// <param name="path">The file.</param>
    /// <param name="run">Whether to RUN it.</param>
    /// <exception cref="ArgumentException">The file does not compile.</exception>
    /// <exception cref="InvalidOperationException">BASIC did not reach its prompt.</exception>
    private void LaunchBasic(string path, bool run)
    {
        string full = Path.GetFullPath(path);
        BasicDialect dialect = Basic;
        BasicRom rom = Target.BasicRom
            ?? throw new InvalidOperationException(NoBasicSource);

        BasicFile file = Load(full);
        if (file.Source.Parse.Program is not { } program)
        {
            string problems = string.Join(Environment.NewLine, file.Source.Parse.Diagnostics
                .Where(diagnostic => diagnostic.Severity == BasicSeverity.Error)
                .Take(5)
                .Select(diagnostic => $"{full}({diagnostic.Line + 1}): {diagnostic.Message}"));

            throw new ArgumentException($"The BASIC file does not compile:{Environment.NewLine}{problems}");
        }

        if (program.Dialect.Name != dialect.Name)
        {
            string name = Path.GetFileName(full);
            throw new ArgumentException($"{name} is {program.Dialect.DisplayName}, and the machine runs {dialect.DisplayName}.");
        }

        ReachPrompt(rom);
        program.Write(new TargetBasicMemory(Target));
        _basicLaunched = full;
        _basicLaunchedInSync = true;
        if (run)
        {
            foreach (char character in "RUN\r") { Target.Key(character); }
        }
    }

    // Runs the machine from power-up to BASIC's prompt, pressing ENTER for the Model I's MEMORY SIZE?.
    private void ReachPrompt(BasicRom rom)
    {
        ulong end = Target.CycleCount + (ulong)(Target.ClockHertz * BootSeconds);
        ulong press = Target.CycleCount + (ulong)Target.ClockHertz;
        while (Target.CycleCount < end)
        {
            // Once a second until the prompt, as the ROM may not be reading the keyboard yet.
            if (Target.CycleCount >= press)
            {
                Target.Key('\r');
                press += (ulong)Target.ClockHertz;
            }

            if (Target.IsInstructionBoundary && Target.ProgramCounter == rom.Prompt)
            {
                // The prompt's own code sets up the line BASIC waits on; a little more and BASIC is waiting.
                ulong settle = Target.CycleCount + (ulong)(Target.ClockHertz / 10);
                while (Target.CycleCount < settle) { Target.StepCycle(); }
                return;
            }

            Target.StepCycle();
        }

        throw new InvalidOperationException("BASIC did not reach its prompt within ten seconds of the machine's time.");
    }

    // Reads and analyzes a BASIC file, as it is on disk.
    private BasicFile Load(string path)
    {
        BasicSource source = BasicSource.Analyze(File.ReadAllText(path), _target is null ? null : Target.Basic, path);
        BasicFile file = new(path, source);
        _basicFiles[path] = file;
        return file;
    }

    // The workspace file the program in memory was compiled from: the launched file first, else one with
    // breakpoints, when it compiles to the bytes in memory.
    private BasicFile? InSyncFile()
    {
        if (_target is null || Target.Basic is null) { return null; }
        string version = BasicVersion();
        IEnumerable<BasicFile> files = _basicFiles.Values.OrderBy(file => Same(file.Path, _basicLaunched) ? 0 : 1);
        return files.FirstOrDefault(file => file.Source.Parse.Program is { } program && VersionOf(program) == version);
    }

    // The version the program in memory would have were it this program, at BASIC's program pointer.
    private string VersionOf(BasicProgram program)
    {
        int start = Word(Basic.Pointers.ProgramStart);
        byte[] image = program.ToImage(start);
        ulong hash = HashBasis;
        hash = (hash ^ (ulong)start) * HashPrime;
        foreach (byte value in image) { hash = (hash ^ value) * HashPrime; }
        return hash.ToString("X16", CultureInfo.InvariantCulture);
    }

    // Says once when the program in memory stops matching the launched file, as the frames move to the machine's.
    private void NoteLaunchedFile()
    {
        if (_basicLaunched is null) { return; }
        bool inSync = Same(InSyncFile()?.Path, _basicLaunched);
        if (_basicLaunchedInSync && !inSync)
        {
            Notify("output", new JsonObject
            {
                ["category"] = "console",
                ["output"] = $"The BASIC program in memory no longer matches {Path.GetFileName(_basicLaunched)}; {MachineFrames}\n"
            });
        }

        _basicLaunchedInSync = inSync;
    }

    // A frame's place in an in-sync workspace file: its line, and its statement's column there.
    private static (int Line, int Column)? FilePlace(BasicFile file, int number, int statement)
    {
        if (file.Source.LineNumbered(number) is not { } line || statement >= line.Statements.Count) { return null; }
        return (line.Line + 1, line.Statements[statement].Column + 1);
    }

    // Breakpoints in a workspace BASIC file: bound while the program in memory is what the file compiles to. A
    // breakpoint on a line without statements, such as a label, stops at the next line that has them.
    private JsonObject BasicFileBreakpoints(JsonObject args, string path)
    {
        string full = Path.GetFullPath(path);
        _basicFileBreakpoints[full] = args;
        string group = $"basicfile\n{full.ToUpperInvariant()}";
        RemoveBasicSites(group);
        HashSet<string> kept = [];
        List<JsonObject> responses = [];
        BasicFile? file = File.Exists(full) ? Load(full) : null;
        bool inSync = file is not null && Same(InSyncFile()?.Path, full);
        BasicView? view = inSync ? View() : null;
        foreach (JsonObject breakpoint in (args["breakpoints"] as JsonArray ?? []).OfType<JsonObject>())
        {
            int line = (breakpoint.Int("line") ?? 0);
            int? column = breakpoint.Int("column");
            BreakpointState state = State(group, $"{line}:{column}", breakpoint, kept);
            state.Kind = "breakpoint";
            state.Line = new(full, line);
            state.Location = $"{Path.GetFileName(full)}:{line}";
            int at = line;
            int? statementColumn = null;
            BasicSourceLine? source = file?.Source.NumberedLines.FirstOrDefault(found => found.Line >= line - 1);
            if (view is null || file is null)
            {
                state.Problem ??= "This file does not match the BASIC program in memory.";
            }
            else if (source is null || view.Line(source.Number) is not { } stored)
            {
                state.Problem ??= "There is no BASIC statement here.";
            }
            else
            {
                int statement = column is { } value && source.Line == line - 1 ? source.StatementAtColumn(value - 1) : 0;
                at = source.Line + 1;
                statementColumn = source.Statements[statement].Column + 1;
                int offset = stored.Statements[Math.Min(statement, stored.Statements.Count - 1)].Offset;
                int address = view.Addresses[source.Number] + Basic.LineHeader + offset;
                state.Location = $"{Path.GetFileName(full)}:{at} (line {source.Number})";
                AddBasicSite(address, source.Number, state);
            }

            state.Response = new JsonObject
            {
                ["id"] = state.Id,
                ["verified"] = state.Problem is null,
                ["line"] = at,
                ["column"] = statementColumn,
                ["source"] = new JsonObject { ["name"] = Path.GetFileName(full), ["path"] = full }
            };

            responses.Add(Describe(state, changed: false));
        }

        Forget(group, kept);
        return new JsonObject { ["breakpoints"] = responses.ToJsonArray() };
    }

    private void AddBasicSite(int address, int number, BreakpointState state)
    {
        if (!_basicSites.TryGetValue(address, out List<(int, BreakpointState)>? sites))
        {
            sites = [];
            _basicSites.Add(address, sites);
        }

        sites.Add((number, state));
    }

    // Removes a group's BASIC breakpoints, and statements left with none.
    private void RemoveBasicSites(string group)
    {
        foreach (int address in _basicSites.Keys.ToArray())
        {
            _basicSites[address].RemoveAll(site => site.State.Group == group);
            if (_basicSites[address].Count == 0) { _basicSites.Remove(address); }
        }
    }

    // Binds the workspace files' BASIC breakpoints again after the program changes.
    private void RebindBasicFileBreakpoints()
    {
        foreach ((string path, JsonObject request) in _basicFileBreakpoints.ToArray())
        {
            foreach (JsonObject breakpoint in (BasicFileBreakpoints(request, path)["breakpoints"] as JsonArray ?? []).OfType<JsonObject>())
            {
                Notify("breakpoint", new JsonObject
                {
                    ["reason"] = "changed",
                    ["breakpoint"] = breakpoint.DeepClone()
                });
            }
        }
    }
}
