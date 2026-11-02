// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Apple2;
using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  DOS 3.3 across the Apple II family: the System Master boots on the II and II Plus, and its FP and INT commands
///  find the other BASIC in the slot 0 card, loaded into a language card or held by a firmware card.
/// </summary>
[TestClass]
public class Apple2DosTests
{
    private const string Master = "DOS 3.3 System Master - 680-0210-A (1982).dsk";
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  The master boots each setup into a BASIC, and the other BASIC answers its command.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   DOS ends its boot with two reads of $C081, to leave a language card reading ROM. On a firmware card the same
    ///   reads select the board's ROM, so a II with the AppleSoft card boots into its own Integer BASIC, and FP selects
    ///   the card. That II boots a DOS 3.3 disk with no HELLO (<c>firmwareCardBlank</c>): the master's HELLO leaves
    ///   it in Integer BASIC without DOS, which is not checked here.
    ///  </para>
    /// </remarks>
    /// <param name="model">The II or II Plus.</param>
    /// <param name="slot0">
    ///  What slot 0 holds: the language card, which DOS loads the other BASIC into, or the firmware card, which holds
    ///  it.
    /// </param>
    /// <param name="prompt">The prompt of the board's BASIC once DOS has booted.</param>
    /// <param name="command">The DOS command for the other BASIC.</param>
    /// <param name="other">The other BASIC's prompt.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus, "languageCard", ']', "INT", '>')]
    [DataRow(Apple2Model.IIPlus, "firmwareCard", ']', "INT", '>')]
    [DataRow(Apple2Model.II, "languageCard", '>', "FP", ']')]
    [DataRow(Apple2Model.II, "firmwareCardBlank", '>', "FP", ']')]
    public void MasterBootsAndSwitchesBasic(Apple2Model model, string slot0, char prompt, string command, char other)
    {
        string disk = Path.Join(ExternalTestData.Root, "iie-disks", Master);
        if (!File.Exists(disk))
        {
            Assert.Inconclusive($"The DOS 3.3 System Master is not in {Path.GetDirectoryName(disk)}.");
        }

        Apple2Machine machine = new(model, SdkModules.BuildRoms(model, s_inputs, autostart: true));
        machine.Bus.InstallDiskII(slot: 6, SdkModules.BuildDiskII(16, s_inputs));
        byte[] dos = SdkModules.AssembleDos(SdkModules.DosPath("Dos33.asm", s_inputs), master: false).Sections[0].Bytes.ToArray();
        byte[] image = slot0 == "firmwareCardBlank" ? DosDisk.Create(DosDisk.Dos33Tracks(dos), [], 16) : File.ReadAllBytes(disk);

        machine.Drives[0].Insert(SectorDiskConverter.Convert(image, proDosOrder: false), disk, "DSK");
        if (slot0 == "languageCard")
        {
            machine.Bus.InstallLanguageCard();
        }
        else
        {
            Apple2Model card = model == Apple2Model.II ? Apple2Model.IIPlus : Apple2Model.II;
            // The AppleSoft card's switch is up on a II, so its Autostart Monitor boots; the Integer card's down on a
            // II Plus, as its original Monitor would not.
            machine.Bus.InstallFirmwareCard(SdkModules.BuildBoardSystem(card, autostart: false, s_inputs), active: model == Apple2Model.II);
        }

        machine.Bus.ResetSwitches();
        machine.Processor.Reset();
        // The master shows its title; a disk with no HELLO says so.
        string booted = slot0 == "firmwareCardBlank" ? "FILE NOT FOUND" : "DOS VERSION 3.3";
        Run(machine, until: screen => screen.Contains(booted, StringComparison.Ordinal) && Prompt(screen) == prompt);

        foreach (char key in command + "\r") { machine.Bus.QueueKey((byte)key); }
        Run(machine, until: screen => Prompt(screen) == other);
    }

    // Runs until the screen shows what is wanted, failing after 30 seconds of the machine's time.
    private static void Run(Apple2Machine machine, Func<string, bool> until)
    {
        for (int second = 0; second < 300; second++)
        {
            machine.Run(cycles: 102_048);
            if (until(Screen(machine))) { return; }
        }

        Assert.Fail($"The screen never showed what was wanted:\n{Screen(machine)}");
    }

    // The last character before the cursor (a flashing space, shown here as `) on the last line that has one: the
    // prompt BASIC is waiting at.
    private static char Prompt(string screen)
    {
        string[] lines = screen.Split('\n');
        string? last = lines.LastOrDefault(line => line.Trim().Length != 0);
        string text = last?.TrimEnd().TrimEnd('`').TrimEnd() ?? "";
        return text.Length > 0 ? text[^1] : ' ';
    }

    private static string Screen(Apple2Machine machine) => string.Join(
        "\n",
        Enumerable.Range(0, 24).Select(row => new string([.. Enumerable.Range(0, 40)
            .Select(column => (char)(machine.Bus.TextByte(row, column) & 0x7F))
            .Select(character => character < 32 ? (char)(character + 64) : character)])));
}
