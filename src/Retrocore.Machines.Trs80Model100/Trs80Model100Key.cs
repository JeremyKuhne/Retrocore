// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80Model100;

/// <summary>
///  A key of the Model 100's keyboard, numbered by its place in the matrix: the column times 8, plus the row.
/// </summary>
/// <remarks>
///  <para>
///   Columns 0-7 are strobed by the 81C55's port A bits 0-7 and column 8 by port B bit 0; a key pressed pulls its
///   row's bit low in a read of ports $E0-$EF while its column is strobed low. The layout is MAME's <c>kc85</c> matrix,
///   which agrees with Covington's <i>System Map</i> but for the arrows: there, column 5's rows 4-7 are down, up,
///   left and right. The ROM bears MAME out: <c>INKEY$</c> gives 29, 28, 30 and 31, left, right, up and down, for
///   rows 4-7.
///  </para>
/// </remarks>
public enum Trs80Model100Key
{
    /// <summary>
    ///  The Z key.
    /// </summary>
    Z = 0,

    /// <summary>
    ///  The X key.
    /// </summary>
    X = 1,

    /// <summary>
    ///  The C key.
    /// </summary>
    C = 2,

    /// <summary>
    ///  The V key.
    /// </summary>
    V = 3,

    /// <summary>
    ///  The B key.
    /// </summary>
    B = 4,

    /// <summary>
    ///  The N key.
    /// </summary>
    N = 5,

    /// <summary>
    ///  The M key.
    /// </summary>
    M = 6,

    /// <summary>
    ///  The L key.
    /// </summary>
    L = 7,

    /// <summary>
    ///  The A key.
    /// </summary>
    A = 8,

    /// <summary>
    ///  The S key.
    /// </summary>
    S = 9,

    /// <summary>
    ///  The D key.
    /// </summary>
    D = 10,

    /// <summary>
    ///  The F key.
    /// </summary>
    F = 11,

    /// <summary>
    ///  The G key.
    /// </summary>
    G = 12,

    /// <summary>
    ///  The H key.
    /// </summary>
    H = 13,

    /// <summary>
    ///  The J key.
    /// </summary>
    J = 14,

    /// <summary>
    ///  The K key.
    /// </summary>
    K = 15,

    /// <summary>
    ///  The Q key.
    /// </summary>
    Q = 16,

    /// <summary>
    ///  The W key.
    /// </summary>
    W = 17,

    /// <summary>
    ///  The E key.
    /// </summary>
    E = 18,

    /// <summary>
    ///  The R key.
    /// </summary>
    R = 19,

    /// <summary>
    ///  The T key.
    /// </summary>
    T = 20,

    /// <summary>
    ///  The Y key.
    /// </summary>
    Y = 21,

    /// <summary>
    ///  The U key.
    /// </summary>
    U = 22,

    /// <summary>
    ///  The I key.
    /// </summary>
    I = 23,

    /// <summary>
    ///  The O key.
    /// </summary>
    O = 24,

    /// <summary>
    ///  The P key.
    /// </summary>
    P = 25,

    /// <summary>
    ///  [ and ].
    /// </summary>
    Brackets = 26,

    /// <summary>
    ///  ; and :.
    /// </summary>
    Semicolon = 27,

    /// <summary>
    ///  ' and ".
    /// </summary>
    Quote = 28,

    /// <summary>
    ///  , and &lt;.
    /// </summary>
    Comma = 29,

    /// <summary>
    ///  . and &gt;.
    /// </summary>
    Period = 30,

    /// <summary>
    ///  / and ?.
    /// </summary>
    Slash = 31,

    /// <summary>
    ///  The 1 key.
    /// </summary>
    D1 = 32,

    /// <summary>
    ///  The 2 key.
    /// </summary>
    D2 = 33,

    /// <summary>
    ///  The 3 key.
    /// </summary>
    D3 = 34,

    /// <summary>
    ///  The 4 key.
    /// </summary>
    D4 = 35,

    /// <summary>
    ///  The 5 key.
    /// </summary>
    D5 = 36,

    /// <summary>
    ///  The 6 key.
    /// </summary>
    D6 = 37,

    /// <summary>
    ///  The 7 key.
    /// </summary>
    D7 = 38,

    /// <summary>
    ///  The 8 key.
    /// </summary>
    D8 = 39,

    /// <summary>
    ///  The 9 key.
    /// </summary>
    D9 = 40,

    /// <summary>
    ///  The 0 key.
    /// </summary>
    D0 = 41,

    /// <summary>
    ///  - and _.
    /// </summary>
    Minus = 42,

    /// <summary>
    ///  = and +.
    /// </summary>
    Equals = 43,

    /// <summary>
    ///  Left arrow.
    /// </summary>
    Left = 44,

    /// <summary>
    ///  Right arrow.
    /// </summary>
    Right = 45,

    /// <summary>
    ///  Up arrow.
    /// </summary>
    Up = 46,

    /// <summary>
    ///  Down arrow.
    /// </summary>
    Down = 47,

    /// <summary>
    ///  The space bar.
    /// </summary>
    Space = 48,

    /// <summary>
    ///  DEL/BKSP.
    /// </summary>
    Delete = 49,

    /// <summary>
    ///  TAB.
    /// </summary>
    Tab = 50,

    /// <summary>
    ///  ESC.
    /// </summary>
    Escape = 51,

    /// <summary>
    ///  PASTE.
    /// </summary>
    Paste = 52,

    /// <summary>
    ///  LABEL.
    /// </summary>
    Label = 53,

    /// <summary>
    ///  PRINT.
    /// </summary>
    Print = 54,

    /// <summary>
    ///  ENTER.
    /// </summary>
    Enter = 55,

    /// <summary>
    ///  F1.
    /// </summary>
    F1 = 56,

    /// <summary>
    ///  F2.
    /// </summary>
    F2 = 57,

    /// <summary>
    ///  F3.
    /// </summary>
    F3 = 58,

    /// <summary>
    ///  F4.
    /// </summary>
    F4 = 59,

    /// <summary>
    ///  F5.
    /// </summary>
    F5 = 60,

    /// <summary>
    ///  F6.
    /// </summary>
    F6 = 61,

    /// <summary>
    ///  F7.
    /// </summary>
    F7 = 62,

    /// <summary>
    ///  F8.
    /// </summary>
    F8 = 63,

    /// <summary>
    ///  SHIFT.
    /// </summary>
    Shift = 64,

    /// <summary>
    ///  CTRL.
    /// </summary>
    Control = 65,

    /// <summary>
    ///  GRPH.
    /// </summary>
    Graph = 66,

    /// <summary>
    ///  CODE.
    /// </summary>
    Code = 67,

    /// <summary>
    ///  NUM.
    /// </summary>
    Num = 68,

    /// <summary>
    ///  CAPS LOCK, which locks down.
    /// </summary>
    CapsLock = 69,

    /// <summary>
    ///  PAUSE/BREAK.
    /// </summary>
    Break = 71
}
