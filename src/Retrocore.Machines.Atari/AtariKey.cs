// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Atari;

/// <summary>
///  The keys POKEY scans, by their <c>KBCODE</c> (bits 0-5).
/// </summary>
public enum AtariKey
{
    /// <summary>
    ///  L.
    /// </summary>
    L = 0x00,

    /// <summary>
    ///  J.
    /// </summary>
    J = 0x01,

    /// <summary>
    ///  The semicolon (colon with SHIFT).
    /// </summary>
    Semicolon = 0x02,

    /// <summary>
    ///  K.
    /// </summary>
    K = 0x05,

    /// <summary>
    ///  The plus sign (backslash with SHIFT, cursor left with CONTROL).
    /// </summary>
    Plus = 0x06,

    /// <summary>
    ///  The asterisk (caret with SHIFT, cursor right with CONTROL).
    /// </summary>
    Asterisk = 0x07,

    /// <summary>
    ///  O.
    /// </summary>
    O = 0x08,

    /// <summary>
    ///  P.
    /// </summary>
    P = 0x0A,

    /// <summary>
    ///  U.
    /// </summary>
    U = 0x0B,

    /// <summary>
    ///  RETURN.
    /// </summary>
    Return = 0x0C,

    /// <summary>
    ///  I.
    /// </summary>
    I = 0x0D,

    /// <summary>
    ///  The minus sign (underscore with SHIFT, cursor up with CONTROL).
    /// </summary>
    Minus = 0x0E,

    /// <summary>
    ///  The equals sign (bar with SHIFT, cursor down with CONTROL).
    /// </summary>
    Equals = 0x0F,

    /// <summary>
    ///  V.
    /// </summary>
    V = 0x10,

    /// <summary>
    ///  C.
    /// </summary>
    C = 0x12,

    /// <summary>
    ///  B.
    /// </summary>
    B = 0x15,

    /// <summary>
    ///  X.
    /// </summary>
    X = 0x16,

    /// <summary>
    ///  Z.
    /// </summary>
    Z = 0x17,

    /// <summary>
    ///  4 ($ with SHIFT).
    /// </summary>
    D4 = 0x18,

    /// <summary>
    ///  3 (# with SHIFT).
    /// </summary>
    D3 = 0x1A,

    /// <summary>
    ///  6 (&amp; with SHIFT).
    /// </summary>
    D6 = 0x1B,

    /// <summary>
    ///  ESC.
    /// </summary>
    Escape = 0x1C,

    /// <summary>
    ///  5 (% with SHIFT).
    /// </summary>
    D5 = 0x1D,

    /// <summary>
    ///  2 (" with SHIFT).
    /// </summary>
    D2 = 0x1E,

    /// <summary>
    ///  1 (! with SHIFT).
    /// </summary>
    D1 = 0x1F,

    /// <summary>
    ///  The comma ([ with SHIFT).
    /// </summary>
    Comma = 0x20,

    /// <summary>
    ///  The space bar.
    /// </summary>
    Space = 0x21,

    /// <summary>
    ///  The full stop (] with SHIFT).
    /// </summary>
    Period = 0x22,

    /// <summary>
    ///  N.
    /// </summary>
    N = 0x23,

    /// <summary>
    ///  M.
    /// </summary>
    M = 0x25,

    /// <summary>
    ///  The slash (? with SHIFT).
    /// </summary>
    Slash = 0x26,

    /// <summary>
    ///  The Atari logo key, which turns on inverse video.
    /// </summary>
    Inverse = 0x27,

    /// <summary>
    ///  R.
    /// </summary>
    R = 0x28,

    /// <summary>
    ///  E.
    /// </summary>
    E = 0x2A,

    /// <summary>
    ///  Y.
    /// </summary>
    Y = 0x2B,

    /// <summary>
    ///  TAB.
    /// </summary>
    Tab = 0x2C,

    /// <summary>
    ///  T.
    /// </summary>
    T = 0x2D,

    /// <summary>
    ///  W.
    /// </summary>
    W = 0x2E,

    /// <summary>
    ///  Q.
    /// </summary>
    Q = 0x2F,

    /// <summary>
    ///  9 (( with SHIFT).
    /// </summary>
    D9 = 0x30,

    /// <summary>
    ///  0 () with SHIFT).
    /// </summary>
    D0 = 0x32,

    /// <summary>
    ///  7 (' with SHIFT).
    /// </summary>
    D7 = 0x33,

    /// <summary>
    ///  BACK S.
    /// </summary>
    Backspace = 0x34,

    /// <summary>
    ///  8 (@ with SHIFT).
    /// </summary>
    D8 = 0x35,

    /// <summary>
    ///  The less-than sign (CLEAR with SHIFT).
    /// </summary>
    Less = 0x36,

    /// <summary>
    ///  The greater-than sign (INSERT with SHIFT).
    /// </summary>
    Greater = 0x37,

    /// <summary>
    ///  F.
    /// </summary>
    F = 0x38,

    /// <summary>
    ///  H.
    /// </summary>
    H = 0x39,

    /// <summary>
    ///  D.
    /// </summary>
    D = 0x3A,

    /// <summary>
    ///  CAPS/LOWR.
    /// </summary>
    Caps = 0x3C,

    /// <summary>
    ///  G.
    /// </summary>
    G = 0x3D,

    /// <summary>
    ///  S.
    /// </summary>
    S = 0x3E,

    /// <summary>
    ///  A.
    /// </summary>
    A = 0x3F
}
