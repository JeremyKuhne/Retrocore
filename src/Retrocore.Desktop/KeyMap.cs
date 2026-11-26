// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia.Input;

namespace Retrocore.Desktop;

/// <summary>
///  The keys each machine takes for the keys that type no character, as the display panel maps them.
/// </summary>
internal static class KeyMap
{
    private static readonly Dictionary<string, Dictionary<Key, int>> s_maps = new()
    {
        ["apple2"] = new()
        {
            [Key.Enter] = 13,
            [Key.Back] = 8,
            [Key.Left] = 8,
            [Key.Right] = 21,
            [Key.Up] = 11,
            [Key.Down] = 10,
            [Key.Escape] = 27,
            [Key.Tab] = 9,
            [Key.Delete] = 127
        },
        ["apple3"] = new()
        {
            [Key.Enter] = 13,
            [Key.Back] = 8,
            [Key.Left] = 8,
            [Key.Right] = 21,
            [Key.Up] = 11,
            [Key.Down] = 10,
            [Key.Escape] = 27,
            [Key.Tab] = 9,
            [Key.Delete] = 127
        },
        ["trs80-model1"] = new()
        {
            [Key.Enter] = 13,
            [Key.Back] = 8,
            [Key.Left] = 8,
            [Key.Right] = 9,
            [Key.Up] = 11,
            [Key.Down] = 10,
            [Key.Home] = 31,
            [Key.Escape] = 1
        },
        ["trs80-model3"] = new()
        {
            [Key.Enter] = 13,
            [Key.Back] = 8,
            [Key.Left] = 8,
            [Key.Right] = 9,
            [Key.Up] = 11,
            [Key.Down] = 10,
            [Key.Home] = 31,
            [Key.Escape] = 1
        },
        ["trs80-model2"] = new()
        {
            [Key.Enter] = 13,
            [Key.Back] = 8,
            [Key.Tab] = 9,
            [Key.Left] = 28,
            [Key.Right] = 29,
            [Key.Up] = 30,
            [Key.Down] = 31,
            [Key.Escape] = 3
        },
        ["apple1"] = new() { [Key.Enter] = 13, [Key.Back] = 95, [Key.Left] = 95, [Key.Escape] = 27 },
        ["coco"] = new()
        {
            [Key.Enter] = 13,
            [Key.Back] = 8,
            [Key.Left] = 8,
            [Key.Right] = 9,
            [Key.Up] = 11,
            [Key.Down] = 10,
            [Key.Home] = 31,
            [Key.Escape] = 1
        },
        // The BBC Micro's DELETE is 127, its cursor keys and COPY the MOS's codes &88-&8B and &87, SHIFT LOCK (Scroll
        // Lock) the keyboard's &8C, and its function keys the keyboard's own codes, &F0-&F9 for f0-f9: F10 is f0.
        ["bbc"] = new()
        {
            [Key.Enter] = 13,
            [Key.Back] = 127,
            [Key.Delete] = 127,
            [Key.Tab] = 9,
            [Key.Escape] = 27,
            [Key.End] = 0x87,
            [Key.Left] = 0x88,
            [Key.Right] = 0x89,
            [Key.Down] = 0x8A,
            [Key.Up] = 0x8B,
            [Key.Scroll] = 0x8C,
            [Key.F10] = 0xF0,
            [Key.F1] = 0xF1,
            [Key.F2] = 0xF2,
            [Key.F3] = 0xF3,
            [Key.F4] = 0xF4,
            [Key.F5] = 0xF5,
            [Key.F6] = 0xF6,
            [Key.F7] = 0xF7,
            [Key.F8] = 0xF8,
            [Key.F9] = 0xF9
        },
        ["pet"] = new()
        {
            [Key.Enter] = 13,
            [Key.Back] = 20,
            [Key.Delete] = 20,
            [Key.Insert] = 148,
            [Key.Left] = 157,
            [Key.Right] = 29,
            [Key.Up] = 145,
            [Key.Down] = 17,
            [Key.Home] = 19,
            [Key.Escape] = 3,

            // The business keyboard's TAB; the graphics keyboard has none and ignores it.
            [Key.Tab] = 9
        },
        // The Atari types ATASCII: BACK S is $7E, TAB $7F, CLEAR $7D and the cursor keys $1C-$1F; the keys that type
        // nothing are the debug host's codes from $F0, F2-F4 for START, SELECT and OPTION, and Pause for BREAK.
        ["atari800"] = new()
        {
            [Key.Enter] = 13,
            [Key.Back] = 0x7E,
            [Key.Delete] = 0x7E,
            [Key.Tab] = 0x7F,
            [Key.Escape] = 27,
            [Key.Home] = 0x7D,
            [Key.Up] = 0x1C,
            [Key.Down] = 0x1D,
            [Key.Left] = 0x1E,
            [Key.Right] = 0x1F,
            [Key.F2] = 0xF0,
            [Key.F3] = 0xF1,
            [Key.F4] = 0xF2,
            [Key.Pause] = 0xF3
        },
        ["altair"] = new()
        {
            [Key.Enter] = 13,
            [Key.Back] = 8,
            [Key.Tab] = 9,
            [Key.Escape] = 27,
            [Key.Delete] = 127,
            [Key.Left] = 8,
            [Key.Right] = 12,
            [Key.Up] = 11,
            [Key.Down] = 10
        },

        // The Model 100's keys are ASCII, with its arrows as the codes its ROM gives them, $1C-$1F (right, left, up,
        // down), PAUSE/BREAK as 139 and F1-F8 as 128-135, the debug host's codes for the keys that type nothing.
        ["trs80-model100"] = new()
        {
            [Key.Enter] = 13,
            [Key.Back] = 8,
            [Key.Tab] = 9,
            [Key.Escape] = 27,
            [Key.Right] = 0x1C,
            [Key.Left] = 0x1D,
            [Key.Up] = 0x1E,
            [Key.Down] = 0x1F,
            [Key.Pause] = 139,
            [Key.F1] = 128,
            [Key.F2] = 129,
            [Key.F3] = 130,
            [Key.F4] = 131,
            [Key.F5] = 132,
            [Key.F6] = 133,
            [Key.F7] = 134,
            [Key.F8] = 135
        },

        // The Kaypro II's keyboard sends ASCII, with its arrows as $F1-$F4; it has no BREAK.
        ["kaypro2"] = new()
        {
            [Key.Enter] = 13,
            [Key.Back] = 8,
            [Key.Tab] = 9,
            [Key.Escape] = 27,
            [Key.Delete] = 127,
            [Key.Up] = 0xF1,
            [Key.Down] = 0xF2,
            [Key.Left] = 0xF3,
            [Key.Right] = 0xF4
        },
    };

    /// <summary>
    ///  Gets the code a key types on a machine, for a key that types no character, or a control letter.
    /// </summary>
    /// <param name="machine">The launch's machine, such as <c>apple2</c>.</param>
    /// <param name="key">The key.</param>
    /// <param name="modifiers">The modifiers held.</param>
    /// <returns>The ASCII code, or null when the key types a character or nothing.</returns>
    internal static int? Code(string machine, Key key, KeyModifiers modifiers)
    {
        // Ctrl with Alt is AltGr on Windows layouts, which types a character, such as @ on a German keyboard, that
        // comes as text; only Ctrl alone makes a control letter, as the display panel has it.
        if ((modifiers & (KeyModifiers.Control | KeyModifiers.Alt)) == KeyModifiers.Control && key is >= Key.A and <= Key.Z)
        {
            return key - Key.A + 1;
        }

        return s_maps.TryGetValue(machine, out Dictionary<Key, int>? map) && map.TryGetValue(key, out int code) ? code : null;
    }
}