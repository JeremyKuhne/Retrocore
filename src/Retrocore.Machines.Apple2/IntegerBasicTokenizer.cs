// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple2;

/// <summary>
///  Turns Integer BASIC text into its tokens by typing it into an Apple II's Integer BASIC, as a person would, and
///  taking the program it makes.
/// </summary>
/// <remarks>
///  <para>
///   Integer BASIC tokenizes by its own syntax tables, so the same text can have several tokens and only Integer
///   BASIC knows which. Letting its ROM do it makes the program byte for byte what Integer BASIC would have made.
///   The machine is a II built from the given ROMs, apart from any machine being debugged. Once its Monitor has
///   reset, it starts Integer BASIC at its cold start, $E000, whichever Monitor the ROMs have.
///  </para>
/// </remarks>
public static class IntegerBasicTokenizer
{
    private const ushort ColdStart = 0xE000;
    private const ushort ProgramStart = 0xCA;
    private const ushort Himem = 0x4C;
    private const int TextPage = 0x400;
    private const int MaxLine = 239;

    /// <summary>
    ///  Tokenizes a program's lines.
    /// </summary>
    /// <param name="roms">The ROMs of an Apple II: Integer BASIC at $E000-$F7FF.</param>
    /// <param name="lines">
    ///  The lines, each starting with its number, such as <c>10 PRINT "HI"</c>; blank ones are skipped.
    /// </param>
    /// <returns>
    ///  The program, from PP up to HIMEM, and what Integer BASIC said was wrong with each line it refused.
    /// </returns>
    public static IntegerBasicTokens Tokenize(Apple2Roms roms, IEnumerable<string> lines)
    {
        ArgumentNullException.ThrowIfNull(roms);
        ArgumentNullException.ThrowIfNull(lines);
        Apple2Machine machine = new(Apple2Model.II, roms);
        // The Monitor's reset sets up the screen and keyboard first, whichever Monitor it is.
        machine.Run(cycles: 1_000_000);
        while (!machine.Processor.IsInstructionBoundary) { machine.StepCycle(); }
        var registers = machine.Processor.Registers;
        registers.ProgramCounter = ColdStart;
        machine.Processor.Registers = registers;
        machine.Run(cycles: 200_000);

        List<IntegerBasicError> errors = [];
        int index = -1;
        foreach (string raw in lines)
        {
            index++;
            string line = raw.Trim();
            if (line.Length == 0) { continue; }
            if (!char.IsAsciiDigit(line[0]))
            {
                errors.Add(new(index, "An Integer BASIC line starts with its number."));
                continue;
            }

            if (line.Length > MaxLine)
            {
                errors.Add(new(index, $"The line is longer than {MaxLine} characters."));
                continue;
            }

            ClearScreen(machine);
            foreach (char character in line)
            {
                if (character is < ' ' or > '~')
                {
                    errors.Add(new(index, "The line has a character the keyboard cannot type."));
                    goto next;
                }

                machine.Bus.QueueKey((byte)character);
            }

            machine.Bus.QueueKey((byte)'\r');
            for (int wait = 0; wait < 400 && machine.Bus.KeysWaiting != 0; wait++) { machine.Run(cycles: 5_000); }
            machine.Run(cycles: 50_000);
            if (Message(machine) is { } message) { errors.Add(new(index, message)); }
        next:;
        }

        int start = Word(machine, ProgramStart);
        int end = Word(machine, Himem);
        byte[] program = new byte[Math.Max(0, end - start)];
        for (int i = 0; i < program.Length; i++) { program[i] = machine.Bus.Peek((ushort)(start + i)); }
        return new(program, errors);
    }

    // Blanks the text screen and homes the cursor, so whatever BASIC prints for the next line is all there is.
    private static void ClearScreen(Apple2Machine machine)
    {
        for (int address = TextPage; address < TextPage + 0x400; address++)
        {
            machine.Bus.SetRam(auxiliary: false, (ushort)address, 0xA0);
        }

        machine.Bus.SetRam(auxiliary: false, 0x24, 0);
        machine.Bus.SetRam(auxiliary: false, 0x25, 0);
        machine.Bus.SetRam(auxiliary: false, 0x28, 0x00);
        machine.Bus.SetRam(auxiliary: false, 0x29, 0x04);
    }

    // What Integer BASIC printed about the line: an error such as *** SYNTAX ERR, or null when it took the line.
    private static string? Message(Apple2Machine machine)
    {
        for (int row = 0; row < 24; row++)
        {
            string text = new([.. Enumerable.Range(0, 40).Select(column => (char)(machine.Bus.TextByte(row, column) & 0x7F))]);
            int stars = text.IndexOf("***", StringComparison.Ordinal);
            if (stars >= 0) { return text[stars..].Trim(); }
        }

        return null;
    }

    private static int Word(Apple2Machine machine, ushort address) =>
        machine.Bus.Peek(address) | (machine.Bus.Peek((ushort)(address + 1)) << 8);
}
