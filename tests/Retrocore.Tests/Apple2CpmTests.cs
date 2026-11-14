// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Apple2;
using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  Microsoft's SoftCard CP/M on the II Plus and the IIe, from its own disks: it boots to <c>A&gt;</c> and lists the
///  disk.
/// </summary>
/// <remarks>
///  <para>
///   The disks are in <c>RETROCORE_SOFTCARD_DISKS</c> or <c>%USERPROFILE%\Retrocore\softcard-disks</c>; the tests are
///   inconclusive without them. The ROMs are the SDK's.
///  </para>
/// </remarks>
[TestClass]
public sealed class Apple2CpmTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    private static string Disks => Environment.GetEnvironmentVariable("RETROCORE_SOFTCARD_DISKS")
        ?? Path.Join(ExternalTestData.Root, "softcard-disks");

    /// <summary>
    ///  Each CP/M disk boots to its prompt on a II Plus with a language card, and DIR lists its files.
    /// </summary>
    /// <param name="disk">The disk image's file name.</param>
    /// <param name="model">The machine.</param>
    [TestMethod]
    [DataRow("Softcard 16-sector disk (Microsoft 1980).dsk", Apple2Model.IIPlus)]
    [DataRow("CPM_Z80SoftCard.dsk", Apple2Model.IIPlus)]
    [DataRow("CPM2.2(56k).dsk", Apple2Model.IIPlus)]
    [DataRow("CPM2.23(60k).dsk", Apple2Model.IIPlus)]
    [DataRow("Softcard 16-sector disk (Microsoft 1980).dsk", Apple2Model.IIeEnhanced)]
    [DataRow("CPM_Z80SoftCard.dsk", Apple2Model.IIeEnhanced)]
    [DataRow("CPM2.2(56k).dsk", Apple2Model.IIeEnhanced)]
    [DataRow("CPM2.23(60k).dsk", Apple2Model.IIeEnhanced)]
    public void BootsToThePromptAndListsTheDisk(string disk, Apple2Model model)
    {
        Apple2Machine machine = Boot(disk, model);
        RunUntil(machine, "A>", seconds: 20);
        Type(machine, "DIR\r");
        RunUntil(machine, "STAT     COM", seconds: 10);
    }

    private static Apple2Machine Boot(string disk, Apple2Model model)
    {
        string path = Path.Join(Disks, disk);
        if (!File.Exists(path))
        {
            Assert.Inconclusive($"Set RETROCORE_SOFTCARD_DISKS to the SoftCard CP/M disks ({disk}).");
        }

        Apple2Machine machine = new(model, SdkModules.BuildRoms(model, s_inputs));
        if (model == Apple2Model.IIPlus) { machine.Bus.InstallLanguageCard(); }
        machine.Bus.InstallDiskII(slot: 6, SdkModules.BuildDiskII(sectors: 16, s_inputs));
        machine.Bus.InstallSoftCard(slot: 4);
        WozDisk media = SectorDiskConverter.Convert(File.ReadAllBytes(path), proDosOrder: false);
        machine.Drives[0].Insert(WozDisk.Load(media.Export(), writable: true), disk, "DSK");
        machine.Reset();
        return machine;
    }

    private static void RunUntil(Apple2Machine machine, string text, int seconds)
    {
        for (int tenth = 0; tenth < seconds * 10; tenth++)
        {
            if (Screen(machine).Contains(text, StringComparison.Ordinal)) { return; }
            machine.Run(BasicMachines.IIeClock / 10);
        }

        Assert.Fail($"No \"{text}\" after {seconds} seconds. The screen:\n{Screen(machine)}");
    }

    private static void Type(Apple2Machine machine, string text)
    {
        foreach (char key in text) { machine.Bus.QueueKey((byte)key); }
    }

    private static string Screen(Apple2Machine machine)
    {
        int columns = machine.Bus.Switches.HasFlag(Apple2Switches.Column80) ? 80 : 40;
        return string.Join(
            "\n",
            Enumerable.Range(0, 24).Select(row => new string([.. Enumerable.Range(0, columns)
                .Select(column => (char)(machine.Bus.TextByte(row, column) & 0x7F))
                .Select(character => character < 32 ? (char)(character + 64) : character)])));
    }
}
