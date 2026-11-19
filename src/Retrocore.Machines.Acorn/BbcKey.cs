// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Acorn;

/// <summary>
///  The BBC Micro's keys, by internal key number: the row in bits 4-6 and the column in bits 0-3, as the operating
///  system numbers them (Advanced User Guide, OSBYTE &amp;79). BREAK is not in the matrix; it resets the CPU.
/// </summary>
/// <remarks>
///  <para>
///   Row 0's columns 2-9 are not keys but the startup-option links; see <see cref="BbcKeyboard.StartupOptions"/>.
///  </para>
/// </remarks>
public enum BbcKey : byte
{
    /// <summary>
    ///  SHIFT.
    /// </summary>
    Shift = 0x00,

    /// <summary>
    ///  CTRL.
    /// </summary>
    Control = 0x01,

    /// <summary>
    ///  Q.
    /// </summary>
    Q = 0x10,

    /// <summary>
    ///  3 #.
    /// </summary>
    D3 = 0x11,

    /// <summary>
    ///  4 $.
    /// </summary>
    D4 = 0x12,

    /// <summary>
    ///  5 %.
    /// </summary>
    D5 = 0x13,

    /// <summary>
    ///  f4.
    /// </summary>
    F4 = 0x14,

    /// <summary>
    ///  8 (.
    /// </summary>
    D8 = 0x15,

    /// <summary>
    ///  f7.
    /// </summary>
    F7 = 0x16,

    /// <summary>
    ///  - =.
    /// </summary>
    Minus = 0x17,

    /// <summary>
    ///  ^ ~.
    /// </summary>
    Caret = 0x18,

    /// <summary>
    ///  cursor left.
    /// </summary>
    Left = 0x19,

    /// <summary>
    ///  f0.
    /// </summary>
    F0 = 0x20,

    /// <summary>
    ///  W.
    /// </summary>
    W = 0x21,

    /// <summary>
    ///  E.
    /// </summary>
    E = 0x22,

    /// <summary>
    ///  T.
    /// </summary>
    T = 0x23,

    /// <summary>
    ///  7 '.
    /// </summary>
    D7 = 0x24,

    /// <summary>
    ///  I.
    /// </summary>
    I = 0x25,

    /// <summary>
    ///  9 ).
    /// </summary>
    D9 = 0x26,

    /// <summary>
    ///  0.
    /// </summary>
    D0 = 0x27,

    /// <summary>
    ///  _ and the pound sign.
    /// </summary>
    Underscore = 0x28,

    /// <summary>
    ///  cursor down.
    /// </summary>
    Down = 0x29,

    /// <summary>
    ///  1 !.
    /// </summary>
    D1 = 0x30,

    /// <summary>
    ///  2 ".
    /// </summary>
    D2 = 0x31,

    /// <summary>
    ///  D.
    /// </summary>
    D = 0x32,

    /// <summary>
    ///  R.
    /// </summary>
    R = 0x33,

    /// <summary>
    ///  6 &amp;.
    /// </summary>
    D6 = 0x34,

    /// <summary>
    ///  U.
    /// </summary>
    U = 0x35,

    /// <summary>
    ///  O.
    /// </summary>
    O = 0x36,

    /// <summary>
    ///  P.
    /// </summary>
    P = 0x37,

    /// <summary>
    ///  [ {.
    /// </summary>
    LeftBracket = 0x38,

    /// <summary>
    ///  cursor up.
    /// </summary>
    Up = 0x39,

    /// <summary>
    ///  CAPS LOCK.
    /// </summary>
    CapsLock = 0x40,

    /// <summary>
    ///  A.
    /// </summary>
    A = 0x41,

    /// <summary>
    ///  X.
    /// </summary>
    X = 0x42,

    /// <summary>
    ///  F.
    /// </summary>
    F = 0x43,

    /// <summary>
    ///  Y.
    /// </summary>
    Y = 0x44,

    /// <summary>
    ///  J.
    /// </summary>
    J = 0x45,

    /// <summary>
    ///  K.
    /// </summary>
    K = 0x46,

    /// <summary>
    ///  @.
    /// </summary>
    At = 0x47,

    /// <summary>
    ///  : *.
    /// </summary>
    Colon = 0x48,

    /// <summary>
    ///  RETURN.
    /// </summary>
    Return = 0x49,

    /// <summary>
    ///  SHIFT LOCK.
    /// </summary>
    ShiftLock = 0x50,

    /// <summary>
    ///  S.
    /// </summary>
    S = 0x51,

    /// <summary>
    ///  C.
    /// </summary>
    C = 0x52,

    /// <summary>
    ///  G.
    /// </summary>
    G = 0x53,

    /// <summary>
    ///  H.
    /// </summary>
    H = 0x54,

    /// <summary>
    ///  N.
    /// </summary>
    N = 0x55,

    /// <summary>
    ///  L.
    /// </summary>
    L = 0x56,

    /// <summary>
    ///  ; +.
    /// </summary>
    Semicolon = 0x57,

    /// <summary>
    ///  ] }.
    /// </summary>
    RightBracket = 0x58,

    /// <summary>
    ///  DELETE.
    /// </summary>
    Delete = 0x59,

    /// <summary>
    ///  TAB.
    /// </summary>
    Tab = 0x60,

    /// <summary>
    ///  Z.
    /// </summary>
    Z = 0x61,

    /// <summary>
    ///  the space bar.
    /// </summary>
    Space = 0x62,

    /// <summary>
    ///  V.
    /// </summary>
    V = 0x63,

    /// <summary>
    ///  B.
    /// </summary>
    B = 0x64,

    /// <summary>
    ///  M.
    /// </summary>
    M = 0x65,

    /// <summary>
    ///  , &lt;.
    /// </summary>
    Comma = 0x66,

    /// <summary>
    ///  . &gt;.
    /// </summary>
    Period = 0x67,

    /// <summary>
    ///  / ?.
    /// </summary>
    Slash = 0x68,

    /// <summary>
    ///  COPY.
    /// </summary>
    Copy = 0x69,

    /// <summary>
    ///  ESCAPE.
    /// </summary>
    Escape = 0x70,

    /// <summary>
    ///  f1.
    /// </summary>
    F1 = 0x71,

    /// <summary>
    ///  f2.
    /// </summary>
    F2 = 0x72,

    /// <summary>
    ///  f3.
    /// </summary>
    F3 = 0x73,

    /// <summary>
    ///  f5.
    /// </summary>
    F5 = 0x74,

    /// <summary>
    ///  f6.
    /// </summary>
    F6 = 0x75,

    /// <summary>
    ///  f8.
    /// </summary>
    F8 = 0x76,

    /// <summary>
    ///  f9.
    /// </summary>
    F9 = 0x77,

    /// <summary>
    ///  \ |.
    /// </summary>
    Backslash = 0x78,

    /// <summary>
    ///  cursor right.
    /// </summary>
    Right = 0x79
}
