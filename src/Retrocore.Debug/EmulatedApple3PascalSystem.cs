// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple3;
using Retrocore.Media;

namespace Retrocore.Debug;

/// <summary>
///  Apple III Pascal running on an emulated Apple III, driven from its keyboard: its system disk (/PASCAL1) in the
///  built-in drive, its tools (/PASCAL2, with the Compiler, Assembler and Linker) in .D2, and a work volume in .D3.
/// </summary>
/// <remarks>
///  <para>
///   The boot ROM is the SDK's <c>BootRom.asm</c>, which is byte-identical to Apple's, and the disk sequencer the
///   Disk II's <c>Sequencer16.asm</c>, the same chip.
///  </para>
/// </remarks>
internal sealed class EmulatedApple3PascalSystem
{
    /// <summary>
    ///  The command line's prompt, as the system shows it.
    /// </summary>
    internal const string CommandLine = "Command: E(dit, R(un, F(ile";

    private readonly Apple3Machine _machine;

    /// <summary>
    ///  Boots Pascal, to its command line.
    /// </summary>
    /// <param name="system">/PASCAL1's image, as a 140K <c>.dsk</c>.</param>
    /// <param name="tools">/PASCAL2's image.</param>
    /// <param name="work">The work volume's image, whose files the work reads and writes.</param>
    /// <param name="roms">The SDK's sources, or null for the copy beside the host.</param>
    /// <param name="output">
    ///  A fourth volume's image, in .D4, for output too big to go beside the work; null for none.
    /// </param>
    /// <param name="prefix">
    ///  Whether to make /WORK the prefix with the Filer, for names without a volume; Apple III Pascal 1.0's Filer, on
    ///  its damaged first disk, cannot.
    /// </param>
    /// <exception cref="TimeoutException">The system never booted.</exception>
    public EmulatedApple3PascalSystem(byte[] system, byte[] tools, byte[] work, string? roms, byte[]? output = null, bool prefix = true)
    {
        string sources = Apple3SdkModules.Directory(roms);
        byte[] boot = Apple3SdkModules.AssembleBootRom(Path.Join(sources, "BootRom.asm")).Sections[0].Bytes.ToArray();
        string sequencerSource = SdkModules.DiskIIPath("Sequencer16.asm", Path.GetDirectoryName(sources));
        if (!File.Exists(sequencerSource)) { sequencerSource = SdkModules.DiskIIPath("Sequencer16.asm"); }
        byte[] sequencer = SdkModules.AssembleDiskII(sequencerSource, origin: 0).Sections[0].Bytes.ToArray();

        _machine = new(new Apple3Roms(boot, sequencer), ramKilobytes: 256);
        byte[][] disks = output is null ? [system, tools, work] : [system, tools, work, output];
        for (int drive = 0; drive < disks.Length; drive++)
        {
            WozDisk media = SectorDiskConverter.Convert(disks[drive], proDosOrder: false);
            _machine.Drives[drive].Insert(WozDisk.Load(media.Export(), writable: true), $"DISK{drive + 1}", "DSK");
        }

        if (WaitFor(["Based on  U.C.S.D. Pascal II.1"], seconds: 120) is null)
        {
            throw new TimeoutException($"Pascal never booted:\n{Screen}");
        }

        Type("\n");
        if (WaitFor([CommandLine], seconds: 60) is null)
        {
            throw new TimeoutException($"Pascal never reached its command line:\n{Screen}");
        }

        Run(tenths: 10);
        if (!prefix) { return; }

        // Names without a volume, such as a unit's code file a source's (*$U*) names, are /WORK's.
        Type("F");
        Expect("Filer:");
        Type("P");
        Expect("Prefix");
        Type("/WORK\n");
        Expect("Prefix is /WORK");
        Type("Q");
        Expect(CommandLine);
        Run(tenths: 10);
    }

    private void Expect(string text)
    {
        if (WaitFor([text], seconds: 60) is null)
        {
            throw new TimeoutException($"Pascal never showed {text}:\n{Screen}");
        }
    }

    /// <summary>
    ///  Gets the text screen.
    /// </summary>
    public string Screen => string.Join('\n', _machine.ReadTextScreen());

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
    /// <param name="texts">The texts, as the screen shows them.</param>
    /// <param name="seconds">How long to wait, in the machine's time.</param>
    /// <returns>The text it showed, or null when it showed none in time.</returns>
    public string? WaitFor(string[] texts, int seconds)
    {
        for (int tenth = 0; tenth < seconds * 10; tenth++)
        {
            string screen = Screen;
            foreach (string text in texts)
            {
                if (screen.Contains(text, StringComparison.Ordinal)) { return text; }
            }

            Run(tenths: 1);
        }

        return null;
    }

    /// <summary>
    ///  Runs the machine.
    /// </summary>
    /// <param name="tenths">How long, in tenths of the machine's seconds.</param>
    public void Run(int tenths) => _machine.Run(TimeSpan.FromSeconds(tenths / 10.0));

    /// <summary>
    ///  Takes the work volume out of .D3, and reads it.
    /// </summary>
    /// <returns>The volume as the system left it.</returns>
    /// <exception cref="InvalidOperationException">The disk left the drive.</exception>
    public SosVolume EjectWork() => Eject(drive: 2);

    /// <summary>
    ///  Takes the output volume out of .D4, and reads it.
    /// </summary>
    /// <returns>The volume as the system left it.</returns>
    /// <exception cref="InvalidOperationException">The disk left the drive.</exception>
    public SosVolume EjectOutput() => Eject(drive: 3);

    private SosVolume Eject(int drive)
    {
        WozDisk disk = _machine.Drives[drive].Eject() ?? throw new InvalidOperationException("The disk left the drive.");
        return SosVolume.Read(SectorDiskReader.Read(disk, proDosOrder: false), proDosOrder: false);
    }
}
