// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    // The records made of variables whose address a call passes for a VAR record, by the variable at their first word.
    private readonly Dictionary<Variable, Variable> _contained = [];

    // A variable whose address a call passes for a VAR record, or a record value, of more than a word is that record, and the variables in
    // its words its fields: the Compiler reaches a record variable's fields at their own offsets, so the code shows a
    // word for each, and the record only as the address of its first.
    private void Contain()
    {
        foreach (Procedure procedure in _procedures)
        {
            Walk(
                procedure.Body,
                statement =>
                {
                    if (statement is not CallStatement { Callee.Procedure: { } callee } call) { return; }

                    List<Expr> values = [.. call.Arguments.Select(argument => argument.Value)];
                    List<Variable> slots = Slots(callee, values);
                    for (int index = 0; index < values.Count; index++)
                    {
                        Expr value = Contained(slots[index], values[index]);
                        if (value != values[index])
                        {
                            call.Arguments[index] = call.Arguments[index] with { Value = value };
                        }
                    }
                },
                expression =>
                {
                    if (expression is not Call { Callee.Procedure: { } callee } call) { return; }

                    List<Variable> slots = Slots(callee, call.Arguments);
                    for (int index = 0; index < call.Arguments.Count; index++)
                    {
                        call.Arguments[index] = Contained(slots[index], call.Arguments[index]);
                    }
                });
        }

        if (_contained.Count == 0) { return; }

        // Where else the code reaches such a record's first word as the whole record, by its address, a move of it
        // whole or a comparison of its words, it is the record.
        foreach (Procedure procedure in _procedures)
        {
            Walk(
                procedure.Body,
                statement =>
                {
                    if (statement is Assignment { Block: true, Target: VariableDesignator target }) { Whole(target); }
                },
                expression =>
                {
                    switch (expression)
                    {
                        case Address { Designator: VariableDesignator address }:
                            Whole(address);
                            break;
                        case Comparison { Comparand: Comparand.Words or Comparand.Bytes } comparison:
                            if (comparison.Left is Load { Designator: VariableDesignator left }) { Whole(left); }
                            if (comparison.Right is Load { Designator: VariableDesignator right }) { Whole(right); }
                            break;
                        case Load { Words: > 1, Designator: VariableDesignator load }:
                            Whole(load);
                            break;
                        default:
                            break;
                    }
                });
        }

        void Whole(VariableDesignator designator)
        {
            if (_contained.TryGetValue(designator.Variable, out Variable? container))
            {
                designator.Variable = container;
            }
        }
    }

    // The record a variable's address passed for a VAR record stands for, its words its fields; the argument itself
    // where it is not the record's first word.
    private Expr Contained(Variable parameter, Expr argument)
    {
        bool passed = parameter.IsReference || parameter.Copy is not null;
        if (!passed || argument is not Address { Designator: VariableDesignator designator })
        {
            return argument;
        }

        Variable first = designator.Variable;
        if (_contained.TryGetValue(first, out Variable? made)) { return new Address(new VariableDesignator(made)); }

        if (first.Container is not null || first.Kind != VariableKind.Variable) { return argument; }

        TypeNode formal = parameter.Copy?.Type ?? parameter.Type.Target();
        TypeNode record = formal.Find();
        if (record.Kind != TypeKind.Record || SizeOf(record) is not int words || words <= 1) { return argument; }

        // The variable is the record already, or its first field, which a record takes the place of.
        TypeNode field = record.Field(0);
        bool whole = first.Type.Find() == record;
        if (!whole && (field.Find().Kind is TypeKind.Record or TypeKind.Array || first.Type.Find() != field.Find()))
        {
            return argument;
        }

        Frame frame = first.Frame;
        Variable container = whole
            ? first
            : new Variable(frame, first.Offset, VariableKind.Variable)
            {
                Type = formal,
                Used = true,
                AddressTaken = true,
                BlockWords = words
            };

        // The variables in its other words are its fields.
        foreach (Variable word in frame.Variables.Values.Where(word => word.Offset >= first.Offset && word.Offset < first.Offset + words).ToList())
        {
            if (word == container || word.Container is not null || word.Kind != VariableKind.Variable) { continue; }

            word.Container = container;
            word.FieldOffset = word.Offset - first.Offset;
            TypeNode type = record.Field(word.FieldOffset);
            TypeNode.Unify(type, word.Type);
            word.Type = type;
        }

        container.BlockWords = Math.Max(container.BlockWords, words);
        frame.Variables[first.Offset] = container;
        _contained[first] = container;
        return new Address(new VariableDesignator(container));
    }
}
