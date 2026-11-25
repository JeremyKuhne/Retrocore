// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Chips;

namespace Retrocore.Machines.Atari;

/// <summary>
///  The Atari 400 and 800's keyboard: 57 keys POKEY scans, SHIFT, CONTROL and BREAK on their own lines, the START,
///  SELECT and OPTION keys GTIA reads, and SYSTEM RESET, which goes to ANTIC.
/// </summary>
/// <remarks>
///  <para>
///   <see cref="Type"/> queues characters as ATASCII and presses each key long enough for the OS's keyboard
///   interrupt, then lets go. A lowercase letter presses CAPS/LOWR first when the OS is in capitals (<c>SHFLOK</c>,
///   <c>$02BE</c>, is <c>$40</c>), and an uppercase one presses SHIFT with CAPS/LOWR when it is in lowercase.
///  </para>
/// </remarks>
public sealed class AtariKeyboard
{
    private const int HoldFrames = 3;
    private const int GapFrames = 3;

    private static readonly Dictionary<char, (AtariKey Key, bool Shift, bool Control)> s_keys = BuildKeyMap();

    private readonly Pokey _pokey;
    private readonly Gtia _gtia;
    private readonly Antic _antic;
    private readonly Queue<char> _queue = new();
    private AtariKey? _held;
    private int _frames;

    /// <summary>
    ///  Constructs the keyboard.
    /// </summary>
    /// <param name="pokey">POKEY, which scans the keys.</param>
    /// <param name="gtia">GTIA, which reads the console keys.</param>
    /// <param name="antic">ANTIC, which takes SYSTEM RESET.</param>
    internal AtariKeyboard(Pokey pokey, Gtia gtia, Antic antic)
    {
        _pokey = pokey;
        _gtia = gtia;
        _antic = antic;
    }

    /// <summary>
    ///  Gets whether typed characters are still queued or held.
    /// </summary>
    public bool IsTyping => _queue.Count != 0 || _held is not null;

    /// <summary>
    ///  Gets or sets a function that reads the OS's <c>SHFLOK</c>, to know the CAPS/LOWR state when typing.
    /// </summary>
    internal Func<byte>? ShiftLock { get; set; }

    /// <summary>
    ///  Gets whether a character can be typed.
    /// </summary>
    /// <param name="character">The character, as ATASCII.</param>
    /// <returns>Whether a key makes it.</returns>
    public static bool CanType(char character) => s_keys.ContainsKey(char.ToUpperInvariant(character));

    /// <summary>
    ///  Queues a character to type.
    /// </summary>
    /// <param name="character">The character as ATASCII: <c>$9B</c> or a carriage return for RETURN.</param>
    /// <returns>Whether a key makes it.</returns>
    public bool Type(byte character)
    {
        char c = character is 0x0D or 0x0A ? (char)0x9B : (char)character;
        if (!CanType(c)) { return false; }
        _queue.Enqueue(c);
        return true;
    }

    /// <summary>
    ///  Presses a key on the matrix.
    /// </summary>
    /// <param name="key">The key.</param>
    public void Press(AtariKey key) => _pokey.SetKey((int)key, pressed: true);

    /// <summary>
    ///  Lets go of a key on the matrix.
    /// </summary>
    /// <param name="key">The key.</param>
    public void Release(AtariKey key) => _pokey.SetKey((int)key, pressed: false);

    /// <summary>
    ///  Gets or sets whether SHIFT is held.
    /// </summary>
    public bool Shift
    {
        get => _pokey.Shift;
        set => _pokey.Shift = value;
    }

    /// <summary>
    ///  Gets or sets whether CONTROL is held.
    /// </summary>
    public bool Control
    {
        get => _pokey.Control;
        set => _pokey.Control = value;
    }

    /// <summary>
    ///  Gets or sets whether BREAK is held.
    /// </summary>
    public bool Break
    {
        get => _pokey.Break;
        set => _pokey.Break = value;
    }

    /// <summary>
    ///  Gets or sets the console keys held: <see cref="AtariConsoleKeys"/>.
    /// </summary>
    public AtariConsoleKeys ConsoleKeys
    {
        get => (AtariConsoleKeys)_gtia.ConsoleKeys;
        set => _gtia.ConsoleKeys = (byte)value;
    }

    /// <summary>
    ///  Gets or sets whether SYSTEM RESET is held.
    /// </summary>
    public bool SystemReset
    {
        get => _antic.ResetKey;
        set => _antic.ResetKey = value;
    }

    /// <summary>
    ///  Steps typing once a frame.
    /// </summary>
    internal void Frame()
    {
        if (_frames > 0)
        {
            _frames--;
            return;
        }

        if (_held is AtariKey held)
        {
            Release(held);
            _pokey.Shift = false;
            _pokey.Control = false;
            _held = null;
            _frames = GapFrames;
            return;
        }

        if (!_queue.TryPeek(out char next)) { return; }

        // Letters follow CAPS/LOWR: switch it first when the case is wrong.
        if (char.IsAsciiLetter(next) && ShiftLock is not null)
        {
            bool capitals = ShiftLock() != 0;
            bool upper = char.IsAsciiLetterUpper(next);
            if (capitals != upper)
            {
                // CAPS/LOWR alone gives lowercase; SHIFT+CAPS/LOWR gives capitals.
                _pokey.Shift = upper;
                Press(AtariKey.Caps);
                _held = AtariKey.Caps;
                _frames = HoldFrames;
                return;
            }
        }

        _queue.Dequeue();
        (AtariKey key, bool shift, bool control) = s_keys[char.ToUpperInvariant(next)];
        _pokey.Shift = shift;
        _pokey.Control = control;
        Press(key);
        _held = key;
        _frames = HoldFrames;
    }

    private static Dictionary<char, (AtariKey, bool, bool)> BuildKeyMap()
    {
        Dictionary<char, (AtariKey, bool, bool)> map = [];
        for (char letter = 'A'; letter <= 'Z'; letter++)
        {
            map[letter] = (Enum.Parse<AtariKey>(letter.ToString()), false, false);
        }

        (char Character, AtariKey Key, bool Shift, bool Control)[] keys =
        [
            ('0', AtariKey.D0, false, false), ('1', AtariKey.D1, false, false), ('2', AtariKey.D2, false, false),
            ('3', AtariKey.D3, false, false), ('4', AtariKey.D4, false, false), ('5', AtariKey.D5, false, false),
            ('6', AtariKey.D6, false, false), ('7', AtariKey.D7, false, false), ('8', AtariKey.D8, false, false),
            ('9', AtariKey.D9, false, false),
            ('!', AtariKey.D1, true, false), ('"', AtariKey.D2, true, false), ('#', AtariKey.D3, true, false),
            ('$', AtariKey.D4, true, false), ('%', AtariKey.D5, true, false), ('&', AtariKey.D6, true, false),
            ('\'', AtariKey.D7, true, false), ('@', AtariKey.D8, true, false), ('(', AtariKey.D9, true, false),
            (')', AtariKey.D0, true, false),
            (' ', AtariKey.Space, false, false), ((char)0x9B, AtariKey.Return, false, false),
            (',', AtariKey.Comma, false, false), ('[', AtariKey.Comma, true, false),
            ('.', AtariKey.Period, false, false), (']', AtariKey.Period, true, false),
            (';', AtariKey.Semicolon, false, false), (':', AtariKey.Semicolon, true, false),
            ('/', AtariKey.Slash, false, false), ('?', AtariKey.Slash, true, false),
            ('+', AtariKey.Plus, false, false), ('\\', AtariKey.Plus, true, false),
            ('*', AtariKey.Asterisk, false, false), ('^', AtariKey.Asterisk, true, false),
            ('-', AtariKey.Minus, false, false), ('_', AtariKey.Minus, true, false),
            ('=', AtariKey.Equals, false, false), ('|', AtariKey.Equals, true, false),
            ('<', AtariKey.Less, false, false), ('>', AtariKey.Greater, false, false),
            ((char)0x1B, AtariKey.Escape, false, false), ((char)0x7F, AtariKey.Tab, false, false),
            ((char)0x7E, AtariKey.Backspace, false, false), ((char)0x7D, AtariKey.Less, true, false),
            ((char)0x1C, AtariKey.Minus, false, true), ((char)0x1D, AtariKey.Equals, false, true),
            ((char)0x1E, AtariKey.Plus, false, true), ((char)0x1F, AtariKey.Asterisk, false, true),
        ];

        foreach ((char character, AtariKey key, bool shift, bool control) in keys)
        {
            map[character] = (key, shift, control);
        }

        return map;
    }
}
