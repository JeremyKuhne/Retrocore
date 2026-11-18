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