// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    private bool Ca65TypeLine(Line line)
    {
        Split(line.Text.Span, out ReadOnlySpan<char> label, out ReadOnlySpan<char> op, out ReadOnlySpan<char> tail);
        string name = label.ToString();
        if (!op.IsEmpty && op[0] != '.' && tail.StartsWith("."))
        {
            name = op.ToString();
            int space = 0;
            while (space < tail.Length && !char.IsWhiteSpace(tail[space])) { space++; }
            op = tail[..space];
            tail = tail[space..].Trim();
        }

        string operation = op.ToString().ToUpperInvariant();
        Ca65State state = Ca65;
        if (op.IsEmpty && name.Length == 0) { return state.Types.Count != 0; }
        if (operation is ".STRUCT" or ".UNION" or ".ENUM")
        {
            string member = name;
            name = tail.ToString();

            if (name.Length != 0 && !AssemblySyntax.IsPlainIdentifier(name))
            {
                throw new AssemblyError(0, "Invalid type name.");
            }

            long start = state.Types.Count == 0 ? 0 : state.Types[^1].Position;
            string? memberKey = null;
            if (state.Types.Count != 0 && member.Length != 0)
            {
                Emit(line, $"{member} = {start}");
                memberKey = ConstantQualified(_constantScope, member);
            }

            string qualified = ConstantQualified(_constantScope, name);
            if (name.Length != 0) { Emit(line, $".scope {name}"); }
            state.Types.Add(new(operation, name, qualified, name.Length == 0 ? start : 0, line.Location)
            {
                Member = memberKey
            });

            return true;
        }

        if (operation is ".ENDSTRUCT" or ".ENDUNION" or ".ENDENUM")
        {
            if (state.Types.Count == 0 || operation != $".END{state.Types[^1].Kind[1..]}")
            {
                throw new AssemblyError(0, "Type terminator does not match an open type.");
            }

            if (!tail.IsEmpty || name.Length != 0)
            {
                throw new AssemblyError(0, "A type terminator takes no operand or label.");
            }

            TypeFrame frame = state.Types[^1];
            state.Types.RemoveAt(state.Types.Count - 1);
            long size = frame.End;
            if (frame.Member is { } memberName) { state.Sizes[memberName] = size; }
            if (frame.Name.Length != 0)
            {
                if (!state.Sizes.TryAdd(frame.Qualified, size)) { throw new AssemblyError(0, "Duplicate type size."); }
                Emit(line, ".endscope");
            }

            if (state.Types.Count != 0)
            {
                TypeFrame parent = state.Types[^1];
                parent.End = parent.Kind == ".UNION" ? Math.Max(parent.End, size) : checked(parent.End + size);
                if (parent.Kind != ".UNION") { parent.Position = checked(parent.Position + size); }
            }

            return true;
        }

        if (state.Types.Count == 0) { return false; }
        TypeFrame current = state.Types[^1];
        if (current.Kind == ".ENUM")
        {
            AssemblyStatement? assignment = Assembler.ParseLine(line.Text, 0, out _, out _);
            if (assignment is { Kind: AssemblyStatementKind.Constant, Label: { } assigned })
            {
                name = assigned;
                current.Position = Ca65Value(assignment.Operand.Text);
            }
            else if (name.Length != 0 || !AssemblySyntax.IsPlainIdentifier(op) || !tail.IsEmpty)
            {
                throw new AssemblyError(0, "Expected an enum member.");
            }
            else
            {
                name = op.ToString();
            }

            // Enum values may be negative, and the current culture can spell the minus sign differently.
            Emit(line, string.Create(CultureInfo.InvariantCulture, $"{name} = {current.Position}"));
            current.Position = checked(current.Position + 1);
            return true;
        }

        if (operation == ".ORG")
        {
            current.Position = Ca65Value(tail.ToString());
            return true;
        }

        int width = operation switch
        {
            ".BYTE" or ".BYT" or ".RES" => 1,
            ".WORD" or ".ADDR" or ".DBYT" => 2,
            ".FARADDR" => 3,
            ".DWORD" => 4,
            ".TAG" => 0,
            _ => -1
        };

        if (width < 0) { throw new AssemblyError(0, $"Unsupported type member directive '{op}'."); }
        List<string> args = Ca65Frontend.Split(tail.ToString());
        long count = 1;
        long stride = width;
        if (operation == ".TAG")
        {
            if (args.Count is < 1 or > 2 || Ca65Size(args[0]) is not { } typeSize)
            {
                throw new AssemblyError(0, ".tag requires a known type and optional count.");
            }

            stride = typeSize;
            if (args.Count == 2) { count = Ca65Value(args[1]); }
        }
        else
        {
            if (args.Count > 1) { throw new AssemblyError(0, "A type field takes at most one element count."); }
            if (args.Count == 1) { count = Ca65Value(args[0]); }
        }

        // As in ca65, an explicit element count must be at least one.
        if (count < 1) { throw new AssemblyError(0, "A type field count must be positive."); }
        long fieldSize = checked(stride * count);
        if (name.Length != 0)
        {
            Emit(line, $"{name} = {current.Position}");
            if (!state.Sizes.TryAdd(ConstantQualified(_constantScope, name), fieldSize))
            {
                throw new AssemblyError(0, $"Duplicate type field '{name}'.");
            }
        }

        current.End = current.Kind == ".UNION" ? Math.Max(current.End, fieldSize) : checked(current.End + fieldSize);
        if (current.Kind != ".UNION") { current.Position = checked(current.Position + fieldSize); }
        return true;
    }

    private long? Ca65Size(string name)
    {
        if (name.StartsWith("::", StringComparison.Ordinal))
        {
            return Ca65.Sizes.TryGetValue(name[2..], out long absolute) ? absolute : null;
        }

        string scope = _constantScope;
        while (true)
        {
            if (Ca65.Sizes.TryGetValue(ConstantQualified(scope, name), out long size)) { return size; }
            if (scope.Length == 0) { return null; }
            int separator = scope.LastIndexOf("::", StringComparison.Ordinal);
            scope = separator < 0 ? "" : scope[..separator];
        }
    }

    private long Ca65Value(string text) => Ca65TryValue(text)
        ?? throw new AssemblyError(0, "ca65 directive requires a constant known at this point.");

    private long? Ca65TryValue(string text)
    {
        string expression = _nativeSyntax ? text : Ca65Expression.Translate(text, _options.BuildTime) ?? text;
        ExpressionEvaluator evaluator = new(ConstantExpression(expression).AsMemory(), _constants, 0, 0);
        return evaluator.TryEvaluate(out long value) && !evaluator.ReadsAddress ? value : null;
    }
}
