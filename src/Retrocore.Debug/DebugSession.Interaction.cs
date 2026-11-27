// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    private InteractionRun? _interaction;
    private InputBatch? _lastInput;
    private readonly Queue<InputBatch> _typing = new();
    private long _launchId;
    private long _nextRun;
    private long _nextBatch;
    private long _textRevision;
    private bool _textOnly;
    private string _textPolicy = "manual";
    private string _textSurface = "visibleText";
    private DebugTextSurface? _lastText;
    private ConsoleCapture? _consoleCapture;
    private bool _captureFailed;

    private void RegisterInteraction(DapTransport transport)
    {
        transport.On("retro/text", args => Reply(() => Snapshot(TextSurface(args.String("surface")))));
        transport.On("retro/snapshot", args => Reply(() => Snapshot(SnapshotSurface(args.String("surface")))));
        transport.On("retro/text/run", args => Reply(() => RunUntil(args, legacy: true)));
        transport.On("retro/runUntil", args => Reply(() => RunUntil(args, legacy: false)));
        transport.On("retro/run/cancel", args => Reply(() =>
        {
            if (args.Long("launchId") != _launchId || _interaction is not { } run || args.Long("runId") != run.Id)
            {
                return new JsonObject { ["cancelled"] = false };
            }

            RetireWorker();
            CompleteInteraction("cancelled");
            Stopped("pause", description: "The automation run was cancelled.");
            return new JsonObject { ["cancelled"] = true };
        }));

        transport.On("retro/input/status", _ => Reply(() => WithIdentity(InputStatus())));
        transport.On("retro/console/read", args => Reply(() =>
        {
            ConsoleCapture capture = _consoleCapture ?? throw new InvalidOperationException("No console sink is enabled.");
            int count = args.Int("maxBytes") ?? 4096;
            ArgumentOutOfRangeException.ThrowIfNegativeOrZero(count);
            return WithIdentity(capture.Read(count));
        }));
    }

    private void ConfigureInteraction(JsonObject args)
    {
        _textPolicy = args.String("textPolicy") switch
        {
            null or "manual" => "manual",
            string policy when policy is "onStop" or "onInputWait" or "changes" => policy,
            _ => throw new ArgumentException("textPolicy must be manual, onStop, onInputWait or changes.")
        };

        _textSurface = TextSurface(args.String("textSurface"));
        _lastText = null;
        _textRevision = 0;
        _consoleCapture = null;
        _captureFailed = false;
        if (args.Object("consoleCapture") is { } capture)
        {
            string sink = Required(capture, "sink");
            int capacity = capture.Int("capacity") ?? 65_536;
            ArgumentOutOfRangeException.ThrowIfLessThan(capacity, 1);
            ArgumentOutOfRangeException.ThrowIfGreaterThan(capacity, 1_048_576);
            if (!Target.SetConsoleSink(sink, CaptureConsoleByte))
            {
                throw new ArgumentException($"Console sink '{sink}' is not supported on this target.");
            }

            _consoleCapture = new(capacity);
        }
    }

    private static string TextSurface(string? surface) => surface switch
    {
        null or "visibleText" => "visibleText",
        "textMemory" => "textMemory",
        "editor" => "editor",
        _ => throw new ArgumentException("The text surface must be visibleText, textMemory or editor.")
    };

    private static string SnapshotSurface(string? surface) => surface == "screen" ? "screen" : TextSurface(surface);

    private JsonObject WithIdentity(JsonObject body)
    {
        body["launchId"] = _launchId;
        return body;
    }

    private JsonObject Snapshot(string surface, DebugTextSurface? state = null)
    {
        JsonObject snapshot = WithIdentity(new JsonObject
        {
            ["surface"] = surface,
            ["revision"] = ++_textRevision,
            ["cycles"] = Target.CycleCount
        });

        if (surface == "screen")
        {
            JsonObject? video = Target.VideoState();
            snapshot["supported"] = video is not null;
            if (video is not null)
            {
                video["pixels"] = Convert.ToBase64String(Target.RenderVideo());
                snapshot["video"] = video;
                snapshot["monitor"] = Target.Screen;
                snapshot["semantics"] = Target is Apple1DebugTarget or AltairDebugTarget or Trs80Model100DebugTarget
                    ? "displayBuffer" : "scanned";
            }

            return snapshot;
        }

        state ??= Target.ReadTextSurface(surface);
        snapshot["supported"] = state is not null;
        if (state is null) { return snapshot; }

        snapshot["machine"] = state.Machine;
        snapshot["model"] = state.Model;
        snapshot["mode"] = state.Mode;
        snapshot["columns"] = state.Columns;
        snapshot["displayRows"] = state.DisplayRows;
        snapshot["firstRow"] = state.FirstRow;
        snapshot["rowCount"] = state.Rows.Length;
        snapshot["rows"] = state.Rows.ToJsonArray();
        snapshot["decoding"] = state.Decoding;
        if (state.Cursor is { } cursor)
        {
            snapshot["cursor"] = new JsonObject { ["row"] = cursor.Row, ["column"] = cursor.Column };
        }

        return snapshot;
    }

    private void NotifyTextChanges()
    {
        if (_textPolicy != "changes" || Target.ReadTextSurface(_textSurface) is not { } next) { return; }
        if (_lastText is { } last
            && last with { Rows = next.Rows } == next
            && last.Rows.AsSpan().SequenceEqual(next.Rows))
        {
            return;
        }

        _lastText = next;
        Notify("retro/text/update", Snapshot(_textSurface, next));
    }

    private JsonObject RunUntil(JsonObject args, bool legacy)
    {
        if (!_launchReady || !_started)
        {
            throw new InvalidOperationException("The machine is not ready; finish launch and configurationDone first.");
        }

        if (_interaction is not null) { throw new InvalidOperationException("An automation run is already waiting."); }

        JsonObject stop = legacy ? args : args.Object("stopOn")
            ?? throw new ArgumentException("stopOn is required.");

        string condition = legacy ? "screenContains" : Required(stop, "kind");
        string surface = TextSurface(stop.String("surface"));
        string? contains = null;
        ConsoleMatch? transcript = null;
        ushort? marker = null;
        switch (condition)
        {
            case "inputDemand":
                RequireGuestInput();
                break;
            case "screenContains":
            case "transcriptContains":
                contains = Required(stop, "contains");
                if (contains.Length is <= 0 or > 4096)
                {
                    throw new ArgumentException("contains must have 1–4096 characters.");
                }

                if (condition == "transcriptContains")
                {
                    if (_consoleCapture is null || _consoleCapture.Overflowed || contains.Any(character => character > '\x7F'))
                    {
                        throw new ArgumentException("A working ASCII console sink is required for transcriptContains.");
                    }

                    transcript = new(contains);
                }
                else if (Target.ReadTextSurface(surface) is null)
                {
                    throw new ArgumentException($"Text surface '{surface}' is unavailable on this target.");
                }

                break;
            case "instruction":
                int address = stop.Int("address") ?? throw new ArgumentException("An instruction address is required.");
                ArgumentOutOfRangeException.ThrowIfNegative(address);
                ArgumentOutOfRangeException.ThrowIfGreaterThan(address, ushort.MaxValue);
                marker = (ushort)address;
                break;
            default:
                throw new ArgumentException($"Unknown stop condition '{condition}'.");
        }

        string policy = legacy ? "legacy" : args.String("policy") switch
        {
            null or "scripted" => "scripted",
            "live" => "live",
            _ => throw new ArgumentException("policy must be scripted or live.")
        };

        long maxCycles = args.Long("maxCycles") ?? (long)Target.ClockHertz * 60;
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maxCycles);
        string? snapshot = legacy ? surface : args.Object("snapshot") is { } output ? SnapshotSurface(output.String("surface")) : null;

        InputBatch? batch = null;
        if (!legacy && args["input"] is not (null or JsonObject))
        {
            throw new ArgumentException("input must be an object.");
        }

        JsonObject? input = legacy ? args : args.Object("input");
        string? text = legacy ? args.String("text") : input is null ? null : Required(input, "text");
        if (input is not null && text is not null)
        {
            if (_typing.Count != 0)
            {
                throw new InvalidOperationException("A physical paste is still queued.");
            }

            bool guest = !legacy && input.String("backend") switch
            {
                null or "guestDemand" => true,
                "physical" => false,
                _ => throw new ArgumentException("The input backend must be guestDemand or physical.")
            };

            if (guest) { RequireGuestInput(); }
            batch = NewInput(text, guest, out _);
        }

        ulong start = Target.CycleCount;
        InteractionRun run = new(++_nextRun, start, (ulong)maxCycles)
        {
            Legacy = legacy,
            Condition = condition,
            Policy = policy,
            Contains = contains,
            Address = marker,
            Transcript = transcript,
            Snapshot = snapshot,
            Surface = surface,
            Input = batch,
            MatchArmed = stop.Bool("fresh") != true
        };

        _interaction = run;
        if (!IsRunning) { Continue(); }
        JsonObject response = WithIdentity(new JsonObject
        {
            ["runId"] = run.Id,
            ["startCycle"] = start,
            ["maxCycles"] = maxCycles,
            ["policy"] = policy,
            ["input"] = batch?.ToJson()
        });

        if (legacy)
        {
            response["waitId"] = run.Id;
            response["typed"] = batch?.Pending ?? 0;
            response["skipped"] = batch?.ToJson()["skipped"]?.DeepClone() ?? 0;
        }

        return response;
    }

    private bool IsRunning => _run is { IsCancellationRequested: false };

    private void RequireManualExecution()
    {
        if (_interaction is not null)
        {
            throw new InvalidOperationException("Cancel or pause the automation run before stepping or continuing.");
        }
    }

    private void RequireGuestInput()
    {
        if (!Target.SupportsGuestInput)
        {
            throw new InvalidOperationException("This target has no supported guest-input profile.");
        }
    }

    private GuestInputPath? InputDemand()
    {
        IDebugTarget target = Target;
        if (target.CoprocessorActive || !target.IsInstructionBoundary || target.IsHeld) { return null; }
        if (target is Apple3DebugTarget { MayBeUnmappedConsoleWait: true }) { AddLoadedModules(); }
        return target.WaitingForInput();
    }

    private JsonObject InputStatus(GuestInputPath? demand = null, InputBatch? batch = null)
    {
        demand ??= InputDemand();
        return new JsonObject
        {
            ["status"] = demand is not null ? "waiting" : Target.SupportsGuestInput ? "unknown" : "unsupported",
            ["kind"] = demand is not null ? "blockingRead" : null,
            ["profile"] = demand?.Profile,
            ["source"] = demand is not null ? "keyboard" : null,
            ["delivery"] = demand?.Backend,
            ["devicePending"] = Target.PendingKeys,
            ["cycles"] = Target.CycleCount,
            ["running"] = IsRunning,
            ["input"] = (batch ?? _interaction?.Input ?? _lastInput)?.ToJson()
        };
    }

    private InputBatch NewInput(string text, bool guest, out int skipped)
    {
        List<int> codes = TypedText.Codes(text, out skipped, Target is BbcDebugTarget ? BbcPound : null);
        return _lastInput = new InputBatch(++_nextBatch, codes, skipped, guest);
    }

    private JsonObject TypeText(string text)
    {
        if (_interaction?.Input is not null) { throw new InvalidOperationException("An automation run owns input."); }
        InputBatch batch = NewInput(text, guest: false, out int skipped);
        if (batch.Pending > 0)
        {
            if (Target.TypingPace is not null || _typing.Count != 0) { _typing.Enqueue(batch); }
            else
            {
                while (batch.Pending != 0) { batch.DeliverPhysical(Target, out _); }
            }
        }

        return new JsonObject
        {
            ["typed"] = batch.Pending + batch.Delivered,
            ["skipped"] = skipped + batch.Rejected
        };
    }

    private JsonObject PhysicalKey(int code)
    {
        if (code == 3)
        {
            CompleteInteraction("interrupted");
            CancelPhysicalInput();
        }
        else if (_interaction?.Input is not null)
        {
            throw new InvalidOperationException("An automation run owns input.");
        }
        else if (_typing.Count != 0)
        {
            _lastInput = new InputBatch(++_nextBatch, [code], 0, guestDemand: false);
            _typing.Enqueue(_lastInput);
            return _lastInput.ToJson();
        }

        return new JsonObject { ["delivered"] = Target.Key(code) ? 1 : 0 };
    }

    private void CancelPhysicalInput()
    {
        while (_typing.TryDequeue(out InputBatch? batch)) { batch.Cancel(); }
        _typingDue = 0;
    }

    private void TypeNext()
    {
        InputBatch? batch = _typing.TryPeek(out InputBatch? paste)
            ? paste
            : _interaction?.Input is { GuestDemand: false } input ? input : null;

        if (batch is null || batch.Pending == 0) { return; }

        if (Target.TypingPace is { } pace)
        {
            if (Target.CycleCount < _typingDue) { return; }
            batch.DeliverPhysical(Target, out int code);
            _typingDue = Target.CycleCount + (code == '\r' ? pace.Line : pace.Key);
        }
        else
        {
            while (batch.Pending != 0) { batch.DeliverPhysical(Target, out _); }
        }

        if (ReferenceEquals(batch, paste) && batch.Pending == 0) { _typing.Dequeue(); }
    }

    private void CaptureConsoleByte(byte code)
    {
        if (_consoleCapture?.Add(code, Target.CycleCount) == true) { _interaction?.Transcript?.Add(code); }
    }

    private bool StopOnCaptureOverflow()
    {
        if (_consoleCapture is not { Overflowed: true } || _captureFailed) { return false; }

        _captureFailed = true;
        RetireWorker();
        CompleteInteraction("captureOverflow");
        Stopped(
            "exception",
            description: "The console capture buffer overflowed. Its retained prefix can still be read.",
            exception: "consoleCapture");

        return true;
    }

    private bool ObserveInteraction(InteractionRun run, IDebugTarget cpu, bool boundary, bool canAdvance)
    {
        ulong cycles = Target.CycleCount;
        // Execute can yield during a device hold, before the instruction or interrupt response has finished.
        bool deadline = cycles >= run.Deadline && (boundary || cpu is { IsIdle: true, InInstruction: false });
        InputBatch? batch = run.Input;
        GuestInputPath? demand = null;
        DebugTextSurface? captured = null;
        string? reason = null;
        if (batch is not null && !run.Legacy && (batch.Rejected != 0 || batch.Unconfirmed != 0))
        {
            reason = "inputNotAccepted";
        }
        else if (run.Condition == "instruction"
            && ReferenceEquals(cpu, Target)
            && boundary
            && Target.ProgramCounter == run.Address)
        {
            reason = "matched";
        }
        else if (run.Transcript is { Matched: true })
        {
            reason = "matched";
        }
        else if (run.Condition == "screenContains" && run.Contains is { } text && (deadline
            || run.LastSample is not { } last
            || cycles - last >= (ulong)Math.Max(1, Target.ClockHertz / 30)))
        {
            run.LastSample = cycles;
            captured = Target.ReadTextSurface(run.Surface);
            bool matched = captured is not null && string.Join('\n', captured.Rows).Contains(text, StringComparison.Ordinal);
            if (matched && run.MatchArmed) { reason = "matched"; }
            if (!matched) { run.MatchArmed = true; }
        }

        if (reason is null && (run.Condition == "inputDemand" || batch is { GuestDemand: true, NeedsInput: true }))
        {
            demand = InputDemand();
            if (demand is not null && run.Condition == "inputDemand" && batch is not { NeedsInput: true })
            {
                reason = "inputDemand";
            }
        }

        reason ??= deadline ? "cycleBudgetExceeded" : null;
        if (reason is not null)
        {
            if (run.Policy != "live") { RetireWorker(); }
            CompleteInteraction(reason, captured, demand);
            if (run.Policy == "live") { return false; }
            Stopped("pause", description: $"Automation run: {reason}.");
            _unchecked = Cpu.IsInstructionBoundary;
            return true;
        }

        if (canAdvance && demand is not null && batch is { GuestDemand: true, Pending: > 0, InFlight: false })
        {
            batch.Deliver(demand);
        }

        return false;
    }

    private void CompleteInteraction(string reason, DebugTextSurface? captured = null, GuestInputPath? demand = null)
    {
        if (_interaction is not { } run) { return; }
        _interaction = null;
        if (run.Policy == "scripted") { _paceAgain = true; }

        run.ReportResult(
            _launchId,
            Target.CycleCount,
            reason,
            () => InputStatus(demand, run.Input),
            surface => Snapshot(surface, surface == run.Surface ? captured : null),
            _textPolicy == "onInputWait" && reason == "inputDemand" ? _textSurface : null,
            Notify);
    }
}
