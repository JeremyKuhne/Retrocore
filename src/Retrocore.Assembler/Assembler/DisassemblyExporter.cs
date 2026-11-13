// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;
using System.Globalization;
using Touki.Text;

namespace Retrocore.Assembler;

/// <summary>
///  Exports native assembly with explicit byte fallbacks rather than changing instruction encodings.
/// </summary>
internal static class DisassemblyExporter
{
    // Exported ROM source averages under ten characters per image byte, so this usually avoids regrowth.
    private const int EstimatedCharactersPerByte = 10;
    private const int BytesPerDataLine = 16;

    /// <summary>
    ///  Exports an independent analysis snapshot as annotated native assembly.
    /// </summary>
    /// <param name="result">The valid analysis.</param>
    /// <returns>Byte-exact source for the result's assembler options.</returns>
    internal static string Export(DisassemblyResult result)
    {
        if (!result.Success) { throw new InvalidOperationException("An invalid analysis project cannot be exported."); }
        InstructionSet codes = result.InstructionSet;
        OperandFormMatcher matcher = OperandFormMatcher.Get(codes.Description);
        using ValueStringBuilder source = new(result.Image.Length * EstimatedCharactersPerByte, CultureInfo.InvariantCulture);
        Dictionary<ushort, string> symbols = result.SymbolMap;
        Dictionary<ushort, string> comments = result.CommentMap;
        ReadOnlySpan<DisassembledInstruction> instructions = result.InstructionSpan;
        source.Append($".cpu {codes.Name}\n");
        int endAddress = result.Origin + result.Image.Length;

        // Outside-image symbols need equates; labels are emitted only when their actual image bytes are visited.
        foreach (KeyValuePair<ushort, string> pair in symbols.OrderBy(pair => pair.Key))
        {
            if (pair.Key >= result.Origin && pair.Key < endAddress) { continue; }
            source.Append($"{pair.Value} = ${pair.Key:X4}\n");
        }

        source.Append($".org ${result.Origin:X4}\n");
        Span<char> formatted = stackalloc char[Disassembler.InstructionTextBufferSize];
        int offset = 0;

        // Instructions are address-ordered, so one forward index replaces a search per line and per data byte.
        int next = 0;
        while (offset < result.Image.Length)
        {
            ushort address = (ushort)(result.Origin + offset);
            while (next < instructions.Length && instructions[next].Address < address) { next++; }
            if (comments.TryGetValue(address, out string? comment))
            {
                foreach (ReadOnlyMemory<char> line in new AssemblyLines(comment.AsMemory()))
                {
                    source.Append($"; {line.Span}\n");
                }
            }

            if (symbols.TryGetValue(address, out string? symbol))
            {
                source.Append($"{symbol}:\n");
            }

            source.Append("    ");
            bool decoded = next < instructions.Length && instructions[next].Address == address;
            if (decoded && CanRepresent(in instructions[next], codes, symbols, comments))
            {
                DisassembledInstruction instruction = instructions[next];
                if (!instruction.TryFormat(formatted, out int length))
                {
                    throw new InvalidOperationException("The instruction formatting buffer was too small.");
                }

                ReadOnlySpan<char> text = formatted[..length];
                bool widthPending = NeedsAbsolutePrefix(in instruction, codes);
                int position = 0;
                while (position < text.Length)
                {
                    if (widthPending && text[position] == ' ')
                    {
                        // The assembler would shorten a low-valued operand; > or a: keeps the wide encoding.
                        source.Append(codes.Description.AngleWidths ? " >" : " a:");
                        widthPending = false;
                        position++;
                        continue;
                    }

                    // A numeric immediate or register offset is not evidence of an address reference.
                    if (text[position] != '$' || IsValue(in instruction))
                    {
                        source.Append(text[position++]);
                        continue;
                    }

                    int end = position + 1;
                    while (end < text.Length && char.IsAsciiHexDigit(text[end])) { end++; }
                    if (!ushort.TryParse(
                        text[
                            (position + 1)..end],
                        NumberStyles.HexNumber,
                        CultureInfo.InvariantCulture,
                        out ushort target))
                    {
                        throw new InvalidOperationException("The instruction formatter produced invalid address text.");
                    }

                    if (symbols.TryGetValue(target, out string? name))
                    {
                        if (matcher.IsLiteral(codes, instruction.Encoding.Mnemonic, name) || matcher.IsPatternName(name))
                        {
                            // Bare A selects accumulator addressing, and a bare HL the register; A+0 and HL+0 keep the
                            // symbol.
                            source.Append($"{name}+0");
                        }
                        else
                        {
                            source.Append(name);
                        }
                    }
                    else
                    {
                        source.Append(text[position..end]);
                    }

                    position = end;
                }

                offset += instruction.Size;
            }
            else
            {
                source.Append(".byte ");
                int count = 1;

                // An unrepresentable instruction at this address is emitted as bytes; the run stops at the next start.
                int nextStart = next + (decoded ? 1 : 0) < instructions.Length
                    ? instructions[next + (decoded ? 1 : 0)].Address : int.MaxValue;

                // Raw runs must not swallow a label, comment or another decoded instruction's start.
                while (count < BytesPerDataLine && offset + count < result.Image.Length)
                {
                    ushort following = (ushort)(address + count);
                    if (symbols.ContainsKey(following) || comments.ContainsKey(following) || following == nextStart)
                    {
                        break;
                    }

                    count++;
                }

                for (int index = 0; index < count; index++)
                {
                    if (index != 0) { source.Append(", "); }
                    source.Append($"${result.Image.Span[offset + index]:X2}");
                }

                offset += count;
            }

            source.Append('\n');
        }

        return source.ToString();
    }

    /// <summary>
    ///  Checks whether native instruction syntax preserves both the exact encoding and annotation boundaries.
    /// </summary>
    /// <param name="instruction">The decoded instruction.</param>
    /// <param name="codes">The native assembler's canonical encoder.</param>
    /// <param name="symbols">The symbol snapshot.</param>
    /// <param name="comments">The comment snapshot.</param>
    /// <returns>Whether instruction text is safe instead of a raw-byte fallback.</returns>
    private static bool CanRepresent(
        in DisassembledInstruction instruction,
        InstructionSet codes,
        Dictionary<ushort, string> symbols,
        Dictionary<ushort, string> comments)
    {
        // Mnemonic/form aliases can assemble to a different opcode, such as an alternate NMOS NOP.
        IsaEncoding decoded = instruction.Encoding;
        if (!codes.TryGet(decoded.Mnemonic, decoded.Form, out int encoding) || encoding != instruction.EncodingId)
        {
            return false;
        }

        for (int index = 1; index < instruction.Size; index++)
        {
            // Native instruction text cannot place a label or comment in the middle of its own encoding.
            ushort address = (ushort)(instruction.Address + index);
            if (symbols.ContainsKey(address) || comments.ContainsKey(address)) { return false; }
        }

        return true;
    }

    /// <summary>
    ///  Checks whether an absolute instruction needs an explicit width because the assembler would shorten it.
    /// </summary>
    /// <param name="instruction">The decoded instruction.</param>
    /// <param name="codes">The native assembler's canonical encoder.</param>
    /// <returns>Whether hex digit width alone would not keep the absolute encoding.</returns>
    private static bool NeedsAbsolutePrefix(in DisassembledInstruction instruction, InstructionSet codes)
    {
        OperandForm form = instruction.Form;
        return form.Narrow >= 0
            && instruction.Operand <= (1 << (codes.Forms[form.Narrow].Size * InstructionEncoding.BitsPerByte)) - 1
            && codes.Has(instruction.Encoding.Mnemonic, form.Narrow);
    }

    /// <summary>
    ///  Gets whether an instruction's formatted hex literal is a value/offset rather than a symbol target.
    /// </summary>
    /// <param name="instruction">The decoded instruction.</param>
    /// <returns>Whether no field is a static memory address or branch target.</returns>
    private static bool IsValue(in DisassembledInstruction instruction)
    {
        OperandForm form = instruction.Form;
        return form.HasPostbyte
            ? instruction.PostbyteReference == PostbyteReference.None
            : form.Role == OperandRole.None && form.RelativeField < 0;
    }
}
