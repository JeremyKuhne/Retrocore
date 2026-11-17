// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    // Finds the WITH statements: a WITH on anything but a whole variable keeps the record's address in a word of its
    // own, after the declared variables, and reaches the fields through it.
    // Whether a value stored may be a WITH's pointer: an address, or a word loaded or a function returns. An assembled
    // function's result is of no type the code says, so it is a value.
    private static void Read(Expr expression, HashSet<Variable> read)
    {
        if (expression is Load { Designator: VariableDesignator { Variable: var loaded } }) { read.Add(loaded); }
    }

    // The pointers a designator reaches a record through.
    private static void Reached(Designator designator, HashSet<Variable> reached)
    {
        switch (designator)
        {
            case Dereference { Pointer: Load { Designator: VariableDesignator { Variable: var pointer } } }:
                reached.Add(pointer);
                break;
            case FieldDesignator field: Reached(field.Record, reached); break;
            case PackedFieldDesignator field: Reached(field.Record, reached); break;
            case IndexDesignator index: Reached(index.Array, reached); break;
            case StringIndexDesignator index: Reached(index.Text, reached); break;
            case LengthDesignator length: Reached(length.Text, reached); break;
            default: break;
        }
    }

    private static bool MayPoint(Expr value) => value is Address
        || (value is Load or Call && value.Words == 1 && value is not Call { Callee.Procedure.Code.IsNative: true });

    // Finds each procedure's WITH statements. A word the Compiler kept the temporaries of several WITH statements in is
    // a variable for each, so that their records keep types of their own: the procedure is decoded again, with each
    // store to the word starting a new one.
    private void Withs()
    {
        foreach (Procedure procedure in _procedures)
        {
            if (procedure.Failed) { continue; }

            HashSet<Variable> temporaries = Withs(procedure);
            Frame frame = procedure.Level <= 0 ? Globals : procedure.Frame;
            byte store = procedure.Level <= 0 ? (byte)171 : (byte)204;
            foreach (Variable temporary in temporaries.Where(temporary => temporary.Frame == frame))
            {
                List<int> stores = [.. procedure.Instructions
                    .Where(instruction => instruction.Opcode.Code == store && instruction.Operands[0] == temporary.Offset)
                    .Select(instruction => instruction.Offset)];

                if (stores.Count < 2) { continue; }

                SortedDictionary<int, Variable> generations = [];
                foreach (int offset in stores)
                {
                    generations[offset] = new Variable(frame, temporary.Offset, VariableKind.Temporary);
                }

                procedure.Generations[temporary.Offset] = generations;
            }

            if (procedure.Generations.Count == 0) { continue; }

            // Each store to the word starts a WITH or holds a FOR loop's limit, or the word is a variable after all,
            // kept as one.
            for (bool again = true; again && procedure.Generations.Count > 0;)
            {
                Redecode(procedure);
                HashSet<Variable> assigned = [];
                Walk(procedure.Body, statement =>
                {
                    if (statement is Assignment { Target: VariableDesignator { Variable: var target } })
                    {
                        assigned.Add(target);
                    }
                }, _ => { });

                List<int> variables = [.. procedure.Generations
                    .Where(pair => pair.Value.Values.Any(generation => assigned.Contains(generation) || generation.Kind == VariableKind.Variable))
                    .Select(pair => pair.Key)];

                foreach (int offset in variables)
                {
                    procedure.Generations.Remove(offset);
                    _variables.Add((procedure, offset));
                }

                again = variables.Count > 0;
                if (again && procedure.Generations.Count == 0) { Redecode(procedure); }
            }
        }
    }

    // Decodes a procedure again, and finds its WITH statements.
    private HashSet<Variable> Redecode(Procedure procedure)
    {
        // The WITH statements' temporaries are found again; a word kept for several is one still.
        Frame frame = procedure.Level <= 0 ? Globals : procedure.Frame;
        foreach (Variable temporary in frame.Variables.Values.Where(_withTemporaries.Contains))
        {
            temporary.Kind = procedure.Generations.ContainsKey(temporary.Offset) ? VariableKind.Temporary : VariableKind.Variable;
        }

        procedure.Labels.Clear();
        try
        {
            new Decoder(this, procedure).Decode();
        }
        catch (InvalidDataException exception)
        {
            Warn($"{procedure} could not be decompiled: {exception.Message}");
            procedure.Failed = true;
            procedure.Body = [new Unsupported($"{procedure} could not be decompiled: {exception.Message}")];
            return [];
        }

        return Withs(procedure);
    }

    // The temporaries assigned or read in statements outside their own WITH statements, those inside being active.
    private static void Outside(List<Statement> statements, HashSet<Variable> active, HashSet<Variable> temporaries, HashSet<Variable> found)
    {
        void Read(Expr expression) => Walk(expression, inner =>
        {
            if (inner is Load { Designator: VariableDesignator { Variable: var loaded } }
                && temporaries.Contains(loaded)
                && !active.Contains(loaded))
            {
                found.Add(loaded);
            }
        });

        foreach (Statement statement in statements)
        {
            switch (statement)
            {
                case WithStatement with:
                    Walk(with.Record, Read);
                    bool added = active.Add(with.Temporary);
                    Outside(with.Body, active, temporaries, found);
                    if (added) { active.Remove(with.Temporary); }
                    break;
                case IfStatement branch:
                    Read(branch.Condition);
                    Outside(branch.Then, active, temporaries, found);
                    if (branch.Else is not null) { Outside(branch.Else, active, temporaries, found); }
                    break;
                case WhileStatement loop:
                    Read(loop.Condition);
                    Outside(loop.Body, active, temporaries, found);
                    break;
                case RepeatStatement loop:
                    Outside(loop.Body, active, temporaries, found);
                    Read(loop.Condition);
                    break;
                case ForStatement loop:
                    Read(loop.From);
                    Read(loop.To);
                    Outside(loop.Body, active, temporaries, found);
                    break;
                case CaseStatement choice:
                    Read(choice.Selector);
                    foreach ((List<int> _, List<Statement> body) in choice.Arms)
                    {
                        Outside(body, active, temporaries, found);
                    }

                    break;
                default:
                    Walk([statement], simple => Assigned(simple, temporaries, found), Read);
                    break;
            }
        }
    }

    // A temporary a statement assigns.
    private static void Assigned(Statement statement, HashSet<Variable> temporaries, HashSet<Variable> found)
    {
        if (statement is not Assignment { Target: VariableDesignator { Variable: var target } }) { return; }
        if (temporaries.Contains(target)) { found.Add(target); }
    }

    // The words found to be variables, though a WITH's temporary shares them, by procedure.
    private readonly HashSet<(Procedure Procedure, int Offset)> _variables = [];

    // The words found to keep WITH statements' records' addresses.
    private readonly HashSet<Variable> _withTemporaries = [];

    // Finds a procedure's WITH statements, and gives the temporaries their records' addresses are kept in.
    private HashSet<Variable> Withs(Procedure procedure)
    {
        {

            Frame frame = procedure.Level <= 0 ? Globals : procedure.Frame;
            Dictionary<Variable, bool> candidates = [];
            Walk(procedure.Body, statement =>
            {
                if (statement is Assignment { Target: VariableDesignator { Variable: var target } } assignment
                    && target.Frame == frame
                    && target.Offset > frame.ParameterWords
                    && !_variables.Contains((procedure, target.Offset))
                    && target.Kind is VariableKind.Variable or VariableKind.Temporary)
                {
                    bool address = MayPoint(assignment.Value);
                    bool still = !candidates.TryGetValue(target, out bool before) || before;
                    candidates[target] = still && address && !assignment.Block;
                }
            }, _ => { });

            // A candidate is used only as the address of the record it stands for.
            Walk(procedure.Body, _ => { }, expression =>
            {
                if (expression is Address { Designator: VariableDesignator { Variable: var taken } })
                {
                    candidates[taken] = false;
                }
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

            // A WITH's pointer is read to reach its record; a word stored and never read is a variable.
            HashSet<Variable> read = [];
            Walk(procedure.Body, _ => { }, expression => Read(expression, read));

            foreach (Variable unread in candidates.Keys.Where(candidate => !read.Contains(candidate)).ToList())
            {
                candidates[unread] = false;
            }

            // A WITH's pointer reaches its record somewhere; a word only passed on, as a function's result kept to
            // pass by value, is a variable.
            HashSet<Variable> reached = [];
            Walk(procedure.Body, statement =>
            {
                if (statement is Assignment { Target: var target }) { Reached(target, reached); }
            }, expression =>
            {
                switch (expression)
                {
                    case Load load: Reached(load.Designator, reached); break;
                    case Address address: Reached(address.Designator, reached); break;
                    case ByteAddress address: Reached(address.Designator, reached); break;
                    case PackedAddress address: Reached(address.Designator, reached); break;
                    default: break;
                }
            });

            foreach (Variable unreached in candidates.Keys.Where(candidate => !reached.Contains(candidate)).ToList())
            {
                candidates[unreached] = false;
            }

            // Temporaries come after every declared variable.
            List<Variable> temporaries = [.. candidates.Where(pair => pair.Value).Select(pair => pair.Key).OrderByDescending(variable => variable.Offset)];
            HashSet<Variable> accepted = [];
            foreach (Variable candidate in temporaries)
            {
                if (frame.Variables.Values.All(other => other.Offset <= candidate.Offset || other.Kind == VariableKind.Temporary || other.Container is not null || accepted.Contains(other)))
                {
                    accepted.Add(candidate);
                }
            }

            foreach (Variable temporary in accepted)
            {
                temporary.Kind = VariableKind.Temporary;
                _withTemporaries.Add(temporary);
            }

            if (accepted.Count > 0) { With(procedure.Body, accepted); }

            // A word still assigned, or read, outside the WITH statements it keeps the records of is a variable,
            // which a WITH's temporary shares.
            HashSet<Variable> variables = [];
            Outside(procedure.Body, [], accepted, variables);
            foreach (Variable variable in variables.Where(accepted.Remove)) { variable.Kind = VariableKind.Variable; }

            return accepted;
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
            case ScanTest test: Values(test.Character, values, address: false); break;
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
            Statement current = statements[index];
            if (current is not Assignment { Target: VariableDesignator { Variable: var temporary } } assignment
                || !temporaries.Contains(temporary))
            {
                continue;
            }

            // A WITH of a field of its record, inside it, ends it no sooner than its own body does.
            int last = index;
            HashSet<Variable> reached = [temporary];
            for (int next = index + 1; next < statements.Count; next++)
            {
                if (statements[next] is Assignment { Target: VariableDesignator { Variable: var again } }
                    && again == temporary)
                {
                    break;
                }

                if (!reached.Any(variable => Uses(statements[next], variable))) { continue; }

                last = next;
                if (statements[next] is Assignment { Target: VariableDesignator { Variable: var inner } }
                    && temporaries.Contains(inner))
                {
                    reached.Add(inner);
                }
            }

            Designator record = assignment.Value is Address address ? address.Designator : new Dereference(assignment.Value);
            List<Statement> body = statements.GetRange(index + 1, last - index);
            statements.RemoveRange(index, last - index + 1);

            // A WITH inside it starts in its body.
            With(body, temporaries);
            // Its code starts with the temporary's assignment, which it takes the place of.
            WithStatement with = new(record, temporary, body)
            {
                Offset = assignment.Offset,
                Start = assignment.Start
            };

            statements.Insert(index, with);
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
            if (expression is Load { Designator: VariableDesignator { Variable: var loaded } } && loaded == variable)
            {
                used = true;
            }

        });

        Walk([statement], inner =>
        {
            if (inner is Assignment { Target: var target } && Reaches(target, variable)) { used = true; }
        }, _ => { });

        return used;
    }

    private static bool Reaches(Designator designator, Variable variable) => designator switch
    {
        Dereference
        {
            Pointer: Load { Designator: VariableDesignator { Variable: var pointer } }
        } => pointer == variable,
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
                if (container.Type.Find().Kind is TypeKind.File or TypeKind.Text or TypeKind.Real or TypeKind.Set)
                {
                    continue;
                }

                foreach (Variable field in variables)
                {
                    if (field.Offset <= container.Offset || field.Offset >= container.Offset + words || field.Container is not null)
                    {
                        continue;
                    }

                    if (field.Kind is VariableKind.Temporary or VariableKind.Parameter or VariableKind.Result)
                    {
                        continue;
                    }

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
