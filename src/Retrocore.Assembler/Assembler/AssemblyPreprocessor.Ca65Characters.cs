// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    private string Ca65CharacterExpression(string text)
    {
        StringBuilder? result = null;
        int copied = 0;
        for (int index = 0; index < text.Length; index++)
        {
            if (text[index] is not ('\'' or '"')) { continue; }
            int end = text.IndexOf(text[index], index + 1);
            if (end < 0) { throw new AssemblyError(0, "Unterminated character literal."); }
            if (text[index] == '\'' && end == index + 2)
            {
                char character = text[index + 1];
                if (character > 255) { throw new AssemblyError(0, "A ca65 character must fit in a byte."); }
                result ??= new(text.Length);
                result.Append(text, copied, index - copied).Append(Ca65.Characters[character]);
                copied = end + 1;
            }

            index = end;
        }

        return result is null ? text : result.Append(text, copied, text.Length - copied).ToString();
    }

    private string Ca65LineCharacters(string text)
    {
        if (text.IndexOf('\'') < 0) { return text; }
        Split(text, out ReadOnlySpan<char> label, out ReadOnlySpan<char> op, out ReadOnlySpan<char> operand);
        string operation = op.ToString();
        string keyword = operation.ToUpperInvariant();
        if (operation.Length == 0 || _macros.ContainsKey(operation)) { return text; }
        if (operation[0] == '.' && keyword is not
            (".BYTE" or ".WORD" or ".DWORD" or ".DBYT" or ".FARADDR" or ".RES" or ".ALIGN" or ".LOGICALORG" or ".ASSERT" or ".REPEAT" or ".IF" or ".ELSEIF"))
        {
            return text;
        }

        List<string> args = Ca65Frontend.Split(operand.ToString());
        bool firstOnly = keyword is ".ASSERT" or ".REPEAT";
        int count = firstOnly ? Math.Min(args.Count, 1) : args.Count;

        for (int index = 0; index < count; index++) { args[index] = Ca65CharacterExpression(args[index]); }
        string arguments = string.Join(", ", args);
        return label.IsEmpty ? $"{operation} {arguments}" : $"{label}: {operation} {arguments}";
    }
}
