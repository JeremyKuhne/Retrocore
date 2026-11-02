// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    private bool Ca65Condition(string operation, string operand)
    {
        operand = ExpandCa65Functions(ExpandCa65Definitions(operand), expression: true);
        if (operation == ".IFNBLANK") { return !string.IsNullOrWhiteSpace(operand); }
        if (operation == ".IFCONST") { return Ca65TryValue(operand) is not null; }
        if (operation == ".IFNCONST") { return Ca65TryValue(operand) is null; }
        if (operation.StartsWith(".IFP", StringComparison.Ordinal))
        {
            return operand.Length != 0
                ? throw new AssemblyError(0, "A CPU conditional takes no operand.")
                : operation switch
            {
                ".IFP02" => Ca65.Cpu == 2,
                ".IFPSC02" => Ca65.Cpu == 18,
                ".IFPC02" => Ca65.Cpu == 50,
                ".IFPWC02" => Ca65.Cpu == 4146,
                _ => false
            };
        }

        if (operation is ".IFDEF" or ".IFNDEF")
        {
            if (!AssemblySyntax.IsIdentifier(operand))
            {
                throw new AssemblyError(0, "Expected a conditional identifier.");
            }

            // As in ca65, a macro name is not a defined symbol.
            bool defined = _defined.Contains(ConstantName(operand));
            return operation == ".IFDEF" ? defined : !defined;
        }

        return operation == ".IFBLANK"
            ? string.IsNullOrWhiteSpace(operand)
            : Ca65Truth(Ca65CharacterExpression(operand))
                ?? throw new AssemblyError(
                    0,
                    _nativeSyntax
                        ? "Conditional requires a constant known at this point in source order."
                        : "ca65 directive requires a constant known at this point.");
    }

    /// <summary>
    ///  Evaluates a condition, deciding a logical operator from one known operand when another is unknown.
    /// </summary>
    /// <param name="text">The condition.</param>
    /// <returns>The truth value, or null when it depends on values known only after layout.</returns>
    /// <remarks>
    ///  <para>
    ///   Conditions run before layout, so an operand that reads <c>*</c> is unknown here. One known-false
    ///   <c>.and</c> operand, or one known-true <c>.or</c> operand, still decides the result. cc65's
    ///   <c>longbranch.mac</c> relies on this: <c>.const</c> of a location-counter expression is 0 here, so its
    ///   branch macros take the always-valid long form.
    ///  </para>
    /// </remarks>
    private bool? Ca65Truth(string text)
    {
        if (Ca65TryValue(text) is { } value) { return value != 0; }
        foreach (string[] operators in s_logicalLevels)
        {
            List<string> parts = Ca65SplitLogical(text, operators);
            if (parts.Count < 2) { continue; }
            bool or = operators[0] == "||";
            bool unknown = false;
            foreach (string part in parts)
            {
                bool? truth = Ca65Truth(part);
                if (truth == or) { return or; }
                unknown |= truth is null;
            }

            return unknown ? null : !or;
        }

        return null;
    }

    // ca65 binds .and more tightly than .or, so a condition splits at .or first.
    private static readonly string[][] s_logicalLevels = [["||", ".or"], ["&&", ".and"]];

    private static List<string> Ca65SplitLogical(string text, string[] operators)
    {
        List<string> parts = [];
        int depth = 0;
        int start = 0;
        for (int index = 0; index < text.Length; index++)
        {
            char character = text[index];
            if (character is '"' or '\'')
            {
                int close = text.IndexOf(character, index + 1);
                if (close < 0) { break; }
                index = close;
                continue;
            }

            if (character == '(') { depth++; }
            if (character == ')') { depth--; }
            if (depth != 0) { continue; }
            foreach (string op in operators)
            {
                bool word = op[0] == '.';
                bool matches = string.Compare(text, index, op, 0, op.Length, StringComparison.OrdinalIgnoreCase) == 0
                    && (!word || index + op.Length == text.Length || !AssemblySyntax.IsWord(text[index + op.Length]));

                if (!matches) { continue; }
                parts.Add(text[start..index]);
                start = index + op.Length;
                index = start - 1;
                break;
            }
        }

        parts.Add(text[start..]);
        return parts;
    }

    private static bool IsCa65Condition(ReadOnlySpan<char> operation) =>
        operation.StartsWith(".if", StringComparison.OrdinalIgnoreCase)
            && (operation.Equals(".ifnblank", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".ifconst", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".ifnconst", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".ifp02", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".ifpc02", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".ifpsc02", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".ifp816", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".ifp4510", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".ifp6280", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".ifp02x", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".ifp45gs02", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".ifpce02", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".ifpdtv", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".ifpm740", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".ifpsweet16", StringComparison.OrdinalIgnoreCase)
                || operation.Equals(".ifpwc02", StringComparison.OrdinalIgnoreCase));
}
