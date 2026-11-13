// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80;

/// <summary>
///  A Model I, III or 4 key, numbered by its place in the keyboard matrix: row times eight plus the data bit.
/// </summary>
public enum Trs80Key : byte
{
    /// <summary>
    ///  @ (row 0, bit 0).
    /// </summary>
    At = 0,

    /// <summary>
    ///  A (row 0, bit 1).
    /// </summary>
    A = 1,

    /// <summary>
    ///  B (row 0, bit 2).
    /// </summary>
    B = 2,

    /// <summary>
    ///  C (row 0, bit 3).
    /// </summary>
    C = 3,

    /// <summary>
    ///  D (row 0, bit 4).
    /// </summary>
    D = 4,

    /// <summary>
    ///  E (row 0, bit 5).
    /// </summary>
    E = 5,

    /// <summary>
    ///  F (row 0, bit 6).
    /// </summary>
    F = 6,

    /// <summary>
    ///  G (row 0, bit 7).
    /// </summary>
    G = 7,

    /// <summary>
    ///  H (row 1, bit 0).
    /// </summary>
    H = 8,

    /// <summary>
    ///  I (row 1, bit 1).
    /// </summary>
    I = 9,

    /// <summary>
    ///  J (row 1, bit 2).
    /// </summary>
    J = 10,

    /// <summary>
    ///  K (row 1, bit 3).
    /// </summary>
    K = 11,

    /// <summary>
    ///  L (row 1, bit 4).
    /// </summary>
    L = 12,

    /// <summary>
    ///  M (row 1, bit 5).
    /// </summary>
    M = 13,

    /// <summary>
    ///  N (row 1, bit 6).
    /// </summary>
    N = 14,

    /// <summary>
    ///  O (row 1, bit 7).
    /// </summary>
    O = 15,

    /// <summary>
    ///  P (row 2, bit 0).
    /// </summary>
    P = 16,

    /// <summary>
    ///  Q (row 2, bit 1).
    /// </summary>
    Q = 17,

    /// <summary>
    ///  R (row 2, bit 2).
    /// </summary>
    R = 18,

    /// <summary>
    ///  S (row 2, bit 3).
    /// </summary>
    S = 19,

    /// <summary>
    ///  T (row 2, bit 4).
    /// </summary>
    T = 20,

    /// <summary>
    ///  U (row 2, bit 5).
    /// </summary>
    U = 21,

    /// <summary>
    ///  V (row 2, bit 6).
    /// </summary>
    V = 22,

    /// <summary>
    ///  W (row 2, bit 7).
    /// </summary>
    W = 23,

    /// <summary>
    ///  X (row 3, bit 0).
    /// </summary>
    X = 24,

    /// <summary>
    ///  Y (row 3, bit 1).
    /// </summary>
    Y = 25,

    /// <summary>
    ///  Z (row 3, bit 2).
    /// </summary>
    Z = 26,

    /// <summary>
    ///  0 (row 4, bit 0).
    /// </summary>
    D0 = 32,

    /// <summary>
    ///  1 (row 4, bit 1).
    /// </summary>
    D1 = 33,

    /// <summary>
    ///  2 (row 4, bit 2).
    /// </summary>
    D2 = 34,

    /// <summary>
    ///  3 (row 4, bit 3).
    /// </summary>
    D3 = 35,

    /// <summary>
    ///  4 (row 4, bit 4).
    /// </summary>
    D4 = 36,

    /// <summary>
    ///  5 (row 4, bit 5).
    /// </summary>
    D5 = 37,

    /// <summary>
    ///  6 (row 4, bit 6).
    /// </summary>
    D6 = 38,

    /// <summary>
    ///  7 (row 4, bit 7).
    /// </summary>
    D7 = 39,

    /// <summary>
    ///  8 (row 5, bit 0).
    /// </summary>
    D8 = 40,

    /// <summary>
    ///  9 (row 5, bit 1).
    /// </summary>
    D9 = 41,

    /// <summary>
    ///  : and * (row 5, bit 2).
    /// </summary>
    Colon = 42,

    /// <summary>
    ///  ; and + (row 5, bit 3).
    /// </summary>
    Semicolon = 43,

    /// <summary>
    ///  , and &lt; (row 5, bit 4).
    /// </summary>
    Comma = 44,

    /// <summary>
    ///  - and = (row 5, bit 5).
    /// </summary>
    Minus = 45,

    /// <summary>
    ///  . and &gt; (row 5, bit 6).
    /// </summary>
    Period = 46,

    /// <summary>
    ///  / and ? (row 5, bit 7).
    /// </summary>
    Slash = 47,

    /// <summary>
    ///  ENTER (row 6, bit 0).
    /// </summary>
    Enter = 48,

    /// <summary>
    ///  CLEAR (row 6, bit 1).
    /// </summary>
    Clear = 49,

    /// <summary>
    ///  BREAK (row 6, bit 2).
    /// </summary>
    Break = 50,

    /// <summary>
    ///  the up arrow (row 6, bit 3).
    /// </summary>
    Up = 51,

    /// <summary>
    ///  the down arrow (row 6, bit 4).
    /// </summary>
    Down = 52,

    /// <summary>
    ///  the left arrow (row 6, bit 5).
    /// </summary>
    Left = 53,

    /// <summary>
    ///  the right arrow (row 6, bit 6).
    /// </summary>
    Right = 54,

    /// <summary>
    ///  the space bar (row 6, bit 7).
    /// </summary>
    Space = 55,

    /// <summary>
    ///  either SHIFT (row 7, bit 0); on a Model III or 4, the left SHIFT.
    /// </summary>
    Shift = 56,

    /// <summary>
    ///  the right SHIFT of a Model III or 4 (row 7, bit 1).
    /// </summary>
    RightShift = 57,

    /// <summary>
    ///  CTRL, on a Model 4 (row 7, bit 2).
    /// </summary>
    Control = 58,

    /// <summary>
    ///  CAPS, on a Model 4 (row 7, bit 3).
    /// </summary>
    Caps = 59,

    /// <summary>
    ///  F1, on a Model 4 (row 7, bit 4).
    /// </summary>
    F1 = 60,

    /// <summary>
    ///  F2, on a Model 4 (row 7, bit 5).
    /// </summary>
    F2 = 61,

    /// <summary>
    ///  F3, on a Model 4 (row 7, bit 6).
    /// </summary>
    F3 = 62
}
