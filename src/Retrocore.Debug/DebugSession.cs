// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Documentation;
using Retrocore.Isa;
using Retrocore.Machines.Devices;
using System.Text.Json.Nodes;
using System.Diagnostics;
using System.Text.Json;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;

namespace Retrocore.Debug;

/// <summary>
///  In-process debugger state with side-effect-free inspection and bounded source stepping, for any machine an
///  <see cref="IDebugTarget"/> describes.
/// </summary>
internal sealed partial class DebugSession
{
    // Machine requests the session forwards to the launched target, which may not support them.
    private const string OnlyBasic = "Only BASIC variables can be set here; change registers and memory in a memory view.";

    private static readonly string[] s_machineRequests =
    [
        "apple2/text",
        "retro/video",
        "apple2/beam",
        "apple2/disk",
        "apple2/sound",
        "apple2/button",
        "apple2/mouse",
        "apple2/fastDisk",
        "apple3/disk",
        "apple3/sound",
        "apple3/button",
        "apple3/fastDisk",
        "retro/media",
        "apple1/clearScreen",
        "altair/clearScreen"
    ];

    private readonly object _gate = new();
    private DebugInfo _debug = new();
    private DebugFrame[]? _frames;
    private DisplayFrame[]? _display;
    private DebugFrame[]? _coprocessorFrames;
    private DisplayFrame[]? _coprocessorDisplay;

    // How many innermost macro levels at the PC the top frame hides: a stop on a macro call line shows that line
    // until stepping in moves inward without running anything.
    private int _hidden;
    private IDebugTarget? _target;
    private DapTransport? _transport;

    // The pixels the last retro/frame carried, which a running frame with the same picture leaves out.
    private byte[] _sentPixels = [];
    private CancellationTokenSource? _run;
    private int _nextBreakpoint = 1;
    private bool _stopOnEntry;

    // Whether the breakpoints at the PC the last stop left are still to be checked: a data or beam breakpoint stops
    // between instructions, before the next one's breakpoints were looked at, so resuming checks them first.
    private bool _unchecked;

    // The last retro/devices event sent, to send another only when a device changes.
    private string? _devices;

    // Whether running keeps to the machine's real speed, rather than running as fast as it can.
    // The speed running keeps to, as a multiple of the machine's clock; 0 runs as fast as the host can.
    private double _speed = 1;

    // Set when the speed changes, so the running loop paces again from where the machine is.
    private volatile bool _paceAgain;

    // The measured speed, as a multiple of the clock: emulated cycles against the wall clock over about half a
    // second of running, or NaN until a half second has run.
    private long _measureTime;
    private ulong _measureCycles;
    private double _measured = double.NaN;

    // VS Code sends breakpoints and configurationDone in answer to the initialized event, which the server sends
    // right after initialize, so they can arrive before launch has loaded the modules they bind to.
    private bool _configured;
    private bool _started;

    // What the launch powers on to: the reset handler, a loaded program's entry, or (null) a BASIC launch already
    // past reset at the prompt.
    private string? _powerOn;
    private readonly Dictionary<string, JsonObject> _requested = new(StringComparer.OrdinalIgnoreCase);

    // Pasted keys still to type, on a machine with a typing pace, and the cycle the next may go at.
    private readonly Queue<int> _typing = new();
    private ulong _typingDue;
    private readonly Dictionary<(string Path, int Line), ulong> _lineCycles = [];
    private (string Path, int Line)? _cycleSource;

    // The cycles run on the current line since they were last added to its count, and whether the line was entered
    // since then, so its count starts over. Counting here and adding once per instruction keeps the dictionary, and
    // hashing the line's path, off every cycle, which cost running at max three quarters of its speed.
    private ulong _pendingLineCycles;

    // The requests waiting for the lock running holds.
    private int _requestsWaiting;
    private bool _lineEntered;
    private readonly DebugCallCycles _callCycles = new();

    // Documented Keeps: contracts, checked when calls return; null when off or nothing documents one.
    private DebugContracts? _contracts;
    private bool _stopOnContracts;
    private ushort _instructionStart;

    /// <summary>
    ///  Registers the DAP and machine-view request handlers.
    /// </summary>
    /// <param name="transport">The protocol's wire, which also sends this session's events.</param>
    /// <param name="disconnect">The host shutdown callback.</param>
    internal void Register(DapTransport transport, Action disconnect)
    {
        _transport = transport;
        transport.On("initialize", _ => Capabilities());
        transport.On("launch", args => Reply(() => Launch(args)));
        transport.On("setBreakpoints", args => Reply(() => Breakpoints(args)));
        transport.On("setFunctionBreakpoints", args => Reply(() => FunctionBreakpoints(args)));
        transport.On("setInstructionBreakpoints", args => Reply(() => InstructionBreakpoints(args)));
        transport.On("setDataBreakpoints", args => Reply(() => DataBreakpoints(args)));
        transport.On("dataBreakpointInfo", args => Reply(() => DataBreakpointInfo(args)));
        transport.On("setExceptionBreakpoints", args => Reply(() => ExceptionBreakpoints(args)));

        transport.On("exceptionInfo", args => Reply(() =>
        {
            (string id, string description) = _exception
                ?? throw new InvalidOperationException("The machine has not stopped on an exception.");

            return new JsonObject { ["exceptionId"] = id, ["description"] = description, ["breakMode"] = "always" };
        }));

        transport.On("disassemble", args => Reply(() => Disassemble(args)));
        transport.On("retro/breakpoints", args => Reply(() => BreakpointList(args)));
        transport.On("retro/memoryBanks", _ => Reply(MemoryBankList));
        transport.On("configurationDone", args => Reply(() =>
        {
            _configured = true;
            if (_target is not null) { Start(); }
            return [];
        }));

        transport.On("threads", args => Reply(() => new JsonObject { ["threads"] = Threads() }));
        transport.On("stackTrace", args => Reply(() =>
            args.Int("threadId") switch
            {
                BasicThread => BasicStackTrace(),
                PascalThread => PascalStackTrace(),
                _ => StackTrace(args)
            }));

        transport.On("scopes", args => Reply(() =>
            (args.Int("frameId") ?? 0) switch
            {
                >= BasicFrameBase => BasicScopes(),
                >= PascalFrameBase and var frame => PascalScopesOf(frame),
                _ => Scopes(args)
            }));

        transport.On("variables", args => Reply(() => Variables((args.Int("variablesReference") ?? 0))));
        transport.On("evaluate", args => Reply(() =>
        {
            string expression = Required(args, "expression");
            int frameId = args.Int("frameId") ?? 1;
            if (frameId >= BasicFrameBase && HasBasicThread) { return EvaluateBasic(expression); }

            // In a Pascal frame, a variable its listing names; other expressions are the CPU's, as the machine is now.
            if (frameId is >= PascalFrameBase and < BasicFrameBase)
            {
                if (PascalVariableNamed(frameId, expression.Trim()) is { } named && Pascal is { } pascal)
                {
                    return new JsonObject
                    {
                        ["result"] = PascalValue(pascal.Memory, named.At, named.Variable),
                        ["type"] = named.Variable.Type,
                        ["variablesReference"] = 0,
                        ["memoryReference"] = named.At.Bank == 0 ? Reference(bank: null, named.At.Address) : null
                    };
                }

                frameId = 1;
            }

            long value;
            DebugMemoryBank? bank;
            try
            {
                value = new ExpressionEvaluator(FrameTarget(frameId), _debug, expression, FrameRegisters(frameId))
                    .EvaluateReference(out bank);
            }
            catch (FormatException) when (HasBasicThread && args.String("context") is "hover" or "watch")
            {
                // A BASIC variable under the cursor while the CPU's frame is selected.
                return EvaluateBasic(expression);
            }


            // A value in the CPU's 64K can open a memory view there; a bank-qualified one, in that bank. While
            // debugging, the editor shows this hover in place of the language server's, so a documented name
            // brings its ;; summary along.
            string result = bank is null ? $"${value:X} ({value})" : $"{bank.Name}:${value:X4}";
            if (args.String("context") == "hover" && SymbolSummary(expression) is { } summary)
            {
                result = $"{result} · {summary}";
            }

            return new JsonObject
            {
                ["result"] = result,
                ["variablesReference"] = 0,
                ["memoryReference"] = value is >= 0 and <= 0xFFFF ? Reference(bank, (int)value) : null
            };
        }));

        transport.On("setVariable", args => Reply(() =>
        {
            int reference = (args.Int("variablesReference") ?? 0);
            if (reference < BasicReferences) { throw new InvalidOperationException(OnlyBasic); }
            return SetBasicVariable(reference, Required(args, "name"), Required(args, "value"));
        }));

        transport.On("setExpression", args => Reply(() =>
        {
            if (!HasBasicThread) { throw new InvalidOperationException(OnlyBasic); }
            return SetBasic(Required(args, "expression"), Required(args, "value"));
        }));

        transport.On("readMemory", args => Reply(() => ReadMemory(args)));
        transport.On("writeMemory", args => Reply(() => WriteMemory(args)));

        transport.On("continue", args => Reply(() =>
        {
            _basicGoal = null;
            _pascalGoal = null;
            Continue();
            return new JsonObject
            {
                ["allThreadsContinued"] = true
            };

        }));

        transport.On("pause", args => Reply(() =>
        {
            if (OnBasic(args))
            {
                PauseBasic();
                return [];
            }

            if (OnPascal(args))
            {
                StepPascal(PascalStep.Pause);
                return [];
            }

            _run?.Cancel();
            Stopped("pause");
            return [];
        }));

        transport.On("next", args => Reply(() =>
        {
            if (OnPascal(args)) { StepPascal(PascalStep.Over, Instruction(args)); }
            else if (OnBasic(args)) { StepBasic(BasicStep.Over); }
            else { Step(over: true, outOf: false, Instruction(args), args.Int("threadId") ?? 1); }
            return [];
        }));

        transport.On("stepIn", args => Reply(() =>
        {
            if (OnPascal(args)) { StepPascal(PascalStep.Into, Instruction(args)); }
            else if (OnBasic(args)) { StepBasic(BasicStep.Into); }
            else { Step(over: false, outOf: false, Instruction(args), args.Int("threadId") ?? 1); }
            return [];
        }));

        transport.On("stepOut", args => Reply(() =>
        {
            if (OnPascal(args)) { StepPascal(PascalStep.Out); }
            else if (OnBasic(args)) { StepBasic(BasicStep.Out); }
            else { Step(over: false, outOf: true, Instruction(args), args.Int("threadId") ?? 1); }
            return [];
        }));

        transport.On("disconnect", args => Reply(() =>
        {
            _run?.Cancel();
            (_target as IDisposable)?.Dispose();
            disconnect();
            return [];
        }));

        foreach (string name in s_machineRequests)
        {
            transport.On(name, args => Reply(() => MachineRequest(name, args)));
        }

        transport.On("retro/cycles", args => Reply(() =>
        {
            if (args.Bool("clear") == true)
            {
                _lineCycles.Clear();
                _pendingLineCycles = 0;
                _lineEntered = false;
                _callCycles.Clear();
                _contracts?.Clear();
            }

            return SourceCycles();
        }));

        transport.On("retro/display", args => Reply(DisplayNow));
        transport.On("retro/devices", args => Reply(DevicesBody));
        transport.On("retro/device", args => Reply(() =>
        {
            string id = args.String("id") ?? throw new ArgumentException("id is required.");
            string action = args.String("action") ?? throw new ArgumentException("action is required.");
            IDevice device = Target.Devices.FirstOrDefault(device => device.Id == id)
                ?? throw new ArgumentException($"There is no device '{id}'.");

            Target.DeviceAction(device, action, args);
            NotifyDevices();
            return DevicesBody();
        }));

        // retro/speed: the speed running keeps to, from now on: 1, 2, 4 or 8 times the machine's clock, or "max".
        transport.On("retro/speed", args => Reply(() =>
        {
            _speed = Speed(args["speed"]);
            _paceAgain = true;
            StartMeasuring();
            return new JsonObject { ["speed"] = SpeedJson(running: false)["setting"]?.DeepClone() };
        }));

        // retro/hardware: changes the installed hardware, such as putting a Disk II card in a free slot. While
        // stopped, the views show what the slot's addresses now hold.
        transport.On("retro/hardware", args => Reply(() =>
        {
            string id = args.String("id") ?? throw new ArgumentException("id is required.");
            string action = args.String("action") ?? throw new ArgumentException("action is required.");
            Target.HardwareAction(id, action, args);
            Invalidate();
            if (_run is not { IsCancellationRequested: false })
            {
                Notify("invalidated", new JsonObject { ["areas"] = new JsonArray("all") });

                // The panel's Sound button follows the cards, so a stopped machine sends it a frame too.
                NotifyFrame(running: false);
            }

            NotifyDevices();
            return DevicesBody();
        }));

        RegisterBasic(transport);
        RegisterBasicThread(transport);
        transport.On("retro/key", args => Reply(() =>
        {
            int code = (args.Int("code") ?? 0);
            if (code is < 0 or > 127) { throw new ArgumentOutOfRangeException(nameof(args)); }

            // A key pressed while a paste is still typing waits its turn behind it, but CONTROL-C, which interrupts,
            // goes now and drops the rest of the paste.
            if (code == 3)
            {
                _typing.Clear();
            }
            else if (_typing.Count != 0)
            {
                _typing.Enqueue(code);
                return [];
            }

            Target.Key(code);
            return [];
        }));

        // retro/type: types text, as pasted into the display panel, through the keyboard's queue: line endings are
        // RETURN, and characters with no key are left out and counted.
        transport.On("retro/type", args => Reply(() =>
        {
            string text = args.String("text") ?? throw new ArgumentException("text is required.");
            List<int> codes = TypedText.Codes(text, out int skipped);

            // A machine with a typing pace takes the keys as the run reaches each one's time.
            if (Target.TypingPace is not null)
            {
                foreach (int code in codes) { _typing.Enqueue(code); }
                return new JsonObject { ["typed"] = codes.Count, ["skipped"] = skipped };
            }

            int typed = 0;
            foreach (int code in codes)
            {
                if (Target.Key(code)) { typed++; } else { skipped++; }
            }

            return new JsonObject { ["typed"] = typed, ["skipped"] = skipped };
        }));

        // retro/screen: shows the video on another of the machine's monitors, such as a green-phosphor one. A new
        // monitor changes the picture, so a stopped machine sends the panel a frame drawn on it.
        transport.On("retro/screen", args => Reply(() =>
        {
            Target.Screen = args.String("screen") ?? throw new ArgumentException("screen is required.");
            if (_run is not { IsCancellationRequested: false }) { NotifyFrame(running: false); }
            return new JsonObject { ["screen"] = Target.Screen };
        }));

        // retro/reset: presses the machine's reset. While stopped, the views show where it now is.
        transport.On("retro/reset", _ => Reply(() =>
        {
            // A reset abandons every call in progress, even where it keeps the stack pointer and RAM, as the 8080's does.
            Target.Reset();
            Target.CallStack.Reset();
            Pascal?.Reset();
            _pascalFrames = null;
            Invalidate();
            if (_run is not { IsCancellationRequested: false })
            {
                Notify("invalidated", new JsonObject { ["areas"] = new JsonArray("all") });
                NotifyFrame(running: false);
            }

            return [];
        }));
    }

    // The display as the panel draws it, while running or stopped.
    private JsonObject DisplayNow() => Target.DisplayFrame(running: _run is { IsCancellationRequested: false });

    private JsonObject MachineRequest(string name, JsonObject args)
    {
        if (!Target.Requests.TryGetValue(name, out Func<JsonObject, JsonObject>? handler))
        {
            throw new InvalidOperationException($"{name} is not supported on this machine.");
        }

        JsonObject result = handler(args);

        // Clearing the screen changes the picture, so a stopped machine sends the panel a frame showing it.
        if (name is "apple1/clearScreen" or "altair/clearScreen" && _run is not { IsCancellationRequested: false })
        {
            NotifyFrame(running: false);
        }

        return result;
    }

    private IDebugTarget Target => _target ?? throw new InvalidOperationException("No machine has been launched.");

    private JsonObject Reply(Func<JsonObject> action)
    {
        // Running ends its slice and steps aside while a request waits, so pause and keys answer at once at max.
        Interlocked.Increment(ref _requestsWaiting);
        bool counted = true;
        try
        {
            lock (_gate)
            {
                Interlocked.Decrement(ref _requestsWaiting);
                counted = false;
                return action();
            }
        }
        finally
        {
            if (counted) { Interlocked.Decrement(ref _requestsWaiting); }
        }
    }

    /// <summary>
    ///  Answers initialize: what the debug host supports on every machine, and every machine's exception filters.
    ///  A launch narrows the filters to its machine's and adds what depends on it.
    /// </summary>
    /// <returns>The capabilities.</returns>
    private static JsonObject Capabilities() => new JsonObject
    {
        ["supportsConfigurationDoneRequest"] = true,
        ["supportsConditionalBreakpoints"] = true,
        ["supportsHitConditionalBreakpoints"] = true,
        ["supportsLogPoints"] = true,
        ["supportsFunctionBreakpoints"] = true,
        ["supportsInstructionBreakpoints"] = true,
        ["supportsDataBreakpoints"] = true,
        ["supportsDataBreakpointBytes"] = true,
        ["supportsDisassembleRequest"] = true,
        ["supportsSteppingGranularity"] = true,
        ["supportsExceptionInfoRequest"] = true,
        ["supportsEvaluateForHovers"] = true,
        ["supportsReadMemoryRequest"] = true,
        ["supportsWriteMemoryRequest"] = true,
        ["supportsExceptionFilterOptions"] = true,
        ["exceptionBreakpointFilters"] = FilterJson(ExceptionFilters(machine: null))
    };

    // Exception filters as the protocol lists them, with each hover and, for a filter with a condition, its hint.
    private static JsonArray FilterJson((string Filter, string Label, string Description, bool Default)[] filters) =>
        filters.Select(filter => new JsonObject
            {
                ["filter"] = filter.Filter,
                ["label"] = filter.Label,
                ["description"] = filter.Description,
                ["default"] = filter.Default,
                ["supportsCondition"] = FilterConditionDescription(filter.Filter) is not null,
                ["conditionDescription"] = FilterConditionDescription(filter.Filter)
            }).ToJsonArray();

    // Puts a launch's program on a DOS disk as one binary file, for the IIe to boot and BRUN. BRUN starts a binary
    // at its load address, so the entry must be the program's first address.
    private static void LoadOnDosDisk(
        Apple2DebugTarget target,
        IEnumerable<(int Address, ReadOnlyMemory<byte> Bytes)> segments,
        int? entry,
        string path)
    {
        List<(int Address, ReadOnlyMemory<byte> Bytes)> parts = [.. segments];
        if (parts.Count == 0) { throw new ArgumentException("The program is empty."); }

        int start = parts.Min(part => part.Address);
        int end = parts.Max(part => part.Address + part.Bytes.Length);
        if (entry is { } given && given != start)
        {
            throw new ArgumentException("With dos, the program starts at its first address, where BRUN runs it.");
        }

        byte[] image = new byte[end - start];
        foreach ((int address, ReadOnlyMemory<byte> bytes) in parts)
        {
            bytes.Span.CopyTo(image.AsSpan(address - start));
        }

        target.LoadOnDosDisk(start, image, DosFileName(path));
    }

    // A DOS file name from a host file's: its name in capitals, letters, digits and dots only, at most 30 characters.
    private static string DosFileName(string path)
    {
        string name = new([.. Path.GetFileNameWithoutExtension(path)
            .ToUpperInvariant()
            .Where(character => character is (>= 'A' and <= 'Z') or (>= '0' and <= '9') or '.')]);

        return name.Length == 0 || !char.IsAsciiLetter(name[0]) ? "PROGRAM" : name[..Math.Min(name.Length, 30)];
    }

    private JsonObject Launch(JsonObject args)
    {
        _run?.Cancel();
        string machine = DebugMachines.Require(args.String("machine"));
        string? sourceFile = args.String("source");
        string? program = args.String("program");
        string? basicFile = args.String("basic");
        if (new[] { sourceFile, program, basicFile }.Count(given => given is not null) > 1)
        {
            throw new ArgumentException("Give one of source, program and basic.");
        }

        bool loads = sourceFile is not null || program is not null;
        (_target as IDisposable)?.Dispose();
        _target = machine switch
        {
            DebugMachines.Trs80Model1 => LaunchModelI(args, loads),
            DebugMachines.Trs80Model3 => LaunchModelIII(args, loads),
            DebugMachines.Trs80Model2 => LaunchModelII(args, loads),
            DebugMachines.Apple3 => Apple3DebugTarget.Launch(args),
            DebugMachines.Apple1 => LaunchApple1(args, loads || args.String("basic") is not null),
            DebugMachines.Coco => LaunchCoco(args, loads),
            DebugMachines.Altair => AltairDebugTarget.Launch(args),
            _ => Apple2DebugTarget.Launch(args)
        };

        if (args.String("screen") is { } screen) { Target.Screen = screen; }

        // The cards and media the editor saved from the last session of this launch configuration replace the
        // launch's own; a DOS launch's disk, built below, still goes in drive 1.
        if (args["machineState"] is JsonObject saved)
        {
            foreach (string problem in MachineConfiguration.Restore(Target, saved))
            {
                Notify("output", new JsonObject
                {
                    ["category"] = "console",
                    ["output"] = $"The saved machine could not be fully restored: {problem}\n"
                });
            }
        }

        _devices = null;
        _basicVersion = null;
        _basicStatement = null;
        _basicGoal = null;
        _basicStarting = null;
        _basicView = null;
        _typing.Clear();
        _typingDue = 0;
        ForgetPascal();
        _basicEnded = false;
        _lineCycles.Clear();
        _callCycles.Clear();
        _contracts?.Clear();
        _cycleSource = null;
        _pendingLineCycles = 0;
        _lineEntered = false;
        Target.CallStack.Reset();
        Invalidate();

        _debug = new();
        if (sourceFile is not null)
        {
            // The retrocore assembler builds any dialect in place, and the debugger reads its source map directly.
            AssemblyDialect? dialect = SourceBuild.Dialect(args.String("dialect"));

            // A .cpu Z80 source on a machine with the SoftCard is the Z80's: it loads where the Z80's addresses reach,
            // and the Z80 takes the bus at its entry.
            SoftCardDebugTarget? z80 = null;
            if (Target.Coprocessor is SoftCardDebugTarget softCard && SourceBuild.DeclaresCpu(sourceFile, dialect, softCard.Cpu))
            {
                z80 = softCard;
            }

            IDebugTarget loader = z80 ?? Target;
            AssemblyResult result = SourceBuild.Assemble(
                sourceFile,
                dialect,
                loader.Cpu,
                args.Int("loadAddress") ?? loader.DefaultLoadAddress,
                args.String("linkerConfiguration"));

            if (z80 is null && Target is Apple2DebugTarget { Dos: not null } dosTarget)
            {
                LoadOnDosDisk(dosTarget, SourceBuild.Emitted(result), args.Int("entryAddress"), sourceFile);
            }
            else
            {
                int? first = null;
                foreach ((int address, ReadOnlyMemory<byte> bytes) in SourceBuild.Emitted(result))
                {
                    loader.Load(address, bytes.Span);
                    first ??= address;
                }

                z80?.Card.TakeBus();
                loader.ProgramCounter = checked((ushort)(args.Int("entryAddress") ?? first ?? loader.DefaultLoadAddress));
            }

            // MACRO-10 sources define instructions as macros, so a single-statement expansion debugs as its call.
            _debug.Add(new SourceMapModule(result, loader.ProgramArea, loader.CollapsesMacros(dialect)));
        }
        else if (program is not null)
        {
            int address = args.Int("loadAddress") ?? Target.DefaultLoadAddress;
            if (Target is Apple2DebugTarget { Dos: not null } dosTarget)
            {
                LoadOnDosDisk(dosTarget, [(address, File.ReadAllBytes(program))], args.Int("entryAddress"), program);
            }
            else
            {
                Target.Load(address, File.ReadAllBytes(program));
                Target.ProgramCounter = checked((ushort)(args.Int("entryAddress") ?? address));
            }
        }

        if (sourceFile is null && args.String("debugFile") is { } debugFile)
        {
            SymbolTable symbols = new();
            symbols.Load(debugFile);
            _debug.Add(new DebugFileModule(symbols, program is null ? null : Target.ProgramArea));
        }

        // The SDK's ROM sources follow the program, each applying only where its memory area is mapped.
        // The SDK's sources can come from the repository instead, so breakpoints set in the files being edited bind.
        string? sdkRoms = args.String("sdkRoms");
        Target.AddSdkModules(_debug, sdkRoms is null ? null : Path.GetFullPath(sdkRoms));
        string contracts = args.String("checkContracts") ?? "warn";
        _stopOnContracts = contracts == "stop";
        _contracts = contracts == "off" ? null : Contracts(Target.ContractModel, args.Bool("checkUses") ?? false);

        _hidden = 0;
        _exception = null;
        _basicLaunched = null;
        _basicStatement = null;
        _stopOnEntry = args.Bool("stopOnEntry") ?? true;
        _powerOn = "The machine reset as it powered on.";
        if (loads) { _powerOn = "The machine reset as it powered on, and is at the program's entry."; }
        if (basicFile is not null) { _powerOn = null; }
        if (basicFile is not null)
        {
            if (Target is Apple2DebugTarget apple2 && IsIntegerBasic(apple2, basicFile))
            {
                StartIntegerBasic(apple2, basicFile);
            }

            // Apple-1 BASIC is loaded with the machine: E000R starts it.
            if (Target is Apple1DebugTarget apple1) { apple1.StartBasic(); }

            LaunchBasic(basicFile, args.Bool("run") ?? true);
        }

        _basicEntry = basicFile is not null && _stopOnEntry && (args.Bool("run") ?? true);
        RebindBreakpoints();
        _memoryViews.Clear();
        _memoryFrames = 0;
        _sentPixels = [];

        if (args["throttle"] is not null)
        {
            throw new ArgumentException("throttle is now speed: 1, 2, 4 or 8 times the machine's clock, or \"max\".");
        }

        _speed = Speed(args["speed"]);
        int? limit = args.Int("logpointLimit");
        if (limit < 0) { throw new ArgumentException("logpointLimit must be 0 or more."); }
        _logpointLimit = limit ?? DefaultLogpointLimit;
        _logged = 0;
        _dropped = 0;
        _started = false;

        // The Breakpoints view lists the launched machine's exception filters, and what a BASIC thread adds.
        Notify("capabilities", new JsonObject
        {
            ["capabilities"] = new JsonObject
{
                ["supportsBreakpointLocationsRequest"] = HasBasicThread,
                ["supportsSetVariable"] = HasBasicThread,
                ["supportsSetExpression"] = HasBasicThread,
                ["supportsGotoTargetsRequest"] = HasBasicThread,
                ["exceptionBreakpointFilters"] = FilterJson(ExceptionFilters(machine, _contracts is not null, HasBasicThread))
}
        });

        Notify("initialized", []);

        // A configurationDone that came first starts the machine once this response is on its way.
        if (_configured)
        {
            _ = Task.Run(() =>
            {
                lock (_gate) { Start(); }
            });
        }

        return [];
    }

    // The Monitor sets up the PIA as it starts, so a loaded program's output through ECHO, and BASIC's own, reaches
    // the terminal: it runs briefly first when a program or a BASIC file loads.
    private static Apple1DebugTarget LaunchApple1(JsonObject args, bool loads)
    {
        Apple1DebugTarget target = Apple1DebugTarget.Launch(args);
        target.Boot(args.Double("bootSeconds") ?? (loads ? 0.05 : 0));
        return target;
    }

    // A program on a Model I calls the ROM through the RAM vectors and device control blocks, so the ROM runs
    // briefly first to set them up.
    private static Trs80DebugTarget LaunchModelI(JsonObject args, bool loads)
    {
        Trs80DebugTarget target = Trs80DebugTarget.Launch(args);
        target.Boot(args.Double("bootSeconds") ?? (loads ? 1 : 0));
        return target;
    }

    // A program on a Model III, 4 or 4P loads once the ROM has set up its RAM, as on a Model I.
    private static Trs80Model3DebugTarget LaunchModelIII(JsonObject args, bool loads)
    {
        Trs80Model3DebugTarget target = Trs80Model3DebugTarget.Launch(args);
        target.Boot(args.Double("bootSeconds") ?? (loads ? 1 : 0));
        return target;
    }

    // A program on a Model II, 12 or 16 loads at once unless the launch asks the boot ROM to run first.
    private static Trs80Model2DebugTarget LaunchModelII(JsonObject args, bool loads)
    {
        Trs80Model2DebugTarget target = Trs80Model2DebugTarget.Launch(args);
        target.Boot(args.Double("bootSeconds") ?? 0);
        return target;
    }

    // A program on a Color Computer calls Color BASIC's routines through RAM hooks it sets up as it starts, so the
    // ROM runs first; Disk BASIC takes longer, as it resets the drives.
    private static CocoDebugTarget LaunchCoco(JsonObject args, bool loads)
    {
        CocoDebugTarget target = CocoDebugTarget.Launch(args);
        target.Boot(args.Double("bootSeconds") ?? (loads ? 2 : 0));
        return target;
    }

    /// <summary>
    ///  Starts the launched machine once, after configuration: stopping on entry, on a breakpoint at the first
    ///  instruction (the reset handler, when booting), or running.
    /// </summary>
    private void Start()
    {
        if (_started) { return; }
        if (_basicEntry)
        {
            // A BASIC file that RUNs stops on its first statement.
            _started = true;
            _basicGoal = new(BasicStep.Entry, Depth: 0, CallsMachine: false, ulong.MaxValue);
            Continue();
            return;
        }

        _started = true;

        // Continue skips the breakpoints where it starts, unless the stop left them unchecked, so that continuing
        // from a breakpoint moves on.
        ushort pc = Cpu.ProgramCounter;
        if (_stopOnEntry)
        {
            Stopped("entry");
        }
        else if (_powerOn is { } powerOn && BreaksOn(MachineResetFilter))
        {
            // One stop at the first instruction: the reset stop, with its breakpoints checked on resuming.
            Stopped("breakpoint", description: powerOn);
            _unchecked = true;
        }
        else if (Hit(pc) is { } hit)
        {
            Stopped(hit);
        }
        else
        {
            Continue();
        }
    }

    private DebugFrame[] Frames => _frames ??= Target.CallStack.Frames(Target.Frame);

    private DebugFrame[] FramesOf(int thread) => thread == SoftCardThread
        ? _coprocessorFrames ??= ThreadTarget(thread).CallStack.Frames(ThreadTarget(thread).Frame)
        : Frames;

    private DisplayFrame[] DisplayOf(int thread) =>
        thread == SoftCardThread ? _coprocessorDisplay ??= BuildDisplay(thread) : Display;

    /// <summary>
    ///  Gets the stack as shown: each CPU frame expands into one frame per macro level at its PC, innermost first.
    /// </summary>
    private DisplayFrame[] Display => _display ??= BuildDisplay(1);

    // A thread's frames as shown. The thread that stopped hides the macro levels its stop hides.
    private DisplayFrame[] BuildDisplay(int thread)
    {
        List<DisplayFrame> frames = [];
        IDebugTarget view = ThreadTarget(thread);
        DebugFrame[] cpuFrames = FramesOf(thread);
        for (int cpu = 0; cpu < cpuFrames.Length; cpu++)
        {
            ushort pc = cpuFrames[cpu].ProgramCounter;
            if (_debug.Position(view, pc) is not { } position)
            {
                frames.Add(new(cpu, pc, Line: null));
                continue;
            }

            int first = cpu == 0 && thread == _stoppedThread ? Math.Min(_hidden, position.Chain.Count - 1) : 0;
            for (int level = first; level < position.Chain.Count; level++)
            {
                frames.Add(new(cpu, pc, position.Chain[level]));
            }
        }

        return [.. frames];
    }

    private void Invalidate()
    {
        _frames = null;
        _display = null;
        _coprocessorFrames = null;
        _coprocessorDisplay = null;
    }

    private DebugFrame FrameRegisters(int frameId)
    {
        (int thread, int index) = FrameIndex(frameId);
        DisplayFrame[] display = DisplayOf(thread);
        return index < 0 || index >= display.Length
            ? throw new ArgumentOutOfRangeException(nameof(frameId))
            : FramesOf(thread)[display[index].Cpu];
    }

    private JsonObject StackTrace(JsonObject args)
    {
        int start = args.Int("startFrame") ?? 0;
        int levels = args.Int("levels") ?? 0;
        if (start < 0 || levels < 0) { throw new ArgumentOutOfRangeException(nameof(args)); }
        int thread = args.Int("threadId") == SoftCardThread && _target?.Coprocessor is not null ? SoftCardThread : 1;
        IDebugTarget view = ThreadTarget(thread);
        DisplayFrame[] display = DisplayOf(thread);
        int frameBase = thread == SoftCardThread ? SoftCardFrameBase : 0;
        List<JsonNode?> frames = [];
        int end = levels == 0 ? display.Length : (int)Math.Min(display.Length, (long)start + levels);
        for (int index = start; index < end; index++)
        {
            (_, ushort pc, SourceLine? line) = display[index];

            // A macro body frame is named by its invocation; other frames by the closest label.
            string name = line?.Name ?? _debug.Label(view, pc) ?? $"${pc:X4}";
            frames.Add(new JsonObject
            {
                ["id"] = frameBase + index + 1, ["name"] = name, ["source"] = line is { } value ? new JsonObject
{
                    ["name"] = Path.GetFileName(value.Path), ["path"] = value.Path
} : null,
                ["line"] = line?.Line ?? 1, ["column"] = 1,
                ["instructionPointerReference"] = Reference(ThreadBank(thread), pc)
            });
        }

        return new JsonObject { ["stackFrames"] = frames.ToJsonArray(), ["totalFrames"] = display.Length };
    }

    private JsonObject Scopes(JsonObject args)
    {
        int frameId = (args.Int("frameId") ?? 0);
        FrameRegisters(frameId);
        List<JsonNode?> scopes =
        [
            new JsonObject
            {
                ["name"] = FrameIndex(frameId).Index == 0 ? "Registers" : "Caller registers at call",
                ["variablesReference"] = frameId * 2 - 1,
                ["expensive"] = false
            },
            new JsonObject
            {
                ["name"] = FrameTarget(frameId).MemoryScope.Name,
                ["variablesReference"] = frameId * 2,
                ["expensive"] = false
            },
            new JsonObject { ["name"] = "Memory", ["variablesReference"] = BanksScope, ["expensive"] = false }
        ];

        // The documented routine the frame is in: its summary names the scope, and its sections fill it.
        if (FrameTopic(frameId) is { } topic)
        {
            string summary = topic.Summary.Length > 80 ? $"{topic.Summary[..77]}..." : topic.Summary;
            string name = summary.Length == 0 ? topic.Name : $"{topic.Name}: {summary}";
            scopes.Add(new JsonObject
            {
                ["name"] = name,
                ["variablesReference"] = DocumentationScope + frameId,
                ["expensive"] = false
            });
        }

        return new JsonObject { ["scopes"] = scopes.ToJsonArray() };
    }

    // Variables references at and above this are documentation scopes, by frame.
    private const int DocumentationScope = 100000;

    /// <summary>
    ///  Gets the <c>;;</c> summary of a name the program's or the ROMs' sources document, inheritance followed, as
    ///  plain text: a link shows its name.
    /// </summary>
    /// <param name="name">The name, as the hover's expression gives it.</param>
    /// <returns>The summary, or null when the name is not a documented one.</returns>
    private string? SymbolSummary(string name)
    {
        if (name.Length == 0 || !name.All(character => char.IsAsciiLetterOrDigit(character) || character is '_' or '.'))
        {
            return null;
        }

        DocumentationSet[] sets = [.. _debug.Modules.Select(module => module.Documentation)];
        // The module whose definition the value came from, as evaluation resolves it: the first that defines the
        // name. Its documentation, or none, describes it; another module's same name is a different symbol.
        IDebugModule? defining = _debug.Modules.FirstOrDefault(module => module.TryResolve(name, out _));
        if (defining is null) { return null; }
        DocumentationSet documentation = defining.Documentation;
        if ((documentation.Find(name) ?? documentation.FindRoutine(name)) is not { } topic) { return null; }
        string summary = new DocumentationResolver(documentation, sets).Effective(topic).Summary;

        // A link shows its name without its module.
        return summary.Length == 0 ? null : LinkPattern().Replace(summary, link => link.Groups[1].Value.Split(':')[^1]);
    }

    // A documentation link, such as <XAMH> or <Monitor:A1L>.
    [GeneratedRegex(@"<([A-Za-z_][\w.]*(?::[A-Za-z_][\w.]*)?)>")]
    private static partial Regex LinkPattern();

    /// <summary>
    ///  Finds the documented routine a frame is in: the nearest documented routine at or before its PC.
    /// </summary>
    private DocumentationTopic? FrameTopic(int frameId)
    {
        (int thread, int index) = FrameIndex(frameId);
        DisplayFrame[] display = DisplayOf(thread);
        if (index < 0 || index >= display.Length) { return null; }
        ushort pc = display[index].Pc;
        IDebugTarget view = ThreadTarget(thread);
        DocumentationSet[] sets = [.. _debug.Modules.Select(module => module.Documentation)];
        (DocumentationTopic Topic, IDebugModule Module)? best = null;
        foreach (IDebugModule module in _debug.Modules)
        {
            foreach (DocumentationTopic topic in module.Documentation.Topics)
            {
                bool before = topic.Kind == DocumentationKind.Routine && topic.Value is { } value && value <= pc;
                if (!before || (best is { } found && found.Topic.Value >= topic.Value)) { continue; }
                if (DebugInfo.Active(module, view, pc)) { best = (topic, module); }
            }
        }

        return best is { } routine ? new DocumentationResolver(routine.Module.Documentation, sets).Effective(routine.Topic) : null;
    }

    private JsonObject DocumentationVariables(int frameId)
    {
        List<JsonNode?> variables = [];
        if (FrameTopic(frameId) is not { } topic) { return new JsonObject { ["variables"] = variables.ToJsonArray() }; }
        DebugFrame registers = FrameRegisters(frameId);
        foreach (DocumentationSection section in topic.Sections)
        {
            string heading = section.Condition is { } condition ? $"{section.Name} ({condition})" : section.Name;
            if (section.Entries.Count != 0)
            {
                foreach (DocumentationEntry entry in section.Entries)
                {
                    string? current = Current(FrameTarget(frameId), entry.Name, registers);
                    string value = current is null ? entry.Meaning : $"{current} — {entry.Meaning}";
                    variables.Add(new JsonObject
                    {
                        ["name"] = $"{heading} {entry.Name}",
                        ["value"] = value,
                        ["variablesReference"] = 0
                    });
                }
            }
            else if (section.Name is not ("Inherit" or "Include"))
            {
                string value = section.Items.Count != 0 ? string.Join(", ", section.Items) : section.Text;
                variables.Add(new JsonObject { ["name"] = heading, ["value"] = value, ["variablesReference"] = 0 });
            }
        }

        return new JsonObject { ["variables"] = variables.ToJsonArray() };
    }

    // The current value of a documented register or byte of memory, or null.
    private string? Current(IDebugTarget view, string name, in DebugFrame registers)
    {
        if (view.Registers.Value(registers, name) is { } value)
        {
            return value > 0xFF ? $"${value:X4}" : $"${value:X2}";
        }

        foreach (IDebugModule module in _debug.Modules)
        {
            if (module.TryResolve(name, out long address) && address is >= 0 and <= 0xFFFF)
            {
                return $"${view.Peek((ushort)address):X2}";
            }
        }

        return null;
    }

    private JsonObject Variables(int reference)
    {
        if (reference >= PascalReferences) { return PascalVariablesOf(reference); }
        if (reference >= BasicReferences) { return BasicVariablesOf(reference); }
        if (reference > DocumentationScope) { return DocumentationVariables(reference - DocumentationScope); }
        if (reference == BanksScope) { return BankVariables(); }
        List<JsonNode?> variables = [];
        int frameId = (reference + 1) / 2;
        (int thread, int index) = FrameIndex(frameId);
        if (reference < 1 || index < 0 || index >= DisplayOf(thread).Length)
        {
            throw new ArgumentOutOfRangeException(nameof(reference));
        }

        IDebugTarget view = ThreadTarget(thread);
        DebugMemoryBank? bank = ThreadBank(thread);
        DebugFrame r = FrameRegisters(frameId);
        if ((reference & 1) != 0)
        {
            // The instruction set names the registers; the frame holds their values.
            foreach (IsaRegister register in view.Registers.Listed)
            {
                long value = view.Registers.Value(r, register.Name) ?? 0;
                int? address = view.PointsTo(register, value);
                variables.Add(new JsonObject
                {
                    ["name"] = register.Name,
                    ["value"] = $"${value:X}",
                    ["variablesReference"] = 0,
                    ["memoryReference"] = address is { } pointer ? Reference(bank, pointer) : null
                });
            }
        }
        else
        {
            (_, ushort start, int length) = view.MemoryScope;
            for (int i = 0; i < length; i++)
            {
                ushort address = (ushort)(start + i);
                string name = start == 0 ? $"${i:X2}" : $"${address:X4}";
                variables.Add(new JsonObject
                {
                    ["name"] = name,
                    ["value"] = $"${view.Peek(address):X2}",
                    ["variablesReference"] = 0,
                    ["memoryReference"] = Reference(bank, address)
                });
            }
        }

        return new JsonObject { ["variables"] = variables.ToJsonArray() };
    }

    // Whether a request is for the BASIC thread.
    private bool OnBasic(JsonObject args) => args.Int("threadId") == BasicThread && _target is not null && HasBasicThread;

    // Whether a step request steps by instruction, as the Disassembly view's steps do.
    private static bool Instruction(JsonObject args) => args.String("granularity") == "instruction";

    private void Step(bool over, bool outOf, bool instruction, int thread)
    {
        _run?.Cancel();

        // A step runs until the thread's own CPU has stepped. While the other CPU has the bus, it runs, and its
        // breakpoints stop the step.
        IDebugTarget cpu = ThreadTarget(thread);
        bool running = ReferenceEquals(cpu, Cpu);
        bool boundary = cpu.IsInstructionBoundary;
        ushort start = boundary || !running ? cpu.ProgramCounter : _instructionStart;
        if (Resume(boundary) && running && Hit(start) is { } waiting)
        {
            Stopped(waiting);
            return;
        }

        DebugPosition? position = _debug.Position(cpu, start);
        int hiddenNow = ThreadOf(cpu) == _stoppedThread ? _hidden : 0;
        int hidden = position is null ? 0 : Math.Min(hiddenNow, position.Chain.Count - 1);
        SourceLine[]? shown = instruction ? null : position?.Chain.Skip(hidden).ToArray();

        // On a macro call line whose invocation starts here, stepping in moves one level inward without running.
        if (!instruction && !over && !outOf && boundary && position is not null && hidden > 0 && hidden <= position.EntryDepth)
        {
            _hidden = hidden - 1;
            Stopped("step", hidden: _hidden, threadId: ThreadOf(cpu));
            return;
        }

        // Stepping out of a macro body leaves its invocation; anywhere else it returns from the current call.
        bool inMacro = shown is { Length: > 1 };
        var returnTarget = outOf && !inMacro ? cpu.CallStack.ReturnTarget() : null;
        if (outOf && !inMacro && returnTarget is null)
        {
            throw new InvalidOperationException("No tracked caller is available for step out.");
        }

        int depth = cpu.CallStack.Depth();
        for (int count = 0; count < 1_000_000; count++)
        {
            IDebugTarget ran = Cpu;
            if (!Execute()) { return; }

            // The other CPU's instruction: only its breakpoints can stop the step. While the stepping CPU is idle no
            // instruction of its has finished, so the step neither ends nor meets a breakpoint of its own.
            if (!ReferenceEquals(ran, cpu) || !cpu.IsInstructionBoundary)
            {
                if (Cpu.IsInstructionBoundary && Hit(Cpu.ProgramCounter) is { } other)
                {
                    Stopped(other);
                    return;
                }

                continue;
            }

            DebugFrame r = cpu.Frame;
            DebugPosition? now = _debug.Position(cpu, r.ProgramCounter);

            // Step over and out never stop inside a call or interrupt entered during the step. A call returns at
            // its return address, or past it when the routine skips inline data after the call.
            int level = cpu.CallStack.Depth();
            bool complete = outOf
                ? inMacro
                    ? level <= depth && shown is not null && !Within(now, shown[1..], shown.Length)
                    : returnTarget is { } target
                        && r.StackPointer == target.StackPointer
                        && (r.ProgramCounter == target.Address || level < depth)
                : over
                    ? level <= depth && !Within(now, shown, shown?.Length ?? 0)
                    : shown is null || now is null || !Arrival(now).SequenceEqual(shown);

            // A breakpoint inside what the step runs over stops it, as it would stop running; so does one where the
            // step ends, which counts the hit, applies its condition and writes its log message. The other CPU may
            // have the bus now, after an instruction that handed it over.
            if (Cpu.IsInstructionBoundary && Hit(Cpu.ProgramCounter) is { } hit)
            {
                Stopped(hit);
                return;
            }

            if (complete)
            {
                Stopped("step", threadId: ThreadOf(cpu));
                return;
            }
        }

        throw new InvalidOperationException("Source stepping exceeded its explicit instruction budget.");
    }

    /// <summary>
    ///  Gets the levels shown on arriving at a position: from the line making the calls that start there.
    /// </summary>
    /// <param name="position">The position.</param>
    /// <returns>The shown levels, innermost first.</returns>
    private static IEnumerable<SourceLine> Arrival(DebugPosition position) => position.Chain.Skip(position.EntryDepth);

    /// <summary>
    ///  Tests whether a position is still inside the given source levels: the same or a deeper line whose
    ///  outermost levels are those.
    /// </summary>
    /// <param name="position">The position, or null for code without source.</param>
    /// <param name="levels">The levels to stay within, innermost first, or null.</param>
    /// <param name="depth">The fewest levels the position must have.</param>
    /// <returns>Whether the position is within.</returns>
    private static bool Within(DebugPosition? position, SourceLine[]? levels, int depth)
    {
        if (position is null || levels is null || position.Chain.Count < depth) { return false; }
        int offset = position.Chain.Count - levels.Length;
        for (int index = 0; index < levels.Length; index++)
        {
            if (position.Chain[offset + index] != levels[index]) { return false; }
        }

        return true;
    }

    // Runs the rest of the current instruction, or the next one; an interrupt's response runs with the
    // instruction after it. A Z80 interrupt response and an indexed bit instruction together stay under 64.
    private const int InstructionCycleBudget = 64;

    private bool Execute()
    {
        Invalidate();

        // Pasted keys go in as the machine runs, whether continuing or stepping.
        if (_typing.Count != 0) { TypeNext(); }

        // The instruction is that of the CPU with the bus as it starts. One that hands the bus over finishes on the
        // CPU's own view; the SoftCard's Z80 runs its last T-states beside the 6502.
        IDebugTarget cpu = Cpu;
        bool instruction = cpu.InInstruction;
        for (int count = 0; count < InstructionCycleBudget; count++)
        {
            if (cpu.CycleBreak() is { } beam && BeamStop(beam) is { } stop)
            {
                Stopped(stop);
                _unchecked = cpu.IsInstructionBoundary;
                return false;
            }

            if (cpu.IsInstructionBoundary && (ResetStops() || !Observe(cpu))) { return false; }
            instruction |= cpu.StepCycle();
            if (_watches.Count != 0)
            {
                Watch(cpu.LastCycle, cpu is SoftCardDebugTarget z80 ? z80.Card.Processor.LastCycle : null);
            }

            if (_cycleSource is not null) { _pendingLineCycles++; }

            if (instruction && cpu.IsInstructionBoundary) { return _dataHits.Count == 0 || DataStop(); }

            // A Z80 that handed the bus back mid-instruction, as a 16-bit store to the switch does, waits there.
            if (cpu is SoftCardDebugTarget { Card.Running: false }) { return _dataHits.Count == 0 || DataStop(); }

            // An idle CPU may stay so for any time, so its cycles go back to the run loop a few at a time; the next
            // instruction is observed once the CPU goes on. An instruction that ends by waiting, as CWAI does, has
            // made its writes, so the watchpoints they hit stop now.
            if (cpu.IsIdle) { return !instruction || _dataHits.Count == 0 || DataStop(); }

            // A held CPU may stay so for any time too. Its instruction has not finished, so the watchpoints it hit
            // wait for the instruction's end.
            if (cpu.IsHeld) { return true; }
        }

        throw new InvalidOperationException($"Instruction execution exceeded its {InstructionCycleBudget}-cycle budget.");
    }

    // Stops where a reset reaches its handler, at a breakpoint there if one hits, so that the two stop once.
    private bool ResetStops()
    {
        if (!Target.TakeResetStop() || !BreaksOn(MachineResetFilter)) { return false; }
        if (Hit(Cpu.ProgramCounter) is { } hit)
        {
            Stopped(hit);
        }
        else
        {
            Stopped("breakpoint", description: "The machine reset.");
        }

        return true;
    }

    // Observes an instruction boundary: its source line's cycles, the calls it starts and the contracts calls
    // returning to it break. Returns false when a broken contract stops.
    private bool Observe(IDebugTarget cpu)
    {
        DebugFrame before = cpu.Frame;
        _instructionStart = before.ProgramCounter;
        bool machineCpu = IsMachineCpu(cpu);
        if (machineCpu)
        {
            ObserveBasic(before.ProgramCounter);
            ObservePascal(before.ProgramCounter);
        }

        FlushLineCycles();
        (string Path, int Line)? previous = _cycleSource;
        _cycleSource = _debug.Position(cpu, before.ProgramCounter)?.Chain[0] is { } line
            ? (line.Path, line.Line)
            : null;

        // Each line shows its latest run: entering it again starts its count over, while consecutive
        // instructions on one line (a macro, or several statements) add up.
        _lineEntered = _cycleSource is { } entered && entered != previous;

        // Call cycles and contracts follow the machine's CPU, whose routines the SDK documents.
        if (!machineCpu) { return true; }
        (ushort Target, int Length)? call = Target.CallAt(before.ProgramCounter);
        _callCycles.Observe(before.ProgramCounter, call?.Length, before.StackPointer, Target.CycleCount, _cycleSource);
        if (_contracts?.Observe(before, call, Target.Peek) is { Count: > 0 } broken)
        {
            foreach (string message in broken)
            {
                Notify("output", new JsonObject { ["category"] = "console", ["output"] = $"{message}\n" });
            }

            if (_stopOnContracts || BreaksOn(ContractsFilter))
            {
                Stopped("exception", description: broken[0], exception: "contract");
                return false;
            }
        }

        return true;
    }

    // Types the next pasted key once its time has come, and sets the time of the one after: longer after a RETURN.
    private void TypeNext()
    {
        if (Target.TypingPace is not { } pace)
        {
            while (_typing.TryDequeue(out int code)) { Target.Key(code); }
            return;
        }

        if (Target.CycleCount < _typingDue) { return; }
        int next = _typing.Dequeue();
        Target.Key(next);
        _typingDue = Target.CycleCount + (next == '\r' ? pace.Line : pace.Key);
    }

    private void Continue()
    {
        _run?.Cancel();
        _run?.Dispose();
        _run = new();
        CancellationToken token = _run.Token;
        bool check = Resume(Cpu.IsInstructionBoundary);
        _ = Task.Run(async () =>
        {
            bool first = !check;

            // Only a stop at the BRK itself has reported it; resuming from any other stop there checks it.
            bool trapReported = _exception is ("brk", _);
            long frameTime = Stopwatch.GetTimestamp();

            // Sound made while stopped would play as a burst; the panel hears only what runs from here.
            Target.TakeAudio();
            long paceTime = frameTime;
            ulong paceCycles = Target.CycleCount;
            lock (_gate) { StartMeasuring(); }
            bool ahead = false;
            try
            {
                while (!token.IsCancellationRequested)
                {
                    lock (_gate)
                    {
                        // Each slice runs until it has kept up with the machine's clock, or for a few milliseconds.
                        long slice = Stopwatch.GetTimestamp();
                        ulong due = Due(ref paceTime, ref paceCycles);
                        ahead = false;
                        for (int count = 0; !token.IsCancellationRequested && Target.CycleCount < due; count++)
                        {
                            if ((count & 63) == 0
                                && (Volatile.Read(ref _requestsWaiting) != 0
                                    || Stopwatch.GetElapsedTime(slice).TotalMilliseconds >= SliceMilliseconds))
                            {
                                break;
                            }

                            IDebugTarget cpu = Cpu;
                            ushort pc = cpu.ProgramCounter;
                            bool boundary = cpu.IsInstructionBoundary;
                            if (boundary
                                && !first
                                && Hit(pc) is { } hit)
                            {
                                Stopped(hit);
                                return;
                            }

                            if (boundary && !first && IsMachineCpu(cpu) && BasicStops(pc)) { return; }
                            if (boundary && !first && IsMachineCpu(cpu) && PascalStops(pc)) { return; }

                            // Continuing from a BRK stop runs the BRK.
                            if (boundary
                                && !(first && trapReported)
                                && BreaksOn(BrkFilter)
                                && cpu.Trap(pc) is { } trap)
                            {
                                Stopped("exception", description: trap, exception: "brk");
                                return;
                            }

                            first = false;

                            if (!Execute()) { return; }
                        }

                        ahead = Target.CycleCount >= due;
                        if (Stopwatch.GetElapsedTime(frameTime).TotalMilliseconds >= 33)
                        {
                            AddLoadedModules();
                            Measure();
                            NotifyFrame(running: true);
                            if (Target.TakeAudio() is { } audio) { Notify("retro/audio", audio); }
                            Notify("retro/cycles", SourceCycles());
                            NotifyStatus();
                            NotifyRunningMemory();
                            frameTime = Stopwatch.GetTimestamp();
                        }
                    }

                    // Ahead of the clock, the loop sleeps; Windows rounds the millisecond up to its 15.6 ms timer tick,
                    // which pacing absorbs. Behind it, or at max, sleeping would idle most of the time, so the loop only
                    // lets go of the lock, for requests such as pause, and runs the next slice.
                    if (ahead)
                    {
                        await Task.Delay(millisecondsDelay: 1, token).ConfigureAwait(continueOnCapturedContext: false);
                    }
                    else
                    {
                        // A waiting request gets the lock before the next slice takes it again.
                        for (int spin = 0; spin < 1000 && Volatile.Read(ref _requestsWaiting) != 0; spin++)
                        {
                            Thread.Yield();
                        }

                        await Task.Yield();
                    }
                }
            }
            catch (OperationCanceledException) when (token.IsCancellationRequested)
            {
            }
            catch (InvalidOperationException exception)
            {
                ExecutionFailed(exception);
            }
            catch (FormatException exception)
            {
                ExecutionFailed(exception);
            }
            catch (OverflowException exception)
            {
                ExecutionFailed(exception);
            }
            catch (IOException exception)
            {
                ExecutionFailed(exception);
            }
        }, token);
    }

    private const double SliceMilliseconds = 10;

    // The cycle count running should reach by now: the machine's clock since pacing started, or no limit when
    // unthrottled. Falling far behind starts the pacing over rather than racing to catch up.
    private ulong Due(ref long paceTime, ref ulong paceCycles)
    {
        if (_speed == 0) { return ulong.MaxValue; }
        if (_paceAgain)
        {
            _paceAgain = false;
            paceTime = Stopwatch.GetTimestamp();
            paceCycles = Target.CycleCount;
        }

        if (Target.Accelerated)
        {
            // Pacing starts over once the acceleration ends, rather than waiting for the clock to catch up.
            paceTime = Stopwatch.GetTimestamp();
            paceCycles = Target.CycleCount;
            return ulong.MaxValue;
        }

        double hertz = Target.ClockHertz * _speed;
        double seconds = Stopwatch.GetElapsedTime(paceTime).TotalSeconds;
        ulong due = paceCycles + (ulong)(seconds * hertz);
        if (due > Target.CycleCount + (ulong)(hertz / 10))
        {
            paceTime = Stopwatch.GetTimestamp();
            paceCycles = Target.CycleCount;
            due = paceCycles + (ulong)(hertz / 100);
        }

        return due;
    }

    // The speed a launch or retro/speed asks for: 1, 2, 4 or 8 times the machine's clock, or "max" (0), as fast as
    // the host can.
    private static double Speed(JsonNode? value) => value switch
    {
        null => 1,
        JsonValue text when text.GetValueKind() == JsonValueKind.String && text.GetValue<string>() == "max" => 0,
        JsonValue number when number.GetValueKind() == JsonValueKind.Number && number.GetValue<double>() is 1 or 2 or 4 or 8 =>
            number.GetValue<double>(),
        _ => throw new ArgumentException("speed must be 1, 2, 4, 8 or \"max\".")
    };

    private void StartMeasuring()
    {
        _measureTime = Stopwatch.GetTimestamp();
        _measureCycles = Target.CycleCount;
        _measured = double.NaN;
    }

    // Measures the speed once at least half a second has run since the last measure.
    private void Measure()
    {
        long now = Stopwatch.GetTimestamp();
        double seconds = Stopwatch.GetElapsedTime(_measureTime, now).TotalSeconds;
        if (seconds < 0.5) { return; }
        _measured = (Target.CycleCount - _measureCycles) / seconds / Target.ClockHertz;
        _measureTime = now;
        _measureCycles = Target.CycleCount;
    }

    // A frame's speed: the setting, and while running the measured multiple and the clock it amounts to.
    private JsonObject SpeedJson(bool running)
    {
        JsonObject speed = new()
        {
            ["setting"] = _speed == 0 ? "max" : (JsonNode)_speed,
            ["accelerated"] = running && _speed != 0 && Target.Accelerated
        };

        bool measured = running && !double.IsNaN(_measured);
        speed["actual"] = measured ? Math.Round(_measured, 3) : null;
        speed["hertz"] = measured ? Math.Round(_measured * Target.ClockHertz) : null;
        return speed;
    }

    private void ExecutionFailed(Exception exception)
    {
        Console.Error.WriteLine(exception);
        lock (_gate) { Stopped("exception", description: exception.Message, exception: "error"); }
    }

    /// <summary>
    ///  Builds the Keeps: contracts of every module's documented routines.
    /// </summary>
    /// <param name="model">The launched model, for model-specific sections.</param>
    /// <param name="checkUses">Whether to also report registers changed that Uses: does not list.</param>
    /// <returns>The checker, or null when no routine documents a contract.</returns>
    private DebugContracts? Contracts(string model, bool checkUses)
    {
        DocumentationSet[] sets = [.. _debug.Modules.Select(module => module.Documentation)];
        List<(IDebugModule Module, Dictionary<ushort, DebugContract> Contracts)> modules = [];
        foreach (IDebugModule module in _debug.Modules)
        {
            DocumentationResolver resolver = new(module.Documentation, sets);
            modules.Add((module, DebugContracts.Build(resolver, model, Target.Registers)));
        }

        if (modules.All(module => module.Contracts.Count == 0)) { return null; }
        return new DebugContracts(
            address =>
            {
                foreach ((IDebugModule module, Dictionary<ushort, DebugContract> contracts) in modules)
                {
                    if (contracts.TryGetValue(address, out DebugContract? contract) && DebugInfo.Active(module, Target, address))
                    {
                        return contract;
                    }
                }

                return null;
            },
            checkUses,
            Target.Registers,
            Target.UsedRegisters);
    }

    /// <summary>
    ///  Reports a stop.
    /// </summary>
    /// <param name="reason">The DAP reason.</param>
    /// <param name="breakpoints">The breakpoints hit, if any.</param>
    /// <param name="description">A description of the stop.</param>
    /// <param name="hidden">
    ///  The innermost macro levels to hide at the PC, or null to show the line making the calls that start there.
    /// </param>
    /// <param name="exception">What an exception stop is, for exceptionInfo: brk, contract or error.</param>
    /// <param name="threadId">The thread that stopped: the CPU's, or BASIC's.</param>
    private void Stopped(
        string reason,
        int[]? breakpoints = null,
        string? description = null,
        int? hidden = null,
        string? exception = null,
        int? threadId = null)
    {
        Invalidate();
        int thread = threadId ?? (_target is null ? 1 : ThreadOf(Cpu));
        _stoppedThread = thread;
        _basicGoal = null;
        _pascalGoal = null;
        _pascalFrames = null;
        ForgetBasicReferences();
        _unchecked = false;
        AddLoadedModules();

        // A stop where a reset reaches its handler is that reset's stop.
        if (_target is not null && Target.IsInstructionBoundary) { Target.TakeResetStop(); }
        ReportDropped();
        _exception = reason == "exception" ? (exception ?? "error", description ?? "The machine stopped.") : null;
        IDebugTarget? stopped = _target is null ? null : ThreadTarget(thread);
        _hidden = hidden ?? (stopped is { IsInstructionBoundary: true }
            ? _debug.Position(stopped, stopped.ProgramCounter)?.EntryDepth ?? 0
            : 0);

        Notify("stopped", new JsonObject
        {
            ["reason"] = reason,
            ["description"] = description,
            ["threadId"] = thread,
            ["allThreadsStopped"] = true,
            ["hitBreakpointIds"] = breakpoints?.ToJsonArray()
        });

        NotifyFrame(running: false);
        Notify("retro/cycles", SourceCycles());
        NotifyStatus();
        NotifyMemory();
    }

    // Whether resuming from the last stop checks the breakpoints at the PC before running, and forgets it.
    private bool Resume(bool boundary)
    {
        bool check = _unchecked && boundary;
        _unchecked = false;
        return check;
    }

    private void NotifyStatus()
    {
        foreach ((string name, JsonObject body) in Target.StatusEvents()) { Notify(name, body); }
        NotifyDevices();
        NotifyHits();
        FlushLog();
    }

    // The retro/devices body: the devices, the machine's installed hardware they sit on, and the configuration the
    // editor saves for the next launch.
    private JsonObject DevicesBody()
    {
        JsonObject body = DeviceJson.Write(Target.Devices);
        body["hardware"] = HardwareRow.Json(Target.Hardware());
        body["configuration"] = MachineConfiguration.Capture(Target);
        return body;
    }

    // Sends retro/devices when any device's state has changed since the last one sent.
    private void NotifyDevices()
    {
        JsonObject devices = DevicesBody();
        string text = devices.ToJsonString();
        if (text == _devices) { return; }
        _devices = text;
        Notify("retro/devices", devices);
    }

    // Adds the cycles run since the last time to the current line's count, starting it over if the line was entered.
    private void FlushLineCycles()
    {
        if (_cycleSource is { } source && (_pendingLineCycles != 0 || _lineEntered))
        {
            ref ulong count = ref CollectionsMarshal.GetValueRefOrAddDefault(_lineCycles, source, out _);
            count = _lineEntered ? _pendingLineCycles : count + _pendingLineCycles;
        }

        _pendingLineCycles = 0;
        _lineEntered = false;
    }

    private JsonObject SourceCycles()
    {
        FlushLineCycles();
        return SourceCyclesJson();
    }

    private JsonObject SourceCyclesJson() => new JsonObject
    {
        ["lines"] = _lineCycles.OrderBy(pair => pair.Key.Path, StringComparer.OrdinalIgnoreCase).ThenBy(pair => pair.Key.Line)
            .Select(pair => new JsonObject
            {
                ["path"] = pair.Key.Path,
                ["line"] = pair.Key.Line,
                ["cycles"] = pair.Value
            }).ToJsonArray(),

        // Each calling line's latest completed call, counting the call, the subroutine and its return.
        ["calls"] = _callCycles.Last.OrderBy(pair => pair.Key.Path, StringComparer.OrdinalIgnoreCase).ThenBy(pair => pair.Key.Line)
            .Select(pair => new JsonObject
            {
                ["path"] = pair.Key.Path,
                ["line"] = pair.Key.Line,
                ["cycles"] = pair.Value
            }).ToJsonArray(),
        ["cycles"] = Target.CycleCount
    };

    // Sends retro/frame. A running frame whose picture has not changed leaves out its pixels, which the panel
    // keeps; a stopped one always has them, so the picture is whole wherever the machine stops.
    private void NotifyFrame(bool running)
    {
        JsonObject state = Target.DisplayState(running);
        state["speed"] = SpeedJson(running);
        ReadOnlySpan<byte> pixels = Target.RenderVideo();
        bool changed = !running || !pixels.SequenceEqual(_sentPixels);
        if (changed)
        {
            if (_sentPixels.Length != pixels.Length) { _sentPixels = new byte[pixels.Length]; }
            pixels.CopyTo(_sentPixels);
        }

        ReadOnlyMemory<byte> sent = changed ? _sentPixels : ReadOnlyMemory<byte>.Empty;
        (_transport ?? throw new InvalidOperationException("The session is not registered with a transport."))
            .SendEvent("retro/frame", writer => DisplayFrameWriter.Write(writer, state, sent.Span));
    }

    private void Notify(string method, JsonObject body) =>
        (_transport ?? throw new InvalidOperationException("The session is not registered with a transport.")).SendEvent(method, body);
    private static string Required(
        JsonObject args,
        string name) => args.String(
            name) ?? throw new ArgumentException(
                $"{name} is required.");
    private static int Address(string value) => Convert.ToInt32(
        value.StartsWith("0x", StringComparison.OrdinalIgnoreCase) ? value[2..] : value.TrimStart('$'),
        fromBase: 16);
}
