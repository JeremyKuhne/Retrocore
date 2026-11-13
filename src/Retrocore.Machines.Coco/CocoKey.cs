// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Coco;

/// <summary>
///  A key of the Color Computer's matrix: row (PIA 0's port A input bit) times 8 plus column (port B output bit).
/// </summary>
public enum CocoKey : byte
{
    /// <summary>
    ///  The @ key.
    /// </summary>
    At = 0,

    /// <summary>
    ///  A.
    /// </summary>
    A,

    /// <summary>
    ///  B.
    /// </summary>
    B,

    /// <summary>
    ///  C.
    /// </summary>
    C,

    /// <summary>
    ///  D.
    /// </summary>
    D,

    /// <summary>
    ///  E.
    /// </summary>
    E,

    /// <summary>
    ///  F.
    /// </summary>
    F,

    /// <summary>
    ///  G.
    /// </summary>
    G,

    /// <summary>
    ///  H.
    /// </summary>
    H,

    /// <summary>
    ///  I.
    /// </summary>
    I,

    /// <summary>
    ///  J.
    /// </summary>
    J,

    /// <summary>
    ///  K.
    /// </summary>
    K,

    /// <summary>
    ///  L.
    /// </summary>
    L,

    /// <summary>
    ///  M.
    /// </summary>
    M,

    /// <summary>
    ///  N.
    /// </summary>
    N,

    /// <summary>
    ///  O.
    /// </summary>
    O,

    /// <summary>
    ///  P.
    /// </summary>
    P,

    /// <summary>
    ///  Q.
    /// </summary>
    Q,

    /// <summary>
    ///  R.
    /// </summary>
    R,

    /// <summary>
    ///  S.
    /// </summary>
    S,

    /// <summary>
    ///  T.
    /// </summary>
    T,

    /// <summary>
    ///  U.
    /// </summary>
    U,

    /// <summary>
    ///  V.
    /// </summary>
    V,

    /// <summary>
    ///  W.
    /// </summary>
    W,

    /// <summary>
    ///  X.
    /// </summary>
    X,

    /// <summary>
    ///  Y.
    /// </summary>
    Y,

    /// <summary>
    ///  Z.
    /// </summary>
    Z,

    /// <summary>
    ///  The up arrow.
    /// </summary>
    Up,

    /// <summary>
    ///  The down arrow.
    /// </summary>
    Down,

    /// <summary>
    ///  The left arrow.
    /// </summary>
    Left,

    /// <summary>
    ///  The right arrow.
    /// </summary>
    Right,

    /// <summary>
    ///  The space bar.
    /// </summary>
    Space,

    /// <summary>
    ///  0.
    /// </summary>
    D0,

    /// <summary>
    ///  1 and !.
    /// </summary>
    D1,

    /// <summary>
    ///  2 and ".
    /// </summary>
    D2,

    /// <summary>
    ///  3 and #.
    /// </summary>
    D3,

    /// <summary>
    ///  4 and $.
    /// </summary>
    D4,

    /// <summary>
    ///  5 and %.
    /// </summary>
    D5,

    /// <summary>
    ///  6 and &amp;.
    /// </summary>
    D6,

    /// <summary>
    ///  7 and '.
    /// </summary>
    D7,

    /// <summary>
    ///  8 and (.
    /// </summary>
    D8,

    /// <summary>
    ///  9 and ).
    /// </summary>
    D9,

    /// <summary>
    ///  : and *.
    /// </summary>
    Colon,

    /// <summary>
    ///  ; and +.
    /// </summary>
    Semicolon,

    /// <summary>
    ///  , and &lt;.
    /// </summary>
    Comma,

    /// <summary>
    ///  - and =.
    /// </summary>
    Minus,

    /// <summary>
    ///  . and &gt;.
    /// </summary>
    Period,

    /// <summary>
    ///  / and ?.
    /// </summary>
    Slash,

    /// <summary>
    ///  ENTER.
    /// </summary>
    Enter,

    /// <summary>
    ///  CLEAR.
    /// </summary>
    Clear,

    /// <summary>
    ///  BREAK.
    /// </summary>
    Break,

    /// <summary>
    ///  ALT, on the CoCo 3.
    /// </summary>
    Alt,

    /// <summary>
    ///  CTRL, on the CoCo 3.
    /// </summary>
    Control,

    /// <summary>
    ///  F1, on the CoCo 3.
    /// </summary>
    F1,

    /// <summary>
    ///  F2, on the CoCo 3.
    /// </summary>
    F2,

    /// <summary>
    ///  SHIFT.
    /// </summary>
    Shift
}
