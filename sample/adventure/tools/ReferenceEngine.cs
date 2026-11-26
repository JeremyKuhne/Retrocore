// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text;

/// <summary>
///  Plays a packed game from a list of commands, following the rules <c>PackedFormat.md</c> gives, so a transcript
///  of the 6502 engine can be checked against it character for character.
/// </summary>
/// <param name="game">The packed game.</param>
/// <param name="columns">The screen's width; the text wraps a column short of it, as the 6502 engine's does.</param>
internal sealed class ReferenceEngine(byte[] game, int columns)
{
    /// <summary>
    ///  What the engine prints when it waits for a command.
    /// </summary>
    internal const string Prompt = "> ";

    /// <summary>
    ///  What the engine prints when the game ends.
    /// </summary>
    internal const string GameOver = "The game is now over.";

    // The interpreter's other text, the same as the 6502 engine's.
    private const string TooDark = "It's too dark to see.";
    private const string ExitsHeading = "Obvious exits: ";
    private const string NoExits = "none";
    private const string ItemsHeading = "I can also see: ";
    private const string UnknownWord = "I don't know that word.";
    private const string NeedDirection = "Give me a direction too.";
    private const string NoWay = "I can't go that way.";
    private const string DangerousDark = "It's dangerous to move in the dark!";
    private const string BrokeNeck = "I fell and broke my neck.";
    private const string Done = "OK";
    private const string TooMuch = "I can't carry any more.";
    private const string NotHere = "I don't see it here.";
    private const string NotCarried = "I'm not carrying it.";
    private const string What = "What?";
    private const string NotYet = "I can't do that yet.";
    private const string NotUnderstood = "I don't understand.";
    private const string Dead = "I'm dead!";
    private const string LightOut = "My light has run out!";
    private const string LightDim = "My light is growing dim.";
    private const string CarryingHeading = "I'm carrying: ";
    private const string CarryingNothing = "I'm carrying nothing.";
    private const string StoredStart = "I've stored ";
    private const string StoredMiddle = " treasures. On a scale of 0 to 100, that rates ";
    private const string WellDone = "Well done!";
    private const string NoSaving = "I can't save the game yet.";
    private static readonly string[] s_directions = ["North", "South", "East", "West", "Up", "Down"];

    // The format's fixed numbers.
    private const int Carried = 255;
    private const int VerbGo = 1;
    private const int VerbGet = 10;
    private const int VerbDrop = 18;
    private const int DarkFlag = 15;
    private const int LightOutFlag = 16;
    private const int DimWarnings = 25;
    private const int SeedState = 0xACE1;
    private const int Taps = 0xB400;

    private readonly WrappedOutput _output = new(columns);
    private readonly byte[] _locations = new byte[256];
    private uint _flags;
    private short _counter;
    private readonly short[] _counters = new short[16];
    private readonly byte[] _savedRooms = new byte[16];
    private byte _savedRoom;
    private int _room;
    private int _lightTime;
    private int _random = SeedState;
    private bool _lookPending;
    private bool _over;
    private bool _continuing;
    private string _nounText = "";

    /// <summary>
    ///  Plays the game until it ends or the commands run out.
    /// </summary>
    /// <param name="commands">The commands, one a line.</param>
    /// <param name="echo">Whether each command is shown after its prompt, as the screen shows it.</param>
    /// <returns>
    ///  The characters the engine sent to the screen, and the commands when <paramref name="echo"/> is set.
    /// </returns>
    internal string Play(IEnumerable<string> commands, bool echo)
    {
        Start();
        using IEnumerator<string> lines = commands.GetEnumerator();
        while (true)
        {
            Occurrences();
            if (_lookPending) { Look(); }
            if (_over) { break; }
            (int Verb, int Noun)? command;
            do
            {
                _output.EndLine();
                _output.Write(Prompt);
                _output.Flush();
                if (!lines.MoveNext()) { return _output.Sent.ToString(); }
                if (echo) { _output.Sent.Append(lines.Current).Append('\n'); }
                _output.AtLineStart();
                command = Parse(lines.Current.ToUpperInvariant());
            }
            while (command is null);

            Command(command.Value.Verb, command.Value.Noun);
            if (_over)
            {
                if (_lookPending) { Look(); }
                break;
            }

            LightTimer();
        }

        Line(GameOver);
        _output.Flush();
        return _output.Sent.ToString();
    }

    private void Start()
    {
        int items = game[PackedHeader.ItemCount];
        game.AsSpan(Table(PackedHeader.ItemLocations), items).CopyTo(_locations);
        _room = game[PackedHeader.StartRoom];
        _lightTime = Word(PackedHeader.LightTime);
        _lookPending = true;
    }

    private int Word(int offset) => game[offset] | (game[offset + 1] << 8);

    private int Table(int field) => Word(field);

    private int LightItem => game[PackedHeader.LightItem];

    private bool Flag(int flag) => (_flags & (1u << (flag & 31))) != 0;

    private void SetFlag(int flag) => _flags |= 1u << (flag & 31);

    private void ClearFlag(int flag) => _flags &= ~(1u << (flag & 31));

    private bool Here(int item) => _locations[item] == Carried || _locations[item] == _room;

    private bool IsDark => Flag(DarkFlag) && !Here(LightItem);

    private int CarriedCount => _locations.AsSpan(0, game[PackedHeader.ItemCount]).Count((byte)Carried);

    // Text.

    private void Line(string text)
    {
        _output.Write(text);
        _output.Write('\n');
    }

    // The bytes of the index'th string of a table of strings each ending in 0.
    private ReadOnlySpan<byte> String(int field, int index)
    {
        int position = Table(field);
        for (; index > 0; index--)
        {
            position = Array.IndexOf(game, TextCompressor.End, position) + 1;
        }

        return game.AsSpan(position, Array.IndexOf(game, TextCompressor.End, position) - position);
    }

    private void PrintString(int field, int index)
    {
        int dictionary = Table(PackedHeader.Dictionary);
        foreach (byte value in String(field, index))
        {
            if (value < TextCompressor.FirstToken)
            {
                _output.Write((char)value);
                continue;
            }

            int entry = dictionary + 1;
            for (int skip = value - TextCompressor.FirstToken; skip > 0; skip--)
            {
                entry += game[entry] + 1;
            }

            _output.Write(Encoding.ASCII.GetString(game, entry + 1, game[entry]));
        }
    }

    private void Message(int message)
    {
        PrintString(PackedHeader.Messages, message);
        _output.Write('\n');
    }

    private void Number(int value) => _output.Write(value.ToString(CultureInfo.InvariantCulture));

    // The world.

    private void Look()
    {
        _lookPending = false;
        if (IsDark)
        {
            Line(TooDark);
            return;
        }

        PrintString(PackedHeader.RoomTexts, _room);
        _output.Write('\n');
        _output.Write(ExitsHeading);
        bool any = false;
        for (int direction = 0; direction < 6; direction++)
        {
            if (game[Table(PackedHeader.Exits) + _room * 6 + direction] == 0) { continue; }
            if (any) { _output.Write(", "); }
            _output.Write(s_directions[direction]);
            any = true;
        }

        if (!any) { _output.Write(NoExits); }
        Line(".");
        ItemList(ItemsHeading, _room, none: null);
    }

    // Lists the items at a location after a heading, or writes the line for none.
    private void ItemList(string heading, int location, string? none)
    {
        bool any = false;
        for (int item = 0; item < game[PackedHeader.ItemCount]; item++)
        {
            if (_locations[item] != location) { continue; }
            _output.Write(any ? ", " : heading);
            PrintString(PackedHeader.ItemTexts, item);
            any = true;
        }

        if (any) { Line("."); }
        else if (none is not null) { Line(none); }
    }

    private void Move(int direction)
    {
        bool dark = IsDark;
        if (dark) { Line(DangerousDark); }
        int destination = game[Table(PackedHeader.Exits) + _room * 6 + direction - 1];
        if (destination != 0)
        {
            _room = destination;
            _lookPending = true;
        }
        else if (dark)
        {
            Line(BrokeNeck);
            _over = true;
        }
        else
        {
            Line(NoWay);
        }
    }

    private void Get(int noun)
    {
        if (_nounText.Length == 0) { Line(What); return; }
        if (IsDark) { Line(TooDark); return; }
        int item = FindItem(noun, _room);
        if (item < 0) { Line(NotHere); return; }
        if (CarriedCount >= game[PackedHeader.CarryLimit]) { Line(TooMuch); return; }
        _locations[item] = Carried;
        Line(Done);
    }

    private void Drop(int noun)
    {
        if (_nounText.Length == 0) { Line(What); return; }
        int item = FindItem(noun, Carried);
        if (item < 0) { Line(NotCarried); return; }
        _locations[item] = (byte)_room;
        Line(Done);
    }

    // The first item at a location that GET and DROP know by the noun, or -1; noun 0, a word the game doesn't know,
    // names none.
    private int FindItem(int noun, int location)
    {
        if (noun == 0) { return -1; }
        int nouns = Table(PackedHeader.ItemNouns);
        for (int item = 0; item < game[PackedHeader.ItemCount]; item++)
        {
            if (game[nouns + item] == noun && _locations[item] == location) { return item; }
        }

        return -1;
    }

    private void LightTimer()
    {
        if (_locations[LightItem] == 0 || _lightTime is PackedHeader.Endless or 0) { return; }
        _lightTime--;
        if (_lightTime == 0)
        {
            SetFlag(LightOutFlag);
            if (Here(LightItem)) { Line(LightOut); }
        }
        else if (_lightTime < DimWarnings && _lightTime % 5 == 0 && Here(LightItem))
        {
            Line(LightDim);
        }
    }

    // Parsing.

    // The verb and noun of a line, or null when the line has no command or a verb the game doesn't know. A second
    // word that is no noun is noun 0, as actions with noun 0 answer any.
    private (int Verb, int Noun)? Parse(string line)
    {
        string[] words = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (words.Length == 0) { return null; }
        string first = words[0];
        string? second = words.Length > 1 ? words[1] : null;
        _nounText = second ?? "";
        if (second is null)
        {
            int letter = "NSEWUD".IndexOf(first, StringComparison.Ordinal);
            if (first.Length == 1 && letter >= 0) { return (VerbGo, letter + 1); }
            if (first == "I") { first = "INVENTORY"; }
        }

        int verb = Lookup(PackedHeader.Verbs, first);
        if (verb < 0 && second is null && Lookup(PackedHeader.Nouns, first) is >= 1 and <= 6 and int direction)
        {
            return (VerbGo, direction);
        }

        int noun = second is null ? 0 : Math.Max(0, Lookup(PackedHeader.Nouns, second));
        if (verb < 0)
        {
            Line(UnknownWord);
            return null;
        }

        return (verb, noun);
    }

    // A word's number in a list, as the first of its synonyms, or -1; word 0 is never matched.
    private int Lookup(int field, string word)
    {
        int length = game[PackedHeader.WordLength];
        string letters = word.Length > length ? word[..length] : word;
        int list = Table(field);
        int first = 0;
        for (int index = 0; index < game[PackedHeader.WordCount]; index++)
        {
            ReadOnlySpan<byte> entry = game.AsSpan(list + index * length, length);
            if (entry[0] < 0x80) { first = index; }
            if (index == 0) { continue; }
            if (Matches(entry, letters)) { return first; }
        }

        return -1;
    }

    // Whether a word list's entry, its first byte's top bit cleared and padded with 0, holds the letters.
    private static bool Matches(ReadOnlySpan<byte> entry, string letters)
    {
        for (int index = 0; index < entry.Length; index++)
        {
            int expected = index < letters.Length ? letters[index] : 0;
            if ((entry[index] & 0x7F) != expected) { return false; }
        }

        return true;
    }

    // Actions.

    private void Occurrences()
    {
        _continuing = false;
        foreach ((int verb, int noun, int start) in Actions())
        {
            if (verb == 0 && noun == 0)
            {
                if (_continuing) { TryPerform(start); }
            }
            else
            {
                _continuing = false;
                if (verb == 0 && Chance(noun)) { TryPerform(start); }
            }

            if (_over) { return; }
        }
    }

    private void Command(int verb, int noun)
    {
        if (verb == VerbGo && noun is >= 1 and <= 6)
        {
            Move(noun);
            return;
        }

        bool matched = false;
        bool performed = false;
        _continuing = false;
        foreach ((int entryVerb, int entryNoun, int start) in Actions())
        {
            if (entryVerb == 0 && entryNoun == 0)
            {
                if (_continuing) { TryPerform(start); }
                if (_over) { return; }
                continue;
            }

            if (performed) { return; }
            if (entryVerb != verb || (entryNoun != noun && entryNoun != 0)) { continue; }
            matched = true;
            performed = TryPerform(start);
            if (_over) { return; }
        }

        if (performed) { return; }
        if (verb == VerbGet) { Get(noun); }
        else if (verb == VerbDrop) { Drop(noun); }
        else if (matched) { Line(NotYet); }
        else if (verb == VerbGo) { Line(noun == 0 ? NeedDirection : NoWay); }
        else { Line(NotUnderstood); }
    }

    // Each action's verb, noun and offset.
    private IEnumerable<(int Verb, int Noun, int Start)> Actions()
    {
        int position = Table(PackedHeader.Actions);
        for (int index = 0; index < Word(PackedHeader.ActionCount); index++)
        {
            yield return (game[position], game[position + 1], position);
            int counts = game[position + 2];
            position += 3 + 2 * (counts >> 4) + (counts & 15);
        }
    }

    private bool Chance(int percent)
    {
        if (percent >= 100) { return true; }
        for (int bit = 0; bit < 8; bit++)
        {
            bool low = (_random & 1) != 0;
            _random >>= 1;
            if (low) { _random ^= Taps; }
        }

        return ((_random & 0xFF) * 100) >> 8 < percent;
    }

    // Performs the action at an offset if its conditions hold.
    private bool TryPerform(int start)
    {
        int counts = game[start + 2];
        int conditions = counts >> 4;
        List<int> parameters = [];
        for (int index = 0; index < conditions; index++)
        {
            int type = game[start + 3 + 2 * index] & 31;
            int value = ((game[start + 3 + 2 * index] >> 5) << 8) | game[start + 4 + 2 * index];
            if (type == 0) { parameters.Add(value); }
            else if (!Holds(type, value)) { return false; }
        }

        int next = 0;
        int Parameter() => next < parameters.Count ? parameters[next++] : 0;
        for (int index = 0; index < (counts & 15); index++)
        {
            Perform(game[start + 3 + 2 * conditions + index], Parameter);
            if (_over) { break; }
        }

        return true;
    }

    private bool Holds(int type, int value)
    {
        int location = _locations[value & 0xFF];
        return type switch
        {
            1 => location == Carried,
            2 => location == _room,
            3 => location == Carried || location == _room,
            4 => _room == value,
            5 => location != _room,
            6 => location != Carried,
            7 => _room != value,
            8 => Flag(value),
            9 => !Flag(value),
            10 => CarriedCount != 0,
            11 => CarriedCount == 0,
            12 => location != Carried && location != _room,
            13 => location != 0,
            14 => location == 0,
            15 => _counter <= value,
            16 => _counter > value,
            17 => location == Original(value),
            18 => location != Original(value),
            19 => _counter == value,
            _ => true
        };
    }

    private int Original(int item) => item < game[PackedHeader.ItemCount] ? game[Table(PackedHeader.ItemLocations) + item] : 0;

    private void Perform(int code, Func<int> parameter)
    {
        switch (code)
        {
            case >= 1 and <= 51: Message(code); break;
            case >= 102 and <= 149: Message(code - 50); break;
            case 52:
                int item = parameter();
                if (CarriedCount >= game[PackedHeader.CarryLimit]) { Line(TooMuch); }
                else { _locations[item & 0xFF] = Carried; }
                break;
            case 53: _locations[parameter() & 0xFF] = (byte)_room; break;
            case 54: _room = parameter() & 0xFF; _lookPending = true; break;
            case 55 or 59: _locations[parameter() & 0xFF] = 0; break;
            case 56: SetFlag(DarkFlag); break;
            case 57: ClearFlag(DarkFlag); break;
            case 58: SetFlag(parameter()); break;
            case 60: ClearFlag(parameter()); break;
            case 61:
                Line(Dead);
                ClearFlag(DarkFlag);
                _room = game[PackedHeader.RoomCount] - 1;
                _lookPending = true;
                break;
            case 62:
                int moved = parameter();
                _locations[moved & 0xFF] = (byte)parameter();
                break;
            case 63: _over = true; break;
            case 64 or 76: Look(); break;
            case 65: Score(); break;
            case 66: ItemList(CarryingHeading, Carried, CarryingNothing); break;
            case 67: SetFlag(0); break;
            case 68: ClearFlag(0); break;
            case 69:
                _lightTime = Word(PackedHeader.LightTime);
                _locations[LightItem] = Carried;
                ClearFlag(LightOutFlag);
                break;
            case 70: _output.AtLineStart(); break;
            case 71: Line(NoSaving); break;
            case 72:
                int first = parameter() & 0xFF;
                int second = parameter() & 0xFF;
                (_locations[first], _locations[second]) = (_locations[second], _locations[first]);
                break;
            case 73: _continuing = true; break;
            case 74: _locations[parameter() & 0xFF] = Carried; break;
            case 75:
                int placed = parameter() & 0xFF;
                _locations[placed] = _locations[parameter() & 0xFF];
                break;
            case 77: if (_counter >= 0) { _counter--; } break;
            case 78: Number(_counter); break;
            case 79: _counter = (short)parameter(); break;
            case 80: (_room, _savedRoom) = (_savedRoom, (byte)_room); _lookPending = true; break;
            case 81:
                int slot = parameter() & 15;
                (_counter, _counters[slot]) = (_counters[slot], _counter);
                break;
            case 82: _counter = (short)(_counter + parameter()); break;
            case 83:
                _counter = (short)(_counter - parameter());
                if (_counter < -1) { _counter = -1; }
                break;
            case 84: _output.Write(_nounText); break;
            case 85: _output.Write(_nounText); _output.Write('\n'); break;
            case 86: _output.Write('\n'); break;
            case 87:
                int saved = parameter() & 15;
                (_room, _savedRooms[saved]) = (_savedRooms[saved], (byte)_room);
                _lookPending = true;
                break;
            default: break;
        }
    }

    private void Score()
    {
        int treasures = Table(PackedHeader.Treasures);
        int stored = 0;
        for (int item = 0; item < game[PackedHeader.ItemCount]; item++)
        {
            bool treasure = (game[treasures + (item >> 3)] & (1 << (item & 7))) != 0;
            if (treasure && _locations[item] == game[PackedHeader.TreasureRoom]) { stored++; }
        }

        int count = game[PackedHeader.TreasureCount];
        _output.Write(StoredStart);
        Number(stored);
        _output.Write(StoredMiddle);
        Number(count == 0 ? 0 : stored * 100 / count);
        Line(".");
        if (count != 0 && stored >= count)
        {
            Line(WellDone);
            _over = true;
        }
    }
}
