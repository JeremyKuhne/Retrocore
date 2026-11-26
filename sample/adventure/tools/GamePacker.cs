// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

/// <summary>
///  Packs a <see cref="ScottFreeGame"/> into the interpreter's binary format, which <c>PackedFormat.md</c> describes.
/// </summary>
internal static class GamePacker
{
    /// <summary>
    ///  What the interpreter prints before a room description that doesn't start with <c>*</c>.
    /// </summary>
    internal const string RoomPrefix = "I'm in a ";

    /// <summary>
    ///  The highest value a condition can hold: the format's two bytes give it 11 bits.
    /// </summary>
    internal const int LargestValue = 0x7FF;

    /// <summary>
    ///  The most items the engine has room for.
    /// </summary>
    internal const int MostItems = 255;

    /// <summary>
    ///  The most rooms, as a location of <see cref="ScottFreeGame.Carried"/> is no room.
    /// </summary>
    internal const int MostRooms = 255;

    /// <summary>
    ///  The most messages the action codes reach: 1 to 51, then 52 to 99 as codes 102 to 149.
    /// </summary>
    internal const int MostMessages = 100;

    /// <summary>
    ///  The most words of each kind: the format's verb and noun numbers are below 150.
    /// </summary>
    internal const int MostWords = 150;

    /// <summary>
    ///  Packs a game.
    /// </summary>
    /// <param name="game">The game.</param>
    /// <returns>
    ///  The packed bytes, the size of each part, and warnings about what the game holds that can't be used.
    /// </returns>
    /// <exception cref="InvalidDataException">The game does not fit the format.</exception>
    internal static (byte[] Bytes, List<(string Part, int Size)> Sizes, List<string> Warnings) Pack(ScottFreeGame game)
    {
        Check(game);
        List<string> warnings = [];

        // Every string shares one dictionary.
        List<string> texts =
        [
            .. game.Rooms.Select(room => room.Description.StartsWith('*') ? room.Description[1..]
                : room.Description.Length == 0 ? "" : RoomPrefix + room.Description),
            .. game.Messages,
            .. game.Items.Select(item => Description(item.Description))
        ];

        (List<byte[]> dictionary, List<byte[]> strings) = TextCompressor.Compress(texts);
        List<byte[]> roomTexts = strings[..game.Rooms.Count];
        List<byte[]> messages = strings.Slice(game.Rooms.Count, game.Messages.Count);
        List<byte[]> itemTexts = strings[(game.Rooms.Count + game.Messages.Count)..];

        List<byte> output = [.. new byte[PackedHeader.Size]];
        List<(string Part, int Size)> sizes = [("header", PackedHeader.Size)];
        output[PackedHeader.Magic] = (byte)'S';
        output[PackedHeader.Magic + 1] = (byte)'A';
        output[PackedHeader.Version] = PackedHeader.CurrentVersion;
        output[PackedHeader.WordLength] = (byte)game.WordLength;
        output[PackedHeader.ItemCount] = (byte)game.Items.Count;
        output[PackedHeader.RoomCount] = (byte)game.Rooms.Count;
        output[PackedHeader.MessageCount] = (byte)game.Messages.Count;
        output[PackedHeader.WordCount] = (byte)game.Verbs.Count;
        output[PackedHeader.StartRoom] = (byte)game.StartRoom;
        output[PackedHeader.TreasureRoom] = (byte)game.TreasureRoom;
        output[PackedHeader.CarryLimit] = (byte)game.CarryLimit;
        output[PackedHeader.TreasureCount] = (byte)game.TreasureCount;
        output[PackedHeader.LightItem] = ScottFreeGame.LightItem;
        SetWord(PackedHeader.LightTime, game.LightTime < 0 ? PackedHeader.Endless : game.LightTime);
        SetWord(PackedHeader.ActionCount, game.Actions.Count);

        Part(PackedHeader.Dictionary, "dictionary", () =>
        {
            output.Add((byte)dictionary.Count);
            foreach (byte[] entry in dictionary)
            {
                output.Add((byte)entry.Length);
                output.AddRange(entry);
            }
        });

        Part(PackedHeader.Verbs, "verbs", () => Words(game.Verbs));
        Part(PackedHeader.Nouns, "nouns", () => Words(game.Nouns));
        Part(PackedHeader.Exits, "exits", () =>
        {
            foreach (GameRoom room in game.Rooms) { output.AddRange(room.Exits.Select(exit => (byte)exit)); }
        });

        Part(PackedHeader.RoomTexts, "room descriptions", () => Strings(roomTexts));
        Part(PackedHeader.Messages, "messages", () => Strings(messages));
        Part(PackedHeader.ItemLocations, "item locations", () => output.AddRange(game.Items.Select(item => (byte)item.Location)));
        Part(PackedHeader.ItemNouns, "item nouns", () => output.AddRange(game.Items.Select(item => (byte)ItemNoun(game, item, warnings))));
        Part(PackedHeader.Treasures, "treasures", () =>
        {
            byte[] bits = new byte[(game.Items.Count + 7) / 8];
            for (int item = 0; item < game.Items.Count; item++)
            {
                if (game.Items[item].Description.StartsWith('*')) { bits[item >> 3] |= (byte)(1 << (item & 7)); }
            }

            output.AddRange(bits);
        });

        Part(PackedHeader.ItemTexts, "item descriptions", () => Strings(itemTexts));
        Part(PackedHeader.Actions, "actions", () =>
        {
            foreach (GameAction action in game.Actions) { output.AddRange(Action(action)); }
        });

        sizes.Add(("total", output.Count));
        Require(output.Count <= 0xFFFF, $"The packed game is {output.Count} bytes; the format's offsets reach 65535.");
        return ([.. output], sizes, warnings);

        void SetWord(int offset, int value)
        {
            output[offset] = (byte)value;
            output[offset + 1] = (byte)(value >> 8);
        }

        void Part(int field, string name, Action write)
        {
            int start = output.Count;
            SetWord(field, start);
            write();
            sizes.Add((name, output.Count - start));
        }

        void Strings(List<byte[]> list)
        {
            foreach (byte[] text in list)
            {
                output.AddRange(text);
                output.Add(TextCompressor.End);
            }
        }

        void Words(List<string> words)
        {
            foreach (string word in words)
            {
                byte[] field = new byte[game.WordLength];
                string letters = Word(word, game.WordLength);
                Encoding.ASCII.GetBytes(letters, field);
                if (word.StartsWith('*')) { field[0] |= 0x80; }
                output.AddRange(field);
            }
        }
    }

    /// <summary>
    ///  A word as the interpreter compares it: in capitals, without its <c>*</c>, and cut to the word length.
    /// </summary>
    /// <param name="word">The word, as the game or the player gives it.</param>
    /// <param name="length">The game's word length.</param>
    /// <returns>The word's significant letters.</returns>
    internal static string Word(string word, int length)
    {
        string letters = word.TrimStart('*').ToUpperInvariant();
        return letters.Length > length ? letters[..length] : letters;
    }

    /// <summary>
    ///  An item's description without the word GET and DROP know it by.
    /// </summary>
    /// <param name="description">The description as the game gives it.</param>
    /// <returns>The description shown.</returns>
    internal static string Description(string description)
    {
        int slash = description.IndexOf('/');
        return slash >= 0 && description.EndsWith('/') && slash < description.Length - 1 ? description[..slash] : description;
    }

    // The noun an item's /WORD/ names, as the first of its synonyms, or 0 for an item GET and DROP don't take: one with
    // no word, or a word that is no noun, which can then never be typed as one.
    private static int ItemNoun(ScottFreeGame game, GameItem item, List<string> warnings)
    {
        int slash = item.Description.IndexOf('/');
        if (slash < 0 || !item.Description.EndsWith('/') || slash == item.Description.Length - 1) { return 0; }
        string word = Word(item.Description[(slash + 1)..^1], game.WordLength);
        int first = 0;
        for (int noun = 0; noun < game.Nouns.Count; noun++)
        {
            if (!game.Nouns[noun].StartsWith('*')) { first = noun; }
            if (noun > 0 && Word(game.Nouns[noun], game.WordLength) == word) { return first; }
        }

        warnings.Add($"The item \"{item.Description}\" is known by \"{word}\", which is not a noun, so GET and DROP can't take it.");
        return 0;
    }

    // An action: its verb, its noun, a byte with its condition count above its code count, then two bytes for each
    // condition (its type in the low five bits and its value's high three bits above them, then the value's low
    // byte), then a byte for each code. Trailing parameters of 0, the conditions no action uses, and codes of 0,
    // which do nothing, are left out.
    private static List<byte> Action(GameAction action)
    {
        List<GameCondition> conditions = [.. action.Conditions];
        while (conditions.Count > 0 && conditions[^1] is { Type: 0, Value: 0 })
        {
            conditions.RemoveAt(conditions.Count - 1);
        }

        List<int> codes = [.. action.Codes.Where(code => code != 0)];
        List<byte> bytes = [(byte)action.Verb, (byte)action.Noun, (byte)((conditions.Count << 4) | codes.Count)];
        foreach (GameCondition condition in conditions)
        {
            bytes.Add((byte)(condition.Type | ((condition.Value >> 8) << 5)));
            bytes.Add((byte)condition.Value);
        }

        bytes.AddRange(codes.Select(code => (byte)code));
        return bytes;
    }

    private static void Check(ScottFreeGame game)
    {
        Require(game.Items.Count is > ScottFreeGame.LightItem and <= MostItems, $"The game has {game.Items.Count} items; the format takes {ScottFreeGame.LightItem + 1} to {MostItems}.");
        Require(game.Rooms.Count is > 1 and <= MostRooms, $"The game has {game.Rooms.Count} rooms; the format takes 2 to {MostRooms}.");
        Require(game.Messages.Count <= MostMessages, $"The game has {game.Messages.Count} messages; the format takes {MostMessages}.");
        Require(game.Verbs.Count <= MostWords, $"The game has {game.Verbs.Count} words of each kind; the format takes {MostWords}.");
        Require(game.Verbs.Count > 18, "The game needs verbs up to DROP, verb 18.");
        Require(game.WordLength is >= 1 and <= 8, $"The word length is {game.WordLength}; the format takes 1 to 8.");
        Require(game.Actions.Count <= 0xFFFF, "The game has more than 65535 actions.");
        Require(game.LightTime is >= -1 and < PackedHeader.Endless, $"The light time {game.LightTime} is out of range.");
        Require(game.StartRoom >= 0 && game.StartRoom < game.Rooms.Count && game.TreasureRoom >= 0 && game.TreasureRoom < game.Rooms.Count, "The start or treasure room is not a room.");
        Require(game.CarryLimit is >= 0 and <= 255 && game.TreasureCount is >= 0 and <= 255, "The carry limit or treasure count is not 0 to 255.");
        foreach (string word in game.Verbs.Concat(game.Nouns))
        {
            Require(word.All(character => character is > ' ' and <= '~'), $"The word \"{word}\" holds a space or a character the format cannot store.");
        }

        foreach (GameRoom room in game.Rooms)
        {
            Require(room.Exits.All(exit => exit >= 0 && exit < game.Rooms.Count), $"An exit of \"{room.Description}\" is not a room.");
        }

        foreach (GameItem item in game.Items)
        {
            Require(item.Location < game.Rooms.Count || item.Location == ScottFreeGame.Carried, $"The item \"{item.Description}\" starts in no room.");
        }

        foreach (GameAction action in game.Actions)
        {
            Require(action.Verb >= 0 && action.Noun >= 0 && action.Verb < game.Verbs.Count && (action.Verb == 0 || action.Noun < game.Nouns.Count), $"An action's words are out of range: {action.Verb}, {action.Noun}.");
            foreach (GameCondition condition in action.Conditions)
            {
                Require(
                    condition.Type is >= 0 and < 20 && condition.Value is >= 0 and <= LargestValue,
                    $"A condition is out of range: type {condition.Type}, value {condition.Value}.");
            }

            foreach (int code in action.Codes)
            {
                Require(code is >= 0 and < MostWords, $"Action code {code} is out of range: codes run from 0 to 149.");
                int message = code is >= 1 and <= 51 ? code : code >= 102 ? code - 50 : 0;
                Require(message < game.Messages.Count, $"Action code {code} prints message {message}, which the game lacks.");
            }
        }
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) { throw new InvalidDataException(message); }
    }
}
