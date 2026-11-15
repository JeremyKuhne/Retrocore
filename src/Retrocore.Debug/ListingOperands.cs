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
    ///  shows for it, the target itself or a direct-page operand's offset.
    /// </returns>
    public static (int? Target, int? Shown) OperandAddress(in DisassembledInstruction instruction, int? directPage)
    {
        OperandForm form = instruction.Form;
        int? target;
        if (form.FieldCount == 0) { target = instruction.DirectTarget; }
        else if (form.HasPostbyte)
        {
            target = instruction.PostbyteReference == PostbyteReference.None ? null : instruction.Field(0);
        }
        else if (instruction.RelativeTarget is { } relative) { target = relative; }
        else if (form.Role == OperandRole.None) { target = instruction.DirectTarget; }
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
    /// <param name="shown">The value the text shows for it, which the label replaces.</param>
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
                && value == written)
            {
                return string.Concat(text.AsSpan(0, position), name, text.AsSpan(digits));
            }
        }

        return text;
    }
}
