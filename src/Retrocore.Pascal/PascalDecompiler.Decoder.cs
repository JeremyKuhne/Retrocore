// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  Decompiles one procedure: runs its p-code on a stack of expressions, and finds its statements in the patterns
    ///  of jumps the Compiler writes for each.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The patterns, where <c>c</c> is a condition's code:
    ///  </para>
    ///  <list type="bullet">
    ///   <item><description>IF: <c>c FJP L1; then; UJP L2; L1: else; L2:</c>, the UJP and else left out without ELSE.</description></item>
    ///   <item><description>WHILE: <c>L1: c FJP L2; body; UJP L1; L2:</c>.</description></item>
    ///   <item><description>REPEAT: <c>L1: body; c FJP L1</c>, the jump back through the jump table.</description></item>
    ///   <item><description>FOR: <c>v := a; t := b; L1: v t LEQI (GEQI for DOWNTO) FJP L2; body; v := v + 1 (- 1); UJP L1; L2:</c>.</description></item>
    ///   <item><description>CASE: <c>selector UJP L1; arms, each ending UJP L2; L1: XJP table; L2:</c>.</description></item>
    ///  </list>
    ///  <para>
    ///   Any other jump is a GOTO.
    ///  </para>
    /// </remarks>
    private sealed partial class Decoder
    {
        private readonly PascalDecompiler _owner;
        private readonly Procedure _procedure;
        private readonly IReadOnlyList<PcodeInstruction> _code;
        private readonly Dictionary<int, int> _index = [];
        private readonly Dictionary<int, List<int>> _backward = [];
        private readonly HashSet<(int Head, int Jump)> _loops = [];
        private readonly Dictionary<Variable, StringFunction> _strings = [];
        private readonly Dictionary<int, (List<Statement> List, int Position)> _boundaries = [];
        private readonly List<int> _gotos = [];

        public Decoder(PascalDecompiler owner, Procedure procedure)
        {
            _owner = owner;
            _procedure = procedure;
            _code = procedure.Instructions;
            for (int index = 0; index < _code.Count; index++) { _index[_code[index].Offset] = index; }
            if (_code.Count > 0) { _index.TryAdd(_code[^1].Next, _code.Count); }

            for (int index = 0; index < _code.Count; index++)
            {
                PcodeInstruction instruction = _code[index];
                if (instruction.Opcode.Code is not (Pcode.Fjp or Pcode.Ujp) || instruction.Targets[0] < 0) { continue; }

                int target = Index(instruction.Targets[0]);
                if (target <= index)
                {
                    if (!_backward.TryGetValue(target, out List<int>? sources))
                    {
                        sources = [];
                        _backward[target] = sources;
                    }

                    sources.Add(index);
                }
            }
        }

        private int Index(int offset) =>
            _index.TryGetValue(offset, out int index) ? index : throw new InvalidDataException($"A jump to ${offset:X4} lands inside a p-code.");

        public void Decode()
        {
            int start = 0;
            int end = Index(_procedure.Code.Exit);

            // The program's body starts with a jump to the segments it loads (or two NOPs where it loads none), then
            // its units' initializations.
            if (_procedure.Level <= 0 && _procedure.Number == 1)
            {
                if (start < end && _code[start].Opcode.Code == Pcode.Ujp)
                {
                    start++;
                }
                else
                {
                    while (start < end && start < 2 && _code[start].Opcode.Code is 210 or 215) { start++; }
                }

                while (start < end && _code[start] is { Opcode.Code: Pcode.Cxp } call && call.Operands[1] == 1 && _owner.IsUnit(call.Operands[0]))
                {
                    _owner.UseUnit(call.Operands[0]);
                    start++;
                }
            }

            List<Expr> stack = [];
            List<Statement> body = Block(start, end, stack);
            if (stack.Count > 0) { throw new InvalidDataException($"{_procedure} ends with {stack.Count} values on the stack."); }

            Prologue(body);
            _procedure.Body = body;

            // Each GOTO's target gets its label where a statement starts.
            foreach (int target in _gotos.Distinct().Order())
            {
                if (!_boundaries.TryGetValue(target, out (List<Statement> List, int Position) boundary))
                {
                    throw new InvalidDataException($"A GOTO's target, ${target:X4}, is not where a statement starts.");
                }

                int label = _procedure.Labels.Count + 1;
                _procedure.Labels[target] = label;
                int position = boundary.List.FindIndex(statement => statement.Offset >= target && statement is not LabelStatement);
                boundary.List.Insert(position < 0 ? boundary.List.Count : position, new LabelStatement(target) { Offset = target });
            }
        }

        // A run of statements from one p-code up to another, leaving any value it ends with on the stack.
        private List<Statement> Block(int from, int to, List<Expr> stack)
        {
            List<Statement> statements = [];
            int at = from;
            while (at < to)
            {
                PcodeInstruction instruction = _code[at];
                if (stack.Count == 0)
                {
                    _boundaries.TryAdd(instruction.Offset, (statements, statements.Count));
                    if (Loop(ref at, to, statements)) { continue; }
                }

                int count = statements.Count;
                switch (instruction.Opcode.Code)
                {
                    case Pcode.Fjp:
                        at = If(at, to, stack, statements);
                        break;
                    case Pcode.Ujp:
                        at = Jump(at, to, stack, statements);
                        break;
                    case Pcode.Xjp:
                        throw new InvalidDataException($"The XJP at ${instruction.Offset:X4} has no CASE before it.");
                    default:
                        Execute(instruction, stack, statements);
                        at++;
                        break;
                }

                for (int index = count; index < statements.Count; index++)
                {
                    if (statements[index].Offset == 0) { statements[index].Offset = instruction.Offset; }
                }
            }

            return statements;
        }

        // A loop whose head is here: REPEAT, WHILE or FOR.
        private bool Loop(ref int at, int to, List<Statement> statements)
        {
            if (!_backward.TryGetValue(at, out List<int>? sources)) { return false; }

            int head = at;
            int jump = sources.Where(source => source < to && !_loops.Contains((head, source))).DefaultIfEmpty(-1).Max();
            if (jump < 0) { return false; }

            _loops.Add((head, jump));
            int offset = _code[at].Offset;
            if (_code[jump].Opcode.Code == Pcode.Fjp)
            {
                List<Expr> stack = [];
                List<Statement> body = Block(at, jump, stack);
                if (stack.Count != 1) { throw new InvalidDataException($"The REPEAT at ${offset:X4} has no condition."); }

                statements.Add(new RepeatStatement(body, stack[0]) { Offset = offset });
                at = jump + 1;
                return true;
            }

            // WHILE: the condition's FJP goes past the jump back.
            int exit = jump + 1;
            for (int test = at; test < jump; test++)
            {
                if (_code[test] is not { Opcode.Code: Pcode.Fjp } fjp || fjp.Targets[0] < 0 || Index(fjp.Targets[0]) != exit) { continue; }

                List<Expr> stack = [];
                List<Statement> condition = Block(at, test, stack);
                if (condition.Count != 0 || stack.Count != 1) { break; }

                List<Statement> body = Block(test + 1, jump, []);
                statements.Add((Statement?)For(stack[0], body, statements, offset) ?? new WhileStatement(stack[0], body) { Offset = offset });
                at = exit;
                return true;
            }

            // Any other loop is a label and a GOTO back to it.
            return false;
        }

        // FOR v := a TO b: the two assignments before the loop, its test, and the step at the end of its body.
        private static ForStatement? For(Expr condition, List<Statement> body, List<Statement> statements, int offset)
        {
            if (condition is not Comparison { Comparand: Comparand.Word, Op: Operator.LessEqual or Operator.GreaterEqual } test
                || test.Left is not Load { Designator: VariableDesignator control }
                || test.Right is not Load { Designator: VariableDesignator { Variable: Variable limit } }
                || statements.Count < 2
                || statements[^1] is not Assignment { Target: VariableDesignator { Variable: Variable limitTarget } } limitAssignment
                || limitTarget != limit
                || statements[^2] is not Assignment { Target: VariableDesignator { Variable: Variable start } } startAssignment
                || start != control.Variable
                || body.Count == 0
                || body[^1] is not Assignment { Target: VariableDesignator { Variable: Variable step } } stepAssignment
                || step != control.Variable)
            {
                return null;
            }

            bool down = test.Op == Operator.GreaterEqual;
            Expr stepValue = stepAssignment.Value is Checked checkedStep ? checkedStep.Value : stepAssignment.Value;
            if (stepValue is not Binary { Left: Load { Designator: VariableDesignator { Variable: Variable stepped } }, Right: Constant { Value: 1 } } binary
                || stepped != control.Variable
                || binary.Op != (down ? Operator.Subtract : Operator.Add))
            {
                return null;
            }

            limit.Kind = VariableKind.Temporary;
            statements.RemoveRange(statements.Count - 2, 2);
            body.RemoveAt(body.Count - 1);
            return new ForStatement(control, startAssignment.Value, limitAssignment.Value, down, body) { Offset = startAssignment.Offset };
        }

        // An FJP: IF, with ELSE where the THEN ends by jumping past it.
        private int If(int at, int to, List<Expr> stack, List<Statement> statements)
        {
            PcodeInstruction fjp = _code[at];
            Expr condition = Pop(stack);
            if (fjp.Targets[0] < 0) { throw new InvalidDataException($"The FJP at ${fjp.Offset:X4} jumps nowhere."); }

            int target = Index(fjp.Targets[0]);
            if (target <= at || target > to)
            {
                throw new InvalidDataException($"The FJP at ${fjp.Offset:X4} leaves its statement.");
            }

            PcodeInstruction last = _code[target - 1];
            if (target - 1 > at && last.Opcode.Code == Pcode.Ujp && last.Targets[0] >= 0)
            {
                int end = Index(last.Targets[0]);
                if (end > target && end <= to && !IsCaseJump(last))
                {
                    List<Statement> then = Block(at + 1, target - 1, []);
                    List<Statement> otherwise = Block(target, end, []);
                    statements.Add(new IfStatement(condition, then, otherwise) { Offset = fjp.Offset });
                    return end;
                }
            }

            statements.Add(new IfStatement(condition, Block(at + 1, target, []), null) { Offset = fjp.Offset });
            return target;
        }

        private bool IsCaseJump(PcodeInstruction ujp) =>
            ujp.Targets[0] >= 0 && Index(ujp.Targets[0]) < _code.Count && _code[Index(ujp.Targets[0])].Opcode.Code == Pcode.Xjp;

        // A UJP: a CASE's jump to its table, or a GOTO.
        private int Jump(int at, int to, List<Expr> stack, List<Statement> statements)
        {
            PcodeInstruction ujp = _code[at];
            if (stack.Count > 0 && IsCaseJump(ujp)) { return Case(at, stack, statements); }
            if (stack.Count > 0) { throw new InvalidDataException($"The UJP at ${ujp.Offset:X4} leaves a value on the stack."); }
            if (ujp.Targets[0] < 0) { throw new InvalidDataException($"The UJP at ${ujp.Offset:X4} jumps nowhere."); }

            _gotos.Add(ujp.Targets[0]);
            statements.Add(new GotoStatement(ujp.Targets[0]) { Offset = ujp.Offset });
            return at + 1;
        }

        private int Case(int at, List<Expr> stack, List<Statement> statements)
        {
            PcodeInstruction ujp = _code[at];
            Expr selector = Pop(stack);
            int table = Index(ujp.Targets[0]);
            PcodeInstruction xjp = _code[table];
            int end = table + 1;
            int low = xjp.Operands[0];
            int high = xjp.Operands[1];
            int otherwise = xjp.Targets[0];

            // The arms in the order of their code, each with the values that lead to it.
            SortedDictionary<int, List<int>> arms = [];
            for (int value = low; value <= high; value++)
            {
                int target = xjp.Targets[value - low + 1];
                if (target == otherwise || target < 0) { continue; }
                if (!arms.TryGetValue(target, out List<int>? labels))
                {
                    labels = [];
                    arms[target] = labels;
                }

                labels.Add(value);
            }

            List<int> starts = [.. arms.Keys.Select(Index)];
            if (starts.Count > 0 && starts[0] != at + 1)
            {
                throw new InvalidDataException($"The CASE at ${ujp.Offset:X4} has code before its first arm.");
            }

            List<(List<int> Labels, List<Statement> Body)> bodies = [];
            for (int arm = 0; arm < starts.Count; arm++)
            {
                int first = starts[arm];
                int next = arm + 1 < starts.Count ? starts[arm + 1] : table;
                int last = next;
                if (last - 1 >= first && _code[last - 1] is { Opcode.Code: Pcode.Ujp } exit && exit.Targets[0] >= 0 && Index(exit.Targets[0]) == end)
                {
                    last--;
                }

                bodies.Add((arms[_code[first].Offset], Block(first, last, [])));
            }

            statements.Add(new CaseStatement(selector, bodies) { Offset = ujp.Offset });
            return end;
        }

        // Value parameters that are strings, records or arrays are copied into the procedure's own variables first.
        private void Prologue(List<Statement> body)
        {
            Frame frame = _procedure.Frame;
            int copied = 0;
            while (copied < body.Count
                && body[copied] is Assignment
                {
                    Block: true,
                    Target: VariableDesignator { Variable: Variable copy },
                    Value: Load { Designator: Dereference { Pointer: Load { Designator: VariableDesignator { Variable: Variable parameter } } } }
                }
                && copy.Frame == frame
                && parameter.Frame == frame
                && parameter.Kind == VariableKind.Parameter
                && copy.Kind == VariableKind.Variable
                && parameter.Copy is null)
            {
                parameter.Copy = copy;
                copy.Kind = VariableKind.Copy;
                TypeNode.Unify(copy.Type, parameter.Type.Target());
                copied++;
            }

            body.RemoveRange(0, copied);
        }

        private static Expr Pop(List<Expr> stack)
        {
            if (stack.Count == 0) { throw new InvalidDataException("The p-code takes a value from an empty stack."); }
            Expr value = stack[^1];
            stack.RemoveAt(stack.Count - 1);
            return value;
        }

        // The thing an address on the stack is the address of.
        private static Designator Designate(Expr address) => address switch
        {
            Address a => a.Designator,
            Checked { Value: Address a } => a.Designator,
            _ => new Dereference(address)
        };

        private Variable Local(int offset) => Use(_procedure.Frame.At(offset));

        private Variable Global(int offset) => Use(_owner.Globals.At(offset));

        private Variable Intermediate(int levels, int offset) => Use(_owner.Enclosing(_procedure, levels).At(offset));

        private static Variable Use(Variable variable)
        {
            variable.Used = true;
            return variable;
        }

        private static Load LoadWord(Variable variable)
        {
            variable.LoadedAsWord = true;
            return new Load(new VariableDesignator(variable), 1);
        }

        private static Address AddressOf(Variable variable)
        {
            variable.AddressTaken = true;
            return new Address(new VariableDesignator(variable));
        }

        private void Store(Variable variable, Expr value, List<Statement> statements)
        {
            variable.LoadedAsWord = true;
            statements.Add(new Assignment(new VariableDesignator(variable), value));
        }
    }
}
