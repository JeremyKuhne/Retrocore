// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.M6809;

/// <summary>
///  Encodes, validates and formats MC6809 indexed, register-pair and stack-mask postbytes without allocating.
/// </summary>
internal static class M6809Postbyte
{
    private const string HexDigits = "0123456789ABCDEF";

    /// <summary>
    ///  Determines whether an operand has MC6809 indexed syntax: enclosed in brackets or containing a top-level comma.
    /// </summary>
    /// <param name="text">The compact operand text.</param>
    /// <returns>Whether the operand has indexed syntax.</returns>
    public static bool HasIndexedSyntax(ReadOnlySpan<char> text) =>
        !text.IsEmpty && text[0] != '#' && (IsBracketed(text) || LastTopLevelComma(text) >= 0);

    /// <summary>
    ///  Determines whether an operand is a single balanced <c>[...]</c> group.
    /// </summary>
    /// <param name="text">The trimmed operand text.</param>
    /// <returns>Whether the opening bracket closes at the final character.</returns>
    public static bool IsBracketed(ReadOnlySpan<char> text)
    {
        if (text.Length < 2 || text[0] != '[' || text[^1] != ']') { return false; }
        int depth = 0;
        char quote = '\0';
        for (int index = 0; index < text.Length; index++)
        {
            char value = text[index];
            if (TogglesQuote(text, index, quote)) { quote = quote == '\0' ? value : '\0'; }
            if (quote != '\0') { continue; }
            if (value is '[' or '(') { depth++; }
            else if (value is ']' or ')' && --depth == 0) { return index == text.Length - 1; }
        }

        return false;
    }

    /// <summary>
    ///  Parses an MC6809 indexed operand into its structural parts and inner expression slice.
    /// </summary>
    /// <param name="operand">The compact operand.</param>
    /// <param name="parsed">Receives the parsed structure.</param>
    /// <param name="error">Receives a diagnostic message when the syntax is malformed.</param>
    /// <returns>Whether parsing succeeded.</returns>
    public static bool TryParseIndexed(
        ReadOnlyMemory<char> operand,
        out M6809IndexedOperand parsed,
        out string? error)
    {
        parsed = default;
        error = null;
        ReadOnlyMemory<char> trimmed = operand.Trim();
        ReadOnlySpan<char> span = trimmed.Span;
        if (span.IsEmpty)
        {
            error = "Expected an indexed operand.";
            return false;
        }

        bool indirect = IsBracketed(span);
        ReadOnlyMemory<char> inner = indirect ? trimmed[1..^1].Trim() : trimmed;
        ReadOnlySpan<char> innerSpan = inner.Span;
        if (innerSpan.IsEmpty)
        {
            error = "Indirect operand cannot be empty.";
            return false;
        }

        int comma = LastTopLevelComma(innerSpan);
        if (comma < 0)
        {
            if (!indirect)
            {
                error = "Expected an index register after ',' or an indirect '[address]' operand.";
                return false;
            }

            parsed = new()
            {
                Kind = M6809IndexedKind.ExtendedIndirect,
                Indirect = true,
                Code = 0x9F,
                Expression = inner
            };

            return true;
        }

        ReadOnlyMemory<char> left = inner[..comma].Trim();
        ReadOnlySpan<char> right = innerSpan[(comma + 1)..].Trim();
        if (LastTopLevelComma(left.Span) >= 0 || right.IsEmpty)
        {
            error = "Malformed indexed operand.";
            return false;
        }

        if (right.Equals("PCR".AsSpan(), StringComparison.OrdinalIgnoreCase)
            || right.Equals("PC".AsSpan(), StringComparison.OrdinalIgnoreCase))
        {
            M6809OffsetWidth width = StripOffsetWidth(ref left);
            if (width == M6809OffsetWidth.FiveBit)
            {
                error = "PC-relative indexed addressing supports only 8-bit (<) and 16-bit (>) offsets.";
                return false;
            }

            if (left.IsEmpty)
            {
                error = "PC-relative indexed addressing requires a target expression.";
                return false;
            }

            parsed = new()
            {
                Kind = M6809IndexedKind.ProgramCounterRelative,
                Indirect = indirect,
                Width = width,
                Expression = left
            };

            return true;
        }

        int autoMode = -1;
        ReadOnlySpan<char> regSpan = right;
        if (regSpan.StartsWith("--".AsSpan(), StringComparison.Ordinal))
        {
            autoMode = 3;
            regSpan = regSpan[2..].TrimStart();
        }
        else if (regSpan[0] == '-')
        {
            autoMode = 2;
            regSpan = regSpan[1..].TrimStart();
        }
        else if (regSpan.EndsWith("++".AsSpan(), StringComparison.Ordinal))
        {
            autoMode = 1;
            regSpan = regSpan[..^2].TrimEnd();
        }
        else if (regSpan[^1] == '+')
        {
            autoMode = 0;
            regSpan = regSpan[..^1].TrimEnd();
        }

        if (!TryIndexRegisterCode(regSpan, out byte reg))
        {
            string unknownRegister = right.ToString();
            error = $"Unknown MC6809 index register '{unknownRegister}'; expected X, Y, U, S or PCR.";
            return false;
        }

        byte indirectBit = indirect ? (byte)0x10 : (byte)0;
        if (autoMode >= 0)
        {
            if (!left.IsEmpty)
            {
                error = "Auto-increment and auto-decrement indexed modes take no offset.";
                return false;
            }

            if (indirect && autoMode is 0 or 2)
            {
                error = "Single-step auto-increment and auto-decrement cannot be indirect on MC6809.";
                return false;
            }

            parsed = new()
            {
                Kind = M6809IndexedKind.Fixed,
                Indirect = indirect,
                Code = (byte)(0x80 | (reg << 5) | indirectBit | autoMode)
            };

            return true;
        }

        if (left.IsEmpty)
        {
            parsed = new()
            {
                Kind = M6809IndexedKind.Fixed,
                Indirect = indirect,
                Code = (byte)(0x84 | (reg << 5) | indirectBit)
            };

            return true;
        }

        ReadOnlySpan<char> leftSpan = left.Span;
        if (leftSpan.Length == 1)
        {
            int accMode = leftSpan[0] switch
            {
                'a' or 'A' => 6,
                'b' or 'B' => 5,
                'd' or 'D' => 11,
                _ => -1
            };

            if (accMode >= 0)
            {
                parsed = new()
                {
                    Kind = M6809IndexedKind.Fixed,
                    Indirect = indirect,
                    Code = (byte)(0x80 | (reg << 5) | indirectBit | accMode)
                };

                return true;
            }
        }

        M6809OffsetWidth offsetWidth = StripOffsetWidth(ref left);
        if (indirect && offsetWidth == M6809OffsetWidth.FiveBit)
        {
            error = "Indirect indexed addressing does not support 5-bit offsets.";
            return false;
        }

        if (left.IsEmpty)
        {
            error = "Expected an indexed offset expression.";
            return false;
        }

        parsed = new()
        {
            Kind = M6809IndexedKind.RegisterOffset,
            Indirect = indirect,
            Code = reg,
            Width = offsetWidth,
            Expression = left
        };

        return true;
    }

    /// <summary>
    ///  Gets the encoded byte length (1-3) of a canonical MC6809 indexed postbyte and its trailing bytes.
    /// </summary>
    /// <param name="postbyte">The indexed postbyte.</param>
    /// <param name="size">Receives the postbyte-plus-offset byte length.</param>
    /// <returns>Whether the postbyte is a valid, canonical MC6809 indexed postbyte.</returns>
    public static bool TryGetIndexedSize(byte postbyte, out int size)
    {
        if ((postbyte & 0x80) == 0)
        {
            size = 1;
            return true;
        }

        bool indirect = (postbyte & 0x10) != 0;
        switch (postbyte & 0x0F)
        {
            case 0 or 2 when !indirect:
            case 1 or 3 or 4 or 5 or 6 or 11:
                size = 1;
                return true;
            case 8 or 12:
                size = 2;
                return true;
            case 9 or 13:
                size = 3;
                return true;
            case 15 when postbyte == 0x9F:
                size = 3;
                return true;
            default:
                size = 0;
                return false;
        }
    }

    /// <summary>
    ///  Gets whether an indexed postbyte uses PC-relative addressing.
    /// </summary>
    /// <param name="postbyte">The indexed postbyte.</param>
    /// <returns>Whether the mode is 8-bit or 16-bit <c>PCR</c>.</returns>
    public static bool IsPcRelative(byte postbyte) =>
        (postbyte & 0x80) != 0 && (postbyte & 0x0F) is 12 or 13;

    /// <summary>
    ///  Gets whether an indexed postbyte is indirect (<c>[...]</c>).
    /// </summary>
    /// <param name="postbyte">The indexed postbyte.</param>
    /// <returns>Whether indirection is set.</returns>
    public static bool IsIndirect(byte postbyte) => (postbyte & 0x90) == 0x90;

    /// <summary>
    ///  Gets whether an indexed postbyte is extended indirect (<c>[$xxxx]</c>).
    /// </summary>
    /// <param name="postbyte">The indexed postbyte.</param>
    /// <returns>Whether the postbyte is <c>$9F</c>.</returns>
    public static bool IsExtendedIndirect(byte postbyte) => postbyte == 0x9F;

    /// <summary>
    ///  Extracts the static 16-bit value encoded by an indexed postbyte: target address for <c>PCR</c>, pointer
    ///  address for <c>[$xxxx]</c>, or signed/unsigned offset for constant-offset modes.
    /// </summary>
    /// <param name="postbyte">The indexed postbyte.</param>
    /// <param name="first">First byte after the postbyte, if any.</param>
    /// <param name="second">Second byte after the postbyte, if any.</param>
    /// <param name="nextAddress">Address immediately following the complete instruction.</param>
    /// <returns>The decoded 16-bit field value.</returns>
    public static ushort DecodeIndexedValue(byte postbyte, byte first, byte second, ushort nextAddress)
    {
        if ((postbyte & 0x80) == 0)
        {
            int signed5 = (postbyte & 0x10) != 0 ? (postbyte | ~0x1F) : (postbyte & 0x1F);
            return unchecked((ushort)signed5);
        }

        return (postbyte & 0x0F) switch
        {
            8 => unchecked((ushort)(sbyte)first),
            9 or 15 => (ushort)((first << 8) | second),
            12 => unchecked((ushort)(nextAddress + (sbyte)first)),
            13 => unchecked((ushort)(nextAddress + (short)((first << 8) | second))),
            _ => 0
        };
    }

    /// <summary>
    ///  Formats a decoded MC6809 indexed operand in canonical round-trip native syntax.
    /// </summary>
    /// <param name="postbyte">The indexed postbyte.</param>
    /// <param name="first">First byte after the postbyte, if any.</param>
    /// <param name="second">Second byte after the postbyte, if any.</param>
    /// <param name="nextAddress">Address immediately following the complete instruction.</param>
    /// <param name="buffer">Destination buffer.</param>
    /// <param name="length">Current write offset, advanced past the formatted operand.</param>
    public static void FormatIndexed(
        byte postbyte,
        byte first,
        byte second,
        ushort nextAddress,
        Span<char> buffer,
        ref int length)
    {
        char reg = IndexRegisterName(postbyte);
        if ((postbyte & 0x80) == 0)
        {
            int offset5 = postbyte & 0x1F;
            int signed5 = offset5 >= 0x10 ? offset5 - 0x20 : offset5;

            // A zero offset would assemble as ,R; << keeps the 5-bit form.
            if (signed5 == 0)
            {
                buffer[length++] = '<';
                buffer[length++] = '<';
            }

            AppendSignedByte(buffer, ref length, signed5);
            buffer[length++] = ',';
            buffer[length++] = reg;
            return;
        }

        bool indirect = (postbyte & 0x10) != 0;
        if (indirect) { buffer[length++] = '['; }
        switch (postbyte & 0x0F)
        {
            case 0:
                buffer[length++] = ',';
                buffer[length++] = reg;
                buffer[length++] = '+';
                break;
            case 1:
                buffer[length++] = ',';
                buffer[length++] = reg;
                buffer[length++] = '+';
                buffer[length++] = '+';
                break;
            case 2:
                buffer[length++] = ',';
                buffer[length++] = '-';
                buffer[length++] = reg;
                break;
            case 3:
                buffer[length++] = ',';
                buffer[length++] = '-';
                buffer[length++] = '-';
                buffer[length++] = reg;
                break;
            case 4:
                buffer[length++] = ',';
                buffer[length++] = reg;
                break;
            case 5:
                buffer[length++] = 'B';
                buffer[length++] = ',';
                buffer[length++] = reg;
                break;
            case 6:
                buffer[length++] = 'A';
                buffer[length++] = ',';
                buffer[length++] = reg;
                break;
            case 8:
                int signed8 = (sbyte)first;
                // An offset the assembler would shorten keeps its byte with <: -16 to 15, or an indirect zero.
                if (signed8 is >= -16 and <= 15 && (!indirect || signed8 == 0)) { buffer[length++] = '<'; }
                AppendSignedByte(buffer, ref length, signed8);
                buffer[length++] = ',';
                buffer[length++] = reg;
                break;
            case 9:
                ushort word = (ushort)((first << 8) | second);
                if (word <= 127) { buffer[length++] = '>'; }
                AppendHex(buffer, ref length, word, 4);
                buffer[length++] = ',';
                buffer[length++] = reg;
                break;
            case 11:
                buffer[length++] = 'D';
                buffer[length++] = ',';
                buffer[length++] = reg;
                break;
            case 12:
                ushort target8 = unchecked((ushort)(nextAddress + (sbyte)first));
                AppendHex(buffer, ref length, target8, 4);
                AppendLiteral(buffer, ref length, ",PCR");
                break;
            case 13:
                short disp16 = unchecked((short)((first << 8) | second));
                if (disp16 is >= -129 and <= 126) { buffer[length++] = '>'; }
                ushort target16 = unchecked((ushort)(nextAddress + disp16));
                AppendHex(buffer, ref length, target16, 4);
                AppendLiteral(buffer, ref length, ",PCR");
                break;
            case 15:
                AppendHex(buffer, ref length, (ushort)((first << 8) | second), 4);
                break;
        }

        if (indirect) { buffer[length++] = ']'; }
    }

    /// <summary>
    ///  Gets whether a <c>TFR</c> or <c>EXG</c> postbyte names two documented MC6809 registers of equal width.
    /// </summary>
    /// <param name="postbyte">The register-pair postbyte.</param>
    /// <returns>Whether both nibbles are valid and matching-width.</returns>
    public static bool IsValidRegisterPair(byte postbyte)
    {
        int source = postbyte >> 4;
        int destination = postbyte & 0x0F;
        return IsTransferRegister(source) && IsTransferRegister(destination) && (source < 8) == (destination < 8);
    }

    /// <summary>
    ///  Encodes an MC6809 <c>TFR</c> or <c>EXG</c> operand (<c>R1,R2</c>).
    /// </summary>
    /// <param name="text">The operand text.</param>
    /// <param name="postbyte">Receives the encoded postbyte.</param>
    /// <param name="error">Receives a diagnostic message when invalid.</param>
    /// <returns>Whether encoding succeeded.</returns>
    public static bool TryEncodeRegisterPair(ReadOnlySpan<char> text, out byte postbyte, out string? error)
    {
        postbyte = 0;
        error = null;
        int comma = text.IndexOf(',');
        if (comma < 0 || text[(comma + 1)..].IndexOf(',') >= 0)
        {
            error = "Expected two registers separated by a comma, such as D,X or A,B.";
            return false;
        }

        ReadOnlySpan<char> left = text[..comma].Trim();
        ReadOnlySpan<char> right = text[(comma + 1)..].Trim();
        if (!TryTransferRegisterCode(left, out byte source) || !TryTransferRegisterCode(right, out byte destination))
        {
            error = "Unknown MC6809 register in register-pair operand.";
            return false;
        }

        if ((source < 8) != (destination < 8))
        {
            error = "TFR and EXG require two 8-bit or two 16-bit registers.";
            return false;
        }

        postbyte = (byte)((source << 4) | destination);
        return true;
    }

    /// <summary>
    ///  Formats a validated <c>TFR</c> or <c>EXG</c> postbyte.
    /// </summary>
    /// <param name="postbyte">The register-pair postbyte.</param>
    /// <param name="buffer">Destination buffer.</param>
    /// <param name="length">Current write offset, advanced past the pair.</param>
    public static void FormatRegisterPair(byte postbyte, Span<char> buffer, ref int length)
    {
        AppendLiteral(buffer, ref length, TransferRegisterName(postbyte >> 4));
        buffer[length++] = ',';
        AppendLiteral(buffer, ref length, TransferRegisterName(postbyte & 0x0F));
    }

    /// <summary>
    ///  Encodes an MC6809 <c>PSHS</c>/<c>PULS</c> or <c>PSHU</c>/<c>PULU</c> register list, or extracts an
    ///  immediate <c>#mask</c> expression.
    /// </summary>
    /// <param name="operand">The compact operand.</param>
    /// <param name="systemStack">True for <c>PSHS</c>/<c>PULS</c>; false for <c>PSHU</c>/<c>PULU</c>.</param>
    /// <param name="mask">Receives the register bitmask when <paramref name="immediate"/> is empty.</param>
    /// <param name="immediate">Receives the expression after <c>#</c> when given as an immediate mask.</param>
    /// <param name="error">Receives a diagnostic message when invalid.</param>
    /// <returns>Whether parsing succeeded.</returns>
    public static bool TryEncodeStackMask(
        ReadOnlyMemory<char> operand,
        bool systemStack,
        out byte mask,
        out ReadOnlyMemory<char> immediate,
        out string? error)
    {
        mask = 0;
        immediate = default;
        error = null;
        ReadOnlyMemory<char> trimmed = operand.Trim();
        ReadOnlySpan<char> span = trimmed.Span;
        if (span.IsEmpty)
        {
            error = "Expected a register list or #mask operand.";
            return false;
        }

        if (span[0] == '#')
        {
            immediate = trimmed[1..].Trim();
            if (immediate.IsEmpty)
            {
                error = "Expected a byte expression after '#'.";
                return false;
            }

            return true;
        }

        int position = 0;
        while (position <= span.Length)
        {
            int next = span[position..].IndexOf(',');
            ReadOnlySpan<char> item = (next < 0 ? span[position..] : span.Slice(position, next)).Trim();
            if (item.IsEmpty)
            {
                error = "Empty item in stack register list.";
                return false;
            }

            if (item.Equals("S".AsSpan(), StringComparison.OrdinalIgnoreCase) && systemStack)
            {
                error = "PSHS and PULS cannot transfer S; use PSHU or PULU.";
                return false;
            }

            if (item.Equals("U".AsSpan(), StringComparison.OrdinalIgnoreCase) && !systemStack)
            {
                error = "PSHU and PULU cannot transfer U; use PSHS or PULS.";
                return false;
            }

            byte bit = StackRegisterBit(item, systemStack);
            if (bit == 0)
            {
                string unknown = item.ToString();
                error = $"Unknown stack register '{unknown}'.";
                return false;
            }

            mask |= bit;
            if (next < 0) { break; }
            position += next + 1;
        }

        return true;
    }

    /// <summary>
    ///  Formats an MC6809 stack register-list mask in canonical native syntax.
    /// </summary>
    /// <param name="mask">The postbyte mask.</param>
    /// <param name="systemStack">True for <c>PSHS</c>/<c>PULS</c>; false for <c>PSHU</c>/<c>PULU</c>.</param>
    /// <param name="buffer">Destination buffer.</param>
    /// <param name="length">Current write offset, advanced past the formatted list.</param>
    public static void FormatStackMask(byte mask, bool systemStack, Span<char> buffer, ref int length)
    {
        if (mask == 0)
        {
            AppendLiteral(buffer, ref length, "#$00");
            return;
        }

        bool first = true;
        AppendBit(mask, 0x01, "CC", buffer, ref length, ref first);
        AppendBit(mask, 0x02, "A", buffer, ref length, ref first);
        AppendBit(mask, 0x04, "B", buffer, ref length, ref first);
        AppendBit(mask, 0x08, "DP", buffer, ref length, ref first);
        AppendBit(mask, 0x10, "X", buffer, ref length, ref first);
        AppendBit(mask, 0x20, "Y", buffer, ref length, ref first);
        AppendBit(mask, 0x40, systemStack ? "U" : "S", buffer, ref length, ref first);
        AppendBit(mask, 0x80, "PC", buffer, ref length, ref first);
    }

    /// <summary>
    ///  Determines whether an identifier at <paramref name="start"/> inside an instruction operand occupies an
    ///  MC6809 register slot (index base, <c>PCR</c>, or accumulator offset), so name resolution must not treat
    ///  it as a symbol.
    /// </summary>
    /// <param name="text">The full operand text.</param>
    /// <param name="start">Token start index.</param>
    /// <param name="length">Token length.</param>
    /// <returns>Whether the token is a register in indexed syntax.</returns>
    public static bool IsIndexedRegisterToken(ReadOnlySpan<char> text, int start, int length)
    {
        ReadOnlySpan<char> token = text.Slice(start, length);
        int before = start - 1;
        while (before >= 0 && char.IsWhiteSpace(text[before])) { before--; }
        int after = start + length;
        while (after < text.Length && char.IsWhiteSpace(text[after])) { after++; }

        // Index register or PCR after comma (allowing - / -- before and + / ++ / ] after).
        int commaCheck = before;
        while (commaCheck >= 0 && text[commaCheck] == '-') { commaCheck--; }
        while (commaCheck >= 0 && char.IsWhiteSpace(text[commaCheck])) { commaCheck--; }
        if (commaCheck >= 0 && text[commaCheck] == ',')
        {
            int endCheck = after;
            while (endCheck < text.Length && text[endCheck] == '+') { endCheck++; }
            while (endCheck < text.Length && char.IsWhiteSpace(text[endCheck])) { endCheck++; }
            if (endCheck == text.Length || (endCheck == text.Length - 1 && text[endCheck] == ']'))
            {
                return TryIndexRegisterCode(token, out _)
                    || token.Equals("PCR".AsSpan(), StringComparison.OrdinalIgnoreCase)
                    || token.Equals("PC".AsSpan(), StringComparison.OrdinalIgnoreCase);
            }
        }

        // Accumulator offset A, B or D standing alone before ','.
        if (length == 1 && token[0] is 'a' or 'A' or 'b' or 'B' or 'd' or 'D')
        {
            bool atStart = before < 0 || (before == 0 && text[0] == '[');
            if (atStart && after < text.Length && text[after] == ',')
            {
                return true;
            }
        }

        return false;
    }

    private static void AppendBit(
        byte mask,
        byte bit,
        string name,
        Span<char> buffer,
        ref int length,
        ref bool first)
    {
        if ((mask & bit) == 0) { return; }
        if (!first) { buffer[length++] = ','; }
        first = false;
        AppendLiteral(buffer, ref length, name);
    }

    private static byte StackRegisterBit(ReadOnlySpan<char> name, bool systemStack) =>
        name.Length switch
        {
            1 => StackSingleLetterBit(name[0], systemStack),
            2 when name.Equals("CC".AsSpan(), StringComparison.OrdinalIgnoreCase) => 0x01,
            2 when name.Equals("DP".AsSpan(), StringComparison.OrdinalIgnoreCase) => 0x08,
            2 when name.Equals("PC".AsSpan(), StringComparison.OrdinalIgnoreCase) => 0x80,
            _ => 0
        };

    private static byte StackSingleLetterBit(char letter, bool systemStack) => letter switch
    {
        'a' or 'A' => 0x02,
        'b' or 'B' => 0x04,
        'd' or 'D' => 0x06,
        'x' or 'X' => 0x10,
        'y' or 'Y' => 0x20,
        'u' or 'U' when systemStack => 0x40,
        's' or 'S' when !systemStack => 0x40,
        _ => 0
    };

    private static bool IsTransferRegister(int code) => code is (>= 0 and <= 5) or (>= 8 and <= 11);

    private static bool TryTransferRegisterCode(ReadOnlySpan<char> name, out byte code)
    {
        if (name.Length == 1)
        {
            switch (name[0])
            {
                case 'd' or 'D':
                    code = 0;
                    return true;
                case 'x' or 'X':
                    code = 1;
                    return true;
                case 'y' or 'Y':
                    code = 2;
                    return true;
                case 'u' or 'U':
                    code = 3;
                    return true;
                case 's' or 'S':
                    code = 4;
                    return true;
                case 'a' or 'A':
                    code = 8;
                    return true;
                case 'b' or 'B':
                    code = 9;
                    return true;
            }
        }
        else if (name.Equals("PC".AsSpan(), StringComparison.OrdinalIgnoreCase))
        {
            code = 5;
            return true;
        }
        else if (name.Equals("CC".AsSpan(), StringComparison.OrdinalIgnoreCase))
        {
            code = 10;
            return true;
        }
        else if (name.Equals("DP".AsSpan(), StringComparison.OrdinalIgnoreCase))
        {
            code = 11;
            return true;
        }

        code = 0xFF;
        return false;
    }

    private static string TransferRegisterName(int code) => code switch
    {
        0 => "D",
        1 => "X",
        2 => "Y",
        3 => "U",
        4 => "S",
        5 => "PC",
        8 => "A",
        9 => "B",
        10 => "CC",
        11 => "DP",
        _ => "?"
    };

    private static bool TryIndexRegisterCode(ReadOnlySpan<char> name, out byte code)
    {
        if (name.Length == 1)
        {
            switch (name[0])
            {
                case 'x' or 'X':
                    code = 0;
                    return true;
                case 'y' or 'Y':
                    code = 1;
                    return true;
                case 'u' or 'U':
                    code = 2;
                    return true;
                case 's' or 'S':
                    code = 3;
                    return true;
            }
        }

        code = 0;
        return false;
    }

    private static char IndexRegisterName(byte postbyte) => ((postbyte >> 5) & 3) switch
    {
        0 => 'X',
        1 => 'Y',
        2 => 'U',
        _ => 'S'
    };

    private static M6809OffsetWidth StripOffsetWidth(ref ReadOnlyMemory<char> expression)
    {
        ReadOnlySpan<char> span = expression.Span;
        if (span.Length >= 2 && span[0] == '<' && span[1] == '<')
        {
            expression = expression[2..].TrimStart();
            return M6809OffsetWidth.FiveBit;
        }

        if (!span.IsEmpty && span[0] == '<')
        {
            expression = expression[1..].TrimStart();
            return M6809OffsetWidth.EightBit;
        }

        if (!span.IsEmpty && span[0] == '>')
        {
            expression = expression[1..].TrimStart();
            return M6809OffsetWidth.SixteenBit;
        }

        return M6809OffsetWidth.Automatic;
    }

    private static int LastTopLevelComma(ReadOnlySpan<char> text)
    {
        int depth = 0;
        char quote = '\0';
        int found = -1;
        for (int index = 0; index < text.Length; index++)
        {
            char value = text[index];
            if (TogglesQuote(text, index, quote)) { quote = quote == '\0' ? value : '\0'; }
            if (quote != '\0') { continue; }
            if (value is '(' or '[') { depth++; }
            else if (value is ')' or ']') { depth--; }
            else if (value == ',' && depth == 0) { found = index; }
        }

        return found;
    }

    private static bool TogglesQuote(ReadOnlySpan<char> text, int index, char quote)
    {
        char value = text[index];
        return value is ('\'' or '"')
            && (quote != '\0' ? value == quote : value == '"' || index == 0 || !IsAsciiLetter(text[index - 1]));
    }

    private static bool IsAsciiLetter(char value) => value is (>= 'A' and <= 'Z') or (>= 'a' and <= 'z');

    private static void AppendSignedByte(Span<char> buffer, ref int length, int signed)
    {
        if (signed < 0)
        {
            buffer[length++] = '-';
            AppendHex(buffer, ref length, (ushort)(-signed), 2);
        }
        else
        {
            AppendHex(buffer, ref length, (ushort)signed, 2);
        }
    }

    private static void AppendHex(Span<char> buffer, ref int length, ushort value, int digits)
    {
        buffer[length++] = '$';
        for (int shift = (digits - 1) * 4; shift >= 0; shift -= 4)
        {
            buffer[length++] = HexDigits[(value >> shift) & 15];
        }
    }

    private static void AppendLiteral(Span<char> buffer, ref int length, string text)
    {
        text.AsSpan().CopyTo(buffer[length..]);
        length += text.Length;
    }
}
