// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Desktop;

/// <summary>
///  A card Add Card offers: what it is, a note, the <c>retro/hardware</c> arguments that add it, the slots it goes in
///  if not any but slot 0, and the machines that take it if not only the Apple II.
/// </summary>
/// <param name="Label">The card's name.</param>
/// <param name="Detail">What it does.</param>
/// <param name="Action">The action that adds it.</param>
/// <param name="Arguments">The action's other arguments.</param>
/// <param name="Slots">The slots it goes in, or null for any but slot 0.</param>
/// <param name="Machines">The machines that take it, or null for the Apple II alone.</param>
internal sealed record Card(
    string Label,
    string Detail,
    string Action,
    IReadOnlyDictionary<string, int>? Arguments = null,
    IReadOnlyList<string>? Slots = null,
    IReadOnlyList<string>? Machines = null)
{
    /// <summary>
    ///  The cards, as the extension's Add Card offers them (<c>hardware.ts</c>).
    /// </summary>
    internal static IReadOnlyList<Card> All { get; } =
    [
        new("Disk II controller", "16-sector: DOS 3.3 and ProDOS disks", "addDiskII", new Dictionary<string, int>
        {
            ["sectors"] = 16
        }),
        new("Disk II controller, 13-sector", "DOS 3.2 and earlier disks", "addDiskII", new Dictionary<string, int>
        {
            ["sectors"] = 13
        }),
        new("Mockingboard", "Two AY-3-8910 sound chips; Sound: speaker + Mockingboard plays them", "addMockingboard", Slots: ["slot4"]),
        new("Mouse card", "An AppleMouse II-compatible mouse; click the screen to move it, Escape to let go", "addMouse"),
        new("ProFile interface card", "Apple's ProFile hard disk; insert a .po or .hdv image", "addProFile", Machines: ["apple2", "apple3"]),
        new("3.5 disk controller", "Two SuperDrives: 400K and 800K Apple disks, 720K and 1.44 MB MFM disks", "addDisk35"),
        new("Z80 SoftCard", "Microsoft's Z80 card, for CP/M; one at a time", "addSoftCard"),
        new("Language card", "16 KB of RAM at $D000-$FFFF, for slot 0 of a II or II Plus", "addLanguageCard", Slots: ["slot0"]),
        new("Firmware card", "The other BASIC in ROM: AppleSoft on a II, Integer BASIC on a II Plus", "addFirmwareCard", Slots: ["slot0"]),
    ];

    /// <summary>
    ///  Gets the cards a machine's slot takes: on the Apple II, slot 0 the language or firmware card, slots 1 to 7 the
    ///  others.
    /// </summary>
    /// <param name="slot">The slot's hardware id, such as <c>slot5</c>.</param>
    /// <param name="machine">The launch's machine option.</param>
    /// <returns>The cards.</returns>
    internal static IEnumerable<Card> For(string slot, string machine) => All.Where(card =>
        (card.Machines ?? ["apple2"]).Contains(machine)
            && (card.Slots is null ? slot != "slot0" : card.Slots.Contains(slot)));

    /// <summary>
    ///  Gets the <c>retro/hardware</c> arguments that add the card.
    /// </summary>
    /// <returns>The arguments, with the action.</returns>
    internal JsonObject Args()
    {
        JsonObject args = new() { ["action"] = Action };
        foreach ((string key, int value) in Arguments ?? new Dictionary<string, int>()) { args[key] = value; }
        return args;
    }
}