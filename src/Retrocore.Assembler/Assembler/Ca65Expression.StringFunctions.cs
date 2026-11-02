// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

namespace Retrocore.Assembler;

internal ref partial struct Ca65Expression
{
    /// <summary>
    ///  Evaluates shared string and identifier functions without changing ca65 token spelling.
    /// </summary>
    /// <param name="name">The lowercase function name.</param>
    /// <param name="args">Expanded arguments.</param>
    /// <param name="number">A source-order numeric resolver.</param>
    /// <returns>Replacement text, or null for a different function.</returns>
    internal static string? StringFunction(string name, string args, Func<string, long?> number)
    {
        switch (name)
        {
            case ".concat":
                return $"\"{string.Concat(Ca65Frontend.Split(args).Select(StringValue))}\"";
            case ".ident":
                string identifier = StringValue(args.Trim());
                if (!AssemblySyntax.IsPlainIdentifier(identifier))
                {
                    throw new AssemblyError(0, ".ident requires an identifier string.");
                }

                return identifier;
            case ".strlen":
                return StringValue(args.Trim()).Length.ToString();
            case ".string":
                string text = args.Trim();
                if (AssemblySyntax.IsIdentifier(text)) { return $"\"{text}\""; }
                long value = number(text) ?? throw new AssemblyError(0, ".string requires an identifier or constant expression.");

                // The value may be negative, and the current culture can spell the minus sign differently.
                return string.Create(CultureInfo.InvariantCulture, $"\"{value}\"");
            default:
                return null;
        }
    }

    private static string StringValue(string value) =>
        value.Length >= 2 && value[0] is '"' or '\'' && value[^1] == value[0]
            ? value[1..^1] : throw new AssemblyError(0, "Expected a ca65 string.");

    private static long? FunctionNumber(string text)
    {
        string expression = Translate(text, DateTimeOffset.FromUnixTimeSeconds(0)) ?? text;
        AssemblySymbols symbols = new();
        ExpressionEvaluator value = new(expression.AsMemory(), symbols, 0, 0);
        return value.TryEvaluate(out long number) && !value.ReadsAddress ? number : null;
    }
}
