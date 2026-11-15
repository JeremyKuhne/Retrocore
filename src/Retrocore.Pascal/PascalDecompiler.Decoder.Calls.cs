// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information


namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    private sealed partial class Decoder
    {
        private int _opened;
        private int _concatLength;

        // A call of a procedure in the code file: its arguments fill its parameters' words.
        private void CallProcedure(Procedure callee, List<Expr> stack, List<Statement> statements)
        {
            if (callee.Code.IsNative)
            {
                _owner.Observe(callee, stack);
                if (!callee.Signed) { Sign(callee, stack, _owner.SignatureOf(callee)); }
            }

            int words = callee.Frame.ParameterWords;
            if (callee.IsFunction)
            {
                Placeholders(stack);
                words -= 2;
            }

            List<Expr> arguments = [];
            int taken = 0;
            while (taken < words)
            {
                Expr argument = Pop(stack);
                taken += argument.Words;

                // A CONCAT's or COPY's temporary passes the string it builds, to a value string.
                if (argument is Address { Designator: VariableDesignator { Variable: Variable temporary } }
                    && _strings.ContainsKey(temporary))
                {
                    argument = StringValue(argument);
                }

                arguments.Insert(0, argument);
            }

            if (taken != words)
            {
                throw new InvalidDataException($"The call of {callee} passes {taken} words for {words}.");
            }

            Callee target = new() { Procedure = callee, ResultType = callee.ResultType };
            if (callee.IsFunction)
            {
                stack.Add(new Call(target, arguments, callee.ResultWords));
            }
            else
            {
                statements.Add(new CallStatement(target, [.. arguments.Select(argument => new Argument(argument))]));
            }
        }

        // An assembled procedure's code says nothing of its parameters or result, so its calls do: two zero words on top
        // are a function's room for its result, of a word, and the words below them, which the statement pushed, its
        // parameters. A first decompile signs it by its first call, and by the words its code takes off the stack where
        // that shows (NativeStackBytes); the next by what all its calls have in common, as a call in an expression has
        // the expression's own words below it (Observe).
        private static void Sign(Procedure callee, List<Expr> stack, NativeSignature? known)
        {
            bool function = known?.IsFunction ?? (stack.Count >= 2 && IsZero(stack[^1]) && IsZero(stack[^2]));
            int below = stack.Take(stack.Count - (function ? 2 : 0)).Sum(argument => argument.Words);
            int parameters = known?.ParameterWords ?? Math.Min(below, NativeParameterWords(callee, function) ?? below);
            callee.Frame = new Frame(callee, callee.Level, parameters + (function ? 2 : 0), dataWords: 0);
            if (function)
            {
                callee.ResultWords = 1;
                Variable result = callee.Frame.At(1);
                result.Kind = VariableKind.Result;
                TypeNode.Unify(result.Type, callee.ResultType);
            }

            callee.Signed = true;
        }

        private static bool IsZero(Expr expression) => expression is Constant { Value: 0 };

        // A function's caller leaves two words for its result.
        private static void Placeholders(List<Expr> stack)
        {
            for (int word = 0; word < 2; word++)
            {
                if (Pop(stack) is not Constant { Value: 0 })
                {
                    throw new InvalidDataException("A function's call leaves no room for its result.");
                }
            }
        }

        // CXP: a segment procedure, a unit's procedure, or the system's.
        private void External(int segment, int number, List<Expr> stack, List<Statement> statements)
        {
            if (segment == 0)
            {
                System(number, stack, statements);
                return;
            }

            if (segment == PascalIo)
            {
                PascalIoCall(number, stack, statements);
                return;
            }

            if (_owner.FindSegment(segment, number) is { } procedure)
            {
                // A unit's initialization, which the Compiler calls for its USES.
                if (number == 1 && _owner._unitSegments.Contains(procedure.Segment)) { return; }

                CallProcedure(procedure, stack, statements);
                return;
            }

            _owner.UseUnit(segment);
            if (_owner._library?.Unit(segment) is null && _owner.IsIntrinsic(segment))
            {
                InferredUnitCall(segment, number, stack, statements);
                return;
            }

            PascalUnit unit = _owner._library?.Unit(segment)
                ?? throw new InvalidDataException($"CXP {segment}, {number} calls a unit the library does not have.");

            PascalUnitProcedure declared = unit.Procedure(number)
                ?? throw new InvalidDataException($"CXP {segment}, {number} calls a procedure {unit.Name}'s interface does not declare.");

            if (declared.IsFunction) { Placeholders(stack); }

            List<Expr> arguments = [];
            for (int parameter = 0; parameter < declared.Parameters.Count; parameter++)
            {
                arguments.Insert(0, Pop(stack));
            }

            TypeNode result = declared.Result is null ? new TypeNode() : _owner.Named(declared.Result);
            Callee callee = new()
            {
                Unit = unit,
                UnitProcedure = declared,
                Segment = segment,
                Number = number,
                ResultType = result
            };

            for (int index = 0; index < arguments.Count; index++)
            {
                PascalUnitParameter parameter = declared.Parameters[index];
                if (parameter.IsReference || parameter.Type is "STRING")
                {
                    arguments[index] = parameter.Type is "STRING" && !parameter.IsReference ? StringValue(arguments[index]) : arguments[index];
                }
            }

            if (declared.IsFunction)
            {
                stack.Add(new Call(callee, arguments, result.Find().Kind == TypeKind.Real ? 2 : 1));
            }
            else
            {
                statements.Add(new CallStatement(callee, [.. arguments.Select(argument => new Argument(argument))]));
            }
        }

        // The system segment's procedures: files, I/O, strings and GOTOXY.
        private void System(int number, List<Expr> stack, List<Statement> statements)
        {
            switch (number)
            {
                case 3: // FINIT(file, window, record size), for a file variable as its procedure starts
                    {
                        Expr size = Pop(stack);
                        Expr window = Pop(stack);
                        Designator file = Designate(Pop(stack));
                        FileVariable(file, size);
                        if (file is VariableDesignator { Variable: var located }
                            && window is Address { Designator: VariableDesignator { Variable: var at } }
                            && at.Frame == located.Frame
                            && at.Offset > located.Offset)
                        {
                            located.Type.Find().WindowWords = at.Offset - located.Offset;
                        }

                        if (file is VariableDesignator { Variable: var opened }) { opened.Opened = ++_opened; }

                        // The window is the file variable's last words; an untyped file's 40 words have none, and its
                        // window's address is past them, which may be the next file's, as Apple III Pascal's
                        // Compiler's untyped files are followed by its listing's text file.
                        if (file is VariableDesignator { Variable: var variable }
                            && window is Address { Designator: VariableDesignator { Variable: var buffer } }
                            && buffer.Opened == 0)
                        {
                            buffer.Container = variable;
                            buffer.FieldOffset = buffer.Offset - variable.Offset;
                            if (variable.Type.Find().Kind == TypeKind.File && variable.Type.Find().RecordWords <= 0)
                            {
                                if (buffer.Used is false || !buffer.LoadedAsWord)
                                {
                                    buffer.Frame.Variables.Remove(buffer.Offset);
                                }
                            }
                            else
                            {
                                variable.BlockWords = Math.Max(variable.BlockWords, buffer.Offset - variable.Offset + 1);
                            }
                        }

                        break;
                    }

                case 4: // FRESET
                    Statement(statements, "RESET", File(Pop(stack)));
                    break;
                case 5: // FOPEN(file, name, old, junk)
                    {
                        // RESET and REWRITE pass 0; a program compiled as part of the system that passes other, as
                        // Apple III Pascal 1.2's Compiler passes NIL, calls FOPEN as the system's procedure 5.
                        if (_owner._systemProgram && stack.Count == 4 && !IsZero(stack[^1]))
                        {
                            List<Argument> opened = [.. stack.Select(value => new Argument(value))];
                            stack.Clear();
                            _owner._systemProcedures.TryAdd(number, opened);
                            Statement(statements, SystemProcedure(number), [.. opened]);
                            break;
                        }

                        Pop(stack);
                        Expr old = Pop(stack);
                        Expr name = StringValue(Pop(stack));
                        Argument file = File(Pop(stack));
                        string opener = old is Constant { Value: 0 } ? "REWRITE" : "RESET";
                        Statement(statements, opener, file, new Argument(name));
                        break;
                    }

                case 6: // FCLOSE(file, mode)
                    {
                        Expr mode = Pop(stack);
                        Argument file = File(Pop(stack));
                        string? option = mode is Constant { Value: var value }
                            ? value switch { 0 => null, 1 => "LOCK", 2 => "PURGE", 3 => "CRUNCH", _ => "?" }
                            : "?";

                        if (option is null)
                        {
                            Statement(statements, "CLOSE", file);
                        }
                        else
                        {
                            Statement(statements, "CLOSE", file, new Argument(new Keyword(option)));
                        }

                        break;
                    }

                case 7: Statement(statements, "GET", File(Pop(stack))); break;
                case 8: Statement(statements, "PUT", File(Pop(stack))); break;
                case 10 or 11: // FEOF, FEOLN
                    {
                        Placeholders(stack);
                        Argument file = File(Pop(stack));
                        stack.Add(Builtin(number == 10 ? "EOF" : "EOLN", ScalarKind.Boolean, file.Value));
                        break;
                    }

                case 12 or 16: // FREADINT, FREADCHAR
                    {
                        Designator target = Designate(Pop(stack));
                        target.Type.Force(number == 12 ? ScalarKind.Integer : ScalarKind.Char);
                        Statement(statements, "READ", File(Pop(stack)), new Argument(new Address(target)));
                        break;
                    }

                case 18: // FREADSTRING(file, string, length)
                    {
                        Expr length = Pop(stack);
                        Designator target = Designate(Pop(stack));
                        if (length is Constant maximum) { target.Type.String(maximum.Value); }
                        Statement(statements, "READ", File(Pop(stack)), new Argument(new Address(target)));
                        break;
                    }

                case 13 or 17 or 19: // FWRITEINT, FWRITECHAR, FWRITESTRING(file, value, width)
                    {
                        Expr width = Pop(stack);
                        Expr value = Pop(stack);
                        if (number == 19) { value = StringValue(value); }
                        Argument file = File(Pop(stack));
                        Statement(statements, "WRITE", file, new Argument(new Written(value, number), Width(width)));
                        break;
                    }

                case 20: // FWRITEBYTES(file, array, width, length)
                    {
                        Expr length = Pop(stack);
                        Expr width = Pop(stack);
                        Expr array = Pop(stack);
                        Expr value = array is PackedConstant or StringConstant ? array : new Load(Designate(array), 1);
                        // What WRITE writes bytes of is a packed array of them, as long as a constant count says.
                        if (array is not (PackedConstant or StringConstant))
                        {
                            TypeNode root = Designate(array).Type.Find();
                            root.ByteElement(low: null, high: null);
                            if (length is Constant bytes && root.IndexLow is { } low)
                            {
                                root.IndexHigh ??= low + bytes.Value - 1;
                            }
                            else if (length is Constant count)
                            {
                                // A record's bytes at its address are its first field's.
                                TypeNode written = root.Find();
                                if (written.Kind == TypeKind.Record) { written = written.Field(0).Find(); }

                                written.Count ??= count.Value;
                            }
                        }

                        Argument file = File(Pop(stack));
                        bool full = width is Constant w && length is Constant l && w.Value == l.Value;
                        Statement(statements, "WRITE", file, new Argument(new Written(value, number), full ? null : width));
                        break;
                    }

                case 21: Statement(statements, "READLN", File(Pop(stack))); break;
                case 22: Statement(statements, "WRITELN", File(Pop(stack))); break;
                case 23: // SCONCAT(temporary, string, length so far)
                    {
                        Expr length = Pop(stack);
                        Expr source = StringValue(Pop(stack));
                        Variable temporary = Temporary(Pop(stack));
                        if (!_strings.TryGetValue(temporary, out StringFunction? concat))
                        {
                            // CONCAT empties its temporary first: its length, a word, is set to 0.
                            if (statements.Count == 0
                                || statements[^1] is not Assignment { Value: Constant { Value: 0 } } emptying
                                || emptying.Target is not VariableDesignator { Variable: Variable emptied }
                                || emptied != temporary)
                            {
                                throw new InvalidDataException("A CONCAT's temporary was not emptied first.");
                            }

                            statements.RemoveAt(statements.Count - 1);
                            _concatLength = 0;
                            concat = new StringFunction("CONCAT", []);
                            _strings[temporary] = concat;
                        }

                        // The lengths so far grow by each string's greatest length.
                        if (length is Constant total)
                        {
                            if (source is Load { Designator: var designator })
                            {
                                designator.Type.String(total.Value - _concatLength);
                            }

                            _concatLength = total.Value;
                        }

                        concat.Arguments.Add(source);
                        break;
                    }

                case 24: // SINSERT(source, string, length, index)
                    {
                        Expr index = Pop(stack);
                        Expr length = Pop(stack);
                        Designator target = Designate(Pop(stack));
                        if (length is Constant maximum) { target.Type.String(maximum.Value); }
                        Expr source = StringValue(Pop(stack));
                        Statement(statements, "INSERT", new Argument(source), new Argument(new Address(target)), new Argument(index));
                        break;
                    }

                case 25: // SCOPY(source, temporary, index, count)
                    {
                        Expr count = Pop(stack);
                        Expr index = Pop(stack);
                        Variable temporary = Temporary(Pop(stack));
                        Expr source = StringValue(Pop(stack));
                        _strings[temporary] = new StringFunction("COPY", [source, index, count]);
                        break;
                    }

                case 26: // SDELETE(string, index, count)
                    {
                        Expr count = Pop(stack);
                        Expr index = Pop(stack);
                        Expr target = Pop(stack);
                        Statement(statements, "DELETE", new Argument(new Address(Designate(target))), new Argument(index), new Argument(count));
                        break;
                    }

                case 27: // SPOS(pattern, string)
                    {
                        Placeholders(stack);
                        Expr text = StringValue(Pop(stack));
                        Expr pattern = StringValue(Pop(stack));
                        stack.Add(Builtin("POS", ScalarKind.Integer, pattern, text));
                        break;
                    }

                case 28: // FBLOCKIO(file, array, offset, blocks, block, read): BLOCKREAD and BLOCKWRITE
                    {
                        Placeholders(stack);
                        Expr read = Pop(stack);
                        Expr block = Pop(stack);
                        Expr count = Pop(stack);
                        Expr array = BytePointer(stack);
                        Argument file = File(Pop(stack));
                        List<Expr> arguments = [file.Value, array, count];
                        if (block is not Unary { Op: Operator.Negate, Operand: Constant { Value: 1 } })
                        {
                            arguments.Add(block);
                        }

                        string transfer = read is Constant { Value: 0 } ? "BLOCKWRITE" : "BLOCKREAD";
                        stack.Add(Builtin(transfer, ScalarKind.Integer, [.. arguments]));
                        break;
                    }

                case 29: // FGOTOXY(x, y)
                    {
                        Expr y = Pop(stack);
                        Statement(statements, "GOTOXY", new Argument(Pop(stack)), new Argument(y));
                        break;
                    }

                default:
                    {
                        if (!_owner._systemProgram)
                        {
                            throw new InvalidDataException($"CXP 0, {number} is a system procedure that is not decompiled.");
                        }

                        // In a program compiled as part of the system, one no standard procedure names is called by a
                        // heading the system's block declares; its arguments are what the stack holds, and two zero
                        // words on top are a function's room for its result, as Apple III Pascal 1.2's system has.
                        bool function = stack.Count >= 2 && IsZero(stack[^1]) && IsZero(stack[^2]);
                        if (function)
                        {
                            Pop(stack);
                            Pop(stack);
                            _owner._systemFunctions.Add(number);
                        }

                        List<Argument> arguments = [.. stack.Select(value => new Argument(value))];
                        stack.Clear();
                        _owner._systemProcedures.TryAdd(number, arguments);
                        if (function)
                        {
                            stack.Add(Builtin(SystemProcedure(number), ScalarKind.Integer, [.. arguments.Select(argument => argument.Value)]));
                        }
                        else
                        {
                            Statement(statements, SystemProcedure(number), [.. arguments]);
                        }

                        break;
                    }
            }
        }

        // PASCALIO, which the system loads for reals' I/O and SEEK.
        private static void PascalIoCall(int number, List<Expr> stack, List<Statement> statements)
        {
            switch (number)
            {
                case 2: // FSEEK(file, record)
                    {
                        Expr record = Pop(stack);
                        Statement(statements, "SEEK", File(Pop(stack)), new Argument(record));
                        break;
                    }

                case 3: // FREADREAL(file, real)
                    {
                        Designator target = Designate(Pop(stack));
                        target.Type.Find().Kind = TypeKind.Real;
                        Statement(statements, "READ", File(Pop(stack)), new Argument(new Address(target)));
                        break;
                    }

                case 4: // FWRITEREAL(file, real, width, decimals)
                    {
                        Expr decimals = Pop(stack);
                        Expr width = Pop(stack);
                        Expr value = Pop(stack);
                        Argument file = File(Pop(stack));
                        Statement(statements, "WRITE", file, new Argument(new Written(value, 0), Width(width), Width(decimals)));
                        break;
                    }

                default:
                    throw new InvalidDataException($"CXP {PascalIo}, {number} is a PASCALIO procedure that is not decompiled.");
            }
        }

        // CSP: the standard procedures the interpreter does itself.
        private static void Standard(int number, List<Expr> stack, List<Statement> statements)
        {
            switch (number)
            {
                case 0: // IOC: the statement before checks its I/O result
                    if (statements.Count > 0 && statements[^1] is CallStatement io) { io.Checked = true; }
                    break;
                case 1: // NEW(pointer, words)
                    {
                        Expr words = Pop(stack);
                        Designator pointer = Designate(Pop(stack));
                        // NEW keeps the words it takes: one of a record's variants takes fewer than the record.
                        if (words is Constant size)
                        {
                            pointer.Type.Target().Size(size.Value);
                            Statement(statements, "NEW", new Argument(new Address(pointer)), new Argument(new Constant(size.Value)));
                        }
                        else
                        {
                            Statement(statements, "NEW", new Argument(new Address(pointer)));
                        }

                        break;
                    }

                case 2 or 3: // MVL, MVR(source, offset, target, offset, count)
                    {
                        Expr count = Pop(stack);
                        Expr target = BytePointer(stack);
                        Expr source = BytePointer(stack);
                        Statement(statements, number == 2 ? "MOVELEFT" : "MOVERIGHT", new Argument(source), new Argument(target), new Argument(count));
                        break;
                    }

                case 4: // EXIT(segment, procedure)
                    {
                        Expr procedure = Pop(stack);
                        Expr segment = Pop(stack);
                        if (segment is not Constant s || procedure is not Constant p)
                        {
                            throw new InvalidDataException("An EXIT names no procedure.");
                        }

                        statements.Add(new ExitStatement(s.Value, p.Value));
                        break;
                    }

                case 5 or 6: // UREAD, UWRITE(unit, array, offset, count, block, mode)
                    {
                        Expr mode = Pop(stack);
                        Expr block = Pop(stack);
                        Expr count = Pop(stack);
                        Expr array = BytePointer(stack);
                        Expr unit = Pop(stack);
                        Statement(statements, number == 5 ? "UNITREAD" : "UNITWRITE", new(unit), new(array), new(count), new(block), new(mode));
                        break;
                    }

                case 7: // IDS(VAR cursor, VAR buffer): the Compiler's IDSEARCH, which scans an identifier
                    {
                        Designator buffer = Designate(Pop(stack));
                        Designator cursor = Designate(Pop(stack));
                        Statement(statements, "IDSEARCH", new Argument(new Address(cursor)), new Argument(new Address(buffer)));
                        break;
                    }

                case 8: // TRS(root, VAR found, VAR name): the Compiler's TREESEARCH, which finds a name in a tree
                    {
                        Designator name = Designate(Pop(stack));
                        Designator found = Designate(Pop(stack));
                        Expr root = Pop(stack);
                        TypeNode.Unify(root.Type, found.Type);
                        stack.Add(Builtin("TREESEARCH", ScalarKind.Integer, root, new Address(found), new Address(name)));
                        break;
                    }

                case 9: // TIM(high, low)
                    {
                        Expr low = Pop(stack);
                        Expr high = Pop(stack);
                        Statement(statements, "TIME", new Argument(high), new Argument(low));
                        break;
                    }

                case 10: // FLC(array, offset, count, character)
                    {
                        Expr character = Pop(stack);
                        Expr count = Pop(stack);
                        Expr target = BytePointer(stack);
                        Statement(statements, "FILLCHAR", new Argument(target), new Argument(count), new Argument(character));
                        break;
                    }

                case 11: // SCN(limit, unequal, character, array, offset, 0): SCAN's result
                    {
                        Pop(stack);
                        Expr array = BytePointer(stack);
                        Expr character = Pop(stack);
                        if (Pop(stack) is not Constant { Value: 0 or 1 } unequal)
                        {
                            throw new InvalidDataException("A SCAN's test is neither = nor <>.");
                        }

                        Expr limit = Pop(stack);
                        stack.Add(Builtin("SCAN", ScalarKind.Integer, limit, new ScanTest(unequal.Value == 1, character), array));
                        break;
                    }

                case 12: // USTAT(unit, array, offset, control), Apple III Pascal's UNITSTATUS
                    {
                        Expr control = Pop(stack);
                        Expr array = BytePointer(stack);
                        Expr unit = Pop(stack);
                        Statement(statements, "UNITSTATUS", new Argument(unit), new Argument(array), new Argument(control));
                        break;
                    }

                case 21 or 22: // GSEG, RSEG
                    Pop(stack);
                    break;
                case 23: stack.Add(Builtin("TRUNC", ScalarKind.Integer, Pop(stack))); break;
                case 24: stack.Add(Builtin("ROUND", ScalarKind.Integer, Pop(stack))); break;
                case >= 25 and <= 31: // SIN, COS, LOG, ATAN, LN, EXP, SQRT
                    {
                        string name = (string[])["SIN", "COS", "LOG", "ATAN", "LN", "EXP", "SQRT"] is var names ? names[number - 25] : "";
                        stack.Add(RealBuiltin(name, Pop(stack)));
                        break;
                    }

                case 32: Statement(statements, "MARK", new Argument(Pop(stack))); break;
                case 33: Statement(statements, "RELEASE", new Argument(Pop(stack))); break;
                case 34: stack.Add(Builtin("IORESULT", ScalarKind.Integer)); break;
                case 35: stack.Add(Builtin("UNITBUSY", ScalarKind.Boolean, Pop(stack))); break;
                case 36: stack.Add(RealBuiltin("PWROFTEN", Pop(stack))); break;
                case 37: Statement(statements, "UNITWAIT", new Argument(Pop(stack))); break;
                case 38: Statement(statements, "UNITCLEAR", new Argument(Pop(stack))); break;
                case 39: Statement(statements, "HALT"); break;
                case 40: stack.Add(Builtin("MEMAVAIL", ScalarKind.Integer)); break;
                default:
                    throw new InvalidDataException($"CSP {Pcode.StandardProcedure(number)} is not decompiled.");
            }
        }

        // A byte array's address and a byte offset into it, as MOVELEFT, FILLCHAR and UNITREAD take them.
        private static Expr BytePointer(List<Expr> stack)
        {
            Expr offset = Pop(stack);
            Expr address = Pop(stack);
            if (address is ByteAddress or Address && offset is Constant { Value: 0 }) { return address; }
            if (address is ByteAddress) { return address; }
            if (offset is Constant { Value: 0 })
            {
                return address is StringConstant or PackedConstant ? address : new Address(Designate(address));
            }

            // A checked index, as SCAN's into a packed array, keeps its bounds; an offset alone says nothing of them.
            Designator array = Designate(address);
            (Expr value, int? low, int? high) = Bounds(offset);
            if (high is not null)
            {
                return new Address(new IndexDesignator(array, value, low, high, array.Type.ByteElement(low, high)));
            }


            TypeNode element = array.Type.ByteElement(0, high: null);
            return new Address(new IndexDesignator(array, offset, 0, high: null, element) { Neutral = true });
        }

        // A WRITE's width: none when 0.
        private static Expr? Width(Expr width) => width is Constant { Value: 0 } ? null : width;

        // A file argument: OUTPUT, INPUT and KEYBOARD are the system's; a file variable is by address.
        private static Argument File(Expr file) => new(file is Address ? file : file);

        private static void Statement(List<Statement> statements, string name, params Argument[] arguments) =>
            statements.Add(new CallStatement(new Callee { Builtin = name }, [.. arguments]));

        private static Call Builtin(string name, ScalarKind kind, params Expr[] arguments) =>
            new(new Callee { Builtin = name, ResultType = TypeNode.Scalar(kind) }, [.. arguments], 1);

        private static Call RealBuiltin(string name, params Expr[] arguments) =>
            new(new Callee { Builtin = name, ResultType = TypeNode.Of(TypeKind.Real) }, [.. arguments], 2);

        // A string temporary, which CONCAT and COPY build their results in.
        private static Variable Temporary(Expr address)
        {
            if (address is not Address { Designator: VariableDesignator { Variable: Variable temporary } })
            {
                throw new InvalidDataException("A string function's result is not in a temporary.");
            }

            temporary.Kind = VariableKind.Temporary;
            return temporary;
        }
    }
}
