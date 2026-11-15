// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    // The calls of intrinsic units no library at hand declares, such as Apple III Pascal's system's own in
    // SYSTEM.PASCAL, whose code files keep no interface text; and the units declared from them.
    private readonly List<UnitCall> _unitCalls = [];
    private readonly SortedDictionary<int, PascalUnit> _inferredUnits = [];
    private readonly HashSet<PascalUnitProcedure> _inferredProcedures = [];

    // The set types the inferred units' parameters take, by their names, with their words.
    private readonly SortedDictionary<string, int> _unitSets = new(StringComparer.Ordinal);

    // The words of inferred units' data segments the code reaches, by segment, which their interfaces declare.
    private readonly SortedDictionary<int, Frame> _unitData = [];

    private Variable UnitVariable(int segment, int offset)
    {
        if (!_unitData.TryGetValue(segment, out Frame? frame))
        {
            frame = new Frame(owner: null, level: 0, parameterWords: 0, dataWords: 0);
            _unitData[segment] = frame;
        }

        bool known = frame.Variables.ContainsKey(offset);
        Variable variable = frame.At(offset);
        if (!known)
        {
            variable.Kind = VariableKind.Variable;
            variable.Name = $"U{segment}V{offset}";
        }

        return variable;
    }

    // Whether the code file says the program uses an intrinsic unit of a segment.
    private bool IsIntrinsic(int segment) => segment is >= 0 and < 64 && (_file.IntrinsicUnits & (1UL << segment)) != 0;

    // The unit of a segment: the library's, or one declared from its calls.
    private PascalUnit? UnitOf(int segment) => _library?.Unit(segment) ?? _inferredUnits.GetValueOrDefault(segment);

    // How many arguments the first call of an inferred unit's procedure passed, or null before its first.
    private int? UnitArguments(int segment, int number) =>
        _unitCalls.FirstOrDefault(call => call.Callee.Segment == segment && call.Callee.Number == number)?.Arguments.Count;

    // Declares each inferred unit's procedures, from 2 to the last called, from what their calls pass: a string
    // constant's parameter is a value string; an address's an untyped VAR, as only an assembled procedure's can be,
    // which takes any variable; a set's a set of its words; two words a real; and one an integer. A procedure no call
    // reaches takes nothing. Runs once the VAR parameters are known, which pass addresses on.
    private void SignUnits()
    {
        foreach (IGrouping<int, UnitCall> calls in _unitCalls.GroupBy(call => call.Callee.Segment).OrderBy(group => group.Key))
        {
            int segment = calls.Key;
            int last = calls.Max(call => call.Callee.Number);
            List<PascalUnitProcedure> procedures = [];
            for (int number = 2; number <= last; number++)
            {
                List<UnitCall> sites = [.. calls.Where(call => call.Callee.Number == number)];
                bool function = sites.Any(call => call.IsFunction);
                int count = sites.Count == 0 ? 0 : sites.Max(call => call.Arguments.Count);
                List<PascalUnitParameter> parameters = [];
                for (int index = 0; index < count; index++)
                {
                    List<Expr> passed = [.. sites.Where(call => index < call.Arguments.Count).Select(call => call.Arguments[index])];
                    parameters.Add(Parameter(segment, index, passed));
                }

                string name = $"U{segment}{(function ? 'F' : 'P')}{number}";
                PascalUnitProcedure procedure = new(name, function, parameters, function ? "INTEGER" : null);
                procedures.Add(procedure);
                _inferredProcedures.Add(procedure);
            }

            PascalUnit unit = new($"UNIT{segment}", segment, procedures, new Dictionary<string, IReadOnlyList<string>>());
            _inferredUnits[segment] = unit;
            foreach (UnitCall call in calls)
            {
                call.Callee.Unit = unit;
                call.Callee.UnitProcedure = unit.Procedure(call.Callee.Number);
            }
        }
    }

    private PascalUnitParameter Parameter(int segment, int index, List<Expr> passed)
    {
        string name = $"A{index + 1}";
        if (passed.Any(argument => argument is StringConstant or StringFunction))
        {
            return new(name, IsReference: false, "STRING");
        }

        if (passed.Any(IsAddress)) { return new(name, IsReference: true, Type: null); }
        if (passed.OfType<SetValue>().FirstOrDefault() is { } set)
        {
            string type = $"U{segment}S{set.Words}";
            _unitSets[type] = set.Words;
            return new(name, IsReference: false, type);
        }

        return new(name, IsReference: false, passed.Any(argument => argument.Words == 2) ? "REAL" : "INTEGER");
    }

    // Each inferred unit's source: an intrinsic unit whose interface declares the procedures as their calls show them,
    // and whose implementation has them EXTERNAL, as it has no code here; it is compiled for its interface, which the
    // program's USES reads, and never linked.
    private List<PascalDecompiledUnit> WriteInferredUnits()
    {
        List<PascalDecompiledUnit> units = [];
        foreach ((int segment, PascalUnit unit) in _inferredUnits)
        {
            List<string> lines =
            [
                $"UNIT {unit.Name};",
                $"INTRINSIC CODE {segment}{(IsIntrinsic(segment + 1) ? $" DATA {segment + 1}" : "")};",
                "INTERFACE"
            ];

            List<KeyValuePair<string, int>> sets = [.. _unitSets.Where(set => set.Key.StartsWith($"U{segment}S", StringComparison.Ordinal))];
            if (sets.Count > 0)
            {
                lines.Add("  TYPE");
                lines.AddRange(sets.Select(set => $"    {set.Key} = SET OF 0..{(set.Value * 16) - 1};"));
            }

            lines.AddRange(UnitVariables(segment + 1));
            lines.AddRange(unit.Procedures.Select(procedure => $"  {UnitHeader(procedure)};"));
            lines.Add("IMPLEMENTATION");
            lines.AddRange(unit.Procedures.Select(procedure => $"  {(procedure.IsFunction ? "FUNCTION" : "PROCEDURE")} {procedure.Name}; EXTERNAL;"));
            lines.Add("END.");
            string source = string.Join('\n', lines) + "\n";
            units.Add(new PascalDecompiledUnit(unit.Name, segment, source) { Intrinsic = true });
        }

        return units;
    }

    // The interface's variables, in the data segment's words from 1: each the code reaches, a string as long as the
    // words to the next, and padding for the words between; a word of padding when the code reaches none.
    private List<string> UnitVariables(int segment)
    {
        List<string> lines = [];
        if (!_unitData.TryGetValue(segment, out Frame? frame) || frame.Variables.Count == 0)
        {
            // A unit with a data segment declares a variable, or the Compiler takes its DATA for an error.
            if (IsIntrinsic(segment)) { lines.AddRange(["  VAR", $"    U{segment}X1: INTEGER;"]); }
            return lines;
        }

        lines.Add("  VAR");
        List<Variable> variables = [.. frame.Variables.Values.OrderBy(variable => variable.Offset)];
        int offset = 1;
        for (int index = 0; index < variables.Count; index++)
        {
            Variable variable = variables[index];
            if (variable.Offset > offset)
            {
                lines.Add($"    U{segment}X{offset}: {Padding(variable.Offset - offset)};");
            }

            int? next = index + 1 < variables.Count ? variables[index + 1].Offset : null;
            TypeNode type = variable.Type.Find();
            int words = 1;
            string name = type.ScalarKind switch
            {
                ScalarKind.Boolean => "BOOLEAN",
                ScalarKind.Char => "CHAR",
                _ => "INTEGER"
            };

            if (type.Kind == TypeKind.String)
            {
                words = next is { } end ? end - variable.Offset : (Math.Max(type.MaxLength, 80) + 2) / 2;
                name = $"STRING[{(words * 2) - 2}]";
            }
            else if (type.Kind is not TypeKind.Scalar)
            {
                Warn($"The unit variable {variable.Name} is not a string or a scalar; it is declared an integer.");
            }

            lines.Add($"    {variable.Name}: {name};");
            offset = variable.Offset + words;
        }

        return lines;

        static string Padding(int words) => words == 1 ? "INTEGER" : $"ARRAY[1..{words}] OF INTEGER";
    }

    private static string UnitHeader(PascalUnitProcedure procedure)
    {
        string parameters = procedure.Parameters.Count == 0
            ? ""
            : $"({string.Join("; ", procedure.Parameters.Select(parameter => parameter.IsReference ? $"VAR {parameter.Name}{(parameter.Type is null ? "" : $": {parameter.Type}")}" : $"{parameter.Name}: {parameter.Type}"))})";

        return procedure.IsFunction
            ? $"FUNCTION {procedure.Name}{parameters}: {procedure.Result}"
            : $"PROCEDURE {procedure.Name}{parameters}";
    }
}
