// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    private string ExpandCa65Functions(string text, int depth = 0, bool expression = false)
    {
        ReadOnlySpan<char> source = text;
        if (depth >= _options.MaximumMacroDepth)
        {
            throw new AssemblyError(0, "Maximum ca65 function nesting exceeded.");
        }

        StringBuilder? result = null;
        int copied = 0;
        AssemblyNameReferences cursor = new(text.AsMemory());
        while (cursor.MoveNext())
        {
            int start = cursor.Start;
            if (start < copied) { continue; }
            ReadOnlySpan<char> word = cursor.Current.Span;
            // ca65 predefines its CPU symbols; native sources may define their own names.
            bool cpu = !_nativeSyntax
                && (word.StartsWith("CPU_", StringComparison.Ordinal) || word.StartsWith("::CPU_", StringComparison.Ordinal));

            if (word[0] != '.' && !cpu) { continue; }

            string token = cursor.Current.ToString();
            string? replacement = null;
            int end = start + token.Length;
            int opening = end;
            while (opening < text.Length && char.IsWhiteSpace(text[opening])) { opening++; }
            if (token[0] == '.' && opening < text.Length && text[opening] == '(')
            {
                end = Ca65FunctionEnd(text, opening);
                string args = ExpandCa65Functions(text[(opening + 1)..(end - 1)], depth + 1, expression: true);
                replacement = Ca65Function(token.ToLowerInvariant(), args);
                if (replacement is null && args != text[(opening + 1)..(end - 1)])
                {
                    replacement = $"{text.AsSpan(start, opening + 1 - start)}{args})";
                }
            }
            else if (!_nativeSyntax
                && token.Equals(".cpu", StringComparison.OrdinalIgnoreCase)
                && (expression || !source[..start].Trim().IsEmpty))
            {
                replacement = Ca65.Cpu.ToString();
            }
            else
            {
                replacement = CpuConstant(token[0] == ':' ? token[2..] : token);
            }

            if (replacement is null) { continue; }
            result ??= new(text.Length);
            result.Append(text, copied, start - copied).Append(replacement);
            copied = end;
        }

        return result is null ? text : result.Append(text, copied, text.Length - copied).ToString();
    }

    // ca65 predefines these symbols; the values were read from ca65 itself, so a new CPU only needs a new row.
    private static string? CpuConstant(string name) => name switch
    {
        "CPU_ISET_NONE" or "CPU_NONE" => "1",
        "CPU_ISET_6502" or "CPU_6502" => "2",
        "CPU_ISET_6502X" => "4",
        "CPU_ISET_6502DTV" => "8",
        "CPU_ISET_65SC02" => "16",
        "CPU_ISET_65C02" => "32",
        "CPU_ISET_65816" => "64",
        "CPU_ISET_SWEET16" or "CPU_SWEET16" => "128",
        "CPU_ISET_HUC6280" => "256",
        "CPU_ISET_M740" => "512",
        "CPU_ISET_4510" => "1024",
        "CPU_ISET_45GS02" => "2048",
        "CPU_ISET_W65C02" => "4096",
        "CPU_ISET_65CE02" => "8192",
        "CPU_6502X" => "6",
        "CPU_6502DTV" => "10",
        "CPU_65SC02" => "18",
        "CPU_65C02" => "50",
        "CPU_65816" => "82",
        "CPU_HUC6280" => "306",
        "CPU_M740" => "514",
        "CPU_4510" => "9250",
        "CPU_45GS02" => "11298",
        "CPU_W65C02" => "4146",
        "CPU_65CE02" => "8226",
        _ => null
    };

    private string? Ca65Function(string name, string args)
    {
        switch (name)
        {
            case ".defined":
            case ".def":
                if (!AssemblySyntax.IsIdentifier(args.Trim()))
                {
                    throw new AssemblyError(0, ".defined requires one identifier.");
                }

                // As in ca65, only symbols count; .definedmacro tests macros.
                return _defined.Contains(ConstantName(args.Trim())) ? "1" : "0";
            case ".definedmacro":
                return AssemblySyntax.IsPlainIdentifier(args.Trim())
                    ? _macros.ContainsKey(args.Trim()) ? "1" : "0"
                    : throw new AssemblyError(0, ".definedmacro requires one macro name.");

            case ".sizeof":
                return Ca65Size(args.Trim()) is { } size ? size.ToString() : null;
            case ".sprintf":
                return Sprintf(args);
            case ".max":
            case ".min":
                return MinMax(name, args);
            case ".loword":
                return $"(({args}) & $FFFF)";
            case ".hiword":
                return $"((({args}) >> 16) & $FFFF)";
            case ".referenced":
            case ".ref":
                throw new AssemblyError(0, "Reference-dependent functions are unsupported.");
            case ".concat":
            case ".ident":
            case ".strlen":
            case ".string":
                Ca65.NumberLookup ??= Ca65TryValue;
                return Ca65Expression.StringFunction(name, args, Ca65.NumberLookup);
        }

        return Ca65TokenFunction(name, args);
    }

    private static string Ca65String(string value) =>
        value.Length >= 2 && value[0] is '"' or '\'' && value[^1] == value[0]
            ? value[1..^1] : throw new AssemblyError(0, "Expected a ca65 string.");


    private static int Ca65FunctionEnd(string text, int opening)
    {
        int depth = 1;
        int end = opening + 1;
        while (end < text.Length && depth != 0)
        {
            char character = text[end++];
            if (character is '\'' or '"')
            {
                while (end < text.Length && text[end++] != character) { }
            }
            else if (character == '(')
            {
                depth++;
            }
            else if (character == ')')
            {
                depth--;
            }
        }

        return depth == 0 ? end : throw new AssemblyError(0, "Unterminated ca65 function or definition argument.");
    }

    private string MapCa65Data(string text)
    {
        Split(text, out ReadOnlySpan<char> label, out ReadOnlySpan<char> op, out ReadOnlySpan<char> operand);
        string operation = op.ToString().ToUpperInvariant();
        if (operation is not (".BYTE" or ".BYT" or ".ASCIIZ" or ".LOBYTES" or ".HIBYTES")) { return text; }
        List<string> bytes = [];
        foreach (string item in Ca65Frontend.Split(operand.ToString()))
        {
            if (_nativeSyntax && item.Length is 2 or > 3 && item[0] == '\'' && item[^1] == '\'')
            {
                // A native character literal is one character, as on the unpreprocessed path.
                throw new AssemblyError(0, ExpressionEvaluator.CharacterLiteralMessage);
            }

            if (item.Length >= 2 && item[0] is '"' or '\'' && item[^1] == item[0])
            {
                ReadOnlySpan<char> characters = item;
                foreach (char character in characters[1..^1])
                {
                    if (character > 255) { throw new AssemblyError(0, "ca65 strings require byte characters."); }
                    bytes.Add(Ca65.Characters[character].ToString());
                }
            }
            else if (operation == ".ASCIIZ")
            {
                throw new AssemblyError(0, ".asciiz requires strings.");
            }
            else if (operation is ".LOBYTES" or ".HIBYTES")
            {
                string expression = _nativeSyntax ? item : Ca65Expression.Translate(item, _options.BuildTime) ?? item;
                bytes.Add(operation == ".LOBYTES" ? $"<({expression})" : $">({expression})");
            }
            else
            {
                bytes.Add(item);
            }
        }

        if (operation == ".ASCIIZ") { bytes.Add("0"); }
        if (bytes.Count == 0) { return label.IsEmpty ? "" : $"{label}:"; }
        string data = string.Join(", ", bytes);
        return label.IsEmpty ? $" .byte {data}" : $"{label}: .byte {data}";
    }
}
