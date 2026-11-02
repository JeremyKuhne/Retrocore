// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text.Json.Nodes;
using Retrocore.Basic;

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    // How long a save waits for a running program to reach the start of a statement.
    private const double StatementWaitSeconds = 0.25;

    private const ulong HashBasis = 0xCBF29CE484222325;
    private const ulong HashPrime = 0x100000001B3;

    private const string StopFirst = "Stop the program (Ctrl-C or BREAK), then save again.";
    private const string NoPromptMessage =
        $"BASIC is running a program, and the debugger has no source for this ROM to bring it back to its prompt. {StopFirst}";

    // The version of the program in memory the last retro/basic/changed event gave.
    private string? _basicVersion;

    /// <summary>
    ///  Registers the BASIC program requests.
    /// </summary>
    /// <param name="transport">The protocol's wire.</param>
    private void RegisterBasic(DapTransport transport)
    {
        transport.On("retro/basic/program", _ => Reply(BasicProgramNow));
        transport.On("retro/basic/write", args => Reply(() => WriteBasic(Required(args, "text"))));
        transport.On("retro/basic/import", args => Reply(() => ImportBasic(Required(args, "path"))));
        transport.On("retro/basic/export", args => Reply(() => ExportBasic(
            Required(args, "path"),
            args.String("format"),
            args.String("name"))));
    }

    private BasicDialect Basic =>
        Target.Basic ?? throw new InvalidOperationException("The debugger does not support this machine's BASIC yet.");

    // The program in memory as text, with the version that identifies its bytes.
    private JsonObject BasicProgramNow()
    {
        BasicDialect dialect = Basic;
        TargetBasicMemory memory = new(Target);
        string text = "";
        string? error = null;
        try
        {
            text = BasicProgram.Read(dialect, memory).ToText();
        }
        catch (InvalidDataException exception)
        {
            error = exception.Message;
        }

        return new JsonObject
        {
            ["dialect"] = dialect.Name,
            ["displayName"] = dialect.DisplayName,
            ["text"] = text,
            ["version"] = BasicVersion(),
            ["running"] = !dialect.InDirectMode(memory),
            ["error"] = error
        };
    }

    private JsonObject WriteBasic(string text)
    {
        BasicDialect dialect = Basic;
        BasicParseResult parsed = BasicProgram.Parse(text, dialect);
        if (parsed.Dialect is { } named && named.Name != dialect.Name)
        {
            return Unsaved([new(0, BasicSeverity.Error, $"The machine runs {dialect.DisplayName}, not {named.DisplayName}.")]);
        }

        return parsed.Program is { } program ? StoreBasic(program, parsed.Diagnostics) : Unsaved(parsed.Diagnostics);
    }

    private JsonObject ImportBasic(string path)
    {
        BasicDialect dialect = Basic;
        byte[] bytes = File.ReadAllBytes(path);
        if (path.EndsWith(".cas", StringComparison.OrdinalIgnoreCase))
        {
            BasicProgram tape = BasicTape.Read(bytes, out _);
            return tape.Dialect.Name == dialect.Name
                ? StoreBasic(tape, [])
                : throw new InvalidOperationException($"A CSAVE tape holds Level II BASIC, not {dialect.DisplayName}.");
        }

        // Every tokenized program has zero bytes, which end its lines; a text file has none.
        if (bytes.AsSpan().IndexOf((byte)0) >= 0) { return StoreBasic(BasicProgram.FromImage(dialect, bytes), []); }
        return WriteBasic(File.ReadAllText(path));
    }

    private JsonObject ExportBasic(string path, string? format, string? name)
    {
        BasicDialect dialect = Basic;
        BasicProgram program = BasicProgram.Read(dialect, new TargetBasicMemory(Target));
        format ??= Path.GetExtension(path).ToLowerInvariant() switch
        {
            ".cas" => "tape",
            ".bas" or ".txt" => "text",
            _ => "tokenized"
        };

        switch (format)
        {
            case "text":
                File.WriteAllText(path, program.ToText(pragma: BasicText.DialectOfPath(path) is null));
                break;
            case "tape":
                char tape = (name ?? Path.GetFileName(path)).ToUpperInvariant().FirstOrDefault(char.IsAsciiLetterOrDigit, 'A');
                File.WriteAllBytes(path, BasicTape.Write(program, tape));
                break;
            case "tokenized":
                File.WriteAllBytes(path, program.ToImage());
                break;
            default:
                throw new ArgumentException($"'{format}' is not a BASIC format; use text, tokenized or tape.");
        }

        return new JsonObject { ["path"] = path, ["format"] = format, ["lines"] = program.Lines.Count };
    }

    // Writes a program into memory. A running program is first brought to the start of a statement, and BASIC goes
    // back to its prompt afterwards, as it does when a line is typed.
    private JsonObject StoreBasic(BasicProgram program, IReadOnlyList<BasicDiagnostic> diagnostics)
    {
        TargetBasicMemory memory = new(Target);
        BasicRom? prompt = null;
        if (!Basic.InDirectMode(memory))
        {
            prompt = Target.BasicRom is { } rom && _debug.Position(Target, rom.StatementStart) is not null
                ? rom
                : throw new InvalidOperationException(NoPromptMessage);

            if (!ReachStatement(prompt) && !Target.InRom(Target.ProgramCounter))
            {
                throw new InvalidOperationException(
                    $"BASIC did not reach a statement, and the CPU is at ${Target.ProgramCounter:X4}, outside the ROM. {StopFirst}");
            }
        }

        program.Write(memory);
        if (prompt is not null)
        {
            Target.EnterBasicPrompt(prompt);
            Notify("output", new JsonObject
            {
                ["category"] = "console",
                ["output"] = "BASIC is back at its prompt; the program is saved.\n"
            });

        }

        Invalidate();
        _hidden = 0;
        NotifyMemory();
        if (prompt is not null && _run is not { IsCancellationRequested: false })
        {
            Notify("invalidated", new JsonObject { ["areas"] = new JsonArray("all") });
            NotifyFrame(running: false);
        }

        return new JsonObject
        {
            ["success"] = true,
            ["diagnostics"] = Diagnostics(diagnostics).ToJsonArray(),
            ["version"] = BasicVersion(),
            ["returnedToPrompt"] = prompt is not null
        };
    }

    // Runs to the statement dispatch, ignoring breakpoints, for at most a quarter of a second of the machine's time;
    // ends between instructions either way. Returns whether it got there.
    private bool ReachStatement(BasicRom rom)
    {
        ulong end = Target.CycleCount + (ulong)(Target.ClockHertz * StatementWaitSeconds);
        while (true)
        {
            if (Target.IsInstructionBoundary)
            {
                if (Target.ProgramCounter == rom.StatementStart) { return true; }
                if (Target.CycleCount >= end) { return false; }
            }

            Target.StepCycle();
        }
    }

    private JsonObject Unsaved(IReadOnlyList<BasicDiagnostic> diagnostics) =>
        new JsonObject
        {
            ["success"] = false,
            ["diagnostics"] = Diagnostics(diagnostics),
            ["version"] = BasicVersion()
        };

    private static JsonArray Diagnostics(IReadOnlyList<BasicDiagnostic> diagnostics) =>
        diagnostics.Select(diagnostic => new JsonObject
            {
                ["line"] = diagnostic.Line,
                ["severity"] = diagnostic.Severity == BasicSeverity.Error ? "error" : "warning",
                ["message"] = diagnostic.Message
            }).ToJsonArray();

    // Sends retro/basic/changed when the program's bytes have changed since the last one sent.
    private void NotifyBasic()
    {
        if (Target.Basic is null) { return; }
        string version = BasicVersion();
        if (version == _basicVersion) { return; }
        _basicVersion = version;
        Notify("retro/basic/changed", new JsonObject { ["version"] = version });
        RebindBasicBreakpoints();
        RebindBasicFileBreakpoints();
        NoteLaunchedFile();
    }

    // Identifies the program in memory: a hash of where it is and its bytes, or "none" when BASIC is not set up.
    private string BasicVersion()
    {
        BasicPointers pointers = Basic.Pointers;
        int start = Word(pointers.ProgramStart);
        int end = Word(pointers.Variables);
        if (start == 0 || end < start + 2) { return "none"; }
        ulong hash = HashBasis;
        hash = (hash ^ (ulong)start) * HashPrime;
        for (int address = start; address < end; address++)
        {
            hash = (hash ^ Target.Peek((ushort)address)) * HashPrime;
        }

        return hash.ToString("X16", CultureInfo.InvariantCulture);
    }

    private int Word(int address) => Target.Peek((ushort)address) | (Target.Peek((ushort)(address + 1)) << 8);
}
