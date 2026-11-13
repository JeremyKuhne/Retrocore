// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    private readonly List<(TypeNode First, TypeNode Second)> _links = [];

    // PASCALIO, the segment the system loads for reals' I/O and SEEK.
    private const int PascalIo = 31;

    // Whether a CXP's segment is a unit: neither the system nor a segment of the code file.
    private bool IsUnit(int segment) =>
        segment is not (0 or PascalIo) && !_procedures.Any(procedure => procedure.Segment.Number == segment);

    private void UseUnit(int segment)
    {
        if (_units.Add(segment)) { _unitOrder.Add(segment); }
    }

    // A unit's type by name.
    private TypeNode Named(string name)
    {
        switch (name)
        {
            case "INTEGER": return TypeNode.Scalar(ScalarKind.Integer);
            case "CHAR": return TypeNode.Scalar(ScalarKind.Char);
            case "BOOLEAN": return TypeNode.Scalar(ScalarKind.Boolean);
            case "REAL": return TypeNode.Of(TypeKind.Real);
            case "STRING":
                {
                    TypeNode text = TypeNode.Of(TypeKind.String);
                    text.MaxLength = 80;
                    return text;
                }

            default:
                {
                    TypeNode node = new() { Kind = TypeKind.Scalar };
                    if (_library?.Units.Any(unit => unit.Enumerations.ContainsKey(name)) == true) { node.Enumeration = name; }
                    return node;
                }
        }
    }

    // A file variable FINIT opens: a TEXT (record size -2), an untyped FILE (-1), or a FILE of records of a size in words.
    private static void FileVariable(Designator file, Expr size)
    {
        TypeNode root = file.Type.Find();
        int bytes = size switch
        {
            Constant constant => constant.Value,
            Unary { Op: Operator.Negate, Operand: Constant negated } => -negated.Value,
            _ => 0
        };

        if (bytes == -2)
        {
            root.Kind = TypeKind.Text;
            root.Element ??= TypeNode.Scalar(ScalarKind.Char);
        }
        else
        {
            root.Kind = TypeKind.File;
            root.RecordWords = bytes;
            if (bytes > 0) { root.Element ??= new TypeNode(); }
        }
    }

    // Decides which parameters are VAR from what their calls pass, then infers every type from how it is used.
    private void Infer()
    {
        Dictionary<Procedure, List<List<Expr>>> calls = [];
        foreach (Procedure procedure in _procedures)
        {
            Walk(procedure.Body, statement =>
            {
                if (statement is CallStatement { Callee.Procedure: { } callee } call)
                {
                    Calls(calls, callee).Add([.. call.Arguments.Select(argument => argument.Value)]);
                }
            }, expression =>
            {
                if (expression is Call { Callee.Procedure: { } callee } call) { Calls(calls, callee).Add(call.Arguments); }
            });
        }

        // A VAR parameter passed on to another is an address too, so this runs until nothing changes.
        for (int pass = 0; pass < 8; pass++)
        {
            bool changed = false;
            foreach (Procedure procedure in _procedures)
            {
                changed |= Parameters(procedure, calls.TryGetValue(procedure, out List<List<Expr>>? sites) ? sites : []);
            }

            if (!changed) { break; }
        }

        // What expressions show of their own types goes first, then what statements show of how they meet.
        foreach (Procedure procedure in _procedures) { Walk(procedure.Body, _ => { }, Constrain); }
        foreach (Procedure procedure in _procedures) { Walk(procedure.Body, statement => Constrain(procedure, statement), _ => { }); }
        Settle();
    }

    private static List<List<Expr>> Calls(Dictionary<Procedure, List<List<Expr>>> calls, Procedure callee)
    {
        if (!calls.TryGetValue(callee, out List<List<Expr>>? sites))
        {
            sites = [];
            calls[callee] = sites;
        }

        return sites;
    }

    // The parameter each argument fills: the first argument's words are the highest.
    private static List<Variable> Slots(Procedure procedure, IReadOnlyList<Expr> arguments)
    {
        List<Variable> slots = [];
        int top = procedure.Frame.ParameterWords;
        foreach (Expr argument in arguments)
        {
            top -= argument.Words;
            slots.Add(procedure.Frame.At(top + 1));
        }

        return slots;
    }

    // A parameter is VAR when its calls pass an address and it has no copy; one never passed is VAR when the
    // procedure uses it as an address.
    private static bool Parameters(Procedure procedure, List<List<Expr>> sites)
    {
        bool changed = false;
        HashSet<Variable> addressed = [];
        HashSet<Variable> valued = [];
        foreach (List<Expr> arguments in sites)
        {
            List<Variable> slots = Slots(procedure, arguments);
            for (int index = 0; index < arguments.Count; index++)
            {
                Variable parameter = slots[index];
                parameter.Words = Math.Max(parameter.Words, arguments[index].Words);
                if (arguments[index].Words == 2) { parameter.Type.Find().Kind = TypeKind.Real; }
                if (IsAddress(arguments[index]))
                {
                    addressed.Add(parameter);
                }
                else
                {
                    valued.Add(parameter);
                }
            }
        }

        int first = procedure.IsFunction ? 3 : 1;
        for (int offset = first; offset <= procedure.Frame.ParameterWords; offset++)
        {
            if (procedure.Level <= 0) { break; }

            Variable parameter = procedure.Frame.At(offset);
            if (parameter.Copy is not null) { continue; }

            bool reference = addressed.Contains(parameter)
                || (!valued.Contains(parameter) && parameter.Type.Find().Kind == TypeKind.Pointer && sites.Count == 0);

            changed |= reference != parameter.IsReference;
            parameter.IsReference = reference;
        }

        return changed;
    }

    // Whether an argument is an address: a designator's, a file's window (its first word), or a VAR parameter's.
    private static bool IsAddress(Expr argument) => argument switch
    {
        Address or ByteAddress => true,
        Load { Designator: VariableDesignator { Variable: var variable } } =>
            variable.IsReference || variable.Type.Find().Kind is TypeKind.File or TypeKind.Text,
        _ => false
    };

    // Visits every statement and expression.
    private static void Walk(List<Statement> statements, Action<Statement> visit, Action<Expr> visitExpression)
    {
        foreach (Statement statement in statements)
        {
            visit(statement);
            switch (statement)
            {
                case Assignment assignment:
                    Walk(assignment.Target, visitExpression);
                    Walk(assignment.Value, visitExpression);
                    break;
                case CallStatement call:
                    foreach (Argument argument in call.Arguments)
                    {
                        Walk(argument.Value, visitExpression);
                        if (argument.Width is not null) { Walk(argument.Width, visitExpression); }
                        if (argument.Decimals is not null) { Walk(argument.Decimals, visitExpression); }
                    }

                    break;
                case IfStatement branch:
                    Walk(branch.Condition, visitExpression);
                    Walk(branch.Then, visit, visitExpression);
                    if (branch.Else is not null) { Walk(branch.Else, visit, visitExpression); }
                    break;
                case WhileStatement loop:
                    Walk(loop.Condition, visitExpression);
                    Walk(loop.Body, visit, visitExpression);
                    break;
                case RepeatStatement loop:
                    Walk(loop.Body, visit, visitExpression);
                    Walk(loop.Condition, visitExpression);
                    break;
                case ForStatement loop:
                    Walk(loop.Control, visitExpression);
                    Walk(loop.From, visitExpression);
                    Walk(loop.To, visitExpression);
                    Walk(loop.Body, visit, visitExpression);
                    break;
                case CaseStatement choice:
                    Walk(choice.Selector, visitExpression);
                    foreach ((List<int> _, List<Statement> body) in choice.Arms) { Walk(body, visit, visitExpression); }
                    break;
                case WithStatement with:
                    Walk(with.Record, visitExpression);
                    Walk(with.Body, visit, visitExpression);
                    break;
                default:
                    break;
            }
        }
    }

    private static void Walk(Expr expression, Action<Expr> visit)
    {
        visit(expression);
        switch (expression)
        {
            case Load load: Walk(load.Designator, visit); break;
            case Address address: Walk(address.Designator, visit); break;
            case ByteAddress address: Walk(address.Designator, visit); break;
            case PackedAddress address: Walk(address.Designator, visit); break;
            case Unary unary: Walk(unary.Operand, visit); break;
            case Binary binary:
                Walk(binary.Left, visit);
                Walk(binary.Right, visit);
                break;
            case Comparison comparison:
                Walk(comparison.Left, visit);
                Walk(comparison.Right, visit);
                break;
            case Checked check: Walk(check.Value, visit); break;
            case Written written: Walk(written.Value, visit); break;
            case SetValue set:
                if (set.Value is not null) { Walk(set.Value, visit); }
                foreach ((Expr low, Expr? high) in set.Members)
                {
                    Walk(low, visit);
                    if (high is not null) { Walk(high, visit); }
                }

                if (set.Left is not null) { Walk(set.Left, visit); }
                if (set.Right is not null) { Walk(set.Right, visit); }
                break;
            case Call call:
                foreach (Expr argument in call.Arguments) { Walk(argument, visit); }
                break;
            case StringFunction function:
                foreach (Expr argument in function.Arguments) { Walk(argument, visit); }
                break;
            default:
                break;
        }
    }

    private static void Walk(Designator designator, Action<Expr> visit)
    {
        switch (designator)
        {
            case FieldDesignator field: Walk(field.Record, visit); break;
            case PackedFieldDesignator field: Walk(field.Record, visit); break;
            case IndexDesignator index:
                Walk(index.Array, visit);
                Walk(index.Index, visit);
                break;
            case StringIndexDesignator index:
                Walk(index.Text, visit);
                Walk(index.Index, visit);
                break;
            case LengthDesignator length: Walk(length.Text, visit); break;
            case Dereference dereference: Walk(dereference.Pointer, visit); break;
            case WindowDesignator window: Walk(window.File, visit); break;
            default:
                break;
        }
    }

    // What a statement shows of its parts' types.
    private void Constrain(Procedure procedure, Statement statement)
    {
        switch (statement)
        {
            case Assignment assignment:
                Assign(assignment.Target.Type, assignment.Value);
                break;
            case CallStatement { Callee.Procedure: { } callee } call:
                Pass(callee, [.. call.Arguments.Select(argument => argument.Value)]);
                break;
            case CallStatement { Callee.UnitProcedure: { } declared } call:
                PassUnit(declared, [.. call.Arguments.Select(argument => argument.Value)]);
                break;
            case IfStatement branch:
                branch.Condition.Type.Vote(ScalarKind.Boolean, 2);
                break;
            case WhileStatement loop:
                loop.Condition.Type.Vote(ScalarKind.Boolean, 2);
                break;
            case RepeatStatement loop:
                loop.Condition.Type.Vote(ScalarKind.Boolean, 2);
                break;
            case ForStatement loop:
                Assign(loop.Control.Type, loop.From);
                Assign(loop.Control.Type, loop.To);
                break;
            case CaseStatement choice:
                choice.Selector.Type.Vote(ScalarKind.Integer);
                break;
            case WithStatement with:
                TypeNode.Unify(with.Temporary.Type.Target(), with.Record.Type);
                break;
            default:
                break;
        }

        _ = procedure;
    }

    // What an expression shows of its parts' types.
    private void Constrain(Expr expression)
    {
        switch (expression)
        {
            case Nil nil:
                nil.Type.Find().Kind = TypeKind.Pointer;
                break;
            case Binary { Op: Operator.Add or Operator.Subtract or Operator.Multiply or Operator.Divide or Operator.Modulo } binary:
                binary.Left.Type.Vote(ScalarKind.Integer, 2);
                binary.Right.Type.Vote(ScalarKind.Integer, 2);
                binary.Type.Force(ScalarKind.Integer);
                break;
            case Binary { Op: Operator.And or Operator.Or } binary:
                binary.Left.Type.Vote(ScalarKind.Boolean, 2);
                binary.Right.Type.Vote(ScalarKind.Boolean, 2);
                binary.Type.Force(ScalarKind.Boolean);
                break;
            case Binary binary:
                binary.Type.Find().Kind = TypeKind.Real;
                Real(binary.Left);
                Real(binary.Right);
                break;
            case Unary { Op: Operator.Negate or Operator.Absolute or Operator.Square } unary:
                unary.Operand.Type.Vote(ScalarKind.Integer, 2);
                unary.Type.Force(ScalarKind.Integer);
                break;
            case Unary { Op: Operator.Not } unary:
                unary.Operand.Type.Vote(ScalarKind.Boolean, 2);
                unary.Type.Force(ScalarKind.Boolean);
                break;
            case Unary { Op: Operator.Float } unary:
                unary.Operand.Type.Vote(ScalarKind.Integer, 2);
                unary.Type.Find().Kind = TypeKind.Real;
                break;
            case Unary unary:
                unary.Type.Find().Kind = TypeKind.Real;
                Real(unary.Operand);
                break;
            case Comparison comparison:
                Compare(comparison);
                break;
            case Written written:
                switch (written.Procedure)
                {
                    case 13: written.Value.Type.Vote(ScalarKind.Integer, 2); break;
                    case 17: written.Value.Type.Vote(ScalarKind.Char, 2); break;
                    case 0: Real(written.Value); break;
                    default: break;
                }

                break;
            case Call { Callee.Procedure: { } callee } call:
                Pass(callee, call.Arguments);
                break;
            case Call { Callee.UnitProcedure: { } declared } call:
                PassUnit(declared, call.Arguments);
                break;
            case Call { Callee.Builtin: "TRUNC" or "ROUND" or "SIN" or "COS" or "LOG" or "ATAN" or "LN" or "EXP" or "SQRT" } call:
                Real(call.Arguments[0]);
                break;
            case Load { Designator: IndexDesignator index }:
                index.Index.Type.Vote(ScalarKind.Integer);
                break;
            case Load { Designator: StringIndexDesignator index }:
                index.Index.Type.Vote(ScalarKind.Integer, 2);
                break;
            case SetValue set:
                Set(set);
                break;
            default:
                break;
        }
    }

    // An assignment, or a value parameter's argument: the two share a type, and a range check gives its subrange.
    private void Assign(TypeNode target, Expr value)
    {
        if (value is Checked check)
        {
            target.Range(check.Low, check.High);
            value = check.Value;
        }

        switch (value)
        {
            case StringConstant or StringFunction:
                target.String(0);
                break;
            case Load load when load.Type.Find().Kind == TypeKind.String || target.Find().Kind == TypeKind.String:
                // Strings of any lengths assign to each other.
                target.String(0);
                load.Type.String(0);
                break;
            case Written written:
                Assign(target, written.Value);
                break;
            default:
                Link(target, value.Type);
                break;
        }
    }

    private static void Characters(TypeNode type, HashSet<TypeNode> seen)
    {
        TypeNode root = type.Find();
        if (!seen.Add(root)) { return; }
        if (root.Kind == TypeKind.Array && root.Bytes && root.Element is { } element && element.Find().Low is null)
        {
            element.Find().Kind = TypeKind.Scalar;
            element.Find().Forced = ScalarKind.Char;
        }

        if (root.Element is { } inner) { Characters(inner, seen); }
        foreach (TypeNode field in root.Fields?.Values ?? Enumerable.Empty<TypeNode>()) { Characters(field, seen); }
    }

    // Two types a value flows between: a scalar's kind is shared, but not a subrange; anything else is one type.
    private void Link(TypeNode first, TypeNode second) => _links.Add((first, second));

    // Settles the links: those that met pointers or structures become one type, and the scalars on each set of links
    // pool their votes for a kind, though each keeps a kind it is forced to and its own subrange.
    private void Settle()
    {
        // A packed array's bytes are characters unless a range check bounds them.
        HashSet<TypeNode> seen = [];
        foreach (Procedure procedure in _procedures)
        {
            foreach (Variable variable in procedure.Frame.Variables.Values) { Characters(variable.Type, seen); }
        }

        static bool Scalar(TypeNode type) => type.Find().Kind is TypeKind.Scalar or TypeKind.Unknown;

        HashSet<int> unified = [];
        for (bool changed = true; changed;)
        {
            changed = false;
            for (int index = 0; index < _links.Count; index++)
            {
                (TypeNode first, TypeNode second) = _links[index];
                if (!unified.Contains(index) && first.Find() != second.Find() && (!Scalar(first) || !Scalar(second)))
                {
                    // A record linked to a scalar is its first field's link.
                    if (first.Find().Kind == TypeKind.Record && Scalar(second) || second.Find().Kind == TypeKind.Record && Scalar(first))
                    {
                        unified.Add(index);
                        _links.Add(first.Find().Kind == TypeKind.Record ? (first.Field(0), second) : (first, second.Field(0)));
                        changed = true;
                        continue;
                    }

                    unified.Add(index);
                    TypeNode.Unify(first, second);
                    changed = true;
                }
            }
        }

        Dictionary<TypeNode, TypeNode> classes = [];
        TypeNode Class(TypeNode type)
        {
            TypeNode root = type.Find();
            if (!classes.TryGetValue(root, out TypeNode? parent)) { return classes[root] = root; }
            if (parent == root) { return root; }

            TypeNode top = Class(parent);
            classes[root] = top;
            return top;
        }

        foreach ((TypeNode first, TypeNode second) in _links)
        {
            TypeNode a = Class(first);
            TypeNode b = Class(second);
            if (a != b) { classes[b] = a; }
        }

        Dictionary<TypeNode, (int Integer, int Char, int Boolean, string? Enumeration)> pooled = [];
        foreach (TypeNode root in classes.Keys.ToList())
        {
            TypeNode top = Class(root);
            (int i, int c, int b, string? e) = pooled.TryGetValue(top, out var votes) ? votes : (0, 0, 0, null);
            int weight = root.Forced is null ? 1 : 4;
            pooled[top] = (
                i + (root.IntegerVotes * weight) + (root.Forced == ScalarKind.Integer ? 4 : 0),
                c + (root.CharVotes * weight) + (root.Forced == ScalarKind.Char ? 4 : 0),
                b + (root.BooleanVotes * weight) + (root.Forced == ScalarKind.Boolean ? 4 : 0),
                e ?? root.Enumeration);
        }

        foreach (TypeNode root in classes.Keys)
        {
            if (!Scalar(root) || root.Forced is not null || root.Enumeration is not null) { continue; }

            (int integer, int character, int boolean, string? enumeration) = pooled[Class(root)];
            if (enumeration is not null && root.IntegerVotes == 0 && root.CharVotes == 0)
            {
                root.Enumeration = enumeration;
                root.Kind = TypeKind.Scalar;
                continue;
            }

            if (integer + character + boolean == 0) { continue; }

            root.Kind = TypeKind.Scalar;
            root.Forced = boolean > integer && boolean >= character ? ScalarKind.Boolean
                : character > integer ? ScalarKind.Char
                : ScalarKind.Integer;
        }
    }

    private static void Real(Expr expression)
    {
        if (expression is WordsConstant) { return; }
        expression.Type.Find().Kind = TypeKind.Real;
    }

    private void Compare(Comparison comparison)
    {
        comparison.Type.Force(ScalarKind.Boolean);
        switch (comparison.Comparand)
        {
            case Comparand.Word:
                Link(comparison.Left.Type, comparison.Right.Type);
                break;
            case Comparand.Boolean:
                comparison.Left.Type.Force(ScalarKind.Boolean);
                comparison.Right.Type.Force(ScalarKind.Boolean);
                break;
            case Comparand.Real:
                Real(comparison.Left);
                Real(comparison.Right);
                break;
            case Comparand.String:
                if (comparison.Left is not (StringConstant or StringFunction)) { comparison.Left.Type.String(0); }
                if (comparison.Right is not (StringConstant or StringFunction)) { comparison.Right.Type.String(0); }
                break;
            case Comparand.Set when comparison.Op == Operator.In:
                {
                    TypeNode set = comparison.Right.Type.Find();
                    set.Element ??= new TypeNode();
                    TypeNode.Unify(set.Element, comparison.Left.Type);
                    break;
                }

            case Comparand.Set or Comparand.Bytes or Comparand.Words:
                if (comparison.Left is not (StringConstant or PackedConstant) && comparison.Right is not (StringConstant or PackedConstant))
                {
                    TypeNode.Unify(comparison.Left.Type, comparison.Right.Type);
                }

                break;
            default:
                break;
        }
    }

    private static void Set(SetValue set)
    {
        TypeNode root = set.Type.Find();
        root.Kind = TypeKind.Set;
        root.Element ??= new TypeNode();
        foreach ((Expr low, Expr? high) in set.Members)
        {
            TypeNode.Unify(root.Element, low.Type);
            if (high is not null) { TypeNode.Unify(root.Element, high.Type); }
        }

        if (set.Value is Load load) { TypeNode.Unify(root, load.Type); }
    }

    // A call of a procedure in the code file: VAR parameters share their arguments' types.
    private void Pass(Procedure callee, IReadOnlyList<Expr> arguments)
    {
        List<Variable> slots = Slots(callee, arguments);
        for (int index = 0; index < arguments.Count; index++)
        {
            Variable parameter = slots[index];
            Expr argument = arguments[index];
            if (parameter.Copy is { } copy)
            {
                TypeNode.Unify(copy.Type, Designate(argument).Type);
            }
            else if (parameter.IsReference)
            {
                // A string of any length passes to a VAR string.
                TypeNode formal = parameter.Type.Target();
                TypeNode actual = Designate(argument).Type;
                if (formal.Find().Kind == TypeKind.String || actual.Find().Kind == TypeKind.String)
                {
                    formal.String(0);
                    actual.String(0);
                }
                else
                {
                    TypeNode.Unify(formal, actual);
                }
            }
            else
            {
                Assign(parameter.Type, argument);
            }
        }
    }

    private void PassUnit(PascalUnitProcedure declared, IReadOnlyList<Expr> arguments)
    {
        for (int index = 0; index < arguments.Count && index < declared.Parameters.Count; index++)
        {
            PascalUnitParameter parameter = declared.Parameters[index];
            if (parameter.Type is null) { continue; }

            TypeNode type = Named(parameter.Type);
            if (parameter.IsReference)
            {
                TypeNode.Unify(Designate(arguments[index]).Type, type);
            }
            else if (type.Find() is { Kind: TypeKind.Scalar } scalar)
            {
                TypeNode argument = arguments[index].Type;
                if (scalar.Enumeration is not null && arguments[index] is Constant or Load or Call) { TypeNode.Unify(argument, type); }
                else if (scalar.Forced is { } kind) { argument.Vote(kind, 2); }
            }
            else if (type.Find().Kind == TypeKind.Real)
            {
                Real(arguments[index]);
            }
        }
    }

    // The thing an argument's address designates.
    private static Designator Designate(Expr address) => address switch
    {
        Address a => a.Designator,
        ByteAddress b => b.Designator,
        Load { Designator: var designator } when designator.Type.Find().Kind is TypeKind.String => designator,
        _ => new Dereference(address)
    };
}
