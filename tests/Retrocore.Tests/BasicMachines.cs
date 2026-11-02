// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Trs80;

namespace Retrocore.Tests;

/// <summary>
///  Machines running the SDK's BASIC ROMs, which are byte-identical to the real ones, and typing on them.
/// </summary>
internal static class BasicMachines
{
    /// <summary>
    ///  The IIe's clock, in cycles a second.
    /// </summary>
    internal const int IIeClock = 1_020_484;

    /// <summary>
    ///  Gets the test inputs, which hold the SDK's ROM sources.
    /// </summary>
    internal static string Inputs { get; } = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  Assembles AppleSoft for a model.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <returns>The assembly, for its symbols.</returns>
    internal static AssemblyResult AppleSoft(Apple2Model model) =>
        SdkModules.AssembleAppleSoft(Path.Join(Inputs, "AppleSoft", "applesoft.mac"), model);

    /// <summary>
    ///  Assembles Level II for a revision.
    /// </summary>
    /// <param name="revision">12 or 13.</param>
    /// <returns>The assembly.</returns>
    internal static AssemblyResult Level2(int revision) =>
        Trs80SdkModules.AssembleLevel2(Path.Join(Inputs, "Trs80", "Level2.asm"), revision);

    /// <summary>
    ///  Boots a IIe to AppleSoft's prompt.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <returns>The machine.</returns>
    internal static Apple2Machine BootIIe(Apple2Model model)
    {
        Apple2Machine machine = new(model, SdkModules.BuildRoms(model, Inputs));
        machine.Run(IIeClock * 2);
        return machine;
    }

    /// <summary>
    ///  Boots a 16K Model I to Level II's prompt.
    /// </summary>
    /// <param name="rom">The Level II assembly.</param>
    /// <returns>The machine.</returns>
    internal static Trs80Machine BootLevel2(AssemblyResult rom)
    {
        Trs80Machine machine = new(
            new Trs80Configuration { RamKilobytes = 16, ExpansionInterface = false, DiskController = false },
            new Trs80Roms(rom.Sections[0].Bytes.Span, new byte[Trs80Roms.CharacterGeneratorSize]));

        machine.Run(Trs80Timing.ClockHertz);
        Type(machine, "\r");
        machine.Run(Trs80Timing.ClockHertz * 2);
        return machine;
    }

    /// <summary>
    ///  Types a line on a IIe, each key once the ROM has taken the one before, then lets BASIC store it.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <param name="line">The line, without its return.</param>
    internal static void TypeLine(Apple2Machine machine, string line)
    {
        foreach (char character in line + "\r")
        {
            machine.Bus.QueueKey((byte)character);
            for (int wait = 0; wait < 1000 && machine.Bus.Peek(0xC000) >= 0x80; wait++) { machine.Run(1000); }
        }

        machine.Run(IIeClock / 5);
    }

    /// <summary>
    ///  Types on a Model I, then lets BASIC take it.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <param name="text">The keys.</param>
    internal static void Type(Trs80Machine machine, string text)
    {
        foreach (char character in text)
        {
            machine.Bus.Keyboard.Type((byte)character).Should().BeTrue($"'{character}' has a key");
        }

        while (machine.Bus.Keyboard.IsTyping) { machine.Run(1000); }
        machine.Run(Trs80Timing.ClockHertz / 2);
    }

}
