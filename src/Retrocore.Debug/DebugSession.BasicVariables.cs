// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text;
using Touki.Text;
using System.Text.RegularExpressions;
using System.Text.Json.Nodes;
using Retrocore.Basic;

namespace Retrocore.Debug;

// The BASIC thread's variables: its scopes, BASIC expressions for watches, hovers, the console, breakpoint conditions
// and logpoints, setting values, and breaking when a variable changes.
internal sealed partial class DebugSession
{
    private const int BasicReferences = 1_000_000;
    private const int BasicVariablesScope = BasicReferences + 1;
    private const int BasicArraysScope = BasicReferences + 2;
    private const int BasicFunctionsScope = BasicReferences + 3;
    private const int BasicLoopsScope = BasicReferences + 4;
    private const int BasicProgramScope = BasicReferences + 5;
    private const int BasicChildren = BasicReferences + 100;
    private const int ChunkSize = 100;
    private const string BasicDataPrefix = "basic:";
    private const string NewVariableBetween =
        "BASIC can make a new variable only between statements: step on the BASIC thread first.";

    // Array and chunk references handed out since the last stop, and each listed variable's BASIC name.
    private readonly Dictionary<int, Func<List<JsonNode?>>> _basicChildren = [];
    private readonly Dictionary<(int Reference, string Name), string> _basicNames = [];
    private readonly List<(BreakpointState State, string Expression)> _basicWatches = [];
    private readonly Dictionary<BreakpointState, string> _basicWatchValues = [];

    private BasicVariables BasicVariablesNow => new(Basic, new TargetBasicMemory(Target));

    private BasicEvaluator Evaluator => new(Basic, new TargetBasicMemory(Target), DefinedFunction);

    // A BASIC frame's scopes: the same for every frame, since BASIC's variables are global.
    private JsonObject BasicScopes()
    {
        if (ActiveBasic is null) { return new JsonObject { ["scopes"] = new JsonArray() }; }
        List<JsonNode?> scopes =
        [
            new JsonObject
            {
                ["name"] = "Variables",
                ["variablesReference"] = BasicVariablesScope,
                ["expensive"] = false
            },
            new JsonObject { ["name"] = "Arrays", ["variablesReference"] = BasicArraysScope, ["expensive"] = false }
        ];

        if (Basic.Name == BasicDialect.AppleSoft.Name)
        {
            scopes.Add(new JsonObject
            {
                ["name"] = "Functions",
                ["variablesReference"] = BasicFunctionsScope,
                ["expensive"] = false
            });
        }

        scopes.Add(new JsonObject
        {
            ["name"] = "Loops",
            ["variablesReference"] = BasicLoopsScope,
            ["expensive"] = false
        });

        scopes.Add(new JsonObject
        {
            ["name"] = "Program",
            ["variablesReference"] = BasicProgramScope,
            ["expensive"] = false
        });

        return new JsonObject { ["scopes"] = scopes.ToJsonArray() };
    }

    // Clears the references a stop's Variables view used.
    private void ForgetBasicReferences()
    {
        _basicChildren.Clear();
        _basicNames.Clear();
    }

    private JsonObject BasicVariablesOf(int reference)
    {
        List<JsonNode?> variables = reference switch
        {
            BasicVariablesScope => SimpleVariables(),
            BasicArraysScope => ArrayVariables(),
            BasicFunctionsScope => FunctionVariables(),
            BasicLoopsScope => LoopVariables(),
            BasicProgramScope => ProgramVariables(),
            _ => _basicChildren.TryGetValue(reference, out Func<List<JsonNode?>>? children) ? children() : []
        };

        return new JsonObject { ["variables"] = variables.ToJsonArray() };
    }

    private List<JsonNode?> SimpleVariables()
    {
        BasicVariables variables = BasicVariablesNow;
        List<JsonNode?> list = [];
        foreach (BasicVariable variable in variables.Simple().Where(variable => variable.Kind != BasicVariableKind.Function))
        {
            string value = Show(variables, variable.Kind, variable.ValueAddress);
            list.Add(Item(BasicVariablesScope, variable.Name, variable.Name, value, Type(variable.Kind)));
        }

        return list;
    }

    private List<JsonNode?> ArrayVariables()
    {
        BasicVariables variables = BasicVariablesNow;
        List<JsonNode?> list = [];
        foreach (BasicArray array in variables.Arrays())
        {
            int reference = BasicChildren + _basicChildren.Count;
            _basicChildren[reference] = () => Elements(array, 0, array.Count, reference);
            string bounds = string.Join(",", array.Dimensions.Select(size => size - 1));
            list.Add(new JsonObject
            {
                ["name"] = array.Name,
                ["value"] = $"{array.Name}({bounds}): {array.Count} elements",
                ["type"] = $"{Type(array.Kind)} array",
                ["variablesReference"] = reference
            });
        }

        return list;
    }

    // An array's elements, or groups of a hundred for a larger one.
    private List<JsonNode?> Elements(BasicArray array, int first, int end, int reference)
    {
        List<JsonNode?> list = [];
        if (end - first > ChunkSize)
        {
            for (int start = first; start < end; start += ChunkSize)
            {
                int stop = Math.Min(start + ChunkSize, end);
                int chunk = BasicChildren + _basicChildren.Count;
                int from = start;
                _basicChildren[chunk] = () => Elements(array, from, stop, chunk);
                list.Add(new JsonObject
                {
                    ["name"] = $"[{start}..{stop - 1}]",
                    ["value"] = "",
                    ["variablesReference"] = chunk
                });
            }

            return list;
        }

        BasicVariables variables = BasicVariablesNow;
        for (int index = first; index < end; index++)
        {
            int[] subscripts = array.Subscripts(index);
            string name = $"{array.Name}({string.Join(",", subscripts)})";
            string value = Show(variables, array.Kind, array.ElementAddress(subscripts));
            list.Add(Item(reference, $"({string.Join(",", subscripts)})", name, value, Type(array.Kind)));
        }

        return list;
    }

    private List<JsonNode?> FunctionVariables()
    {
        List<JsonNode?> list = [];
        foreach (BasicVariable function in BasicVariablesNow.Simple().Where(variable => variable.Kind == BasicVariableKind.Function))
        {
            string value = DefinedFunction(function.Name) is { } definition
                ? $"FN {function.Name}({definition.Parameter}) = {definition.Body}"
                : "defined";

            list.Add(new JsonObject
            {
                ["name"] = $"FN {function.Name}",
                ["value"] = value,
                ["variablesReference"] = 0
            });
        }

        return list;
    }

    private List<JsonNode?> LoopVariables()
    {
        BasicVariables variables = BasicVariablesNow;
        IReadOnlyList<BasicVariable> simple = variables.Simple();
        BasicEvaluator evaluator = Evaluator;
        List<JsonNode?> list = [];
        foreach (BasicLoop loop in variables.Loops(BasicStackTop, Target.BasicForSize, Target.BasicGosubSize))
        {
            BasicVariable? variable = simple.FirstOrDefault(found => found.ValueAddress == loop.VariableAddress);
            string name = variable?.Name ?? $"${loop.VariableAddress:X4}";
            string now = variable is null ? "?" : Show(variables, variable.Kind, variable.ValueAddress);
            string limit = evaluator.Format(new(new(loop.Limit)));
            string step = evaluator.Format(new(new(loop.Step)));
            string value = $"{now} TO {limit} STEP {step} (FOR in line {loop.Line})";
            list.Add(new JsonObject { ["name"] = name, ["value"] = value, ["variablesReference"] = 0 });
        }

        return list;
    }

    private List<JsonNode?> ProgramVariables()
    {
        string line = BasicDirect ? "direct mode" : CurrentLine.ToString(CultureInfo.InvariantCulture);
        string Span(int from, int to) => $"${from:X4}-${Math.Max(from, to - 1):X4} ({Math.Max(0, to - from)} bytes)";
        if (Basic == BasicDialect.Integer)
        {
            // Integer BASIC's variables grow up from LOMEM to PV, and its program down from HIMEM to PP.
            int lomem = Word(IntegerBasicDialect.LoMem);
            int pv = Word(IntegerBasicDialect.Pv);
            int pp = Word(IntegerBasicDialect.Pp);
            int himem = Word(IntegerBasicDialect.HiMem);
            return
            [
                new JsonObject { ["name"] = "Variables", ["value"] = Span(lomem, pv), ["variablesReference"] = 0 },
                new JsonObject { ["name"] = "Free", ["value"] = Span(pv, pp), ["variablesReference"] = 0 },
                new JsonObject { ["name"] = "Program", ["value"] = Span(pp, himem), ["variablesReference"] = 0 },
                new JsonObject { ["name"] = "Current line", ["value"] = line, ["variablesReference"] = 0 }
            ];
        }

        BasicPointers pointers = Basic.Pointers;
        int start = Word(pointers.ProgramStart);
        int variables = Word(pointers.Variables);
        int arrays = Word(pointers.Arrays);
        int free = Word(pointers.FreeStart);
        int strings = Word(pointers.StringBottom);
        int top = Word(pointers.MemoryTop);
        return
        [
            new JsonObject { ["name"] = "Program", ["value"] = Span(start, variables), ["variablesReference"] = 0 },
            new JsonObject { ["name"] = "Variables", ["value"] = Span(variables, arrays), ["variablesReference"] = 0 },
            new JsonObject { ["name"] = "Arrays", ["value"] = Span(arrays, free), ["variablesReference"] = 0 },
            new JsonObject { ["name"] = "Free", ["value"] = Span(free, strings), ["variablesReference"] = 0 },
            new JsonObject { ["name"] = "Strings", ["value"] = Span(strings, top), ["variablesReference"] = 0 },
            new JsonObject { ["name"] = "Current line", ["value"] = line, ["variablesReference"] = 0 },
            new JsonObject
            {
                ["name"] = "Next DATA",
                ["value"] = $"${Word(pointers.DataPointer) + 1:X4}",
                ["variablesReference"] = 0
            }
        ];
    }

    // A Variables view entry for a BASIC value, remembering the BASIC name that sets or watches it.
    private JsonObject Item(int reference, string name, string expression, string value, string type)
    {
        _basicNames[(reference, name)] = expression;
        return new JsonObject
        {
            ["name"] = name,
            ["value"] = value,
            ["type"] = type,
            ["evaluateName"] = expression,
            ["variablesReference"] = 0
        };
    }

    private string Show(BasicVariables variables, BasicVariableKind kind, int address) =>
        Evaluator.Format(new(variables.Read(kind, address), kind == BasicVariableKind.Double));

    private static string Type(BasicVariableKind kind) => kind switch
    {
        BasicVariableKind.Integer => "integer",
        BasicVariableKind.String => "string",
        BasicVariableKind.Single => "single",
        BasicVariableKind.Double => "double",
        _ => "real"
    };

    // Evaluates a BASIC expression for a watch, a hover or the console.
    private JsonObject EvaluateBasic(string expression)
    {
        BasicEvaluator evaluator = Evaluator;
        BasicResult result = evaluator.Evaluate(expression);
        return new JsonObject
        {
            ["result"] = evaluator.Format(result),
            ["type"] = result.Value.IsString ? "string" : "number",
            ["variablesReference"] = 0
        };
    }

    // A DEF FN function's parameter and body, from its DEF in the program.
    private (string Parameter, string Body)? DefinedFunction(string name)
    {
        if (View() is not { } view) { return null; }
        foreach (BasicSourceLine line in view.Source.NumberedLines)
        {
            for (int statement = 0; statement < line.Statements.Count; statement++)
            {
                Match match = Definition().Match(view.Text(line, statement));
                if (match.Success && string.Equals(match.Groups["name"].Value, name, StringComparison.OrdinalIgnoreCase))
                {
                    return (match.Groups["parameter"].Value, match.Groups["body"].Value.Trim());
                }
            }
        }

        return null;
    }

    // Sets a BASIC variable or array element from a BASIC expression: setExpression, and setVariable by name.
    private JsonObject SetBasic(string target, string value)
    {
        Match match = Assignable().Match(target);
        if (!match.Success) { throw new ArgumentException($"'{target}' is not a BASIC variable or array element."); }
        BasicEvaluator evaluator = Evaluator;
        BasicResult result = evaluator.Evaluate(value);
        BasicVariables variables = BasicVariablesNow;
        string name = match.Groups["name"].Value;
        BasicVariableKind kind;
        int address;
        if (match.Groups["subscripts"].Success)
        {
            BasicArray array = variables.FindArray(name)
                ?? throw new InvalidOperationException($"BASIC has no array {name} yet; DIM it first.");

            string[] texts = match.Groups["subscripts"].Value.Split(',');
            int[] subscripts = [.. texts.Select(text => (int)Math.Truncate(evaluator.Evaluate(text).Value.Number))];
            (kind, address) = (array.Kind, array.ElementAddress(subscripts));
        }
        else
        {
            BasicVariable? variable = variables.Find(name);
            if (variable is null)
            {
                bool between = BasicDirect
                    || (ActiveBasic is not null
                        && Target.IsInstructionBoundary
                        && Target.BasicStatementStart(Target.ProgramCounter) is not null);

                if (!between) { throw new InvalidOperationException(NewVariableBetween); }
                variable = variables.Create(name);
            }

            (kind, address) = (variable.Kind, variable.ValueAddress);
        }

        variables.Write(kind, address, result.Value);
        NotifyMemory();
        Notify("invalidated", new JsonObject { ["areas"] = new JsonArray("variables") });
        return new JsonObject
        {
            ["value"] = Show(variables, kind, address),
            ["type"] = Type(kind),
            ["variablesReference"] = 0
        };
    }

    // Sets a value in a BASIC scope.
    private JsonObject SetBasicVariable(int reference, string name, string value) =>
        _basicNames.TryGetValue((reference, name), out string? expression)
            ? SetBasic(expression, value)
            : throw new ArgumentException($"{name} cannot be set.");

    // The data breakpoint id for a BASIC variable or element, from the Variables view or a watch.
    private JsonObject? BasicDataBreakpointInfo(int reference, string name)
    {
        string? expression = reference != 0 ? _basicNames.GetValueOrDefault((reference, name)) : name;
        if (expression is null || !Assignable().IsMatch(expression)) { return null; }
        return new JsonObject
        {
            ["dataId"] = BasicDataPrefix + expression.ToUpperInvariant(),
            ["description"] = $"{expression} (BASIC)",
            ["accessTypes"] = new JsonArray("write"),
            ["canPersist"] = true
        };
    }

    // Adds a data breakpoint on a BASIC variable, which the run checks as each statement starts.
    private void WatchBasic(BreakpointState state, string id)
    {
        string expression = id[BasicDataPrefix.Length..];
        state.Location = $"BASIC {expression} changes";
        _basicWatches.Add((state, expression));
        _basicWatchValues[state] = WatchValue(expression);
    }

    private string WatchValue(string expression)
    {
        if (_target is null || Target.Basic is null) { return ""; }
        try
        {
            return Evaluator.Format(Evaluator.Evaluate(expression));
        }
        catch (FormatException exception)
        {
            return exception.Message;
        }
    }

    // The watched variables that changed in the statement that just ran, as a stop.
    private bool BasicWatchStops()
    {
        List<int> ids = [];
        string? description = null;
        foreach ((BreakpointState state, string expression) in _basicWatches)
        {
            string now = WatchValue(expression);
            string before = _basicWatchValues.GetValueOrDefault(state, "");
            if (now == before) { continue; }
            _basicWatchValues[state] = now;
            state.Hits++;
            if (state.HitTest is { } test && !test.Matches(state.Hits)) { continue; }
            ids.Add(state.Id);
            description ??= $"{expression} changed from {before} to {now}.";
        }

        if (ids.Count == 0) { return false; }
        Stopped("data breakpoint", [.. ids], description, threadId: BasicThread);
        return true;
    }

    // Whether a BASIC breakpoint counts this hit: its condition holds, as a BASIC expression, and its hit count says
    // to stop; a logpoint writes its message, with {expression} as BASIC values, and does not stop.
    private bool BasicTriggers(BreakpointState state, out string? error)
    {
        error = null;
        if (state.Condition is { } condition)
        {
            try
            {
                if (!BasicEvaluator.IsTrue(Evaluator.Evaluate(condition))) { return false; }
            }
            catch (FormatException exception)
            {
                error = $"The breakpoint condition '{condition}' failed: {exception.Message}";
                state.Hits++;
                return true;
            }
        }

        state.Hits++;
        if (state.HitTest is { } test && !test.Matches(state.Hits)) { return false; }
        if (state.LogMessage is not { } message) { return true; }
        JsonObject output = new JsonObject { ["category"] = "console", ["output"] = $"{BasicInterpolate(message)}\n" };
        if (state.Line is { } line)
        {
            output["source"] = new JsonObject
            {
                ["name"] = line.Path[(line.Path.LastIndexOf('/') + 1)..],
                ["path"] = line.Path
            };

            output["line"] = line.Line;
        }

        Log(output);
        return false;
    }

    // Fills a BASIC logpoint's {expression} placeholders: strings as their text, numbers as PRINT writes them.
    private string BasicInterpolate(string message)
    {
        using ValueStringBuilder text = new(stackalloc char[256]);
        BasicEvaluator evaluator = Evaluator;
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

            string expression = message[(index + 1)..end];
            try
            {
                BasicResult result = evaluator.Evaluate(expression);
                text.Append(result.Value.Text is { } bytes ? Encoding.ASCII.GetString(bytes) : evaluator.Format(result));
            }
            catch (FormatException exception)
            {
                text.Append($"<{exception.Message}>");
            }

            index = end;
        }

        return text.ToString();
    }

    [GeneratedRegex(@"^\s*DEF\s*FN\s*(?<name>[A-Z][A-Z0-9]*)\s*\(\s*(?<parameter>[A-Z][A-Z0-9]*)\s*\)\s*=(?<body>.*)$", RegexOptions.IgnoreCase)]
    private static partial Regex Definition();

    [GeneratedRegex(@"^\s*(?<name>[A-Za-z][A-Za-z0-9]*[$%!#]?)\s*(\((?<subscripts>[^()]*)\))?\s*$")]
    private static partial Regex Assignable();
}
