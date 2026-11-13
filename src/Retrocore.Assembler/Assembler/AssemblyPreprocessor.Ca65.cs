// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    private Ca65State? _ca65State;

    private Ca65State Ca65 => _ca65State ??= new() { Cpu = Ca65CpuNumber(_cpu ?? _options.Cpu) };

    /// <summary>
    ///  Gets ca65's <c>.cpu</c> value for a CPU name: the instruction-set bits its <c>.ifp*</c> tests compare.
    /// </summary>
    /// <param name="name">A native <c>.cpu</c> name, in any case.</param>
    /// <returns>The value, which is 0 for a CPU outside the 6502 family, such as the Z80 or the 8080.</returns>
    private static int Ca65CpuNumber(string? name) =>
        name switch
        {
            _ when string.Equals(name, "65SC02", StringComparison.OrdinalIgnoreCase) => 18,
            _ when string.Equals(name, "Rockwell65C02", StringComparison.OrdinalIgnoreCase) => 50,
            _ when string.Equals(name, "Wdc65C02", StringComparison.OrdinalIgnoreCase) => 4146,
            _ when string.Equals(name, "Z80", StringComparison.OrdinalIgnoreCase) => 0,
            _ when string.Equals(name, "M6809", StringComparison.OrdinalIgnoreCase) => 0,
            _ when string.Equals(name, "I8080", StringComparison.OrdinalIgnoreCase) => 0,
            _ when string.Equals(name, "I8085", StringComparison.OrdinalIgnoreCase) => 0,
            _ => 2
        };

    private bool PrepareCa65(ref Line original, ref ReadOnlyMemory<char> text)
    {
        Split(
            text.Span,
            out ReadOnlySpan<char> initialLabel,
            out ReadOnlySpan<char> initialOperation,
            out ReadOnlySpan<char> initialOperand);

        if (!NeedsCa65Expansion(text.Span, initialLabel, initialOperation, initialOperand)) { return false; }
        bool active = _conditions.Count == 0 || _conditions[^1].Active;
        original = new(text, original.Location, original.Dialect);
        if (Ca65Definition(original, active)) { return true; }
        if (!active) { return false; }
        original = new(ExpandCa65Functions(ExpandCa65Definitions(AssemblySyntax.AsString(text))), original.Location, original.Dialect);
        text = original.Text;
        Split(text.Span, out ReadOnlySpan<char> label, out ReadOnlySpan<char> op, out ReadOnlySpan<char> operand);
        string operation = op.ToString().ToUpperInvariant();
        if (operation == ".CHARMAP")
        {
            List<string> args = Ca65Frontend.Split(operand.ToString());
            if (args.Count != 2) { throw new AssemblyError(0, ".charmap requires source and destination bytes."); }
            long from = Ca65Value(args[0]);
            long to = Ca65Value(args[1]);
            if (from is < 0 or > 255 || to is < 0 or > 255)
            {
                throw new AssemblyError(0, "Character-map values must fit in a byte.");
            }

            Ca65.Characters[(int)from] = (byte)to;
            Ca65.CharactersChanged = true;
            return true;
        }

        if (operation is ".ERROR" or ".FATAL") { throw new AssemblyError(0, Ca65String(operand.ToString())); }
        if (operation is ".OUT" or ".WARNING" or ".DEBUGINFO" or ".LIST" or ".SMART") { return true; }
        if (operation == ".FEATURE")
        {
            return operand.ToString().Equals("ubiquitous_idents", StringComparison.OrdinalIgnoreCase)
                ? true
                : throw new AssemblyError(0, $"Unsupported ca65 feature '{operand}'.");
        }

        if (operation is ".IFREF" or ".IFNREF")
        {
            throw new AssemblyError(0, "Reference-dependent conditionals are unsupported.");
        }

        if (IsDirective(op)) { return false; }
        bool typeOpening = operation is ".STRUCT" or ".UNION" or ".ENUM";
        if ((typeOpening || _ca65State?.Types.Count > 0) && Ca65TypeLine(original)) { return true; }
        if (operation == ".PROC" && !label.IsEmpty)
        {
            Emit(original, $"{label}:");
            text = $".proc {operand}".AsMemory();
        }

        if (operation == ".TAG")
        {
            List<string> args = Ca65Frontend.Split(operand.ToString());
            long? knownSize = args.Count is 1 or 2 ? Ca65Size(args[0]) : null;
            if (knownSize is not { } size)
            {
                throw new AssemblyError(0, ".tag requires a known type.");
            }

            long count = args.Count == 1 ? 1 : Ca65Value(args[1]);
            if (count < 0) { throw new AssemblyError(0, ".tag count must be nonnegative."); }
            long total = checked(size * count);
            if (!label.IsEmpty) { Ca65.Sizes[ConstantQualified(_constantScope, label.ToString())] = total; }
            text = (label.IsEmpty ? $".res {total}" : $"{label}: .res {total}").AsMemory();
        }
        else if (operation is ".BYTE" or ".BYT" or ".ASCIIZ" or ".LOBYTES" or ".HIBYTES")
        {
            text = MapCa65Data(AssemblySyntax.AsString(text)).AsMemory();
        }

        return false;
    }

    private bool NeedsCa65Expansion(
        ReadOnlySpan<char> text,
        ReadOnlySpan<char> label,
        ReadOnlySpan<char> operation,
        ReadOnlySpan<char> operand)
    {
        if (_ca65State is { } state)
        {
            // Only a line that names a definition or contains a quoted string needs the definition or character map.
            if (state.Types.Count != 0
                || (state.Defines.Count != 0 && MentionsDefinition(text, state))
                || (state.CharactersChanged && text.IndexOfAny('"', '\'') >= 0))
            {
                return true;
            }
        }

        if (operand.IndexOfAny('.', '\'') >= 0 || operand.IndexOf("CPU_", StringComparison.Ordinal) >= 0)
        {
            return true;
        }

        if (operation.IsEmpty || operation[0] != '.') { return false; }
        bool labelOnProcedure = !label.IsEmpty && operation.Equals(".proc", StringComparison.OrdinalIgnoreCase);
        return labelOnProcedure || IsCa65Condition(operation) || IsCa65Metadata(operation);
    }

    private static bool IsCa65Metadata(ReadOnlySpan<char> operation) =>
        operation.Equals(".struct", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".union", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".enum", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".define", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".undefine", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".charmap", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".asciiz", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".byt", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".lobytes", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".hibytes", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".tag", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".out", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".warning", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".error", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".fatal", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".feature", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".debuginfo", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".list", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".smart", StringComparison.OrdinalIgnoreCase)
            || operation.StartsWith(".ident", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".ifref", StringComparison.OrdinalIgnoreCase)
            || operation.Equals(".ifnref", StringComparison.OrdinalIgnoreCase);
}
