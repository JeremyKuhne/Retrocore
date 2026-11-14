// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;
using Retrocore.Media;

namespace Retrocore.Debug;

/// <summary>
///  Apple Pascal running on an emulated Apple II Plus, driven from its keyboard: APPLE1, a copy of the boot disk, in
///  drive 1 (#4), and APPLE2, with the Compiler, Assembler and Linker, in drive 2 (#5).
/// </summary>
internal sealed class EmulatedPascalSystem
{
    private const long CyclesPerTenth = 102_048;

    private readonly Apple2Machine _machine;

    /// <summary>
    ///  Boots Pascal, to its command line.
    /// </summary>
    /// <param name="boot">APPLE1's image, as a 140K <c>.dsk</c>, with the files the work needs written onto it.</param>
    /// <param name="toolsDisk">APPLE2's image.</param>
    /// <param name="roms">The SDK's ROM sources, or null for the copy beside the host.</param>
    /// <exception cref="TimeoutException">The system never booted.</exception>
    public EmulatedPascalSystem(byte[] boot, string toolsDisk, string? roms)
    {
        _machine = new(Apple2Model.IIPlus, SdkModules.BuildRoms(Apple2Model.IIPlus, roms, autostart: true));
        _machine.Bus.InstallDiskII(slot: 6, SdkModules.BuildDiskII(16, roms));
        _machine.Bus.InstallLanguageCard();
        WozDisk media = SectorDiskConverter.Convert(boot, proDosOrder: false);
        _machine.Drives[0].Insert(WozDisk.Load(media.Export(), writable: true), "APPLE1", "DSK");
        _machine.Drives[1].Insert(SectorDiskConverter.Convert(File.ReadAllBytes(toolsDisk), proDosOrder: false), "APPLE2", "DSK");
        _machine.Bus.ResetSwitches();
        _machine.Processor.Reset();

        // 1.0 says only that it is UCSD Pascal; 1.1 and 1.2 welcome APPLE1.
        if (WaitFor(["COMMAND: E(DIT"], seconds: 60) is null)
        {
            throw new TimeoutException($"Pascal never booted:\n{Screen}");
        }

        Run(tenths: 10);
    }

    /// <summary>
    ///  Gets the text screen.
    /// </summary>
    public string Screen => string.Join(
        "\n",
        Enumerable.Range(0, 24).Select(row => new string([.. Enumerable.Range(0, 40)
            .Select(column => (char)(_machine.Bus.TextByte(row, column) & 0x7F))
            .Select(character => character < 32 ? (char)(character + 64) : character)]).TrimEnd()));

    /// <summary>
    ///  Types keys, a carriage return for <c>\n</c>.
    /// </summary>
    /// <param name="keys">The keys.</param>
    public void Type(string keys)
    {
        foreach (char key in keys) { _machine.Bus.QueueKey(key == '\n' ? (byte)13 : (byte)key); }
    }

    /// <summary>
    ///  Runs until the screen shows one of the texts.
    /// </summary>
    /// <param name="texts">The texts, in any case.</param>
    /// <param name="seconds">How long to wait, in the machine's time.</param>
    /// <returns>The text it showed, or null when it showed none in time.</returns>
    public string? WaitFor(string[] texts, int seconds)
    {
        for (int tenth = 0; tenth < seconds * 10; tenth++)
        {
            string screen = Screen;
            foreach (string text in texts)
            {
                if (screen.Contains(text, StringComparison.OrdinalIgnoreCase)) { return text; }
            }

            Run(tenths: 1);
        }

        return null;
    }

    /// <summary>
    ///  Runs the machine.
    /// </summary>
    /// <param name="tenths">How long, in tenths of the machine's seconds.</param>
    public void Run(int tenths) => _machine.Run(cycles: (ulong)(CyclesPerTenth * tenths));

    /// <summary>
    ///  Takes APPLE1 out of its drive, and reads its volume.
    /// </summary>
    /// <returns>The volume as the system left it.</returns>
    /// <exception cref="InvalidOperationException">The disk left the drive.</exception>
    public PascalVolume Eject()
    {
        WozDisk disk = _machine.Drives[0].Eject() ?? throw new InvalidOperationException("The disk left the drive.");
        return PascalVolume.Read(SectorDiskReader.Read(disk, proDosOrder: false), proDosOrder: false);
    }
}
