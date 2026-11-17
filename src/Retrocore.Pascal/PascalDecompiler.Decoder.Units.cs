// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    private sealed partial class Decoder
    {
        // LDE, LAE and STE: a word of an intrinsic unit's data segment, which only an inferred unit's interface, whose
        // variables the decompiler declares, lets a source reach.
        private Variable UnitVariable(PcodeInstruction instruction)
        {
            int segment = instruction.Operands[0];
            if (!_owner.IsIntrinsic(segment) || _owner._library?.Unit(segment - 1) is not null)
            {
                throw new InvalidDataException($"{instruction} reaches a unit's variables, which are not decompiled.");
            }

            return Use(_owner.UnitVariable(segment, instruction.Operands[1]));
        }

        // A call of an intrinsic unit no library at hand declares, such as one of Apple III Pascal's system's, whose
        // procedures are declared from their calls: two zero words on top are a function's room for its result, and
        // the words below them, which the statement pushed, its arguments, as many as its first call's.
        private void InferredUnitCall(int segment, int number, List<Expr> stack, List<Statement> statements)
        {
            bool function = stack.Count >= 2 && IsZero(stack[^1]) && IsZero(stack[^2]);
            if (function)
            {
                Pop(stack);
                Pop(stack);
            }

            int count = _owner.UnitArguments(segment, number) ?? stack.Count;
            List<Expr> arguments = [];
            for (int argument = 0; argument < count; argument++) { arguments.Insert(0, Pop(stack)); }

            Callee callee = new()
            {
                Segment = segment,
                Number = number,
                ResultType = function ? TypeNode.Scalar(ScalarKind.Integer) : new TypeNode()
            };

            _owner._unitCalls.Add(new UnitCall(callee, arguments, function));
            if (function)
            {
                stack.Add(new Call(callee, arguments, words: 1));
            }
            else
            {
                statements.Add(new CallStatement(callee, [.. arguments.Select(argument => new Argument(argument))]));
            }
        }
    }
}
