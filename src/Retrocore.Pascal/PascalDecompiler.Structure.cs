// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    // Finds the WITH statements: a WITH on anything but a whole variable keeps the record's address in a word of its
    // own, after the declared variables, and reaches the fields through it.
    private void Withs()
    {
        foreach (Procedure procedure in _procedures)
        {
            if (procedure.Failed) { continue; }

            Frame frame = procedure.Level <= 0 ? Globals : procedure.Frame;
            Dictionary<Variable, bool> candidates = [];
            Walk(procedure.Body, statement =>
            {
                if (statement is Assignment { Target: VariableDesignator { Variable: var target } } assignment
                    && target.Frame == frame
                    && target.Offset > frame.ParameterWords
                    && target.Kind == VariableKind.Variable)
                {
                    bool address = assignment.Value is Address || (assignment.Value is Load or Call && assignment.Value.Words == 1);
                    candidates[target] = (!candidates.TryGetValue(target, out bool before) || before) && address && !assignment.Block;
                }
            }, _ => { });

            // A candidate is used only as the address of the record it stands for.
            Walk(procedure.Body, _ => { }, expression =>
            {
                if (expression is Address { Designator: VariableDesignator { Variable: var taken } }) { candidates[taken] = false; }
            });

            // A candidate's value is used only as an address: to reach the record, or as a VAR argument.
            HashSet<Variable> values = [];
            Walk(procedure.Body, statement =>
            {
                switch (statement)
                {
                    case Assignment assignment:
                        Values(assignment.Target, values);
                        if (assignment.Value is not Address) { Values(assignment.Value, values, address: false); }
                        break;
                    case CallStatement call:
                        foreach (Argument argument in call.Arguments)
                        {
                            Values(argument.Value, values, address: true);
                            if (argument.Width is not null) { Values(argument.Width, values, address: false); }
                        }

                        break;
                    case IfStatement branch: Values(branch.Condition, values, address: false); break;
                    case WhileStatement loop: Values(loop.Condition, values, address: false); break;
                    case RepeatStatement loop: Values(loop.Condition, values, address: false); break;
                    case CaseStatement choice: Values(choice.Selector, values, address: false); break;
                    case ForStatement loop:
                        Values(loop.From, values, address: false);
                        Values(loop.To, values, address: false);
                        break;
                    default:
                        break;
                }
            }, _ => { });

            foreach (Variable used in values) { candidates[used] = false; }

            // Temporaries come after every declared variable.
            List<Variable> temporaries = [.. candidates.Where(pair => pair.Value).Select(pair => pair.Key).OrderByDescending(variable => variable.Offset)];
            HashSet<Variable> accepted = [];
            foreach (Variable candidate in temporaries)
            {
                if (frame.Variables.Values.All(other => other.Offset <= candidate.Offset || other.Kind == VariableKind.Temporary || accepted.Contains(other)))
                {
                    accepted.Add(candidate);
                }
            }

            foreach (Variable temporary in accepted) { temporary.Kind = VariableKind.Temporary; }
            if (accepted.Count > 0) { With(procedure.Body, accepted); }
        }
    }

    // The variables whose values an expression uses other than as an address.
    private static void Values(Expr expression, HashSet<Variable> values, bool address)
    {
        switch (expression)
        {
            case Load { Designator: VariableDesignator { Variable: var variable } }:
                if (!address) { values.Add(variable); }
                break;
            case Load load: Values(load.Designator, values); break;
            case Address a: Values(a.Designator, values); break;
            case ByteAddress a: Values(a.Designator, values); break;
            case PackedAddress a: Values(a.Designator, values); break;
            case Unary unary: Values(unary.Operand, values, address: false); break;
            case Binary binary:
                Values(binary.Left, values, address: false);
                Values(binary.Right, values, address: false);
                break;
            case Comparison comparison:
                Values(comparison.Left, values, comparison.Comparand is Comparand.String or Comparand.Bytes or Comparand.Words);
                Values(comparison.Right, values, comparison.Comparand is Comparand.String or Comparand.Bytes or Comparand.Words);
                break;
            case Checked check: Values(check.Value, values, address: false); break;
            case Written written: Values(written.Value, values, address: written.Procedure is 19 or 20); break;
            case Call call:
                foreach (Expr argument in call.Arguments) { Values(argument, values, address: true); }
                break;
            case StringFunction function:
                foreach (Expr argument in function.Arguments) { Values(argument, values, address: true); }
                break;
            case SetValue set:
                if (set.Value is not null) { Values(set.Value, values, address: false); }
                foreach ((Expr low, Expr? high) in set.Members)
                {
                    Values(low, values, address: false);
                    if (high is not null) { Values(high, values, address: false); }
                }

                if (set.Left is not null) { Values(set.Left, values, address: false); }
                if (set.Right is not null) { Values(set.Right, values, address: false); }
                break;
            default:
                break;
        }
    }

    private static void Values(Designator designator, HashSet<Variable> values)
    {
        switch (designator)
        {
            case Dereference dereference: Values(dereference.Pointer, values, address: true); break;
            case FieldDesignator field: Values(field.Record, values); break;
            case PackedFieldDesignator field: Values(field.Record, values); break;
            case IndexDesignator index:
                Values(index.Array, values);
                Values(index.Index, values, address: false);
                break;
            case StringIndexDesignator index:
                Values(index.Text, values);
                Values(index.Index, values, address: false);
                break;
            case LengthDesignator length: Values(length.Text, values); break;
            default:
                break;
        }
    }

    // Wraps the statements after each assignment of a WITH's temporary, through the last that uses it, in the WITH.
    private static void With(List<Statement> statements, HashSet<Variable> temporaries)
    {
        foreach (Statement statement in statements) { ForEachList(statement, list => With(list, temporaries)); }

        for (int index = 0; index < statements.Count; index++)
        {
            if (statements[index] is not Assignment { Target: VariableDesignator { Variable: var temporary } } assignment || !temporaries.Contains(temporary))
            {
                continue;
            }

            int last = index;
            for (int next = index + 1; next < statements.Count; next++)
            {
                if (statements[next] is Assignment { Target: VariableDesignator { Variable: var again } } && again == temporary) { break; }
                if (Uses(statements[next], temporary)) { last = next; }
            }

            Designator record = assignment.Value is Address address ? address.Designator : new Dereference(assignment.Value);
            List<Statement> body = statements.GetRange(index + 1, last - index);
            statements.RemoveRange(index, last - index + 1);
            statements.Insert(index, new WithStatement(record, temporary, body) { Offset = assignment.Offset });
        }
    }

    private static void ForEachList(Statement statement, Action<List<Statement>> action)
    {
        switch (statement)
        {
            case IfStatement branch:
                action(branch.Then);
                if (branch.Else is not null) { action(branch.Else); }
                break;
            case WhileStatement loop: action(loop.Body); break;
            case RepeatStatement loop: action(loop.Body); break;
            case ForStatement loop: action(loop.Body); break;
            case WithStatement with: action(with.Body); break;
            case CaseStatement choice:
                foreach ((List<int> _, List<Statement> body) in choice.Arms) { action(body); }
                break;
            default:
                break;
        }
    }

    private static bool Uses(Statement statement, Variable variable)
    {
        bool used = false;
        Walk([statement], _ => { }, expression =>
        {
            if (expression is Load { Designator: VariableDesignator { Variable: var loaded } } && loaded == variable) { used = true; }
        });

        Walk([statement], inner =>
        {
            if (inner is Assignment { Target: var target } && Reaches(target, variable)) { used = true; }
        }, _ => { });

        return used;
    }

    private static bool Reaches(Designator designator, Variable variable) => designator switch
    {
        Dereference { Pointer: Load { Designator: VariableDesignator { Variable: var pointer } } } => pointer == variable,
        FieldDesignator field => Reaches(field.Record, variable),
        PackedFieldDesignator field => Reaches(field.Record, variable),
        IndexDesignator index => Reaches(index.Array, variable),
        StringIndexDesignator index => Reaches(index.Text, variable),
        _ => false
    };

    // Where a whole-variable operation shows a variable's words, the variables inside them are its fields: the
    // Compiler reaches a record variable's field at the field's own offset.
    private void Absorb()
    {
        foreach (Procedure procedure in _procedures)
        {
            Frame frame = procedure.Frame;
            List<Variable> variables = [.. frame.Variables.Values.OrderBy(variable => variable.Offset)];
            foreach (Variable container in variables)
            {
                int words = Math.Max(container.BlockWords, container.Kind == VariableKind.Copy ? container.BlockWords : 0);
                if (words <= 1 || container.Container is not null) { continue; }
                if (container.Type.Find().Kind is TypeKind.File or TypeKind.Text or TypeKind.Real or TypeKind.Set) { continue; }

                foreach (Variable field in variables)
                {
                    if (field.Offset <= container.Offset || field.Offset >= container.Offset + words || field.Container is not null) { continue; }
                    if (field.Kind is VariableKind.Temporary or VariableKind.Parameter or VariableKind.Result) { continue; }

                    field.Container = container;
                    field.FieldOffset = field.Offset - container.Offset;
                    TypeNode type = container.Type.Field(field.FieldOffset);
                    TypeNode.Unify(type, field.Type);
                    field.Type = type;
                }

                if (container.Type.Find().Kind == TypeKind.Record) { container.Type.Size(words); }
            }
        }
    }
}
