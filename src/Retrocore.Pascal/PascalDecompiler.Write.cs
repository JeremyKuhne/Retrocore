// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text;

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    private StringBuilder _source = new();
    private readonly List<TypeNode> _types = [];
    private readonly SortedDictionary<int, string> _constants = [];
    private int _indent;
    private bool _ioChecked = true;
    private bool _rangeChecked = true;

    // The WITH statements the writer is inside, innermost last: their records' fields go by name alone.
    private readonly List<Variable> _with = [];

    // The number the Compiler gives the next segment procedure, in a (*$U-*) program, which numbers them in order.
    private int? _nextSegment;

    // The records of the WITH statements, by their temporaries.
    private readonly Dictionary<Variable, Designator> _withRecords = [];

    // The units of the program's own, written by Write after the program.
    private List<PascalDecompiledUnit> _unitSources = [];

    private string Write()
    {
        NamedFields();
        NameTypes();
        Prefixes();

        Options([.. _procedures.Where(procedure => !InUnit(procedure))]);

        // A (*$U-*) program is a segment procedure in the system's outer block, which declares the system's globals.
        if (_systemProgram)
        {
            Line("(*$U-*)  (* Compiled as part of the system: its globals are the system's, I/O and range checks off. *)");
            _ioChecked = false;
            _rangeChecked = false;
            Line($"PROGRAM {(_shell is null ? "PASCALSYSTEM" : Identifier(_shell.Name))};");
        }
        else
        {
            if (Comment(Program) is { } about) { Line(about); }
            Line($"PROGRAM {Program.Name};");
        }

        // The library's units, whose segments are their own; then the program's, by their code files, whose order in
        // USES numbers their segments from 7. The Compiler initializes a library's units in the reverse of their order.
        List<string> uses = [.. Enumerable.Reverse(_unitOrder).Select(segment => _library?.Unit(segment)?.UsesName ?? $"UNIT{segment}")];
        uses.AddRange(UnitSegments().Select(segment => $"(*$U {segment.Name.Trim()}.CODE*) {segment.Name.Trim()}"));
        if (_unitSegments.Count > 0)
        {
            Line("(* Each unit's interface is read from the code file its $U option names. *)");
        }

        if (uses.Count > 0) { Line($"USES {string.Join(", ", uses)};"); }

        if (!_systemProgram) { Labels(Program); }
        int constants = _source.Length;

        // The types the program's own declarations use, but those a unit's interface declares for it.
        HashSet<TypeNode> types = TypesOf(_procedures.Where(procedure => !InUnit(procedure)), variables: true, signatures: true);
        types.ExceptWith(InterfaceTypes());
        if (_systemProgram)
        {
            foreach (Variable global in _declared[_system]) { Reach(global.Type, types); }
        }

        foreach (TypeNode pointer in _plainPointers.Values) { Reach(pointer, types); }

        Types(types);

        if (_systemProgram)
        {
            Declarations(_system);
            SystemProcedures();
            SystemSegment();
        }
        else
        {
            Declarations(Program);
            Nested(Program);
            Line("BEGIN");
            Statements(Program, Program.Body);
            Line("END.");
        }

        Alignment([.. _procedures.Select(procedure => procedure.Segment).Where(segment => !_unitSegments.Contains(segment)).Distinct()]);

        // The constants the statements named, which come before the types.
        if (_constants.Count > 0)
        {
            _source.Insert(
                constants,
                $"CONST\n{string.Concat(_constants.Select(constant => $"  {constant.Value} = {constant.Key.ToString(CultureInfo.InvariantCulture)};\n"))}");
        }

        string program = _source.ToString();
        _unitSources = WriteUnits();
        return program;
    }

    // The options a source needs, each with what it does and why: GOTO, where its procedures have labels; and no
    // string length checks, where they call a procedure with a VAR string parameter, which a string of another length
    // may go to.
    private void Options(List<Procedure> procedures)
    {
        HashSet<Procedure> called = [];
        foreach (Procedure procedure in procedures)
        {
            Walk(procedure.Body, statement => Calls(statement is CallStatement call ? call.Callee : null), expression => Calls(expression is Call call ? call.Callee : null));
        }

        void Calls(Callee? callee)
        {
            if (callee?.Procedure is { } target) { called.Add(target); }
        }

        if (called.Any(procedure => _parameters[procedure].Any(IsStringReference)))
        {
            Line("(*$V-*)  (* No string length checks: a string goes to a VAR string of another length. *)");
        }

        if (procedures.Any(procedure => procedure.Labels.Count > 0))
        {
            Line("(*$G+*)  (* GOTO allowed: the code jumps to labels. *)");
        }

    }

    private static bool IsStringReference(Variable parameter) =>
        parameter.IsReference && parameter.Type.Target().Find().Kind == TypeKind.String;

    // A (*$U-*) program's segment procedure, segment 1, then the system's outer block, empty. The Compiler numbers
    // its segment procedures on from 2, so the first of Apple's, 7, needs (*$NS 7*).
    private void SystemSegment()
    {
        if (Main.Number != 1)
        {
            Warn($"The program's segment is {Main.Number}, not 1, as the system's user program is.");
        }

        if (Comment(Program) is { } about) { Line(about); }
        Line($"SEGMENT PROCEDURE {Program.Name}{ParameterList(Program)};");
        _nextSegment = 2;

        _indent++;
        Labels(Program);
        Declarations(Program);
        Nested(Program);
        _indent--;
        Line("BEGIN");
        Statements(Program, Program.Body);
        Line("END;");
        Line("BEGIN");
        Line("END.");
    }

    // The byte the Compiler skips to put an LDC's or XJP's words on a word boundary holds whatever its buffer had there,
    // which no source says; those that are not 0 are written after END., where the Compiler reads nothing, for
    // --pascal compile to put back.
    private void Alignment(List<Media.PascalSegment> only)
    {
        IEnumerable<IGrouping<Media.PascalSegment, Procedure>> segments = _procedures
            .Where(procedure => !procedure.Code.IsNative && !procedure.Failed && only.Contains(procedure.Segment))
            .GroupBy(procedure => procedure.Segment);

        foreach (IGrouping<Media.PascalSegment, Procedure> segment in segments)
        {
            byte[] code = segment.Key.Code;
            List<string> pads = [];
            foreach (PcodeInstruction instruction in segment.SelectMany(procedure => procedure.Instructions).OrderBy(instruction => instruction.Offset))
            {
                int at = Pad(instruction);
                if (at > 0 && (at & 1) != 0 && at < code.Length && code[at] != 0)
                {
                    pads.Add($"${at:X4}=${code[at]:X2}");
                }
            }

            if (pads.Count > 0) { Line($"(* Alignment bytes {segment.Key.Name.Trim()} {string.Join(" ", pads)} *)"); }
        }
    }

    // Where an LDC's or XJP's alignment byte would be: after LDC's count, and after XJP; -1 for others.
    private static int Pad(PcodeInstruction instruction) => instruction.Opcode.Code switch
    {
        Pcode.Ldc => instruction.Offset + 2,
        Pcode.Xjp => instruction.Offset + 1,
        _ => -1
    };

    private void Line(string text)
    {
        _source.Append(' ', _indent * 2);
        _source.Append(text);
        _source.Append('\n');
    }

    private void Labels(Procedure procedure)
    {
        if (procedure.Labels.Count > 0) { Line($"LABEL {string.Join(", ", procedure.Labels.Values)};"); }
    }

    private void Declarations(Procedure procedure) => Declarations(procedure.Frame);

    private void Declarations(Frame frame)
    {
        List<Variable> variables = _declared[frame];
        if (variables.Count == 0) { return; }

        Line("VAR");
        _indent++;
        for (int index = 0; index < variables.Count; index++)
        {
            Variable variable = variables[index];
            string type = TypeName(variable.Type, parameter: false);

            // The Compiler opens files in the reverse of their order in the source, but gives a list's last the
            // lowest offset: files opened in the order of their offsets were declared in one list.
            List<Variable> list = [variable];
            while (variable.Opened > 0
                && index + list.Count < variables.Count
                && variables[index + list.Count] is { } next
                && next.Opened == list[^1].Opened + 1
                && TypeName(next.Type, parameter: false) == type)
            {
                list.Add(next);
            }

            Line($"{string.Join(", ", Enumerable.Reverse(list).Select(item => item.Name))}: {type};");
            index += list.Count - 1;
        }

        _indent--;
    }

    // A procedure's nested procedures, in the order of their code; one numbered before another whose code comes first
    // is declared FORWARD before it, or, assembled, EXTERNAL there, as it has no code the Compiler places.
    private void Nested(Procedure parent)
    {
        // A unit's procedures are in its own source.
        List<Procedure> children = [.. parent.Children.Where(child => !InUnit(child))];
        List<Procedure> segments = [.. children.Where(child => child.IsSegmentProcedure).OrderBy(child => child.Segment.Number)];
        List<Procedure> ordinary = [.. children.Where(child => !child.IsSegmentProcedure)];

        // A segment procedure comes before the ordinary procedures, so those it calls (CXP 1, n) are declared FORWARD
        // first, with every one numbered before them.
        HashSet<Procedure> declared = [];
        int called = segments.Count == 0 ? 0 : ordinary.Where(child => segments.Any(segment => Reaches(segment, child))).Select(child => child.Number).DefaultIfEmpty(0).Max();
        foreach (Procedure earlier in ordinary.Where(child => child.Number <= called).OrderBy(child => child.Number))
        {
            if (earlier.Code.IsNative) { WriteProcedure(earlier, forwarded: false); }
            else { Line($"{Header(earlier, full: true)} FORWARD;"); }

            declared.Add(earlier);
        }

        foreach (Procedure segment in segments)
        {
            // A segment the Compiler would number otherwise is numbered with NS, the next segment's number.
            if (_nextSegment is { } next && segment.Segment.Number != next)
            {
                Line($"(*$NS {segment.Segment.Number}*)  (* The next segment is numbered {segment.Segment.Number}. *)");
            }

            if (_nextSegment is not null) { _nextSegment = segment.Segment.Number + 1; }
            WriteProcedure(segment, forwarded: false);
        }

        Ordinary(ordinary, declared);
    }

    // Procedures in the order of their code, with those already declared (a unit's interface) by name alone.
    private void Ordinary(List<Procedure> ordinary, HashSet<Procedure> declared)
    {
        foreach (Procedure child in ordinary.OrderBy(child => child.Code.Attributes))
        {
            if (child.Code.IsNative && declared.Contains(child)) { continue; }

            // The Compiler numbers a procedure at its first heading: those numbered before the child, or before one
            // nested in it, are declared first.
            int numbered = Descendants(child).Select(nested => nested.Number).DefaultIfEmpty(child.Number).Max();
            numbered = Math.Max(numbered, child.Number);
            List<Procedure> earlier = [.. ordinary.Where(other => other.Number < numbered && other != child && !declared.Contains(other))];
            if (earlier.Any(other => other.Number > child.Number) && !declared.Contains(child)) { earlier.Add(child); }

            foreach (Procedure heading in earlier.OrderBy(other => other.Number))
            {
                if (heading.Code.IsNative) { WriteProcedure(heading, forwarded: false); }
                else { Line($"{Header(heading, full: true)} FORWARD;"); }

                declared.Add(heading);
            }

            WriteProcedure(child, declared.Contains(child));
            declared.Add(child);
        }
    }

    // The procedures nested in one, in its segment, and those nested in them.
    private static IEnumerable<Procedure> Descendants(Procedure procedure) =>
        procedure.Children
            .Where(child => !child.IsSegmentProcedure)
            .SelectMany(child => (IEnumerable<Procedure>)[child, .. Descendants(child)]);

    // Whether a procedure, or one nested in it, calls another.
    private static bool Reaches(Procedure caller, Procedure callee)
    {
        bool found = false;
        Walk(caller.Body, statement => found |= statement is CallStatement call && call.Callee.Procedure == callee,
            expression => found |= expression is Call call && call.Callee.Procedure == callee);

        return found || caller.Children.Any(child => Reaches(child, callee));
    }

    private void WriteProcedure(Procedure procedure, bool forwarded)
    {
        if (Comment(procedure) is { } about) { Line(about); }
        Line(Header(procedure, full: !forwarded));
        if (procedure.Code.IsNative)
        {
            Line("  EXTERNAL;");
            return;
        }

        _indent++;
        Labels(procedure);
        Declarations(procedure);
        Nested(procedure);
        _indent--;
        IEnumerable<string> resident = procedure.Resident.Select(number => ResidentName(procedure, number));
        Line(procedure.Resident.Count == 0 ? "BEGIN" : $"BEGIN (*$R {string.Join(",", resident)}*)");
        Statements(procedure, procedure.Body);
        Line("END;");
    }

    // The system's procedures the code calls that no standard procedure names, by their numbers, with the
    // arguments of a call to each.
    private readonly SortedDictionary<int, List<Argument>> _systemProcedures = [];

    private static string SystemProcedure(int number) => $"SYSTEM{number}";

    // A heading for each of the system's procedures up to the last the code calls that no standard procedure names,
    // in the system's block: the Compiler numbers them as the system does. Those the code calls take parameters as
    // their arguments are: a VAR one for an address, a value otherwise.
    private void SystemProcedures()
    {
        if (_systemProcedures.Count == 0) { return; }

        Line("(* The system's procedures, by number: the code calls those with parameters. *)");
        for (int number = 2; number <= _systemProcedures.Keys.Max(); number++)
        {
            string list = "";
            if (_systemProcedures.TryGetValue(number, out List<Argument>? arguments) && arguments.Count > 0)
            {
                list = $"({string.Join("; ", arguments.Select(SystemParameter))})";
            }

            Line($"PROCEDURE {SystemProcedure(number)}{list}; FORWARD;");
        }
    }

    private string SystemParameter(Argument argument, int index) => argument.Value switch
    {
        Address { Designator: var designator } => $"VAR A{index + 1}: {TypeName(designator.Type, parameter: true)}",
        var value => $"A{index + 1}: {Simple(value.Type.Find()) ?? "INTEGER"}"
    };

    // The string a designator of a length is of: its byte 0.
    private static Designator? LengthOf(Designator designator) => designator switch
    {
        LengthDesignator length => length.Text,
        IndexDesignator { Index: Constant { Value: 0 }, High: null } index
            when index.Array.Type.Find().Kind == TypeKind.String => index.Array,
        _ => null
    };

    // A segment the R option names: by its segment procedure's name, where the procedure sees it, declared in it or
    // in a block around it before it; otherwise by its number, which the option takes too.
    private string ResidentName(Procedure procedure, int number)
    {
        Procedure? segment = _procedures.FirstOrDefault(Loads);
        string numbered = number.ToString(CultureInfo.InvariantCulture);
        if (segment?.Parent is not { } parent) { return numbered; }

        bool inside = parent == procedure;
        bool around = !procedure.IsSegmentProcedure && Ancestors(procedure).Contains(parent);
        return inside || around ? segment.Name : numbered;

        static IEnumerable<Procedure> Ancestors(Procedure procedure)
        {
            for (Procedure? current = procedure.Parent; current is not null; current = current.Parent)
            {
                yield return current;
            }
        }

        bool Loads(Procedure other) => other.Segment.Number == number && other.Number == 1 && other.IsSegmentProcedure;
    }

    private string Header(Procedure procedure, bool full)
    {
        string kind = procedure.IsFunction ? "FUNCTION" : "PROCEDURE";
        string segment = procedure.IsSegmentProcedure ? "SEGMENT " : "";
        if (!full) { return $"{segment}{kind} {procedure.Name};"; }

        string list = ParameterList(procedure);
        string result = !procedure.IsFunction ? "" : Plain(procedure.ResultType) ? ": INTEGER" : $": {TypeName(procedure.ResultType, parameter: true)}";
        return $"{segment}{kind} {procedure.Name}{list}{result};";
    }

    private string ParameterList(Procedure procedure)
    {
        List<Variable> parameters = _parameters[procedure];
        return parameters.Count == 0
            ? ""
            : $"({string.Join("; ", parameters.Select(parameter => $"{(parameter.IsReference ? "VAR " : "")}{parameter.Name}: {ParameterType(parameter)}"))})";
    }

    private string ParameterType(Variable parameter)
    {
        if (_plainParameters.Contains(parameter))
        {
            return TypeName(_plainPointers[Punned(parameter)], parameter: true);
        }

        if (parameter.Copy is { } copy) { return TypeName(copy.Type, parameter: true); }
        TypeNode formal = Narrowed(parameter) ?? (parameter.IsReference ? parameter.Type.Target() : parameter.Type);
        return TypeName(formal, parameter: true);
    }

    // Gives a name to each type a declaration cannot write in place: records, pointers, arrays, sets and files, and
    // any type a parameter has that is not a single word.
    // Value parameters whose words are used both ways, which are their pointers: a record, though of a word, is passed
    // by its address and copied, as the Compiler's pointers are not. Each pointer type, by the word's type.
    private readonly HashSet<Variable> _plainParameters = [];
    private readonly Dictionary<TypeNode, TypeNode> _plainPointers = [];

    private void PlainParameters()
    {
        // Each parameter whose word is used both ways, but a VAR one that is assigned.
        HashSet<Variable> assigned = [];
        List<(Expr Argument, Variable Formal)> passed = [];
        HashSet<Expr> arguments = [];
        foreach (Procedure procedure in _procedures)
        {
            Walk(
                procedure.Body,
                statement =>
                {
                    if (statement is Assignment assignment && Root(assignment.Target) is { } target)
                    {
                        assigned.Add(target);
                    }

                    if (statement is CallStatement { Callee.Procedure: { } callee } call)
                    {
                        Passed(callee, [.. call.Arguments.Select(argument => argument.Value)]);
                    }
                },
                expression =>
                {
                    if (expression is Call { Callee.Procedure: { } callee } call) { Passed(callee, call.Arguments); }
                });
        }

        HashSet<Variable> plain =
        [
            .. _parameters.Values
                .SelectMany(parameters => parameters)
                .Where(parameter => parameter.Copy is null && IsPunned(Punned(parameter)))
                .Where(parameter => !parameter.IsReference || !assigned.Contains(parameter))
        ];

        // Whose record a statement needs whole, by its address or as a block: but as a VAR argument to one that is
        // plain too.
        List<(Variable Variable, Variable? Formal)> wholes = [];
        foreach (Procedure procedure in _procedures)
        {
            Walk(
                procedure.Body,
                statement =>
                {
                    if (statement is Assignment { Block: true, Target: VariableDesignator { Variable: var target } })
                    {
                        wholes.Add((target, null));
                    }
                },
                expression =>
                {
                    if (expression is Address { Designator: VariableDesignator { Variable: var addressed } }
                        && !arguments.Contains(expression))
                    {
                        wholes.Add((addressed, null));
                    }
                });
        }

        foreach ((Expr argument, Variable formal) in passed)
        {
            if (Source(argument) is { } source) { wholes.Add((source, formal.IsReference ? formal : null)); }
        }

        bool changed = true;
        while (changed)
        {
            changed = false;
            foreach ((Variable variable, Variable? formal) in wholes)
            {
                if (plain.Contains(variable) && (formal is null || !plain.Contains(formal)))
                {
                    changed |= plain.Remove(variable);
                }
            }

            // A VAR one is passed what is used both ways too.
            foreach ((Expr argument, Variable formal) in passed)
            {
                if (formal.IsReference && plain.Contains(formal) && !Punnable(argument))
                {
                    changed |= plain.Remove(formal);
                }
            }
        }

        foreach (Variable parameter in plain)
        {
            TypeNode punned = Punned(parameter);
            if (!_plainPointers.ContainsKey(punned))
            {
                TypeNode pointer = TypeNode.Of(TypeKind.Pointer);
                pointer.Element = punned.Element ?? new TypeNode();
                _plainPointers[punned] = pointer;
            }

            _plainParameters.Add(parameter);
        }

        void Passed(Procedure callee, IReadOnlyList<Expr> values)
        {
            if (!_parameters.ContainsKey(callee)) { return; }

            List<Variable> slots = Slots(callee, values);
            for (int index = 0; index < values.Count && index < slots.Count; index++)
            {
                if (values[index] is Address) { arguments.Add(values[index]); }
                if (values[index] is Address || slots[index].IsReference) { passed.Add((values[index], slots[index])); }
            }
        }

        // The parameter an argument passes the address of: its own, or a VAR one's on.
        static Variable? Source(Expr argument) => argument switch
        {
            Address { Designator: VariableDesignator { Variable: var variable } } => variable,
            Load { Designator: VariableDesignator { Variable: { IsReference: true } variable } } => variable,
            _ => null
        };

        bool Punnable(Expr argument) => argument switch
        {
            Address { Designator: var designator } => IsPunned(designator.Type),
            Load { Designator: VariableDesignator { Variable: { IsReference: true } variable } } =>
                IsPunned(Punned(variable)),
            _ => false
        };
    }

    // The VAR parameters of assembled procedures that calls pass both a record and its first field, as the Compiler's
    // tree search is passed an identifier or its name: each is its first field's type, which a record passes by its
    // first field. An assembled procedure has no body that needs the record.
    private readonly Dictionary<Variable, TypeNode> _narrowed = [];

    private TypeNode? Narrowed(Variable parameter) => _narrowed.GetValueOrDefault(parameter);

    // The type a parameter is declared with: its copy's, its narrowed one, a VAR one's target, or its own.
    private TypeNode Formal(Variable parameter) =>
        parameter.Copy?.Type ?? Narrowed(parameter) ?? (parameter.IsReference ? parameter.Type.Target() : parameter.Type);

    private void NarrowParameters()
    {
        foreach (Procedure procedure in _procedures)
        {
            Walk(
                procedure.Body,
                statement =>
                {
                    if (statement is CallStatement { Callee.Procedure: { } callee } call)
                    {
                        Narrow(callee, [.. call.Arguments.Select(argument => argument.Value)]);
                    }
                },
                expression =>
                {
                    if (expression is Call { Callee.Procedure: { } callee } call) { Narrow(callee, call.Arguments); }
                });
        }

        void Narrow(Procedure callee, IReadOnlyList<Expr> arguments)
        {
            if (!callee.Code.IsNative || !_parameters.ContainsKey(callee)) { return; }

            List<Variable> slots = Slots(callee, arguments);
            for (int index = 0; index < arguments.Count && index < slots.Count; index++)
            {
                Variable parameter = slots[index];
                if (!parameter.IsReference || parameter.Type.Target().Find() is not { Kind: TypeKind.Record } record)
                {
                    continue;
                }

                TypeNode passed = Designate(arguments[index]).Type.Find();
                if (passed != record && record.Fields?.GetValueOrDefault(0)?.Find() == passed)
                {
                    _narrowed[parameter] = passed;
                }
            }
        }
    }

    // A parameter's type, or a VAR one's target's.
    private static TypeNode Punned(Variable parameter) =>
        (parameter.IsReference ? parameter.Type.Target() : parameter.Type).Find();

    // The variable a designator is part of, a VAR parameter's for what it points to.
    private static Variable? Root(Designator designator) => designator switch
    {
        VariableDesignator { Variable: var variable } => variable,
        Dereference { Pointer: Load { Designator: VariableDesignator { Variable: { IsReference: true } variable } } } =>
            variable,
        FieldDesignator field => Root(field.Record),
        IndexDesignator index => Root(index.Array),
        _ => null
    };

    private void NameTypes()
    {
        PlainParameters();
        NarrowParameters();
        foreach (TypeNode pointer in _plainPointers.Values) { Visit(pointer, parameter: false); }

        if (_declared.TryGetValue(_system, out List<Variable>? globals))
        {
            foreach (Variable global in globals) { Visit(global.Type, parameter: false); }
        }

        foreach (Procedure procedure in _procedures)
        {
            foreach (Variable variable in _declared[procedure.Frame]) { Visit(variable.Type, parameter: false); }
            foreach (Variable parameter in _parameters[procedure])
            {
                Visit(Formal(parameter), parameter: true);
            }

            if (procedure.IsFunction) { Visit(procedure.ResultType, parameter: true); }
        }

        // The system's procedures take their arguments' types, named, as parameters.
        foreach (Argument argument in _systemProcedures.Values.SelectMany(arguments => arguments))
        {
            if (argument.Value is Address { Designator: var designator }) { Visit(designator.Type, parameter: true); }
        }

        foreach (TypeNode type in _types) { Overlapped(type); }
    }

    // A record's field that starts inside the one before it, which is longer than a word and cannot be shorter, as a
    // real or a record cannot, is a variant's: the Compiler would put it after.
    private static void Overlapped(TypeNode record)
    {
        if (record.Kind != TypeKind.Record || record.PackedFields is not null || record.Fields is not { } fields)
        {
            return;
        }

        int end = 0;
        foreach (int offset in fields.Keys.ToList())
        {
            TypeNode field = fields[offset];
            if (offset < end)
            {
                fields.Remove(offset);
                record.Variants ??= [];
                if (!record.Variants.TryGetValue(offset, out List<TypeNode>? variants))
                {
                    variants = [];
                    record.Variants[offset] = variants;
                }

                variants.Insert(0, field);
                continue;
            }

            TypeNode root = field.Find();
            bool fixedSize = root.Kind is TypeKind.Real or TypeKind.Record or TypeKind.Set;
            end = fixedSize && SizeOf(root) is { } size ? offset + size : offset + 1;
        }
    }

    // A pointer's target is a type's name, so an untyped file it points to is named too.
    private void Visit(TypeNode type, bool parameter, bool pointed = false)
    {
        TypeNode root = type.Find();
        bool named = root.Kind is TypeKind.Record or TypeKind.Pointer or TypeKind.Array or TypeKind.Set
            || (root.Kind == TypeKind.File && (root.RecordWords > 0 || pointed))
            || root.ByteView
            || (parameter && Simple(root) is null);

        if (named && root.Name is null)
        {
            root.Name = $"T{_types.Count + 1}";
            _types.Add(root);
            switch (root.Kind)
            {
                case TypeKind.Pointer or TypeKind.Array or TypeKind.Set or TypeKind.File:
                    if (root.Element is { } element)
                    {
                        Visit(element, parameter: root.Kind == TypeKind.Pointer, pointed: root.Kind == TypeKind.Pointer);
                    }

                    foreach (TypeNode view in root.Views ?? []) { Visit(view, parameter: true, pointed: true); }

                    break;
                case TypeKind.Record:
                    foreach (TypeNode field in root.AllFields)
                    {
                        Visit(field, parameter: false);
                    }

                    break;
                default:
                    break;
            }
        }
    }

    // The named types, each after those its declaration names.
    private List<TypeNode> Ordered()
    {
        List<TypeNode> ordered = [];
        HashSet<TypeNode> done = [];
        foreach (TypeNode type in _types) { Order(type, ordered, done); }
        return ordered;
    }

    // A type after the types it is made of, a pointer's target among them: a pointer is a forward reference only
    // where the types are recursive. The 1.1 Compiler loses one of two forward references to the same type that come
    // together in its list of them, other than first, and then stops with error 117.
    private void Order(TypeNode type, List<TypeNode> ordered, HashSet<TypeNode> done)
    {
        TypeNode root = type.Find();
        if (!done.Add(root)) { return; }

        IEnumerable<TypeNode> parts = root.Kind switch
        {
            TypeKind.Pointer when root.Element is { } target && Names(target, root, []) => [],
            TypeKind.Record => [.. root.AllFields, .. root.PackedFields?.Values.Select(field => field.Type) ?? []],
            _ => root.Element is { } element ? [element, .. root.Views ?? []] : []
        };

        foreach (TypeNode part in parts) { Order(part, ordered, done); }
        if (root.Name is not null && _types.Contains(root)) { ordered.Add(root); }
    }

    // Whether a type's declaration names a pointer type, there or in the types it is made of, but those a pointer
    // points to: then the pointer comes first, as a forward reference.
    private static bool Names(TypeNode type, TypeNode pointer, HashSet<TypeNode> seen)
    {
        TypeNode root = type.Find();
        if (root == pointer) { return true; }
        if (!seen.Add(root) || root.Kind == TypeKind.Pointer) { return false; }

        IEnumerable<TypeNode> parts = root.Element is { } element ? [element] : [];
        if (root.Kind == TypeKind.Record)
        {
            parts = [.. root.AllFields, .. root.PackedFields?.Values.Select(field => field.Type) ?? []];
        }

        return parts.Any(part => Names(part, pointer, seen));
    }

    // A type's name where it has one; otherwise its declaration.
    private string TypeName(TypeNode type, bool parameter)
    {
        TypeNode root = type.Find();
        if (root.Name is not null) { return root.Name; }
        return Simple(root) ?? Declare(root, inline: true);
    }

    // The name of a type that has one of its own: INTEGER, CHAR, BOOLEAN, REAL, STRING, TEXT or a unit's type.
    private static string? Simple(TypeNode root) => root.Kind switch
    {
        TypeKind.Scalar when root.Low is null => root.ScalarKind switch
        {
            ScalarKind.Char => "CHAR",
            ScalarKind.Boolean => "BOOLEAN",
            ScalarKind.Enumeration => root.Enumeration,
            _ => "INTEGER"
        },
        TypeKind.Unknown => "INTEGER",
        TypeKind.Real => "REAL",
        TypeKind.Text => "TEXT",
        TypeKind.File when root.RecordWords <= 0 => "FILE",
        TypeKind.String when root.MaxLength is 80 or 0 => "STRING",
        _ => null
    };

    private string Declare(TypeNode type, bool inline)
    {
        TypeNode root = type.Find();
        if (root.ByteView && root.Kind == TypeKind.Scalar)
        {
            return "RECORD CASE BOOLEAN OF TRUE: (I: INTEGER); FALSE: (B: PACKED ARRAY[0..1] OF CHAR) END";
        }

        switch (root.Kind)
        {
            case TypeKind.Scalar when root.Low is { } low && root.High is { } high:
                return $"{Value(low, root)}..{Value(high, root)}";
            case TypeKind.String:
                return root.MaxLength is 80 or 0 ? "STRING" : $"STRING[{root.MaxLength}]";
            case TypeKind.Pointer when root.Punned && root.Views is { Count: > 0 } views:
                {
                    // A word that points to things that cannot be one has a variant for each.
                    IEnumerable<string> pointers = views.Select((view, index) => $"{index + 2}: (P{index + 2}: ^{TypeName(view, parameter: true)})");
                    return $"RECORD CASE INTEGER OF 0: (I: INTEGER); 1: (P: ^{TypeName(root.Element ?? new TypeNode(), parameter: true)}); {string.Join("; ", pointers)} END";
                }

            case TypeKind.Pointer when root.Punned:
                return $"RECORD CASE BOOLEAN OF TRUE: (I: INTEGER); FALSE: (P: ^{TypeName(root.Element ?? new TypeNode(), parameter: true)}) END";
            case TypeKind.Pointer:
                return $"^{TypeName(root.Element ?? new TypeNode(), parameter: true)}";
            case TypeKind.Set:
                {
                    int words = Math.Max(1, root.Words);
                    if (root.Element?.ScalarKind == ScalarKind.Char && words == 16) { return "SET OF CHAR"; }
                    return $"SET OF 0..{(words * 16) - 1}";
                }

            case TypeKind.File:
                return root.RecordWords > 0 && root.Element is { } component
                    ? $"FILE OF {TypeName(component, parameter: true)}"
                    : "FILE";

            case TypeKind.Array:
                {
                    int low = root.IndexLow ?? 0;
                    int count = root.Words <= 0
                        ? 1
                        : root.Bytes
                            ? root.Words * 2
                            : root.PerWord > 0
                                ? root.Words * root.PerWord
                                : root.Words / Math.Max(1, root.ElementWords);

                    int high = root.IndexHigh ?? low + Math.Max(1, count) - 1;
                    TypeNode element = root.Element ?? TypeNode.Scalar(ScalarKind.Integer);
                    if (root.Bytes)
                    {
                        // Bytes are characters, unless storing one is range checked.
                        string bytes = element.Find().Low is not null ? Declare(element, inline: true) : "CHAR";
                        return $"PACKED ARRAY[{low}..{high}] OF {bytes}";
                    }

                    if (root.PerWord > 0)
                    {
                        string bits = element.Find().Low is not null
                            ? Declare(element, inline: true)
                            : root.Bits == 1 && element.ScalarKind == ScalarKind.Boolean ? "BOOLEAN" : $"0..{(1 << root.Bits) - 1}";

                        return $"PACKED ARRAY[{low}..{high}] OF {bits}";
                    }

                    return $"ARRAY[{low}..{high}] OF {TypeName(element, parameter: false)}";
                }

            case TypeKind.Record:
                return RecordType(root);

            default:
                _ = inline;
                return Simple(root) ?? "INTEGER";
        }
    }

    // A record's fields in order, with padding where the code uses no word. From the first offset where its words are
    // used both as pointers and as integers, it has a variant part: the first variant holds the fields the record
    // has anyway, and each other some of the other fields, those that do not overlap, with padding between them.
    private string RecordType(TypeNode root)
    {
        if (root.PackedFields is { Count: > 0 }) { return PackedRecordType(root); }

        int words = SizeOf(root) ?? 0;
        SortedDictionary<int, TypeNode> known = root.Fields ?? [];
        // The offsets of variants' fields: those with more than one, and those where the fixed part has none.
        IEnumerable<int> offsets = root.Variants is { } all ? known.Keys.Union(all.Keys) : known.Keys;
        List<int> varied = [.. offsets.Order().Where(offset => root.Alternatives(offset).Count > 1 || !known.ContainsKey(offset))];
        int start = varied.DefaultIfEmpty(words).Min();

        // But not inside a field of the fixed part, which is whole there.
        start = known.Keys
            .Where(offset => offset < start && offset + (SizeOf(known[offset]) ?? 1) > start)
            .DefaultIfEmpty(start)
            .Min();

        // Variants only as long as NEW takes of the record, the variant part from its start where one is shorter.
        List<int> shorter = [.. (_allocated.GetValueOrDefault(root) ?? []).Where(size => size < words)];
        if (shorter.Count > 0 && shorter[0] < start) { start = 0; }

        // Views of the first words as one array, for moves of them.
        SortedSet<int> views = _moved.GetValueOrDefault(root) ?? [];
        if (views.Count > 0) { start = 0; }

        List<string> fixedPart = Run(0, Math.Min(start, words));
        if (start >= words) { return $"RECORD {string.Join("; ", fixedPart)} END"; }

        // The other fields, each in the first variant it does not overlap a field of.
        List<List<string>> variants = [Run(start, words)];
        List<int> ends = [words];
        foreach (int offset in varied)
        {
            List<TypeNode> alternatives = root.Alternatives(offset);
            for (int index = known.ContainsKey(offset) ? 1 : 0; index < alternatives.Count; index++)
            {
                TypeNode field = alternatives[index];
                int size = Math.Max(1, SizeOf(field) ?? 1);
                Fit(field, size);
                int variant = Enumerable.Range(1, ends.Count - 1).FirstOrDefault(other => ends[other] <= offset);
                if (variant == 0)
                {
                    variants.Add([]);
                    ends.Add(start);
                    variant = variants.Count - 1;
                }

                if (ends[variant] < offset)
                {
                    variants[variant].Add($"X{ends[variant]}V{variant}: {Declare(Padding(offset - ends[variant]), inline: true)}");
                }

                variants[variant].Add($"{FieldName(root, offset, index)}: {TypeName(field, parameter: false)}");
                ends[variant] = offset + size;
            }
        }

        List<string> labelled = [.. variants.Select((fields, index) => $"{index}: ({string.Join("; ", fields)})")];
        foreach (int size in shorter)
        {
            string padding = size > start ? $"X{size}N: {Declare(Padding(size - start), inline: true)}" : "";
            labelled.Add($"{Shorter + size}: ({padding})");
        }

        foreach (int size in views)
        {
            labelled.Add($"{Viewing + size}: (B{size}N: {Declare(Padding(size), inline: true)})");
        }

        string cases = string.Join("; ", labelled);
        string head = fixedPart.Count == 0 ? "" : $"{string.Join("; ", fixedPart)}; ";
        return $"RECORD {head}CASE INTEGER OF {cases} END";

        List<string> Run(int from, int to)
        {
            List<string> parts = [];
            int offset = from;
            while (offset < to)
            {
                int next = known.Keys.Where(key => key > offset).DefaultIfEmpty(words).Min();
                next = Math.Min(next, to);

                // Fields no code names, but the first, which a record's address reaches, are padding with the words
                // after them up to the next one named.
                if (offset > 0 && root.PackedFields is null && !_namedFields.Contains((root, offset)))
                {
                    int named = known.Keys.Where(key => key > offset && _namedFields.Contains((root, key))).DefaultIfEmpty(to).Min();
                    named = Math.Min(named, to);
                    parts.Add($"{FieldName(root, offset, 0)}: {Declare(Padding(named - offset), inline: true)}");
                    offset = named;
                    continue;
                }

                if (known.TryGetValue(offset, out TypeNode? field))
                {
                    // A field the code shows nothing of the size of is a word, the words after it padding.
                    TypeNode shown = field.Find();
                    int unknown = shown.Kind == TypeKind.Unknown && shown.Words <= 1 ? 1 : next - offset;
                    int size = Math.Min(SizeOf(field) ?? unknown, next - offset);
                    Fit(field, size);
                    parts.Add($"{FieldName(root, offset, 0)}: {TypeName(field, parameter: false)}");
                    offset += Math.Max(1, size);
                }
                else
                {
                    parts.Add($"{FieldName(root, offset, 0)}: {Declare(Padding(next - offset), inline: true)}");
                    offset = next;
                }
            }

            return parts;
        }
    }

    // The fields the code names, by their records: a record's other words are padding, which keeps the Compiler's
    // symbol table, in which every field's name takes room, small.
    private readonly HashSet<(TypeNode Record, int Offset)> _namedFields = [];

    private void NamedFields()
    {
        foreach (Procedure procedure in _procedures)
        {
            Walk(procedure.Body, statement =>
            {
                if (statement is Assignment assignment) { Name(assignment.Target); }
                if (statement is WithStatement with) { Name(with.Record); }
                if (statement is CallStatement { Callee.Builtin: "NEW" } allocation) { Allocated(allocation); }
                if (statement is Assignment { Block: true } moved) { Moved(moved); }

            }, expression =>
            {
                switch (expression)
                {
                    case Load load: Name(load.Designator); break;
                    case Address address: Name(address.Designator); break;
                    case ByteAddress address: Name(address.Designator); break;
                    case PackedAddress address: Name(address.Designator); break;
                    default: break;
                }
            });

        }

        void Name(Designator designator)
        {
            switch (designator)
            {
                case FieldDesignator field:
                    _namedFields.Add((field.Record.Type.Find(), field.Offset));
                    Name(field.Record);
                    break;
                case PackedFieldDesignator field: Name(field.Record); break;
                case IndexDesignator index: Name(index.Array); break;
                case StringIndexDesignator index: Name(index.Text); break;
                case LengthDesignator length: Name(length.Text); break;
                case WindowDesignator window: Name(window.File); break;
                default: break;
            }
        }
    }

    // A record with fields packed into words: the Compiler packs a packed record's fields in order from each word's low
    // bit, starting a word where one does not fit, so each word's fields go in order, with fillers for the bits before
    // and between them and to the word's end; a word with none is a field of its own.
    private string PackedRecordType(TypeNode root)
    {
        int words = SizeOf(root) ?? 0;
        SortedDictionary<(int Word, int Bit), (int Width, TypeNode Type)> packed = root.PackedFields ?? [];
        SortedDictionary<int, TypeNode> known = root.Fields ?? [];
        List<string> parts = [];

        // A word also used whole, as an integer or read by bytes, is another variant's field.
        bool both = known.Any(pair => pair.Value.Find().Kind != TypeKind.Unknown && packed.Keys.Any(key => key.Word == pair.Key));
        List<string> wholes = [];
        for (int word = 0; word < words; word++)
        {
            List<KeyValuePair<(int Word, int Bit), (int Width, TypeNode Type)>> fields = [.. packed.Where(pair => pair.Key.Word == word)];
            if (both)
            {
                wholes.Add(known.TryGetValue(word, out TypeNode? used) && SizeOf(used) is 1
                    ? $"F{word}: {TypeName(used, parameter: false)}"
                    : $"X{word}: INTEGER");
            }

            if (fields.Count == 0)
            {
                if (known.TryGetValue(word, out TypeNode? whole) && SizeOf(whole) is 1)
                {
                    parts.Add(both ? $"X{word}V1: INTEGER" : $"F{word}: {TypeName(whole, parameter: false)}");
                }
                else
                {
                    parts.Add(both ? $"X{word}V1: INTEGER" : $"F{word}: INTEGER");
                }

                continue;
            }

            int bit = 0;
            foreach (((int _, int at), (int width, TypeNode type)) in fields)
            {
                if (at > bit) { parts.Add($"X{word}B{bit}: 0..{(1 << (at - bit)) - 1}"); }
                TypeNode field = type.Find();
                string name = width == 1 && field.Kind == TypeKind.Scalar && field.ScalarKind == ScalarKind.Boolean ? "BOOLEAN" : $"0..{(1 << width) - 1}";
                parts.Add($"F{word}B{at}: {name}");
                bit = Math.Max(bit, at + width);
            }

            if (bit is > 0 and < 16) { parts.Add($"X{word}B{bit}: 0..{(1 << (16 - bit)) - 1}"); }
        }

        return both
            ? $"PACKED RECORD CASE INTEGER OF 0: ({string.Join("; ", wholes)}); 1: ({string.Join("; ", parts)}) END"
            : $"PACKED RECORD {string.Join("; ", parts)} END";
    }

    // The label of a variant that only makes a record as long as NEW takes, 100 more than its words.
    private const int Shorter = 100;

    // The words NEW takes of records, where fewer than the records have.
    private readonly Dictionary<TypeNode, SortedSet<int>> _allocated = [];

    private void Allocated(CallStatement allocation)
    {
        if (allocation.Arguments.Count != 2) { return; }
        if (allocation.Arguments[0].Value is not Address { Designator: var pointer }) { return; }
        if (allocation.Arguments[1].Value is not Constant { Value: var words }) { return; }

        TypeNode? record = Descend(pointer, use: null).Type.Find().Element?.Find();
        if (record is null || record.Kind != TypeKind.Record) { return; }
        if (!_allocated.TryGetValue(record, out SortedSet<int>? sizes))
        {
            sizes = [];
            _allocated[record] = sizes;
        }

        sizes.Add(words);
    }

    // The label of a variant that views a record's first words as one array, 200 more than its words.
    private const int Viewing = 200;

    // The words of records that moves take, where no field is as long, and the moves that take them.
    private readonly Dictionary<TypeNode, SortedSet<int>> _moved = [];
    private readonly HashSet<Assignment> _moves = [];

    // A move of fewer words than its records have, where no first field of each is as long, moves an array of them,
    // which each record has as a variant.
    private void Moved(Assignment move)
    {
        if (move.Value is not Load { Designator: var source } whole) { return; }

        int words = whole.Words;
        TypeNode target = move.Target.Type.Find();
        TypeNode from = source.Type.Find();
        if (!Viewable(target, words) || !Viewable(from, words) || (Prefix(target, words) && Prefix(from, words)))
        {
            return;
        }

        foreach (TypeNode record in (TypeNode[])[target, from])
        {
            if (!_moved.TryGetValue(record, out SortedSet<int>? sizes))
            {
                sizes = [];
                _moved[record] = sizes;
            }

            sizes.Add(words);
        }

        _moves.Add(move);

        static bool Viewable(TypeNode record, int words) =>
            record.Kind == TypeKind.Record && record.PackedFields is null && SizeOf(record) > words && words > 1;

        // Whether a record's first field, or its first field's, is as long as the move.
        static bool Prefix(TypeNode record, int words)
        {
            TypeNode current = record;
            for (int depth = 0; depth < 8; depth++)
            {
                if (SizeOf(current) == words) { return true; }
                if (current.Kind != TypeKind.Record || current.Fields?.ContainsKey(0) != true) { return false; }
                current = current.Field(0).Find();
            }

            return false;
        }
    }

    // A field's name: its offset's, and for another variant's field, which of the offset's it is.
    private string FieldName(TypeNode record, int offset, int alternative)
    {
        string prefix = _prefixed.Contains(record.Find()) ? $"{record.Find().Name}F" : "F";
        return alternative <= 0 ? $"{prefix}{offset}" : $"{prefix}{offset}V{alternative}";
    }

    // The name of the field a designator reaches: the one at its offset whose type is the designator's.
    private string FieldName(FieldDesignator field)
    {
        TypeNode record = field.Record.Type.Find();
        return FieldName(record, field.Offset, record.Alternatives(field.Offset).IndexOf(field.Type.Find()));
    }

    // The records of WITH statements with others inside on records of other types, whose fields are named with their
    // types' names: an inner record's would otherwise name them, and the outer's were reached by the record's own
    // designator, not by its WITH.
    private readonly HashSet<TypeNode> _prefixed = [];

    private void Prefixes()
    {
        foreach (Procedure procedure in _procedures)
        {
            Walk(procedure.Body, Outer, _ => { });
        }

        void Outer(Statement statement)
        {
            if (statement is not WithStatement outer || Within(outer) is not { PackedFields: null } record) { return; }

            Walk(
                outer.Body,
                inside =>
                {
                    if (inside is WithStatement inner && Within(inner) is { } other && other != record)
                    {
                        _prefixed.Add(record);
                    }
                },
                _ => { });
        }

        static TypeNode? Within(WithStatement with) =>
            with.Temporary.Type.Find().Element?.Find() is { Kind: TypeKind.Record } record ? record : null;
    }

    private void Statements(Procedure procedure, List<Statement> statements)
    {
        List<string> lines = [];
        Statements(procedure, statements, lines);
        foreach (string line in lines) { _source.Append(line); }
    }

    private void Statements(Procedure procedure, List<Statement> statements, List<string> lines)
    {
        _indent++;
        int first = lines.Count;
        for (int index = 0; index < statements.Count; index++)
        {
            Statement statement = statements[index];

            // A run of WRITEs to one file, perhaps ended by a WRITELN, is one statement; and so with READ.
            if (statement is CallStatement { Callee.Builtin: ("WRITE" or "READ") and { } ioName } io)
            {
                int end = index;
                List<Argument> arguments = [.. io.Arguments.Skip(1)];
                string name = ioName;
                string file = FileName(io.Arguments[0]);
                while (end + 1 < statements.Count
                    && statements[end + 1] is CallStatement next
                    && next.Checked == io.Checked
                    && next.Callee.Builtin == name
                    && FileName(next.Arguments[0]) == file)
                {
                    arguments.AddRange(next.Arguments.Skip(1));
                    end++;
                }

                if (end + 1 < statements.Count
                    && statements[end + 1] is CallStatement line
                    && line.Checked == io.Checked
                    && line.Callee.Builtin == name + "LN"
                    && FileName(line.Arguments[0]) == file)
                {
                    name += "LN";
                    end++;
                }

                Separate(lines, first);
                Check(io.Checked, lines);
                if (RangeChecked(statement) is { } ioRange) { CheckRange(ioRange, lines); }
                lines.Add(Io(name, io.Arguments[0], arguments));
                index = end;
                continue;
            }

            Separate(lines, first);
            if (statement is CallStatement { Callee.Builtin: { } builtin } call && IsIo(builtin))
            {
                Check(call.Checked, lines);
            }

            if (RangeChecked(statement) is { } range) { CheckRange(range, lines); }
            WriteStatement(procedure, statement, lines);
        }

        _indent--;
    }

    private static bool IsIo(string name) =>
        name is "RESET" or "REWRITE" or "CLOSE" or "GET" or "PUT" or "SEEK" or "READLN" or "WRITELN" or "PAGE";

    // Turns I/O checking on or off ahead of a statement whose I/O is checked or not.
    private void Check(bool on, List<string> lines)
    {
        if (on == _ioChecked) { return; }
        _ioChecked = on;
        lines.Add(Indented(on
            ? "(*$I+*)  (* I/O checks on again: an I/O error stops the program. *)"
            : "(*$I-*)  (* I/O checks off: errors are left for IORESULT. *)"));
    }

    // Turns range checking on or off ahead of a statement whose indexes are checked (CHK) or not.
    private void CheckRange(bool on, List<string> lines)
    {
        if (on == _rangeChecked) { return; }
        _rangeChecked = on;
        lines.Add(Indented(on
            ? "(*$R+*)  (* Range checks on again: an index out of its bounds stops the program. *)"
            : "(*$R-*)  (* Range checks off: the code checks no indexes here. *)"));
    }

    // Whether a statement's own expressions, not those of the statements inside it, check ranges: true where one
    // does, false where an index goes unchecked, and null where nothing says.
    private static bool? RangeChecked(Statement statement)
    {
        bool? result = null;
        void Visit(Expr expression) => Walk(expression, inner =>
        {
            if (inner is Checked) { result ??= true; }
        });

        List<Expr> parts = statement switch
        {
            Assignment assignment => [new Address(assignment.Target), assignment.Value],
            CallStatement call => [.. call.Arguments.Select(argument => argument.Value)],
            IfStatement branch => [branch.Condition],
            WhileStatement loop => [loop.Condition],
            ForStatement loop => [new Address(loop.Control), loop.From, loop.To],
            CaseStatement choice => [choice.Selector],
            WithStatement with => [new Address(with.Record)],
            _ => []
        };

        foreach (Expr part in parts)
        {
            Visit(part);
            Walk(part, inner =>
            {
                Designator? designator = inner switch
                {
                    Load load => load.Designator,
                    Address address => address.Designator,
                    ByteAddress address => address.Designator,
                    PackedAddress address => address.Designator,
                    _ => null
                };

                for (Designator? at = designator; at is not null;)
                {
                    if (at is IndexDesignator { Neutral: false } index
                        && !(index.Index is Constant { Value: 0 }
                            && index.High is null
                            && index.Array.Type.Find().Kind == TypeKind.String))
                    {
                        if (index.High is null) { result = false; } else { result ??= true; }
                    }

                    at = at switch
                    {
                        FieldDesignator field => field.Record,
                        PackedFieldDesignator field => field.Record,
                        IndexDesignator index2 => index2.Array,
                        StringIndexDesignator text => text.Text,
                        _ => null
                    };
                }
            });
        }

        return result;
    }

    // Statements in a list are separated by semicolons, after the last line of the one before; not after a label.
    private static void Separate(List<string> lines, int first)
    {
        for (int index = lines.Count - 1; index >= first; index--)
        {
            string line = lines[index].TrimEnd('\n');
            if (line.TrimStart().StartsWith("(*$", StringComparison.Ordinal)) { continue; }
            if (!line.EndsWith(':') && !line.EndsWith(';')) { lines[index] = line + ";\n"; }
            return;
        }
    }

    private string Io(string name, Argument file, List<Argument> arguments)
    {
        string fileName = FileName(file);
        bool standard = name.StartsWith("WRITE", StringComparison.Ordinal) ? fileName == "OUTPUT" : fileName == "INPUT";
        List<string> parts = standard ? [] : [fileName];
        foreach (Argument argument in arguments)
        {
            string value = argument.Value is Written written ? WrittenValue(written) : DesignatorText(Designate(argument.Value));
            if (argument.Width is not null)
            {
                value += ":" + Expression(argument.Width, TypeNode.Scalar(ScalarKind.Integer), 0);
            }

            if (argument.Decimals is not null)
            {
                value += ":" + Expression(argument.Decimals, TypeNode.Scalar(ScalarKind.Integer), 0);
            }

            parts.Add(value);
        }

        return Indented(parts.Count == 0 ? name : $"{name}({string.Join(", ", parts)})");
    }

    private string WrittenValue(Written written) => written.Procedure switch
    {
        13 => Expression(written.Value, TypeNode.Scalar(ScalarKind.Integer), 0),
        17 => written.Value is Constant { Value: 12 }
            ? "CHR(12)"
            : Expression(written.Value, TypeNode.Scalar(ScalarKind.Char), 0),
        0 => Expression(written.Value, TypeNode.Of(TypeKind.Real), 0),
        _ => Expression(written.Value, expected: null, 0)
    };

    private string FileName(Argument file) => file.Value switch
    {
        // A (*$U-*) program's own system globals hold their files' addresses; INPUT, OUTPUT and KEYBOARD are files.
        Load { Designator: VariableDesignator { Variable: { Kind: VariableKind.System } system } } =>
            _systemFiles.Contains(system) ? $"{system.Name}^" : system.Name,
        Address address => DesignatorText(address.Designator),
        var other => DesignatorText(Designate(other))
    };

    private string Indented(string text) => new string(' ', _indent * 2) + text + "\n";

    private void WriteStatement(Procedure procedure, Statement statement, List<string> lines)
    {
        switch (statement)
        {
            case Assignment { Value: Load { Designator: var source } whole } move when _moves.Contains(move):
                {
                    string view = $"B{whole.Words}N";
                    lines.Add(Indented($"{DesignatorText(move.Target)}.{view} := {DesignatorText(source)}.{view}"));
                    break;
                }

            case Assignment assignment:
                {
                    Expr value = Narrow(assignment.Value);
                    Designator target = Descend(assignment.Target, value is Constant ? null : value.Type);
                    if (LengthOf(target) is { } counted)
                    {
                        // A string's length is its byte 0, a character, which range checks off let the code index.
                        string count = Expression(assignment.Value, TypeNode.Scalar(ScalarKind.Integer), 0);
                        lines.Add(Indented($"{DesignatorText(counted)}[0] := CHR({count})"));
                        break;
                    }

                    string text = DesignatorText(target);
                    if (Viewed(target) && target.Type.Find() is { Kind: TypeKind.Scalar, ByteView: true })
                    {
                        lines.Add(Indented($"{text}.I := {Expression(value, TypeNode.Scalar(ScalarKind.Integer), 0)}"));
                        break;
                    }

                    if (target is VariableDesignator { Variable: var plain } && _plainParameters.Contains(plain))
                    {
                        lines.Add(Indented($"{text} := {Expression(assignment.Value, expected: null, 0)}"));
                        break;
                    }

                    // A word used both ways moved whole, as the Compiler moves a record, is assigned whole.
                    if (assignment.Block
                        && Narrow(assignment.Value) is Load { Designator: var moved }
                        && IsPunned(target.Type)
                        && moved.Type.Find() == target.Type.Find()
                        && !IsPlain(target)
                        && !IsPlain(moved))
                    {
                        lines.Add(Indented($"{text} := {DesignatorText(moved)}"));
                        break;
                    }

                    if (Viewed(target) && IsPunned(target.Type))
                    {
                        bool pointer = assignment.Value is Nil || Natural(assignment.Value) is null && assignment.Value is not Constant;
                        text += pointer ? ".P" : ".I";
                        lines.Add(Indented($"{text} := {Expression(assignment.Value, pointer ? null : TypeNode.Scalar(ScalarKind.Integer), 0)}"));
                        break;
                    }

                    // A character assigned to a string is the string of it; a string's element is a character.
                    TypeNode expected = target.Type.Find().Kind == TypeKind.String && assignment.Value is Constant ? TypeNode.Scalar(ScalarKind.Char) : target.Type;
                    if (target is IndexDesignator { Array: var characters }
                        && characters.Type.Find().Kind == TypeKind.String)
                    {
                        expected = TypeNode.Scalar(ScalarKind.Char);
                    }

                    lines.Add(Indented($"{text} := {Expression(assignment.Value, expected, 0)}"));
                    break;
                }

            case CallStatement call:
                lines.Add(Indented(CallText(call)));
                break;
            case IfStatement branch:
                {
                    lines.Add(Indented($"IF {Condition(branch.Condition)} THEN"));
                    List<Statement> then = branch.Then;

                    // An IF without ELSE inside an IF with one needs its own BEGIN and END, or it takes the ELSE.
                    bool dangling = branch.Else is not null && then.Count == 1 && EndsWithIf(then[0]);
                    Block(procedure, then, lines, forceCompound: dangling);
                    if (branch.Else is not null)
                    {
                        lines.Add(Indented("ELSE"));
                        Block(procedure, branch.Else, lines, forceCompound: false);
                    }

                    break;
                }

            case WhileStatement loop:
                lines.Add(Indented($"WHILE {Condition(loop.Condition)} DO"));
                Block(procedure, loop.Body, lines, forceCompound: false);
                break;
            case RepeatStatement loop:
                lines.Add(Indented("REPEAT"));
                Inner(procedure, loop.Body, lines);
                lines.Add(Indented($"UNTIL {Condition(loop.Condition)}"));
                break;
            case ForStatement loop:
                {
                    string control = DesignatorText(loop.Control);
                    string from = Expression(loop.From, loop.Control.Type, 0);
                    string to = Expression(loop.To, loop.Control.Type, 0);
                    lines.Add(Indented($"FOR {control} := {from} {(loop.Down ? "DOWNTO" : "TO")} {to} DO"));
                    Block(procedure, loop.Body, lines, forceCompound: false);
                    break;
                }

            case CaseStatement choice:
                // A selector is a scalar: a word used both ways by its integer view, a pointer by ORD. A label is a
                // constant, which a character that is not printable has none of: the selector is then ORD of it.
                TypeNode? selector = choice.Selector.Type.Find().Kind == TypeKind.Pointer ? TypeNode.Scalar(ScalarKind.Integer) : null;
                TypeNode labelType = choice.Selector.Type.Find();
                bool unprintable = Kind(labelType) == ScalarKind.Char && choice.Arms.SelectMany(arm => arm.Labels).Any(label => label is < 32 or >= 127);
                if (unprintable)
                {
                    selector = TypeNode.Scalar(ScalarKind.Integer);
                    labelType = selector;
                }

                lines.Add(Indented($"CASE {Expression(choice.Selector, selector, 0)} OF"));
                _indent++;
                for (int arm = 0; arm < choice.Arms.Count; arm++)
                {
                    (List<int> labels, List<Statement> body) = choice.Arms[arm];
                    lines.Add(Indented($"{string.Join(", ", labels.Select(label => Value(label, labelType)))}:"));
                    Block(procedure, body, lines, forceCompound: false);
                    if (arm + 1 < choice.Arms.Count) { Separate(lines, 0); }
                }

                _indent--;
                lines.Add(Indented("END"));
                break;
            case WithStatement with:
                lines.Add(Indented($"WITH {DesignatorText(with.Record)} DO"));
                _with.Add(with.Temporary);
                _withRecords[with.Temporary] = with.Record;
                Block(procedure, with.Body, lines, forceCompound: false);
                _with.RemoveAt(_with.Count - 1);
                break;
            case GotoStatement jump:
                lines.Add(Indented($"GOTO {procedure.Labels[jump.Target]}"));
                break;
            case LabelStatement label:
                lines.Add(Indented($"{procedure.Labels[label.Target]}:"));
                break;
            case ExitStatement exit:
                {
                    Procedure? target = exit.Segment == Main.Number || exit.Segment == 1
                        ? _procedures.FirstOrDefault(other => other.Segment == _main && other.Number == exit.Procedure)
                        : FindSegment(exit.Segment, exit.Procedure);

                    // A system program is a segment procedure, which EXIT names; PROGRAM would be the system's.
                    string exited = target == _program && !_systemProgram ? "PROGRAM" : target?.Name ?? "PROGRAM";
                    lines.Add(Indented($"EXIT({exited})"));
                    break;
                }

            case Unsupported unsupported:
                lines.Add(Indented($"(* {unsupported.Text} *)"));
                break;
            default:
                break;
        }
    }

    private static bool EndsWithIf(Statement statement) => statement switch
    {
        IfStatement { Else: null } => true,
        IfStatement { Else: { Count: 1 } otherwise } => EndsWithIf(otherwise[0]),
        WhileStatement { Body: { Count: 1 } body } => EndsWithIf(body[0]),
        ForStatement { Body: { Count: 1 } body } => EndsWithIf(body[0]),
        WithStatement { Body: { Count: 1 } body } => EndsWithIf(body[0]),
        _ => false
    };

    // A statement or several in BEGIN and END.
    private void Block(Procedure procedure, List<Statement> body, List<string> lines, bool forceCompound)
    {
        if (body.Count == 1 && !forceCompound && body[0] is not LabelStatement && !Writes(body))
        {
            _indent++;
            WriteStatement(procedure, body[0], lines);
            _indent--;
            return;
        }

        lines.Add(Indented("BEGIN"));
        Inner(procedure, body, lines);
        lines.Add(Indented("END"));
    }

    // Whether a single statement writes more than one line, as a run of WRITEs does.
    private static bool Writes(List<Statement> body) => body[0] is CallStatement { Callee.Builtin: "WRITE" or "READ" };

    private void Inner(Procedure procedure, List<Statement> body, List<string> lines) => Statements(procedure, body, lines);

    private string CallText(CallStatement call)
    {
        Callee callee = call.Callee;
        if (callee.Procedure is { } procedure)
        {
            return Invocation(procedure.Name, Arguments(procedure, [.. call.Arguments.Select(a => a.Value)]));
        }

        if (callee.UnitProcedure is { } declared)
        {
            return Invocation(declared.Name, UnitArguments(declared, [.. call.Arguments.Select(a => a.Value)]));
        }

        string name = callee.Builtin ?? "?";

        // NEW of fewer words than a record has takes the variant that long, labelled with 100 more than its words.
        if (name == "NEW" && call.Arguments is [{ Value: Address allocated }, { Value: Constant { Value: var words } }])
        {
            Designator pointer = Descend(allocated.Designator, use: null);
            TypeNode? record = pointer.Type.Find().Element?.Find();
            return record is { Kind: TypeKind.Record } && (SizeOf(record) ?? 0) > words
                ? $"NEW({Pointer(pointer)}, {Shorter + words})"
                : $"NEW({Pointer(pointer)})";
        }

        List<string> parts = [];
        foreach (Argument argument in call.Arguments)
        {
            // FILLCHAR fills with a character.
            if (name == "FILLCHAR" && argument == call.Arguments[^1])
            {
                parts.Add(Expression(argument.Value, TypeNode.Scalar(ScalarKind.Char), 0));
                continue;
            }

            parts.Add(argument.Value switch
            {
                Keyword keyword => keyword.Text,

                // NEW and MARK set a pointer, a record's first field where it is a record's address: a word used
                // both ways by its pointer view.
                Address address when name is "NEW" or "MARK" or "RELEASE" => Pointer(Descend(address.Designator, use: null)),
                Address address => Untyped(address.Designator),
                ByteAddress address => Untyped(address.Designator),
                Load
                {
                    Designator: VariableDesignator { Variable.Kind: VariableKind.System }
                } file => FileName(new Argument(file)),
                var value => Expression(value, expected: null, 0)
            });
        }

        return name is "RESET" or "REWRITE" or "CLOSE" or "GET" or "PUT" or "SEEK" && call.Arguments.Count > 0
            ? Invocation(name, [FileName(call.Arguments[0]), .. parts.Skip(1)])
            : Invocation(name, parts);
    }

    // An untyped argument's designator: inside a WITH on a record, its first field for the record, which the WITH
    // reaches, as the record's own designator would reach it again. A record has a field at its address, if only of
    // padding.
    private string Untyped(Designator designator)
    {
        if (designator is Dereference { Pointer: Load { Designator: VariableDesignator { Variable: var temporary } } }
            && _with.Contains(temporary)
            && temporary.Type.Find().Element?.Find() is { Kind: TypeKind.Record, PackedFields: null } record)
        {
            return $"{Record(designator, 0)}{FieldName(record, 0, 0)}";
        }

        return DesignatorText(designator);
    }

    private string Pointer(Designator pointer) =>
        IsPunned(pointer.Type) && !IsPlain(pointer) ? $"{DesignatorText(pointer)}.P" : DesignatorText(pointer);

    // Whether a designator is a value parameter written as its pointer.
    private bool IsPlain(Designator designator) => designator switch
    {
        VariableDesignator { Variable: var variable } => _plainParameters.Contains(variable),
        Dereference { Pointer: Load { Designator: VariableDesignator { Variable: { IsReference: true } variable } } } =>
            _plainParameters.Contains(variable),
        _ => false
    };

    private static string Invocation(string name, List<string> arguments) =>
        arguments.Count == 0 ? name : $"{name}({string.Join(", ", arguments)})";

    // A call's arguments: a VAR parameter's or a structured value's by designator, others as values of its type.
    private List<string> Arguments(Procedure callee, IReadOnlyList<Expr> arguments)
    {
        List<Variable> slots = Slots(callee, arguments);
        List<string> parts = [];
        for (int index = 0; index < arguments.Count; index++)
        {
            Variable parameter = slots[index];
            Expr argument = arguments[index];
            if (parameter.IsReference && _plainParameters.Contains(parameter))
            {
                // A VAR parameter written as its pointer takes the pointer of a word used both ways.
                parts.Add(Pointer(Designate(argument)));
            }
            else if (parameter.IsReference || parameter.Copy is not null)
            {
                TypeNode formal = parameter.Copy?.Type ?? Narrowed(parameter) ?? parameter.Type.Target();
                parts.Add(argument is StringConstant or StringFunction ? Expression(argument, expected: null, 0) : DesignatorText(Descend(Designate(argument), formal)));
            }
            else if (_plainParameters.Contains(parameter))
            {
                // A parameter written as its pointer takes the pointer of a word used both ways.
                parts.Add(Narrow(argument) is Load { Designator: var punned } && IsPunned(punned.Type)
                    ? Pointer(punned)
                    : Expression(argument, _plainPointers[parameter.Type.Find()], 0));
            }
            else if (Narrow(argument) is Load { Designator: var whole }
                && IsPunned(parameter.Type)
                && whole.Type.Find() == parameter.Type.Find())
            {
                // A word used both ways passes whole to a parameter that is one.
                parts.Add(DesignatorText(whole));
            }
            else
            {
                parts.Add(Expression(argument, parameter.Type, 0));
            }
        }

        return parts;
    }

    private List<string> UnitArguments(PascalUnitProcedure declared, IReadOnlyList<Expr> arguments)
    {
        List<string> parts = [];
        for (int index = 0; index < arguments.Count; index++)
        {
            PascalUnitParameter? parameter = index < declared.Parameters.Count ? declared.Parameters[index] : null;
            Expr argument = arguments[index];
            if (parameter is { IsReference: true })
            {
                parts.Add(DesignatorText(Designate(argument)));
            }
            else
            {
                parts.Add(Expression(argument, parameter?.Type is { } type ? Named(type) : null, 0));
            }
        }

        return parts;
    }

    private string Condition(Expr condition) => Expression(condition, TypeNode.Scalar(ScalarKind.Boolean), 0);

    private string DesignatorText(Designator designator)
    {
        switch (designator)
        {
            case VariableDesignator { Variable: { Container: { } container } field }:
                {
                    // A word of a record variable is the field at its offset whose type is its own.
                    int alternative = container.Type.Find().Alternatives(field.FieldOffset).IndexOf(field.Type.Find());
                    return $"{DesignatorText(new VariableDesignator(container))}.{FieldName(container.Type, field.FieldOffset, alternative)}";
                }

            case VariableDesignator { Variable: var variable }:
                return variable.Kind == VariableKind.Copy
                    ? variable.Frame.Variables.Values.FirstOrDefault(parameter => parameter.Copy == variable)?.Name ?? variable.Name
                    : variable.Kind == VariableKind.Result && variable.Frame.Owner is { } owner
                        ? owner.Name
                        : variable.Name;

            case ResultDesignator result:
                return result.Procedure.Name;
            case FieldDesignator field:
                return $"{Record(field.Record, field.Offset)}{FieldName(field)}";
            case PackedFieldDesignator field:
                return $"{Record(field.Record)}F{field.Word}B{field.Bit}";
            case IndexDesignator
            {
                Array: Dereference { Pointer: Load { Designator: VariableDesignator { Variable: var file } } },
                Index: Constant { Value: 0 }
            } when file.Type.Find().Kind == TypeKind.Text:
                return $"{file.Name}^";
            case IndexDesignator { Index: Constant { Value: 0 }, High: null } length
                when length.Array.Type.Find().Kind == TypeKind.String:
                return $"LENGTH({DesignatorText(length.Array)})";
            case IndexDesignator { Array: VariableDesignator { Variable: var bytes } } byteIndex
                when bytes.Type.Find() is { Kind: TypeKind.Scalar, ByteView: true }:
                return $"{bytes.Name}.B[{Expression(byteIndex.Index, expected: null, 0)}]";
            case IndexDesignator { Array: var whole } recordBytes
                when whole.Type.Find().Kind == TypeKind.Record
                    && Descend(whole, use: null) is var first
                    && first.Type.Find() is { Kind: TypeKind.Scalar, ByteView: true }:
                // A record read by bytes is its first word's byte view.
                return $"{DesignatorText(first)}.B[{Expression(recordBytes.Index, expected: null, 0)}]";
            case IndexDesignator index:
                {
                    // Arrays are declared with integer subranges for indexes.
                    string array = DesignatorText(index.Array);
                    string value = Expression(index.Index, TypeNode.Scalar(ScalarKind.Integer), 0);

                    // Without range checks, the bound an index lost may not be the one the array has.
                    if (index.Low is { } lost
                        && index.Array.Type.Find().IndexLow is { } declared
                        && lost != declared
                        && !index.Neutral)
                    {
                        int difference = lost - declared;
                        value = $"{Expression(index.Index, TypeNode.Scalar(ScalarKind.Integer), Adding)} {(difference > 0 ? "-" : "+")} {Math.Abs(difference)}";
                    }

                    return array.EndsWith(']') && index.Array is IndexDesignator ? $"{array[..^1]}, {value}]" : $"{array}[{value}]";
                }

            case LengthDesignator length:
                return $"LENGTH({DesignatorText(length.Text)})";
            case StringIndexDesignator index:
                return $"{DesignatorText(index.Text)}[{Expression(index.Index, TypeNode.Scalar(ScalarKind.Integer), 0)}]";
            case Dereference dereference:
                {
                    if (dereference.Pointer is Load { Designator: VariableDesignator { Variable: var pointer } })
                    {
                        if (pointer.IsReference) { return pointer.Name; }
                        if (pointer.Type.Find().Kind is TypeKind.Text or TypeKind.File) { return $"{pointer.Name}^"; }
                    }

                    // What a word used both ways points to as another variant's pointer is read through it.
                    if (dereference.View is { } view
                        && dereference.Pointer is Load { Designator: var word }
                        && IsPunned(word.Type)
                        && word.Type.Find().Views is { } views
                        && views.FindIndex(other => other.Find() == view.Find()) is var index and >= 0)
                    {
                        return $"{DesignatorText(word)}.P{index + 2}^";
                    }

                    return $"{Expression(dereference.Pointer, expected: null, 4)}^";
                }

            case WindowDesignator window:
                return $"{DesignatorText(window.File)}^";
            default:
                return "?";
        }
    }

    // A record's designator before a field's name; nothing inside a WITH statement on it.
    private string Record(Designator record, int offset = -1)
    {
        if (record is Dereference { Pointer: Load { Designator: VariableDesignator { Variable: var temporary } } }
            && _with.Contains(temporary))
        {
            // A field of an outer WITH's record that an inner one's has a field at the offset of, which its name would
            // name, is named with its record's.
            bool hidden = offset >= 0 && _with.Skip(_with.IndexOf(temporary) + 1).Any(inner => Hides(inner, temporary, offset));

            return hidden && _withRecords.TryGetValue(temporary, out Designator? whole) ? DesignatorText(whole) + "." : "";
        }

        return DesignatorText(record) + ".";
    }

    // Whether an inner WITH's record, of another type, has words at an offset, whose field there an outer one's shares
    // a name with.
    private bool Hides(Variable inner, Variable outer, int offset)
    {
        TypeNode? record = inner.Type.Find().Element?.Find();
        if (record is null || record.Kind != TypeKind.Record) { return false; }
        if (outer.Type.Find().Element?.Find() is { } own && _prefixed.Contains(own)) { return false; }

        return record != outer.Type.Find().Element?.Find() && (SizeOf(record) ?? 0) > offset;
    }

    private string Value(int value, TypeNode type) => type.Find().Kind == TypeKind.Scalar
        ? ConstantText(value, type)
        : value.ToString(CultureInfo.InvariantCulture);

    private static string Character(int value) => value switch
    {
        '\'' => "''''",
        >= 32 and < 127 => $"'{(char)value}'",
        _ => $"CHR({value})"
    };
}
