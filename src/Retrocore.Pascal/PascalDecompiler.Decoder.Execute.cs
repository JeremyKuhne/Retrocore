// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    private sealed partial class Decoder
    {
        // Runs a p-code that is not a jump.
        private void Execute(PcodeInstruction instruction, List<Expr> stack, List<Statement> statements)
        {
            byte code = instruction.Opcode.Code;
            IReadOnlyList<int> operands = instruction.Operands;
            if (code < 128)
            {
                stack.Add(new Constant(code));
                return;
            }

            if (code is >= 216 and <= 231)
            {
                stack.Add(LoadWord(Local(code - 215)));
                return;
            }

            if (code is >= 232 and <= 247)
            {
                stack.Add(LoadWord(Global(code - 231)));
                return;
            }

            if (code >= 248)
            {
                stack.Add(Indirect(Pop(stack), code - 248));
                return;
            }

            switch (code)
            {
                case 199: // LDCI
                    stack.Add(new Constant((short)operands[0]));
                    break;
                case 159: // LDCN
                    stack.Add(new Nil());
                    break;
                case 179: // LDC
                    stack.Add(new WordsConstant(Words(instruction.Data)));
                    break;
                case 166: // LSA
                    stack.Add(new StringConstant(instruction.Data));
                    break;
                case 208: // LPA
                    stack.Add(new PackedConstant(instruction.Data));
                    break;
                case 202: // LDL
                    stack.Add(LoadWord(Local(operands[0])));
                    break;
                case 198: // LLA
                    stack.Add(AddressOf(Local(operands[0])));
                    break;
                case 204: // STL
                    Store(Local(operands[0]), Pop(stack), statements);
                    break;
                case 169: // LDO
                    stack.Add(LoadWord(Global(operands[0])));
                    break;
                case 165: // LAO
                    stack.Add(AddressOf(Global(operands[0])));
                    break;
                case 171: // SRO
                    Store(Global(operands[0]), Pop(stack), statements);
                    break;
                case 182: // LOD
                    stack.Add(LoadWord(Intermediate(operands[0], operands[1])));
                    break;
                case 178: // LDA
                    stack.Add(AddressOf(Intermediate(operands[0], operands[1])));
                    break;
                case 184: // STR
                    Store(Intermediate(operands[0], operands[1]), Pop(stack), statements);
                    break;
                case 157 or 167 or 209: // LDE, LAE, STE
                    throw new InvalidDataException($"{instruction} reaches a unit's variables, which are not decompiled.");
                case 163: // IND
                    stack.Add(Indirect(Pop(stack), operands[0]));
                    break;
                case 162: // INC
                    {
                        Expr address = Pop(stack);
                        stack.Add(operands[0] == 0 ? address : new Address(new FieldDesignator(Designate(address), operands[0])));
                        break;
                    }

                case 164: // IXA
                    {
                        Expr index = Pop(stack);
                        Designator array = Designate(Pop(stack));
                        (Expr value, int? low, int? high) = Bounds(index);
                        TypeNode element = array.Type.ArrayElement(operands[0], low, high);
                        element.Size(operands[0]);
                        stack.Add(new Address(new IndexDesignator(array, value, low, high, element)));
                        break;
                    }

                case 192: // IXP
                    {
                        Expr index = Pop(stack);
                        Designator array = Designate(Pop(stack));
                        (Expr value, int? low, int? high) = Bounds(index);
                        TypeNode element = array.Type.PackedElement(operands[0], operands[1], low, high);
                        stack.Add(new PackedAddress(new IndexDesignator(array, value, low, high, element)));
                        break;
                    }

                case 155: // IXS
                    {
                        Expr index = Pop(stack);
                        Designator text = Designate(Pop(stack));
                        text.Type.String(0);
                        stack.Add(new ByteAddress(new StringIndexDesignator(text, index)));
                        break;
                    }

                case 190: // LDB
                    stack.Add(new Load(ByteDesignator(stack), 1));
                    break;
                case 191: // STB
                    {
                        Expr value = Pop(stack);
                        statements.Add(new Assignment(ByteDesignator(stack), value));
                        break;
                    }

                case 186: // LDP
                    stack.Add(new Load(PackedDesignator(stack), 1));
                    break;
                case 187: // STP
                    {
                        Expr value = Pop(stack);
                        statements.Add(new Assignment(PackedDesignator(stack), value));
                        break;
                    }

                case 188: // LDM
                    {
                        Designator source = Designate(Pop(stack));
                        source.Type.Size(operands[0]);
                        Blocks(source, operands[0]);
                        stack.Add(new Load(source, operands[0]));
                        break;
                    }

                case 189: // STM
                    {
                        Expr value = Pop(stack);
                        Designator target = Designate(Pop(stack));
                        target.Type.Size(operands[0]);
                        Blocks(target, operands[0]);
                        statements.Add(new Assignment(target, value));
                        break;
                    }

                case 154: // STO
                    {
                        Expr value = Pop(stack);
                        statements.Add(new Assignment(Designate(Pop(stack)), value));
                        break;
                    }

                case 168: // MOV
                    {
                        Designator source = Designate(Pop(stack));
                        Designator target = Designate(Pop(stack));
                        source.Type.Size(operands[0]);
                        Blocks(source, operands[0]);
                        Blocks(target, operands[0]);
                        statements.Add(new Assignment(target, new Load(source, operands[0]), block: true));
                        break;
                    }

                case 170: // SAS
                    {
                        Expr source = StringValue(Pop(stack));
                        Designator target = Designate(Pop(stack));
                        target.Type.String(operands[0]);
                        Blocks(target, (operands[0] + 2) / 2);
                        statements.Add(new Assignment(target, source, block: true));
                        break;
                    }

                case 136: // CHK
                    {
                        Expr high = Pop(stack);
                        Expr low = Pop(stack);
                        Expr value = Pop(stack);
                        stack.Add(Fold(low) is { } l && Fold(high) is { } h ? new Checked(value, l, h) : value);
                        break;
                    }

                case 130: Arithmetic(stack, Operator.Add); break;
                case 149: Arithmetic(stack, Operator.Subtract); break;
                case 143: Arithmetic(stack, Operator.Multiply); break;
                case 134: Arithmetic(stack, Operator.Divide); break;
                case 142: Arithmetic(stack, Operator.Modulo); break;
                case 131: Arithmetic(stack, Operator.RealAdd); break;
                case 150: Arithmetic(stack, Operator.RealSubtract); break;
                case 144: Arithmetic(stack, Operator.RealMultiply); break;
                case 135: Arithmetic(stack, Operator.RealDivide); break;
                case 132: Arithmetic(stack, Operator.And); break;
                case 141: Arithmetic(stack, Operator.Or); break;
                case 145: stack.Add(new Unary(Operator.Negate, Pop(stack))); break;
                case 146: stack.Add(new Unary(Operator.RealNegate, Pop(stack))); break;
                case 128: stack.Add(new Unary(Operator.Absolute, Pop(stack))); break;
                case 129: stack.Add(new Unary(Operator.RealAbsolute, Pop(stack))); break;
                case 152: stack.Add(new Unary(Operator.Square, Pop(stack))); break;
                case 153: stack.Add(new Unary(Operator.RealSquare, Pop(stack))); break;
                case 147: stack.Add(new Unary(Operator.Not, Pop(stack))); break;
                case 138: // FLT
                    stack.Add(new Unary(Operator.Float, Pop(stack)));
                    break;
                case 137: // FLO
                    {
                        Expr top = Pop(stack);
                        stack.Add(new Unary(Operator.Float, Pop(stack)));
                        stack.Add(top);
                        break;
                    }

                case 195: Compare(stack, Operator.Equal); break;
                case 203: Compare(stack, Operator.NotEqual); break;
                case 201: Compare(stack, Operator.Less); break;
                case 200: Compare(stack, Operator.LessEqual); break;
                case 197: Compare(stack, Operator.Greater); break;
                case 196: Compare(stack, Operator.GreaterEqual); break;
                case 175: Compare(stack, Operator.Equal, operands); break;
                case 183: Compare(stack, Operator.NotEqual, operands); break;
                case 181: Compare(stack, Operator.Less, operands); break;
                case 180: Compare(stack, Operator.LessEqual, operands); break;
                case 177: Compare(stack, Operator.Greater, operands); break;
                case 176: Compare(stack, Operator.GreaterEqual, operands); break;
                case 151: // SGS
                    {
                        SetValue set = new();
                        set.Members.Add((Pop(stack), null));
                        stack.Add(set);
                        break;
                    }

                case 148: // SRS
                    {
                        Expr high = Pop(stack);
                        SetValue set = new();
                        set.Members.Add((Pop(stack), high));
                        stack.Add(set);
                        break;
                    }

                case 156: SetOperation(stack, Operator.Union); break;
                case 140: SetOperation(stack, Operator.Intersection); break;
                case 133: SetOperation(stack, Operator.Difference); break;
                case 160: // ADJ
                    {
                        SetValue set = PopSet(stack);
                        set.Fixed = operands[0];
                        set.Type.Size(operands[0]);
                        stack.Add(set);
                        break;
                    }

                case 139: // INN
                    {
                        SetValue set = PopSet(stack);
                        Expr element = Pop(stack);
                        stack.Add(new Comparison(Operator.In, Comparand.Set, element, set, 0));
                        break;
                    }

                case 158: // CSP
                    Standard(operands[0], stack, statements);
                    break;
                case 206 or 207 or 174 or 194: // CLP, CGP, CIP, CBP
                    {
                        Procedure callee = _owner.Find(_procedure.Segment, operands[0])
                            ?? throw new InvalidDataException($"{instruction} calls a procedure the segment does not have.");
                        CallProcedure(callee, stack, statements);
                        break;
                    }

                case 205: // CXP
                    External(operands[0], operands[1], stack, statements);
                    break;
                case 210 or 215 or 213: // NOP, BPT
                    break;
                default:
                    throw new InvalidDataException($"{instruction} at ${instruction.Offset:X4} is not decompiled.");
            }
        }

        // A constant's value: the Compiler writes a negative one as its magnitude and NGI.
        private static int? Fold(Expr expression) => expression switch
        {
            Constant constant => constant.Value,
            Unary { Op: Operator.Negate, Operand: Constant negated } => -negated.Value,
            _ => null
        };

        // A variable a whole-variable operation moves has at least its words.
        private static void Blocks(Designator designator, int words)
        {
            if (designator is VariableDesignator { Variable: var variable }) { variable.BlockWords = Math.Max(variable.BlockWords, words); }
        }

        // An LDC's words, as they follow the opcode.
        private static ushort[] Words(byte[] data)
        {
            ushort[] words = new ushort[data.Length / 2];
            for (int index = 0; index < words.Length; index++) { words[index] = (ushort)(data[index * 2] | (data[(index * 2) + 1] << 8)); }
            return words;
        }

        // SIND and IND: a word at an offset from an address.
        private static Load Indirect(Expr address, int offset)
        {
            Designator designator = Designate(address);
            return new Load(offset == 0 ? designator : new FieldDesignator(designator, offset), 1);
        }

        // An index, less its range check and lower bound: CHK leaves the index type's bounds, and the lower bound is
        // subtracted (or a negative one added) after.
        private static (Expr Value, int? Low, int? High) Bounds(Expr index)
        {
            int? low = null;
            Expr value = index;
            if (value is Binary { Op: Operator.Subtract, Right: Constant subtracted } subtract)
            {
                low = subtracted.Value;
                value = subtract.Left;
            }
            else if (value is Binary { Op: Operator.Add, Right: Unary { Op: Operator.Negate, Operand: Constant added } } add)
            {
                low = -added.Value;
                value = add.Left;
            }

            if (value is Checked range && (low is null || low == range.Low))
            {
                return (range.Value, range.Low, range.High);
            }

            if (low is null && value is Checked zero && zero.Low == 0) { return (zero.Value, 0, zero.High); }
            return (value, low ?? 0, null);
        }

        // LDB and STB: a byte at an index from an address, from IXS or pushed apart.
        private static Designator ByteDesignator(List<Expr> stack)
        {
            Expr top = Pop(stack);
            if (top is ByteAddress byteAddress) { return byteAddress.Designator; }

            Designator array = Designate(Pop(stack));
            (Expr value, int? low, int? high) = Bounds(top);

            // Byte 0 of a string is its length.
            if (array.Type.Find().Kind == TypeKind.String && value is Constant { Value: 0 } && high is null)
            {
                return new LengthDesignator(array);
            }

            return new IndexDesignator(array, value, low, high, array.Type.ByteElement(low, high));
        }

        // LDP and STP: a packed array's element from IXP, or a packed record's field, an address, width and first bit.
        private static Designator PackedDesignator(List<Expr> stack)
        {
            Expr top = Pop(stack);
            if (top is PackedAddress packed) { return packed.Designator; }

            Expr width = Pop(stack);
            Expr address = Pop(stack);
            if (top is not Constant bit || width is not Constant bits)
            {
                throw new InvalidDataException("A packed field's width and position are not constants.");
            }

            (Designator record, int word) = address is Address { Designator: FieldDesignator field } ? (field.Record, field.Offset) : (Designate(address), 0);
            return new PackedFieldDesignator(record, word, bit.Value, bits.Value);
        }

        // A string's value from its address: a constant, a variable, or a function's temporary.
        private Expr StringValue(Expr address)
        {
            if (address is Address { Designator: VariableDesignator { Variable: Variable temporary } } && _strings.Remove(temporary, out StringFunction? function))
            {
                return function;
            }

            return address switch
            {
                StringConstant or PackedConstant or Constant => address,
                _ => new Load(Designate(address), 1)
            };
        }

        private static void Arithmetic(List<Expr> stack, Operator op)
        {
            Expr right = Pop(stack);
            Expr left = Pop(stack);
            stack.Add(new Binary(op, left, right));
        }

        private void Compare(List<Expr> stack, Operator op, IReadOnlyList<int>? operands = null)
        {
            Comparand comparand = operands?[0] switch
            {
                null => Comparand.Word,
                2 => Comparand.Real,
                4 => Comparand.String,
                6 => Comparand.Boolean,
                8 => Comparand.Set,
                10 => Comparand.Bytes,
                _ => Comparand.Words
            };

            int size = operands is { Count: > 1 } ? operands[1] : 0;
            Expr right;
            Expr left;
            switch (comparand)
            {
                case Comparand.Set:
                    right = PopSet(stack);
                    left = PopSet(stack);
                    break;
                case Comparand.String:
                    right = StringValue(Pop(stack));
                    left = StringValue(Pop(stack));
                    break;
                case Comparand.Bytes or Comparand.Words:
                    right = ArrayValue(Pop(stack), comparand, size);
                    left = ArrayValue(Pop(stack), comparand, size);
                    break;
                default:
                    right = Pop(stack);
                    left = Pop(stack);
                    break;
            }

            stack.Add(new Comparison(op, comparand, left, right, size));
        }

        // An array compared whole: its address, as a value.
        private static Expr ArrayValue(Expr address, Comparand comparand, int size)
        {
            if (address is StringConstant or PackedConstant) { return address; }

            Designator designator = Designate(address);
            TypeNode root = designator.Type.Find();
            if (comparand == Comparand.Bytes)
            {
                root.ByteElement(null, null);
                if (root.IndexLow is { } low) { root.IndexHigh ??= low + size - 1; }
            }
            else
            {
                root.Size(size);
            }

            return new Load(designator, 1);
        }

        private static void SetOperation(List<Expr> stack, Operator op)
        {
            SetValue right = PopSet(stack);
            SetValue left = PopSet(stack);
            SetValue set = new() { Op = op, Left = left, Right = right };
            TypeNode.Unify(set.Type, left.Type);
            TypeNode.Unify(set.Type, right.Type);
            stack.Add(set);
        }

        // A set with its size on the stack: one built here, or a value's words under its size.
        private static SetValue PopSet(List<Expr> stack)
        {
            Expr top = Pop(stack);
            if (top is SetValue built) { return built; }
            if (top is not Constant size) { throw new InvalidDataException("A set has no size on the stack."); }
            if (size.Value == 0) { return new SetValue(); }

            Expr value = Pop(stack);
            if (value.Words != size.Value && value is not Constant)
            {
                throw new InvalidDataException($"A set of {size.Value} words is {value.Words} words.");
            }

            SetValue set = new() { Value = value };
            if (value is Load load) { TypeNode.Unify(set.Type, load.Type); }
            set.Type.Size(size.Value);
            return set;
        }
    }
}
