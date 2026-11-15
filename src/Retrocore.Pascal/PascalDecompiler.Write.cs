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

    // The records of the WITH statements, by their temporaries.
    private readonly Dictionary<Variable, Designator> _withRecords = [];

    // The units of the program's own, written by Write after the program.
    private List<PascalDecompiledUnit> _unitSources = [];

    private string Write()
    {
        NamedFields();
        NameTypes();

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

        Types(types);

        if (_systemProgram)
        {
            Declarations(_system);
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

    // A (*$U-*) program's segment procedure, segment 1, after FORWARD declarations of it and the system's segments up
    // to the first of its own, which the Compiler numbers on from them; then the system's outer block, empty.
    private void SystemSegment()
    {
        if (Main.Number != 1)
        {
            Warn($"The program's segment is {Main.Number}, not 1, as the system's user program is.");
        }

        string header = $"SEGMENT PROCEDURE {Program.Name}{ParameterList(Program)};";
        int first = _procedures.Where(procedure => procedure.IsSegmentProcedure).Select(procedure => procedure.Segment.Number).DefaultIfEmpty(2).Min();
        if (first > 2)
        {
            if (Comment(Program) is { } early) { Line(early); }
            Line($"{header} FORWARD;");
            for (int segment = 2; segment < first; segment++) { Line($"SEGMENT PROCEDURE SYSSEG{segment}; FORWARD;"); }
            Line($"SEGMENT PROCEDURE {Program.Name};");
        }
        else
        {
            if (Comment(Program) is { } about) { Line(about); }
            Line(header);
        }

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

        foreach (Procedure segment in segments) { WriteProcedure(segment, forwarded: false); }

        Ordinary(ordinary, declared);
    }

    // Procedures in the order of their code, with those already declared (a unit's interface) by name alone.
    private void Ordinary(List<Procedure> ordinary, HashSet<Procedure> declared)
    {
        foreach (Procedure child in ordinary.OrderBy(child => child.Code.Attributes))
        {
            if (child.Code.IsNative && declared.Contains(child)) { continue; }

            foreach (Procedure earlier in ordinary.Where(other => other.Number < child.Number && !declared.Contains(other)).OrderBy(other => other.Number))
            {
                if (earlier.Code.IsNative) { WriteProcedure(earlier, forwarded: false); }
                else { Line($"{Header(earlier, full: true)} FORWARD;"); }

                declared.Add(earlier);
            }

            WriteProcedure(child, declared.Contains(child));
            declared.Add(child);
        }
    }

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
        Line("BEGIN");
        Statements(procedure, procedure.Body);
        Line("END;");
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
        if (parameter.Copy is { } copy) { return TypeName(copy.Type, parameter: true); }
        return TypeName(parameter.IsReference ? parameter.Type.Target() : parameter.Type, parameter: true);
    }

    // Gives a name to each type a declaration cannot write in place: records, pointers, arrays, sets and files, and
    // any type a parameter has that is not a single word.
    private void NameTypes()
    {
        if (_declared.TryGetValue(_system, out List<Variable>? globals))
        {
            foreach (Variable global in globals) { Visit(global.Type, parameter: false); }
        }

        foreach (Procedure procedure in _procedures)
        {
            foreach (Variable variable in _declared[procedure.Frame]) { Visit(variable.Type, parameter: false); }
            foreach (Variable parameter in _parameters[procedure])
            {
                Visit(parameter.Copy?.Type ?? (parameter.IsReference ? parameter.Type.Target() : parameter.Type), parameter: true);
            }

            if (procedure.IsFunction) { Visit(procedure.ResultType, parameter: true); }
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

    // The named types, each after those its declaration names, but a pointer's target, which may come later.
    private List<TypeNode> Ordered()
    {
        List<TypeNode> ordered = [];
        HashSet<TypeNode> done = [];
        foreach (TypeNode type in _types) { Order(type, ordered, done); }
        return ordered;
    }

    private void Order(TypeNode type, List<TypeNode> ordered, HashSet<TypeNode> done)
    {
        TypeNode root = type.Find();
        if (!done.Add(root)) { return; }

        IEnumerable<TypeNode> parts = root.Kind switch
        {
            TypeKind.Pointer => [],
            TypeKind.Record => [.. root.AllFields, .. root.PackedFields?.Values.Select(field => field.Type) ?? []],
            _ => root.Element is { } element ? [element] : []
        };

        foreach (TypeNode part in parts) { Order(part, ordered, done); }
        if (root.Name is not null && _types.Contains(root)) { ordered.Add(root); }
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
        int start = known.Keys.Where(offset => root.Alternatives(offset).Count > 1).DefaultIfEmpty(words).Min();
        List<string> fixedPart = Run(0, Math.Min(start, words));
        if (start >= words) { return $"RECORD {string.Join("; ", fixedPart)} END"; }

        // The other fields, each in the first variant it does not overlap a field of.
        List<List<string>> variants = [Run(start, words)];
        List<int> ends = [words];
        foreach (int offset in known.Keys.Where(key => key >= start))
        {
            List<TypeNode> alternatives = root.Alternatives(offset);
            for (int index = 1; index < alternatives.Count; index++)
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

                variants[variant].Add($"{FieldName(offset, index)}: {TypeName(field, parameter: false)}");
                ends[variant] = offset + size;
            }
        }

        string cases = string.Join("; ", variants.Select((fields, index) => $"{index}: ({string.Join("; ", fields)})"));
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
                    parts.Add($"F{offset}: {Declare(Padding(named - offset), inline: true)}");
                    offset = named;
                    continue;
                }

                if (known.TryGetValue(offset, out TypeNode? field))
                {
                    int size = Math.Min(SizeOf(field) ?? (next - offset), next - offset);
                    Fit(field, size);
                    parts.Add($"F{offset}: {TypeName(field, parameter: false)}");
                    offset += Math.Max(1, size);
                }
                else
                {
                    parts.Add($"F{offset}: {Declare(Padding(next - offset), inline: true)}");
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
        for (int word = 0; word < words; word++)
        {
            List<KeyValuePair<(int Word, int Bit), (int Width, TypeNode Type)>> fields = [.. packed.Where(pair => pair.Key.Word == word)];
            if (fields.Count == 0)
            {
                if (known.TryGetValue(word, out TypeNode? whole) && SizeOf(whole) is 1)
                {
                    parts.Add($"F{word}: {TypeName(whole, parameter: false)}");
                }
                else
                {
                    parts.Add($"F{word}: INTEGER");
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

        return $"PACKED RECORD {string.Join("; ", parts)} END";
    }

    // A field's name: its offset's, and for another variant's field, which of the offset's it is.
    private static string FieldName(int offset, int alternative) => alternative <= 0 ? $"F{offset}" : $"F{offset}V{alternative}";

    // The name of the field a designator reaches: the one at its offset whose type is the designator's.
    private static string FieldName(FieldDesignator field) =>
        FieldName(field.Offset, field.Record.Type.Find().Alternatives(field.Offset).IndexOf(field.Type.Find()));

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
            case Assignment assignment:
                {
                    Expr value = Narrow(assignment.Value);
                    Designator target = Descend(assignment.Target, value is Constant ? null : value.Type);
                    string text = DesignatorText(target);
                    if (Viewed(target) && target.Type.Find() is { Kind: TypeKind.Scalar, ByteView: true })
                    {
                        lines.Add(Indented($"{text}.I := {Expression(value, TypeNode.Scalar(ScalarKind.Integer), 0)}"));
                        break;
                    }

                    if (Viewed(target) && IsPunned(target.Type))
                    {
                        bool pointer = assignment.Value is Nil || Natural(assignment.Value) is null && assignment.Value is not Constant;
                        text += pointer ? ".P" : ".I";
                        lines.Add(Indented($"{text} := {Expression(assignment.Value, pointer ? null : TypeNode.Scalar(ScalarKind.Integer), 0)}"));
                        break;
                    }

                    // A character assigned to a string is the string of it.
                    TypeNode expected = target.Type.Find().Kind == TypeKind.String && assignment.Value is Constant ? TypeNode.Scalar(ScalarKind.Char) : target.Type;
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
                lines.Add(Indented($"CASE {Expression(choice.Selector, expected: null, 0)} OF"));
                _indent++;
                for (int arm = 0; arm < choice.Arms.Count; arm++)
                {
                    (List<int> labels, List<Statement> body) = choice.Arms[arm];
                    lines.Add(Indented($"{string.Join(", ", labels.Select(label => Value(label, choice.Selector.Type.Find())))}:"));
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

                    lines.Add(Indented($"EXIT({(target == _program ? "PROGRAM" : target?.Name ?? "PROGRAM")})"));
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
                Address address => DesignatorText(address.Designator),
                ByteAddress address => DesignatorText(address.Designator),
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

    private string Pointer(Designator pointer) => IsPunned(pointer.Type) ? $"{DesignatorText(pointer)}.P" : DesignatorText(pointer);

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
            if (parameter.IsReference || parameter.Copy is not null)
            {
                TypeNode formal = parameter.Copy?.Type ?? parameter.Type.Target();
                parts.Add(argument is StringConstant or StringFunction ? Expression(argument, expected: null, 0) : DesignatorText(Descend(Designate(argument), formal)));
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
                return DesignatorText(new FieldDesignator(new VariableDesignator(container), field.FieldOffset));
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
    private static bool Hides(Variable inner, Variable outer, int offset)
    {
        TypeNode? record = inner.Type.Find().Element?.Find();
        if (record is null || record.Kind != TypeKind.Record) { return false; }
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
