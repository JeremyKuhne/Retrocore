// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    /// <summary>
    ///  Formats ca65's <c>.sprintf</c>, a C-style format applied to constant and string arguments.
    /// </summary>
    /// <param name="args">The expanded format string and arguments.</param>
    /// <returns>The resulting string literal.</returns>
    /// <remarks>
    ///  <para>
    ///   As in ca65, each conversion (<c>%c %d %i %o %s %u %x %X</c>) may carry the flags <c>- + 0 #</c> and space,
    ///   a width and a precision; <c>%%</c> is a percent sign.
    ///  </para>
    /// </remarks>
    private string Sprintf(string args)
    {
        List<string> parts = Ca65Frontend.Split(args);
        if (parts.Count == 0) { throw new AssemblyError(0, ".sprintf requires a format string."); }
        string format = Ca65String(parts[0].Trim());
        List<string> result = [];
        int next = 1;
        for (int index = 0; index < format.Length; index++)
        {
            char character = format[index];
            if (character != '%')
            {
                result.Add(character.ToString());
                continue;
            }

            if (++index == format.Length) { throw new AssemblyError(0, "Incomplete .sprintf conversion."); }
            if (format[index] == '%')
            {
                result.Add("%");
                continue;
            }

            bool left = false, plus = false, space = false, zero = false, alternate = false;
            for (; index < format.Length && format[index] is '-' or '+' or ' ' or '0' or '#'; index++)
            {
                switch (format[index])
                {
                    case '-':
                        left = true;
                        break;
                    case '+':
                        plus = true;
                        break;
                    case ' ':
                        space = true;
                        break;
                    case '0':
                        zero = true;
                        break;
                    default:
                        alternate = true;
                        break;
                }
            }

            int width = ReadNumber(format, ref index);
            int precision = -1;
            if (index < format.Length && format[index] == '.')
            {
                index++;
                precision = ReadNumber(format, ref index);
            }

            if (index == format.Length) { throw new AssemblyError(0, "Incomplete .sprintf conversion."); }
            char conversion = format[index];
            if (next >= parts.Count) { throw new AssemblyError(0, ".sprintf has too few arguments."); }
            string argument = parts[next++].Trim();
            string text;
            string sign = "";
            if (conversion == 's')
            {
                text = Ca65String(argument);
                if (precision >= 0 && precision < text.Length) { text = text[..precision]; }
                zero = false;
            }
            else
            {
                long value = Ca65Value(argument);
                switch (conversion)
                {
                    case 'c':
                        text = ((char)(byte)value).ToString();
                        zero = false;
                        break;
                    case 'd':
                    case 'i':
                        sign = value < 0 ? "-" : plus ? "+" : space ? " " : "";
                        text = Math.Abs(value).ToString(CultureInfo.InvariantCulture);
                        break;
                    case 'u':
                        text = ((ulong)value).ToString(CultureInfo.InvariantCulture);
                        break;
                    case 'o':
                        text = Convert.ToString(value, 8);
                        if (alternate && text[0] != '0') { text = "0" + text; }
                        break;
                    case 'x':
                    case 'X':
                        text = value.ToString(conversion == 'x' ? "x" : "X", CultureInfo.InvariantCulture);
                        if (alternate && value != 0) { sign = conversion == 'x' ? "0x" : "0X"; }
                        break;
                    default:
                        throw new AssemblyError(0, $"Unsupported .sprintf conversion '%{conversion}'.");
                }

                // As in C, a precision is the minimum digit count and disables zero padding.
                if (precision >= 0)
                {
                    text = text.PadLeft(precision, '0');
                    zero = false;
                }
            }

            int padding = width - sign.Length - text.Length;
            if (padding > 0 && !left && !zero) { result.Add(new(' ', padding)); }
            result.Add(sign);
            if (padding > 0 && zero && !left) { result.Add(new('0', padding)); }
            result.Add(text);
            if (padding > 0 && left) { result.Add(new(' ', padding)); }
        }

        if (next != parts.Count) { throw new AssemblyError(0, ".sprintf has too many arguments."); }
        string formatted = string.Concat(result);
        return formatted.Contains('"')
            ? throw new AssemblyError(0, ".sprintf cannot produce a quote.")
            : $"\"{formatted}\"";
    }

    private static int ReadNumber(string text, ref int index)
    {
        int value = 0;
        for (; index < text.Length && char.IsAsciiDigit(text[index]); index++)
        {
            value = checked((value * 10) + text[index] - '0');
        }

        return value;
    }

    /// <summary>
    ///  Evaluates ca65's <c>.min</c> and <c>.max</c>, as a constant when both values are known.
    /// </summary>
    /// <param name="name">The lowercase function name.</param>
    /// <param name="args">The two expanded arguments.</param>
    /// <returns>The value, or an equivalent expression valid in both ca65 and native syntax.</returns>
    private string MinMax(string name, string args)
    {
        List<string> parts = Ca65Frontend.Split(args);
        if (parts.Count != 2) { throw new AssemblyError(0, $"{name} requires two values."); }
        string a = parts[0].Trim();
        string b = parts[1].Trim();
        bool max = name == ".max";
        if (Ca65TryValue(a) is { } first && Ca65TryValue(b) is { } second)
        {
            return (max ? Math.Max(first, second) : Math.Min(first, second)).ToString(CultureInfo.InvariantCulture);
        }

        string compare = max ? ">=" : "<=";
        return $"((({a}) {compare} ({b})) * ({a}) + (1 - (({a}) {compare} ({b}))) * ({b}))";
    }
}
