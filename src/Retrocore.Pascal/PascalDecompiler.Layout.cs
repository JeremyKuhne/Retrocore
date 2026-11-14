// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    private readonly Dictionary<Frame, List<Variable>> _declared = [];
    private readonly Dictionary<Procedure, List<Variable>> _parameters = [];

    // The system globals a (*$U-*) program passes as files, each a pointer to its file.
    private readonly HashSet<Variable> _systemFiles = [];

    // The built-in procedures and functions whose first argument is a file.
    private static readonly HashSet<string> s_fileFirst =
    [
        "BLOCKREAD", "BLOCKWRITE", "EOF", "EOLN", "RESET", "REWRITE", "CLOSE", "GET", "PUT", "SEEK"
    ];

    // Lays out each frame: its parameters, and the variables to declare in offset order, with padding where the code
    // uses no word, so that each variable keeps its offset.
    private void Layout()
    {
        // A pointer to more words than the scalar the code reads through it points to a record that starts with it.
        HashSet<TypeNode> seen = [];
        foreach (Procedure procedure in _procedures)
        {
            foreach (Variable variable in procedure.Frame.Variables.Values) { Blocks(variable.Type, seen); }
        }

        _system.At(2).Name = "INPUT";
        _system.At(3).Name = "OUTPUT";
        _system.At(4).Name = "KEYBOARD";

        // Any other word of the system's globals is one only a program compiled as part of the system, (*$U-*), with
        // the system's declarations, can reach; such a program declares them.
        if (_systemProgram)
        {
            SystemGlobals();
        }
        else
        {
            foreach (Variable variable in _system.Variables.Values.Where(variable => variable.Name.Length == 0))
            {
                variable.Name = $"SYS{variable.Offset}";
                Warn($"The code reaches the system's global at word {variable.Offset}, which only a program compiled as part of the system, (*$U-*), can name; it is written {variable.Name}.");
            }
        }

        foreach (Procedure procedure in _procedures)
        {
            Frame frame = procedure.Frame;
            string prefix = procedure.Level <= 0 ? "G" : ((char)('A' + Math.Min(procedure.Level, 25) - 1)).ToString();
            if (procedure.Segment != _main && procedure.Level > 0) { prefix = $"{prefix}{procedure.Segment.Number}X"; }

            _parameters[procedure] = Parameters(procedure, prefix, outer: _systemProgram && procedure == _program);
            _declared[frame] = Variables(frame, prefix);
            procedure.Name = procedure == _program
                ? Identifier(procedure.Segment.Name)
                : procedure.IsSegmentProcedure
                    ? $"SEG{procedure.Segment.Number}"
                    : procedure.Segment == _main
                        ? $"{(procedure.IsFunction ? "FUNC" : "PROC")}{procedure.Number}"
                        : $"S{procedure.Segment.Number}{(procedure.IsFunction ? "F" : "P")}{procedure.Number}";
        }
    }

    private static void Blocks(TypeNode type, HashSet<TypeNode> seen)
    {
        TypeNode root = type.Find();
        if (!seen.Add(root)) { return; }
        if (root.Kind == TypeKind.Pointer && root.Element?.Find() is { Kind: TypeKind.Unknown, Words: > 1 } block)
        {
            Fit(block, block.Words);
        }
        else if (root.Kind == TypeKind.Pointer
            && root.Element?.Find() is { Kind: TypeKind.Scalar or TypeKind.Real, Words: > 1 } target
            && target.Words > (SizeOf(target) ?? 1))
        {
            int words = target.Words;
            target.Field(0);
            target.Find().Words = words;
        }

        if (root.Element is { } element) { Blocks(element, seen); }
        foreach (TypeNode field in root.AllFields) { Blocks(field, seen); }
    }

    // A procedure's parameters in the order they are declared: the first has the highest words.
    private static List<Variable> Parameters(Procedure procedure, string prefix, bool outer)
    {
        List<Variable> parameters = [];
        if (procedure.Level <= 0 && !outer) { return parameters; }

        Frame frame = procedure.Frame;
        int offset = procedure.IsFunction ? 3 : 1;
        while (offset <= frame.ParameterWords)
        {
            Variable parameter = frame.At(offset);
            parameter.Kind = VariableKind.Parameter;
            int words = parameter.IsReference || parameter.Copy is not null ? 1 : Math.Max(parameter.Words, SizeOf(parameter.Type) ?? 1);
            words = Math.Min(words, frame.ParameterWords - offset + 1);
            parameter.Words = words;
            parameter.Name = $"{prefix}{offset}";
            parameters.Insert(0, parameter);
            offset += words;
        }

        return parameters;
    }

    // The system's globals a (*$U-*) program reaches, which its outer block declares up to the last: one the code
    // passes as a file holds the file's address, a pointer to the file. INPUT, OUTPUT and KEYBOARD, at words 2 to 4,
    // the Compiler declares itself.
    private void SystemGlobals()
    {
        HashSet<Variable> files = _systemFiles;
        foreach (Procedure procedure in _procedures)
        {
            Walk(procedure.Body, statement =>
            {
                if (statement is CallStatement { Callee.Builtin: { } name } call
                    && s_fileFirst.Contains(name)
                    && call.Arguments.Count > 0)
                {
                    SystemFile(call.Arguments[0].Value, files);
                }
            }, expression =>
            {
                if (expression is Call { Callee.Builtin: { } name } call
                    && s_fileFirst.Contains(name)
                    && call.Arguments.Count > 0)
                {
                    SystemFile(call.Arguments[0], files);
                }
            });
        }

        // One type of untyped file, and one of a pointer to it, serve them all.
        TypeNode pointer = TypeNode.Of(TypeKind.Pointer);
        pointer.Element = TypeNode.Of(TypeKind.File);
        foreach (Variable file in files) { file.Type = pointer; }

        Dictionary<int, Variable> predeclared = [];
        for (int word = 2; word <= 4; word++)
        {
            if (_system.Variables.Remove(word, out Variable? file)) { predeclared[word] = file; }
        }

        int last = _system.Variables.Values
            .Select(variable => variable.Offset + Math.Max(1, SizeOf(variable.Type) ?? 1) - 1)
            .DefaultIfEmpty(0)
            .Max();

        _declared[_system] = last == 0 ? [] : Variables(_system, "SYS", last);
        foreach ((int word, Variable file) in predeclared) { _system.Variables[word] = file; }
    }

    // A system global the code passes as a file.
    private static void SystemFile(Expr argument, HashSet<Variable> files)
    {
        if (argument is Load { Designator: VariableDesignator { Variable: { Kind: VariableKind.System } system } }
            && system.Offset is < 2 or > 4)
        {
            files.Add(system);
        }
    }

    // The variables to declare, from the first after the parameters up to the compiler's temporaries, or, in the
    // system's frame, up to a number of words.
    private List<Variable> Variables(Frame frame, string prefix, int? systemWords = null)
    {
        List<Variable> declared = [];
        int start = frame.ParameterWords + 1;
        int end = (systemWords ?? frame.Words) + 1;
        foreach (Variable variable in frame.Variables.Values)
        {
            if (variable.Offset >= start && variable.Kind == VariableKind.Temporary)
            {
                end = Math.Min(end, variable.Offset);
            }
        }

        // A record's fields are inside it.
        List<Variable> fields = [.. frame.Variables.Values.Where(variable => variable.Container is not null)];
        foreach (Variable field in fields) { frame.Variables.Remove(field.Offset); }

        int offset = start;
        while (offset < end)
        {
            int next = frame.Variables.Keys.Where(key => key > offset && key < end).DefaultIfEmpty(end).Min();
            if (!frame.Variables.TryGetValue(offset, out Variable? variable) || variable.Kind is VariableKind.Temporary)
            {
                // Words the code never uses keep the ones after them in place.
                variable = new Variable(frame, offset, VariableKind.Variable) { Words = next - offset };
                variable.Type = Padding(next - offset);
                variable.Name = $"{prefix}{offset}";
                frame.Variables[offset] = variable;
                declared.Add(variable);
                offset = next;
                continue;
            }

            int gap = next - offset;
            if (variable.Kind == VariableKind.Copy)
            {
                variable.Words = Math.Min(gap, SizeOf(variable.Type) ?? gap);
                variable.Name = $"{prefix}{offset}";
                offset += variable.Words;
                continue;
            }

            int words = SizeOf(variable.Type) is { } size ? Math.Min(Math.Max(size, variable.BlockWords), gap) : gap;
            Fit(variable.Type, words);
            variable.Words = words;
            variable.Name = $"{prefix}{offset}";
            declared.Add(variable);
            offset += words;
        }

        foreach (Variable variable in frame.Variables.Values.Where(variable => variable.Name.Length == 0))
        {
            variable.Name = $"{prefix}{variable.Offset}";
        }

        foreach (Variable field in fields) { field.Name = $"{prefix}{field.Offset}"; }

        _ = this;
        return declared;
    }

    // A type for words the code never uses.
    private static TypeNode Padding(int words)
    {
        if (words == 1) { return TypeNode.Scalar(ScalarKind.Integer); }

        TypeNode array = TypeNode.Of(TypeKind.Array);
        array.ElementWords = 1;
        array.Element = TypeNode.Scalar(ScalarKind.Integer);
        array.IndexLow = 1;
        array.IndexHigh = words;
        return array;
    }

    // Gives a type whose size the code does not show the words it has.
    private static void Fit(TypeNode type, int words)
    {
        TypeNode root = type.Find();
        switch (root.Kind)
        {
            case TypeKind.Unknown when words > 1:
                root.Kind = TypeKind.Array;
                root.Element ??= TypeNode.Scalar(ScalarKind.Integer);
                root.ElementWords = 1;
                root.IndexLow = 1;
                root.IndexHigh = words;
                break;
            case TypeKind.String when root.MaxLength == 0:
                root.MaxLength = Math.Max(1, (words * 2) - 2);
                break;
            case TypeKind.Array when root.IndexHigh is null:
                {
                    int low = root.IndexLow ?? 0;
                    int count = root.Bytes ? words * 2 : root.PerWord > 0 ? words * root.PerWord : words / Math.Max(1, root.ElementWords);
                    root.IndexLow = low;
                    root.IndexHigh = low + count - 1;
                    break;
                }

            case TypeKind.Record or TypeKind.Set:
                root.Words = Math.Max(root.Words, words);
                break;
            default:
                break;
        }
    }

    // A type's words, or null where the code does not show them.
    private static int? SizeOf(TypeNode type)
    {
        TypeNode root = type.Find();
        switch (root.Kind)
        {
            case TypeKind.Scalar or TypeKind.Pointer:
                return 1;
            case TypeKind.Real:
                return 2;
            case TypeKind.String:
                return root.MaxLength == 0 ? null : (root.MaxLength + 2) / 2;
            case TypeKind.Set:
                return root.Words == 0 ? null : root.Words;
            case TypeKind.Text:
                return 301;
            case TypeKind.File:
                return root.RecordWords > 0 ? 300 + root.RecordWords : 40;
            case TypeKind.Record:
                {
                    int words = root.Words;
                    if (root.Fields is not null)
                    {
                        foreach ((int offset, TypeNode field) in root.Fields)
                        {
                            words = Math.Max(words, offset + (SizeOf(field) ?? 1));
                        }
                    }

                    foreach ((int offset, List<TypeNode> variants) in root.Variants ?? [])
                    {
                        foreach (TypeNode variant in variants)
                        {
                            words = Math.Max(words, offset + (SizeOf(variant) ?? 1));
                        }
                    }

                    if (root.PackedFields is not null)
                    {
                        foreach (((int word, int _), _) in root.PackedFields) { words = Math.Max(words, word + 1); }
                    }

                    return words == 0 ? null : words;
                }

            case TypeKind.Array:
                {
                    if (root.IndexLow is not { } low || root.IndexHigh is not { } high)
                    {
                        return root.Words == 0 ? null : root.Words;
                    }

                    int count = high - low + 1;
                    int words = root.Bytes
                        ? (count + 1) / 2
                        : root.PerWord > 0
                            ? (count + root.PerWord - 1) / root.PerWord
                            : count * Math.Max(1, root.ElementWords);

                    return Math.Max(words, root.Words);
                }

            default:
                return root.Words == 0 ? null : root.Words;
        }
    }

    // A segment's name as an identifier.
    private static string Identifier(string name)
    {
        string identifier = new([.. name.Where(char.IsLetterOrDigit)]);
        return identifier.Length == 0 || char.IsDigit(identifier[0]) ? $"P{identifier}" : identifier;
    }
}
