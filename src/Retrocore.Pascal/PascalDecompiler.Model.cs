// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    // What a variable is to its procedure.
    private enum VariableKind
    {
        // A declared variable.
        Variable,

        // A parameter.
        Parameter,

        // A function's result, which the function's name stands for.
        Result,

        // A word the compiler keeps for itself: a FOR loop's limit, a WITH statement's record, a string expression.
        Temporary,

        // A system variable: INPUT, OUTPUT or KEYBOARD.
        System,

        // A value parameter's copy, which the parameter's name stands for in the procedure.
        Copy
    }

    /// <summary>
    ///  A procedure's activation record: its parameters and variables, by word offset from 1.
    /// </summary>
    private sealed class Frame(Procedure? owner, int level, int parameterWords, int dataWords)
    {
        public Procedure? Owner { get; } = owner;

        public int Level { get; } = level;

        public int ParameterWords { get; } = parameterWords;

        public int DataWords { get; } = dataWords;

        public int Words => ParameterWords + DataWords;

        public SortedDictionary<int, Variable> Variables { get; } = [];

        public Variable At(int offset)
        {
            if (!Variables.TryGetValue(offset, out Variable? variable))
            {
                VariableKind kind = Owner is null
                    ? VariableKind.System
                    : offset <= ParameterWords ? VariableKind.Parameter : VariableKind.Variable;

                variable = new Variable(this, offset, kind);
                Variables[offset] = variable;
            }

            return variable;
        }
    }

    /// <summary>
    ///  A parameter or variable, at its frame's word offset.
    /// </summary>
    private sealed class Variable(Frame frame, int offset, VariableKind kind)
    {
        public Frame Frame { get; } = frame;

        public int Offset { get; } = offset;

        public VariableKind Kind { get; set; } = kind;

        public TypeNode Type { get; set; } = new();

        // How many words it takes, once laid out.
        public int Words { get; set; } = 1;

        // A parameter's arguments are addresses.
        public bool IsReference { get; set; }

        // A value parameter's copy, which stands for it.
        public Variable? Copy { get; set; }

        // Its value or address is used by the code, so it is declared.
        public bool Used { get; set; }

        // How it is used: as a scalar word or by address.
        public bool LoadedAsWord { get; set; }

        public bool AddressTaken { get; set; }

        public string Name { get; set; } = "";

        // The most words a whole-variable operation (MOV, LDM, STM, SAS) shows it has.
        public int BlockWords { get; set; }

        // The record variable it is a field of, where the code reaches a record's field at its own offset.
        public Variable? Container { get; set; }

        public int FieldOffset { get; set; }

        // The order FINIT opens a file variable in, from 1.
        public int Opened { get; set; }
    }

    /// <summary>
    ///  A procedure or function, from its segment's procedure dictionary.
    /// </summary>
    private sealed class Procedure(PascalSegment segment, PascalProcedure code)
    {
        public PascalSegment Segment { get; } = segment;

        public PascalProcedure Code { get; } = code;

        public int Number => Code.Index;

        public int Level => Code.LexicalLevel;

        public Procedure? Parent { get; set; }

        public List<Procedure> Children { get; } = [];

        public Frame Frame { get; set; } = null!;

        public IReadOnlyList<PcodeInstruction> Instructions { get; set; } = [];

        // A function leaves its result with RNP 1 or 2.
        public int ResultWords { get; set; }

        public bool IsFunction => ResultWords > 0;

        public TypeNode ResultType { get; } = new();

        // Whether its segment holds it as the segment's procedure 1, a SEGMENT PROCEDURE.
        public bool IsSegmentProcedure => Number == 1 && Level >= 1;

        public List<Statement> Body { get; set; } = [];

        // The labels its GOTOs jump to, by offset.
        public SortedDictionary<int, int> Labels { get; } = [];

        public string Name { get; set; } = "";

        public bool Failed { get; set; }

        public override string ToString() => $"{Segment.Name}.{Number}";
    }
}
