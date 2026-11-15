// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Isa;
using System.Globalization;

namespace Retrocore.Debug;

/// <summary>
///  The addresses Retrocore Memory's listing gives instruction operands, and the labels it names them by.
/// </summary>
internal static class ListingOperands
{
    /// <summary>
    ///  Gets the address an instruction's operand names, for going there: a memory or pointer operand, a branch's
    ///  target, a target the opcode implies, as <c>RST $08</c> has, or a postbyte's pointer or PC-relative address.
    /// </summary>
    /// <param name="instruction">The instruction.</param>
    /// <param name="directPage">
    ///  The page a one-byte memory operand is an offset in, as the 6809's DP gives; null for a CPU without one, or
    ///  -1 where it is not known, where such an operand names no address.
    /// </param>
    /// <returns>
    ///  The target, null for values, registers and offsets from a register; and the value the instruction's text
    ///  shows for it, the target itself, a direct-page operand's offset, or -1 for an implied target.
    /// </returns>
    public static (int? Target, int? Shown) OperandAddress(in DisassembledInstruction instruction, int? directPage)
    {
        OperandForm form = instruction.Form;
        int? target;
        if (form.FieldCount == 0)
        {
            // An opcode that implies its target, as the 8080's RST 1 does for $0008: the text may show the target
            // or a number for it, which -1 says.
            return (instruction.DirectTarget, instruction.DirectTarget is null ? null : -1);
        }
        else if (form.HasPostbyte)
        {
            target = instruction.PostbyteReference == PostbyteReference.None ? null : instruction.Field(0);
        }
        else if (instruction.RelativeTarget is { } relative) { target = relative; }
        else if (form.Role == OperandRole.None)
        {
            // A restart's text gives its number or its address, as RST 1 and RST $08 do.
            return (instruction.DirectTarget, instruction.DirectTarget is null ? null : -1);
        }
        else if (directPage is { } page && form.Field(0) == OperandFieldKind.Byte)
        {
            int offset = instruction.Operand & 0xFF;
            return page < 0 ? (null, null) : ((page << 8) | offset, offset);
        }
        else { target = instruction.Operand; }

        return (target, target);
    }

    /// <summary>
    ///  Gets an instruction's text with the address its operand names given by its label, as <c>LDA KBD</c> for
    ///  <c>LDA $C000</c>.
    /// </summary>
    /// <param name="text">The instruction's text.</param>
    /// <param name="target">The address the operand names.</param>
    /// <param name="shown">
    ///  The value the text shows for it, which the label replaces; -1 where an opcode implies the target, whose text
    ///  may show the target or a number for it, as <c>RST 1</c> does.
    /// </param>
    /// <param name="names">The labels by address.</param>
    /// <returns>The text, with the label where there is one.</returns>
    public static string Named(string text, int? target, int? shown, SortedDictionary<int, string> names)
    {
        if (target is not { } address || shown is not { } written || !names.TryGetValue(address, out string? name))
        {
            return text;
        }

        for (int position = text.IndexOf('$'); position >= 0; position = text.IndexOf('$', position + 1))
        {
            int digits = position + 1;
            while (digits < text.Length && char.IsAsciiHexDigit(text[digits])) { digits++; }
            if (digits > position + 1
                && int.TryParse(text.AsSpan(position + 1, digits - position - 1), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out int value)
                && value == (written < 0 ? address : written))
            {
                return string.Concat(text.AsSpan(0, position), name, text.AsSpan(digits));
            }
        }

        // A plain number alone after the mnemonic, as the 8080's RST 1 gives for an implied target, is replaced too.
        int space = text.IndexOf(' ');
        string operand = space > 0 ? text[(space + 1)..].Trim() : "";
        bool number = operand.Length != 0 && operand.All(char.IsAsciiDigit);
        if (number && (written < 0 || operand == written.ToString(CultureInfo.InvariantCulture)))
        {
            return string.Concat(text.AsSpan(0, space + 1), name);
        }

        return text;
    }
}
