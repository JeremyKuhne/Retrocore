// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class Macro10Expander
{
    // The 6502's instructions, which the M6502 universal file defines under their usual names.
    private static readonly HashSet<string> s_mnemonics = new(StringComparer.Ordinal)
    {
        "ADC", "AND", "ASL", "BCC", "BCS", "BEQ", "BIT", "BMI", "BNE", "BPL", "BRK", "BVC", "BVS", "CLC", "CLD", "CLI",
        "CLV", "CMP", "CPX", "CPY", "DEC", "DEX", "DEY", "EOR", "INC", "INX", "INY", "JMP", "JSR", "LDA", "LDX", "LDY",
        "LSR", "NOP", "ORA", "PHA", "PHP", "PLA", "PLP", "ROL", "ROR", "RTI", "RTS", "SBC", "SEC", "SED", "SEI", "STA",
        "STX", "STY", "TAX", "TAY", "TSX", "TXA", "TXS", "TYA"
    };

    // Instructions with a zero-page form, and those also indexed by X or Y in zero page.
    private static readonly HashSet<string> s_zeroPage = new(StringComparer.Ordinal)
    {
        "ADC", "AND", "ASL", "BIT", "CMP", "CPX", "CPY", "DEC", "EOR", "INC", "LDA", "LDX", "LDY", "LSR", "ORA", "ROL",
        "ROR", "SBC", "STA", "STX", "STY"
    };

    private static readonly HashSet<string> s_zeroPageX = new(StringComparer.Ordinal)
    {
        "ADC", "AND", "ASL", "CMP", "DEC", "EOR", "INC", "LDA", "LDY", "LSR", "ORA", "ROL", "ROR", "SBC", "STA", "STY"
    };

    private static readonly HashSet<string> s_zeroPageY = new(StringComparer.Ordinal) { "LDX", "STX" };

    /// <summary>
    ///  Emits an M6502 instruction.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A suffix selects the addressing mode: <c>I</c> immediate (<c>LDAI</c>), <c>DY</c> <c>(zp),Y</c>
    ///   (<c>LDADY</c>), <c>DX</c> <c>(zp,X)</c>, and <c>JMPD</c> an indirect jump. Otherwise the operand is an
    ///   address, optionally followed by <c>,X</c> or <c>,Y</c>, or <c>A</c> for a shift of the accumulator; the
    ///   native assembler chooses zero page when the address is known by then and fits. A trailing comma, as in
    ///   <c>LDA TABLE,X,</c>, changes nothing.
    ///  </para>
    /// </remarks>
    /// <param name="word">The operation, uppercase.</param>
    /// <param name="operand">The operand text.</param>
    /// <param name="location">The source location.</param>
    /// <returns>Whether the operation is an instruction.</returns>
    private bool Instruction(string word, string operand, AssemblyLocation location)
    {
        string mnemonic;
        string mode;
        if (s_mnemonics.Contains(word))
        {
            mnemonic = word;
            mode = "";
        }
        else if (word == "JMPD")
        {
            mnemonic = "JMP";
            mode = "D";
        }
        else if (word.Length > 3 && s_mnemonics.Contains(word[..3]) && word[3..] is "I" or "DY" or "DX")
        {
            mnemonic = word[..3];
            mode = word[3..];
        }
        else
        {
            return false;
        }

        string native = mnemonic.ToLowerInvariant();
        if (mode.Length != 0)
        {
            string expression = Translate(operand).Text;
            string statement = mode switch
            {
                "I" => $"{native} #<({expression})",
                "DY" => $"{native} ({expression}),y",
                "DX" => $"{native} ({expression},x)",
                _ => $"{native} ({expression})"
            };

            Emit(statement, location, mode == "D" ? 3 : 2);

            return true;
        }

        List<string> parts = Arguments(operand);
        if (parts.Count == 0)
        {
            Emit(native, location, size: 1);
            return true;
        }

        if (parts.Count > 3 || (parts.Count == 3 && parts[2].Length != 0))
        {
            throw new AssemblyError(0, $"Invalid {word} operand '{operand}'.");
        }

        if (parts[0].Equals("A", StringComparison.OrdinalIgnoreCase) && (parts.Count == 1 || parts[1].Length == 0))
        {
            Emit($"{native} a", location, size: 1);
            return true;
        }

        string address = Translate(parts[0]).Text;
        if (parts.Count == 1 || parts[1].Length == 0)
        {
            Emit($"{native} {address}", location, Size(mnemonic, parts[0], s_zeroPage));
            return true;
        }

        string index = parts[1].Trim().ToUpperInvariant();
        if (index is not ("X" or "Y")) { throw new AssemblyError(0, $"Invalid index register '{parts[1]}'."); }
        int size = Size(mnemonic, parts[0], index == "X" ? s_zeroPageX : s_zeroPageY);
        Emit($"{native} {address},{index.ToLowerInvariant()}", location, size);
        return true;
    }

    /// <summary>
    ///  Sizes an addressed instruction as the native assembler lays it out: zero page when the address is known by
    ///  then, fits a byte and the instruction has that form; otherwise absolute. Branches are always two bytes.
    /// </summary>
    /// <param name="mnemonic">The mnemonic.</param>
    /// <param name="operand">The address expression.</param>
    /// <param name="zeroPage">The instructions with this addressing mode's zero-page form.</param>
    /// <returns>The size in bytes.</returns>
    private int Size(string mnemonic, string operand, HashSet<string> zeroPage)
    {
        bool branch = mnemonic[0] == 'B' && mnemonic != "BIT";
        return branch || (zeroPage.Contains(mnemonic) && Evaluate(operand) is >= 0 and <= 0xFF) ? 2 : 3;
    }

    /// <summary>
    ///  Tests whether a name is a 6502 mnemonic or register, which native syntax reads as such.
    /// </summary>
    /// <param name="symbol">The normalized symbol.</param>
    /// <returns>Whether the symbol needs an alias.</returns>
    private static bool IsReserved(string symbol) => symbol is "A" or "X" or "Y" || s_mnemonics.Contains(symbol);
}
