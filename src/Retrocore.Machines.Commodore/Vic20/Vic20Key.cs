// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Commodore.Vic20;

/// <summary>
///  The VIC-20's keys by their place in the 8 × 8 matrix: the value is the column (VIA 2's port B bit) times 8 plus
///  the row (port A bit), the order of the kernal's key tables at <c>$EC5E</c>. RESTORE is not in the matrix.
/// </summary>
public enum Vic20Key
{
    /// <summary>
    ///  The 1 and ! key.
    /// </summary>
    Digit1 = 0,

    /// <summary>
    ///  The 3 and # key.
    /// </summary>
    Digit3 = 1,

    /// <summary>
    ///  The 5 and % key.
    /// </summary>
    Digit5 = 2,

    /// <summary>
    ///  The 7 and ' key.
    /// </summary>
    Digit7 = 3,

    /// <summary>
    ///  The 9 and ) key.
    /// </summary>
    Digit9 = 4,

    /// <summary>
    ///  The + key.
    /// </summary>
    Plus = 5,

    /// <summary>
    ///  The £ key.
    /// </summary>
    Pound = 6,

    /// <summary>
    ///  The INST/DEL key.
    /// </summary>
    Delete = 7,

    /// <summary>
    ///  The ← key.
    /// </summary>
    LeftArrow = 8,

    /// <summary>
    ///  The W key.
    /// </summary>
    W = 9,

    /// <summary>
    ///  The R key.
    /// </summary>
    R = 10,

    /// <summary>
    ///  The Y key.
    /// </summary>
    Y = 11,

    /// <summary>
    ///  The I key.
    /// </summary>
    I = 12,

    /// <summary>
    ///  The P key.
    /// </summary>
    P = 13,

    /// <summary>
    ///  The * key.
    /// </summary>
    Asterisk = 14,

    /// <summary>
    ///  The RETURN key.
    /// </summary>
    Return = 15,

    /// <summary>
    ///  The CTRL key.
    /// </summary>
    Control = 16,

    /// <summary>
    ///  The A key.
    /// </summary>
    A = 17,

    /// <summary>
    ///  The D key.
    /// </summary>
    D = 18,

    /// <summary>
    ///  The G key.
    /// </summary>
    G = 19,

    /// <summary>
    ///  The J key.
    /// </summary>
    J = 20,

    /// <summary>
    ///  The L key.
    /// </summary>
    L = 21,

    /// <summary>
    ///  The ; and ] key.
    /// </summary>
    Semicolon = 22,

    /// <summary>
    ///  The CRSR ⇔ key: right, and left with SHIFT.
    /// </summary>
    CursorRight = 23,

    /// <summary>
    ///  The RUN/STOP key.
    /// </summary>
    Stop = 24,

    /// <summary>
    ///  The left SHIFT key, which SHIFT LOCK holds down.
    /// </summary>
    LeftShift = 25,

    /// <summary>
    ///  The X key.
    /// </summary>
    X = 26,

    /// <summary>
    ///  The V key.
    /// </summary>
    V = 27,

    /// <summary>
    ///  The N key.
    /// </summary>
    N = 28,

    /// <summary>
    ///  The , and &lt; key.
    /// </summary>
    Comma = 29,

    /// <summary>
    ///  The / and ? key.
    /// </summary>
    Slash = 30,

    /// <summary>
    ///  The CRSR ⇕ key: down, and up with SHIFT.
    /// </summary>
    CursorDown = 31,

    /// <summary>
    ///  The SPACE key.
    /// </summary>
    Space = 32,

    /// <summary>
    ///  The Z key.
    /// </summary>
    Z = 33,

    /// <summary>
    ///  The C key.
    /// </summary>
    C = 34,

    /// <summary>
    ///  The B key.
    /// </summary>
    B = 35,

    /// <summary>
    ///  The M key.
    /// </summary>
    M = 36,

    /// <summary>
    ///  The . and &gt; key.
    /// </summary>
    Period = 37,

    /// <summary>
    ///  The right SHIFT key.
    /// </summary>
    RightShift = 38,

    /// <summary>
    ///  The f1 key, and f2 with SHIFT.
    /// </summary>
    F1 = 39,

    /// <summary>
    ///  The Commodore key.
    /// </summary>
    Commodore = 40,

    /// <summary>
    ///  The S key.
    /// </summary>
    S = 41,

    /// <summary>
    ///  The F key.
    /// </summary>
    F = 42,

    /// <summary>
    ///  The H key.
    /// </summary>
    H = 43,

    /// <summary>
    ///  The K key.
    /// </summary>
    K = 44,

    /// <summary>
    ///  The : and [ key.
    /// </summary>
    Colon = 45,

    /// <summary>
    ///  The = key.
    /// </summary>
    Equals = 46,

    /// <summary>
    ///  The f3 key, and f4 with SHIFT.
    /// </summary>
    F3 = 47,

    /// <summary>
    ///  The Q key.
    /// </summary>
    Q = 48,

    /// <summary>
    ///  The E key.
    /// </summary>
    E = 49,

    /// <summary>
    ///  The T key.
    /// </summary>
    T = 50,

    /// <summary>
    ///  The U key.
    /// </summary>
    U = 51,

    /// <summary>
    ///  The O key.
    /// </summary>
    O = 52,

    /// <summary>
    ///  The @ key.
    /// </summary>
    At = 53,

    /// <summary>
    ///  The ↑ key.
    /// </summary>
    UpArrow = 54,

    /// <summary>
    ///  The f5 key, and f6 with SHIFT.
    /// </summary>
    F5 = 55,

    /// <summary>
    ///  The 2 and " key.
    /// </summary>
    Digit2 = 56,

    /// <summary>
    ///  The 4 and $ key.
    /// </summary>
    Digit4 = 57,

    /// <summary>
    ///  The 6 and &amp; key.
    /// </summary>
    Digit6 = 58,

    /// <summary>
    ///  The 8 and ( key.
    /// </summary>
    Digit8 = 59,

    /// <summary>
    ///  The 0 key.
    /// </summary>
    Digit0 = 60,

    /// <summary>
    ///  The - key.
    /// </summary>
    Minus = 61,

    /// <summary>
    ///  The CLR/HOME key.
    /// </summary>
    Home = 62,

    /// <summary>
    ///  The f7 key, and f8 with SHIFT.
    /// </summary>
    F7 = 63
}
