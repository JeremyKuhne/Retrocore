// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    // Pascal's precedence: relations, then adding operators (and a sign), then multiplying ones, then factors.
    private const int Relational = 1;
    private const int Adding = 2;
    private const int Multiplying = 3;
    private const int Factor = 4;

    // An expression, converted to the type its place expects, in parentheses where its place binds tighter.
    private string Expression(Expr expression, TypeNode? expected, int precedence)
    {
        // A record's address where a word is used is its first field's.
        expression = Narrow(expression);
        if (expression is Load { Designator: var whole } load && whole.Type.Find().Kind == TypeKind.Record)
        {
            Designator field = Descend(whole, expected);
            if (field != whole) { expression = new Load(field, load.Words); }
        }

        // A word also read by bytes is a variant record's.
        if (expression is Load { Designator: VariableDesignator { Variable: var viewed } }
            && viewed.Type.Find() is { Kind: TypeKind.Scalar, ByteView: true })
        {
            return Convert($"{viewed.Name}.I", Factor, ScalarKind.Integer, Kind(expected), out _);
        }

        // A word used both as a pointer and as an integer is a variant record's.
        if (expression is Load { Designator: VariableDesignator { Variable: var punned } } && IsPunned(punned.Type))
        {
            bool integer = Kind(expected) is not null;
            string pun = $"{punned.Name}.{(integer ? "I" : "P")}";
            return Convert(pun, Factor, integer ? ScalarKind.Integer : null, Kind(expected), out _);
        }

        // SUCC and PRED step a character or an enumerated value.
        if (Kind(expected) is ScalarKind.Char or ScalarKind.Enumeration
            && expression is Binary { Op: Operator.Add or Operator.Subtract, Right: Constant { Value: 1 } } step
            && Natural(step.Left) == Kind(expected))
        {
            return $"{(step.Op == Operator.Add ? "SUCC" : "PRED")}({Expression(step.Left, expected, 0)})";
        }

        (string text, int level) = Text(expression, expected);
        string converted = Convert(text, level, Natural(expression), Kind(expected), out int convertedLevel);
        return convertedLevel < precedence ? $"({converted})" : converted;
    }

    // A record's first field, and its first field's, down to the type a use expects.
    private static Designator Descend(Designator designator, TypeNode? use)
    {
        TypeNode? target = use?.Find();
        Designator field = designator;
        for (int depth = 0; depth < 8; depth++)
        {
            TypeNode root = field.Type.Find();
            if (root.Kind != TypeKind.Record || root == target || root.Fields?.ContainsKey(0) != true) { break; }
            field = new FieldDesignator(field, 0);
        }

        return field;
    }

    // A load of fewer words than a record has is of its first field.
    private static Expr Narrow(Expr expression)
    {
        if (expression is not Load { Designator: var designator } load || load.Words == 0) { return expression; }

        Designator field = designator;
        for (int depth = 0; depth < 8; depth++)
        {
            TypeNode root = field.Type.Find();
            if (root.Kind != TypeKind.Record || SizeOf(root) is not { } size || size <= load.Words) { break; }
            field = new FieldDesignator(field, 0);
        }

        return field == designator ? expression : new Load(field, load.Words);
    }

    private static bool IsPunned(TypeNode type) => type.Find() is { Kind: TypeKind.Pointer, Punned: true };

    // The scalar kind a type is, or null when it is not a scalar.
    private static ScalarKind? Kind(TypeNode? type)
    {
        if (type is null) { return null; }
        TypeNode root = type.Find();
        return root.Kind == TypeKind.Scalar ? root.ScalarKind : null;
    }

    // The scalar kind an expression has of itself; null for a constant, which takes the kind its place expects.
    private static ScalarKind? Natural(Expr expression) => expression switch
    {
        Constant or Nil or Keyword => null,
        Checked check => Natural(check.Value),
        Written written => Natural(written.Value),
        Binary
        {
            Op: Operator.Add or Operator.Subtract or Operator.Multiply or Operator.Divide or Operator.Modulo
        } => ScalarKind.Integer,
        Binary { Op: Operator.And or Operator.Or } => ScalarKind.Boolean,
        Unary { Op: Operator.Negate or Operator.Absolute or Operator.Square } => ScalarKind.Integer,
        Unary { Op: Operator.Not } => ScalarKind.Boolean,
        Comparison => ScalarKind.Boolean,
        Load { Designator: IndexDesignator { Array: VariableDesignator { Variable: var bytes } } }
            when bytes.Type.Find() is { Kind: TypeKind.Scalar, ByteView: true } => ScalarKind.Char,
        Load { Designator: IndexDesignator { Index: Constant { Value: 0 }, High: null } length }
            when length.Array.Type.Find().Kind == TypeKind.String => ScalarKind.Integer,
        _ => Kind(expression.Type)
    };

    // ORD, CHR and ODD, which compile to nothing, make a scalar of one kind the kind its place expects.
    private static string Convert(string text, int level, ScalarKind? from, ScalarKind? to, out int result)
    {
        result = level;
        if (from is not { } source || to is not { } target || source == target) { return text; }

        result = Factor;
        return (source, target) switch
        {
            (ScalarKind.Integer, ScalarKind.Char) => $"CHR({text})",
            (ScalarKind.Integer, ScalarKind.Boolean) => $"ODD({text})",
            (ScalarKind.Char, ScalarKind.Boolean) => $"ODD(ORD({text}))",
            (ScalarKind.Boolean, ScalarKind.Char) => $"CHR(ORD({text}))",
            (ScalarKind.Enumeration, ScalarKind.Char) => $"CHR(ORD({text}))",
            (ScalarKind.Enumeration, ScalarKind.Boolean) => $"ODD(ORD({text}))",
            (_, ScalarKind.Integer) => $"ORD({text})",
            _ => Keep(text, level, out result)
        };
    }

    private static string Keep(string text, int level, out int result)
    {
        result = level;
        return text;
    }

    // An expression's text and how tightly it binds.
    private (string Text, int Level) Text(Expr expression, TypeNode? expected)
    {
        switch (expression)
        {
            case Constant constant:
                return (ConstantText(constant.Value, expected), constant.Value < 0 ? Adding : Factor);
            case Nil:
                return ("NIL", Factor);
            case Keyword keyword:
                return (keyword.Text, Factor);
            case WordsConstant words when words.Values.Length == 2:
                return (RealText(words.Values), Factor);
            case WordsConstant words:
                return (SetText(words.Values, expected?.Find().Element), Factor);
            case StringConstant text:
                return (Quote(text.Characters), Factor);
            case PackedConstant packed:
                return (Quote(packed.Bytes), Factor);
            case Load load:
                return (DesignatorText(load.Designator), Factor);
            case Address address:
                return (DesignatorText(address.Designator), Factor);
            case ByteAddress address:
                return (DesignatorText(address.Designator), Factor);
            case PackedAddress address:
                return (DesignatorText(address.Designator), Factor);
            case Checked check:
                return Text(check.Value, expected);
            case Written written:
                return Text(written.Value, expected);
            case Unary unary:
                return UnaryText(unary, expected);
            case Binary binary:
                return BinaryText(binary);
            case Comparison comparison:
                return ComparisonText(comparison);
            case SetValue set:
                return SetValueText(set);
            case Call call:
                return (CallText(call), Factor);
            case StringFunction function:
                return ($"{function.Name}({string.Join(", ", function.Arguments.Select((argument, index) => index > 0 && function.Name == "COPY" ? Expression(argument, TypeNode.Scalar(ScalarKind.Integer), 0) : Expression(argument, expected: null, 0)))})", Factor);
            default:
                return ("?", Factor);
        }
    }

    private string ConstantText(int value, TypeNode? expected)
    {
        TypeNode? root = expected?.Find();
        if (root?.Kind == TypeKind.Pointer && value == 0) { return "NIL"; }
        if (root is not { Kind: TypeKind.Scalar }) { return value.ToString(CultureInfo.InvariantCulture); }

        switch (root.ScalarKind)
        {
            case ScalarKind.Char:
                return Character(value);
            case ScalarKind.Boolean:
                return value switch { 0 => "FALSE", 1 => "TRUE", _ => $"ODD({value})" };
            case ScalarKind.Enumeration:
                {
                    string? enumeration = root.Enumeration;
                    IReadOnlyList<string>? names = _library?.Units
                        .Select(unit => enumeration is not null && unit.Enumerations.TryGetValue(enumeration, out IReadOnlyList<string>? values) ? values : null)
                        .FirstOrDefault(values => values is not null);

                    return names is not null && value >= 0 && value < names.Count ? names[value] : value.ToString(CultureInfo.InvariantCulture);
                }

            default:
                return value.ToString(CultureInfo.InvariantCulture);
        }
    }

    // A constant LDCI loaded though SLDC holds it, whose negation is a declared constant's.
    private static int? Wide(Expr expression) => expression is Constant { Wide: true } constant ? constant.Value : null;

    // A negative constant the program declares, by the name the source's CONST gives it.
    private string Declared(int value)
    {
        if (!_constants.TryGetValue(value, out string? name))
        {
            name = $"NEG{-value}";
            _constants[value] = name;
        }

        return name;
    }

    private (string Text, int Level) UnaryText(Unary unary, TypeNode? expected)
    {
        TypeNode integer = TypeNode.Scalar(ScalarKind.Integer);
        TypeNode real = TypeNode.Of(TypeKind.Real);
        return unary.Op switch
        {
            Operator.Negate when Wide(unary.Operand) is int magnitude => (Declared(-magnitude), Factor),
            Operator.Negate when unary.Operand is Constant constant => ($"-{constant.Value.ToString(CultureInfo.InvariantCulture)}", Adding),
            Operator.Negate => ($"-{Expression(unary.Operand, integer, Multiplying)}", Adding),
            Operator.RealNegate => ($"-{Expression(unary.Operand, real, Multiplying)}", Adding),
            Operator.Absolute => ($"ABS({Expression(unary.Operand, integer, 0)})", Factor),
            Operator.RealAbsolute => ($"ABS({Expression(unary.Operand, real, 0)})", Factor),
            Operator.Square => ($"SQR({Expression(unary.Operand, integer, 0)})", Factor),
            Operator.RealSquare => ($"SQR({Expression(unary.Operand, real, 0)})", Factor),
            Operator.Not => ($"NOT {Expression(unary.Operand, TypeNode.Scalar(ScalarKind.Boolean), Factor)}", Factor),
            Operator.Float => Text(unary.Operand, integer) is var inner && Natural(unary.Operand) is { } kind and not ScalarKind.Integer
                ? (Convert(inner.Text, inner.Level, kind, ScalarKind.Integer, out int level), level)
                : Text(unary.Operand, integer),
            _ => ("?", Factor)
        };
    }

    private (string Text, int Level) BinaryText(Binary binary)
    {
        (string symbol, int level, TypeNode operand) = binary.Op switch
        {
            Operator.Add => ("+", Adding, TypeNode.Scalar(ScalarKind.Integer)),
            Operator.Subtract => ("-", Adding, TypeNode.Scalar(ScalarKind.Integer)),
            Operator.Multiply => ("*", Multiplying, TypeNode.Scalar(ScalarKind.Integer)),
            Operator.Divide => ("DIV", Multiplying, TypeNode.Scalar(ScalarKind.Integer)),
            Operator.Modulo => ("MOD", Multiplying, TypeNode.Scalar(ScalarKind.Integer)),
            Operator.And => ("AND", Multiplying, TypeNode.Scalar(ScalarKind.Boolean)),
            Operator.Or => ("OR", Adding, TypeNode.Scalar(ScalarKind.Boolean)),
            Operator.RealAdd => ("+", Adding, TypeNode.Of(TypeKind.Real)),
            Operator.RealSubtract => ("-", Adding, TypeNode.Of(TypeKind.Real)),
            Operator.RealMultiply => ("*", Multiplying, TypeNode.Of(TypeKind.Real)),
            Operator.RealDivide => ("/", Multiplying, TypeNode.Of(TypeKind.Real)),
            _ => ("?", Factor, TypeNode.Scalar(ScalarKind.Integer))
        };

        // Pascal's binary operators group to the left, so the right operand binds one level tighter.
        string left = Expression(binary.Left, operand, level);
        string right = Expression(binary.Right, operand, level + 1);
        return ($"{left} {symbol} {right}", level);
    }

    private (string Text, int Level) ComparisonText(Comparison comparison)
    {
        string symbol = comparison.Op switch
        {
            Operator.Equal => "=",
            Operator.NotEqual => "<>",
            Operator.Less => "<",
            Operator.LessEqual => "<=",
            Operator.Greater => ">",
            Operator.GreaterEqual => ">=",
            _ => "IN"
        };

        TypeNode? left = comparison.Comparand switch
        {
            Comparand.Boolean => TypeNode.Scalar(ScalarKind.Boolean),
            Comparand.Real => TypeNode.Of(TypeKind.Real),
            Comparand.Set when comparison.Op == Operator.In => comparison.Right.Type.Find().Element,
            Comparand.Word => comparison.Right is Constant ? comparison.Left.Type : comparison.Right.Type,
            _ => null
        };

        TypeNode? right = comparison.Comparand switch
        {
            Comparand.Set when comparison.Op == Operator.In => null,
            Comparand.Word => comparison.Left is Constant ? comparison.Right.Type : comparison.Left.Type,
            _ => left
        };

        return ($"{Expression(comparison.Left, left, Adding)} {symbol} {Expression(comparison.Right, right, Adding)}", Relational);
    }

    // A set: a variable, a constructor, or set operators between them.
    private (string Text, int Level) SetValueText(SetValue set)
    {
        TypeNode? element = set.Type.Find().Element;
        if (set.Op is { } op && set.Left is { } left && set.Right is { } right)
        {
            // A union of constructors is one constructor: the Compiler builds [A, B] as [A] + [B].
            if (op == Operator.Union && IsConstructor(left) && IsConstructor(right))
            {
                return ($"[{string.Join(", ", Members(left).Concat(Members(right)).Where(member => member.Length > 0))}]", Factor);
            }

            (string symbol, int level) = op switch
            {
                Operator.Union => ("+", Adding),
                Operator.Difference => ("-", Adding),
                _ => ("*", Multiplying)
            };

            return ($"{Expression(left, expected: null, level)} {symbol} {Expression(right, expected: null, level + 1)}", level);
        }

        if (set.Value is { } value)
        {
            return value switch
            {
                Constant constant => (SetText([(ushort)constant.Value], element), Factor),
                WordsConstant words => (SetText(words.Values, element), Factor),
                _ => Text(value, expected: null)
            };
        }

        return ($"[{string.Join(", ", Members(set))}]", Factor);
    }

    private static bool IsConstructor(SetValue set) => set.Op is null
        ? set.Value is null or Constant or WordsConstant
        : set is { Op: Operator.Union, Left: { } left, Right: { } right }
            && IsConstructor(left)
            && IsConstructor(right);

    private IEnumerable<string> Members(SetValue set)
    {
        TypeNode? element = set.Type.Find().Element;
        if (set is { Op: not null, Left: { } left, Right: { } right })
        {
            foreach (string member in Members(left).Concat(Members(right))) { yield return member; }
            yield break;
        }

        if (set.Value is Constant constant)
        {
            string text = SetText([(ushort)constant.Value], element);
            yield return text[1..^1];
            yield break;
        }

        if (set.Value is WordsConstant words)
        {
            string text = SetText(words.Values, element);
            yield return text[1..^1];
            yield break;
        }

        foreach ((Expr low, Expr? high) in set.Members)
        {
            yield return high is null
                ? Expression(low, element, 0)
                : $"{Expression(low, element, 0)}..{Expression(high, element, 0)}";
        }
    }

    // A constant set's members from its words, the highest word first, as runs.
    private string SetText(ushort[] words, TypeNode? element)
    {
        List<string> parts = [];
        TypeNode type = element ?? TypeNode.Scalar(ScalarKind.Integer);
        int bits = words.Length * 16;
        int member = 0;
        while (member < bits)
        {
            if (!Has(words, member))
            {
                member++;
                continue;
            }

            int end = member;
            while (end + 1 < bits && Has(words, end + 1)) { end++; }
            parts.Add(end == member ? Value(member, type) : end == member + 1 ? $"{Value(member, type)}, {Value(end, type)}" : $"{Value(member, type)}..{Value(end, type)}");
            member = end + 1;
        }

        return $"[{string.Join(", ", parts)}]";
    }

    private static bool Has(ushort[] words, int member) => (words[words.Length - 1 - (member / 16)] & (1 << (member % 16))) != 0;

    // A real constant, as the shortest decimal that reads back as its bits.
    private static string RealText(ushort[] words)
    {
        int bits = (words[0] << 16) | words[1];
        float value = BitConverter.Int32BitsToSingle(bits);
        string text = value.ToString("R", CultureInfo.InvariantCulture).Replace("E+", "E", StringComparison.Ordinal);
        if (!text.Contains('.', StringComparison.Ordinal))
        {
            int exponent = text.IndexOf('E', StringComparison.Ordinal);
            text = exponent < 0 ? text + ".0" : text[..exponent] + ".0" + text[exponent..];
        }

        return text;
    }

    private static string Quote(byte[] characters) =>
        $"'{new string([.. characters.Select(value => (char)(value & 0x7F))]).Replace("'", "''", StringComparison.Ordinal)}'";

    private string CallText(Call call)
    {
        Callee callee = call.Callee;
        if (callee.Procedure is { } procedure)
        {
            return Invocation(procedure.Name, Arguments(procedure, call.Arguments));
        }

        if (callee.UnitProcedure is { } declared)
        {
            return Invocation(declared.Name, UnitArguments(declared, call.Arguments));
        }

        string name = callee.Builtin ?? "?";
        List<string> parts = name switch
        {
            "EOF" or "EOLN" => [FileName(new Argument(call.Arguments[0]))],
            "TRUNC" or "ROUND" => [Expression(call.Arguments[0], TypeNode.Of(TypeKind.Real), 0)],
            "UNITBUSY" or "PWROFTEN" => [Expression(call.Arguments[0], TypeNode.Scalar(ScalarKind.Integer), 0)],
            _ => [.. call.Arguments.Select(argument => Expression(argument, expected: null, 0))]
        };

        return Invocation(name, parts);
    }
}
