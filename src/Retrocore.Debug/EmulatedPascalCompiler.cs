// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;
using Retrocore.Media;

namespace Retrocore.Debug;

/// <summary>
///  Compiles a Pascal source with Apple Pascal's own Compiler, on an emulated Apple II Plus.
/// </summary>
/// <remarks>
///  <para>
///   The source goes onto a copy of the boot disk (APPLE1) as the workfile, <c>SYSTEM.WRK.TEXT</c>; the machine boots
///   with the Compiler's disk (APPLE2) in drive 2, C(ompile)s the workfile, and the code file it writes,
///   <c>SYSTEM.WRK.CODE</c>, is read back from the disk. Units the program uses come from APPLE1's
///   <c>SYSTEM.LIBRARY</c>, as on the machine.
///  </para>
/// </remarks>
internal static class EmulatedPascalCompiler
{
    private const long CyclesPerTenth = 102_048;

    /// <summary>
    ///  Compiles a source.
    /// </summary>
    /// <param name="source">The program, as plain text.</param>
    /// <param name="bootDisk">APPLE1's image, as a 140K <c>.dsk</c>.</param>
    /// <param name="compilerDisk">APPLE2's image, with <c>SYSTEM.COMPILER</c>.</param>
    /// <param name="roms">The SDK's ROM sources, or null for the copy beside the host.</param>
    /// <returns>
    ///  The code file the Compiler wrote, or null when it stopped with an error; and the screen when it finished, which
    ///  shows an error.
    /// </returns>
    /// <exception cref="TimeoutException">The system never booted, or the Compiler never finished.</exception>
    internal static (byte[]? Code, string Screen) Compile(string source, string bootDisk, string compilerDisk, string? roms = null)
    {
        (byte[]? code, string screen, _) = CompileWithListing(source, bootDisk, compilerDisk, listing: null, roms);
        return (code, screen);
    }

    /// <summary>
    ///  Compiles a source, and reads back the listing it asks for.
    /// </summary>
    /// <param name="source">The program, as plain text.</param>
    /// <param name="bootDisk">APPLE1's image, as a 140K <c>.dsk</c>.</param>
    /// <param name="compilerDisk">APPLE2's image, with <c>SYSTEM.COMPILER</c>.</param>
    /// <param name="listing">
    ///  The listing file the source's <c>(*$L APPLE1:NAME.TEXT*)</c> names, on APPLE1, to read back; null for none.
    /// </param>
    /// <param name="roms">The SDK's ROM sources, or null for the copy beside the host.</param>
    /// <returns>
    ///  The code file, or null on an error; the screen when it finished; and the listing's text, or null.
    /// </returns>
    /// <exception cref="TimeoutException">The system never booted, or the Compiler never finished.</exception>
    internal static (byte[]? Code, string Screen, string? Listing) CompileWithListing(
        string source,
        string bootDisk,
        string compilerDisk,
        string? listing,
        string? roms = null)
    {
        byte[] boot = File.ReadAllBytes(bootDisk);
        // A listing takes a free area of its own besides the code file's: APPLE1 has one, so the Editor, which a
        // compile does not need, makes room.
        if (listing is not null) { PascalVolume.DeleteFile(boot, proDosOrder: false, "SYSTEM.EDITOR"); }
        PascalVolume.WriteFile(boot, proDosOrder: false, "SYSTEM.WRK.TEXT", PascalFileKind.Text, PascalTextFile.Write(source));

        Apple2Machine machine = new(Apple2Model.IIPlus, SdkModules.BuildRoms(Apple2Model.IIPlus, roms, autostart: true));
        machine.Bus.InstallDiskII(slot: 6, SdkModules.BuildDiskII(16, roms));
        machine.Bus.InstallLanguageCard();
        WozDisk media = SectorDiskConverter.Convert(boot, proDosOrder: false);
        machine.Drives[0].Insert(WozDisk.Load(media.Export(), writable: true), "APPLE1", "DSK");
        machine.Drives[1].Insert(SectorDiskConverter.Convert(File.ReadAllBytes(compilerDisk), proDosOrder: false), "APPLE2", "DSK");
        machine.Bus.ResetSwitches();
        machine.Processor.Reset();

        // 1.0 says only that it is UCSD Pascal; 1.1 and 1.2 welcome APPLE1.
        if (RunUntil(machine, ["COMMAND: E(DIT"], seconds: 60) is null)
        {
            throw new TimeoutException($"Pascal never booted:\n{Screen(machine)}");
        }

        machine.Run(cycles: CyclesPerTenth * 10);
        machine.Bus.QueueKey((byte)'C');

        // The Compiler ends with the space it had left, or stops at an error with a prompt to go on, stop or edit.
        string ended = RunUntil(machine, ["SMALLEST AVAILABLE", "(CONTINUE)"], seconds: 1_800)
            ?? throw new TimeoutException($"The Compiler never finished:\n{Screen(machine)}");

        string screen = Screen(machine);
        if (ended != "SMALLEST AVAILABLE") { return (null, screen, null); }

        // The code file and listing are closed as the system comes back to its command line; its line is still on the
        // screen from before, so the wait is long enough for both.
        machine.Run(cycles: (ulong)(CyclesPerTenth * (listing is null ? 50 : 300)));
        WozDisk disk = machine.Drives[0].Eject() ?? throw new InvalidOperationException("The disk left the drive.");
        PascalVolume volume = PascalVolume.Read(SectorDiskReader.Read(disk, proDosOrder: false), proDosOrder: false);
        string? text = listing is not null && volume.Files.Any(file => string.Equals(file.Name, listing, StringComparison.OrdinalIgnoreCase))
            ? PascalTextFile.Read(volume.ReadFile(listing))
            : null;

        return volume.Files.Any(file => file.Name == "SYSTEM.WRK.CODE")
            ? (volume.ReadFile("SYSTEM.WRK.CODE"), screen, text)
            : (null, screen, text);
    }

    // Runs until the screen shows one of the texts, and says which.
    private static string? RunUntil(Apple2Machine machine, string[] texts, int seconds)
    {
        for (int tenth = 0; tenth < seconds * 10; tenth++)
        {
            string screen = Screen(machine);
            foreach (string text in texts)
            {
                if (screen.Contains(text, StringComparison.OrdinalIgnoreCase)) { return text; }
            }

            machine.Run(cycles: CyclesPerTenth);
        }

        return null;
    }

    private static string Screen(Apple2Machine machine) => string.Join(
        "\n",
        Enumerable.Range(0, 24).Select(row => new string([.. Enumerable.Range(0, 40)
            .Select(column => (char)(machine.Bus.TextByte(row, column) & 0x7F))
            .Select(character => character < 32 ? (char)(character + 64) : character)]).TrimEnd()));
}
