// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Commodore;

/// <summary>
///  A key on the PET 2001's keyboard, numbered by its place in the matrix: row times 8 plus the port B bit it pulls
///  low.
/// </summary>
/// <remarks>
///  <para>
///   The 2001's keys carry their symbols unshifted: the top row is <c>! " # $ % ' &amp; \ ( ) ←</c>, the digits are
///   on the numeric pad, and SHIFT with a letter or symbol types a graphics character. SHIFT LOCK holds the left
///   SHIFT's place. The 2001-N's graphics keyboard is wired to the same matrix.
///  </para>
/// </remarks>
public enum PetKey : byte
{
    /// <summary>
    ///  The ! key.
    /// </summary>
    Exclamation = 0,

    /// <summary>
    ///  The # key.
    /// </summary>
    Hash,

    /// <summary>
    ///  The % key.
    /// </summary>
    Percent,

    /// <summary>
    ///  The &amp; key.
    /// </summary>
    Ampersand,

    /// <summary>
    ///  The ( key.
    /// </summary>
    OpenParenthesis,

    /// <summary>
    ///  The ← key, which BASIC reads as <c>_</c>.
    /// </summary>
    LeftArrow,

    /// <summary>
    ///  CLR/HOME: home the cursor, or with SHIFT clear the screen.
    /// </summary>
    Home,

    /// <summary>
    ///  The cursor right key; with SHIFT, left.
    /// </summary>
    CursorRight,

    /// <summary>
    ///  The " key.
    /// </summary>
    DoubleQuote = 8,

    /// <summary>
    ///  The $ key.
    /// </summary>
    Dollar,

    /// <summary>
    ///  The ' key.
    /// </summary>
    Apostrophe,

    /// <summary>
    ///  The \ key.
    /// </summary>
    Backslash,

    /// <summary>
    ///  The ) key.
    /// </summary>
    CloseParenthesis,

    /// <summary>
    ///  The cursor down key; with SHIFT, up.
    /// </summary>
    CursorDown = 14,

    /// <summary>
    ///  INST/DEL: delete, or with SHIFT insert.
    /// </summary>
    Delete,

    /// <summary>
    ///  Q.
    /// </summary>
    Q = 16,

    /// <summary>
    ///  E.
    /// </summary>
    E,

    /// <summary>
    ///  T.
    /// </summary>
    T,

    /// <summary>
    ///  U.
    /// </summary>
    U,

    /// <summary>
    ///  O.
    /// </summary>
    O,

    /// <summary>
    ///  The ↑ key, which BASIC reads as <c>^</c>.
    /// </summary>
    UpArrow,

    /// <summary>
    ///  7, on the numeric pad.
    /// </summary>
    Keypad7,

    /// <summary>
    ///  9, on the numeric pad.
    /// </summary>
    Keypad9,

    /// <summary>
    ///  W.
    /// </summary>
    W = 24,

    /// <summary>
    ///  R.
    /// </summary>
    R,

    /// <summary>
    ///  Y.
    /// </summary>
    Y,

    /// <summary>
    ///  I.
    /// </summary>
    I,

    /// <summary>
    ///  P.
    /// </summary>
    P,

    /// <summary>
    ///  8, on the numeric pad.
    /// </summary>
    Keypad8 = 30,

    /// <summary>
    ///  /, on the numeric pad.
    /// </summary>
    KeypadSlash,

    /// <summary>
    ///  A.
    /// </summary>
    A = 32,

    /// <summary>
    ///  D.
    /// </summary>
    D,

    /// <summary>
    ///  G.
    /// </summary>
    G,

    /// <summary>
    ///  J.
    /// </summary>
    J,

    /// <summary>
    ///  L.
    /// </summary>
    L,

    /// <summary>
    ///  4, on the numeric pad.
    /// </summary>
    Keypad4 = 38,

    /// <summary>
    ///  6, on the numeric pad.
    /// </summary>
    Keypad6,

    /// <summary>
    ///  S.
    /// </summary>
    S = 40,

    /// <summary>
    ///  F.
    /// </summary>
    F,

    /// <summary>
    ///  H.
    /// </summary>
    H,

    /// <summary>
    ///  K.
    /// </summary>
    K,

    /// <summary>
    ///  The : key.
    /// </summary>
    Colon,

    /// <summary>
    ///  5, on the numeric pad.
    /// </summary>
    Keypad5 = 46,

    /// <summary>
    ///  *, on the numeric pad.
    /// </summary>
    KeypadAsterisk,

    /// <summary>
    ///  Z.
    /// </summary>
    Z = 48,

    /// <summary>
    ///  C.
    /// </summary>
    C,

    /// <summary>
    ///  B.
    /// </summary>
    B,

    /// <summary>
    ///  M.
    /// </summary>
    M,

    /// <summary>
    ///  The ; key.
    /// </summary>
    Semicolon,

    /// <summary>
    ///  RETURN.
    /// </summary>
    Return,

    /// <summary>
    ///  1, on the numeric pad.
    /// </summary>
    Keypad1,

    /// <summary>
    ///  3, on the numeric pad.
    /// </summary>
    Keypad3,

    /// <summary>
    ///  X.
    /// </summary>
    X = 56,

    /// <summary>
    ///  V.
    /// </summary>
    V,

    /// <summary>
    ///  N.
    /// </summary>
    N,

    /// <summary>
    ///  The , key.
    /// </summary>
    Comma,

    /// <summary>
    ///  The ? key.
    /// </summary>
    Question,

    /// <summary>
    ///  2, on the numeric pad.
    /// </summary>
    Keypad2 = 62,

    /// <summary>
    ///  +, on the numeric pad.
    /// </summary>
    KeypadPlus,

    /// <summary>
    ///  The left SHIFT, and SHIFT LOCK.
    /// </summary>
    LeftShift = 64,

    /// <summary>
    ///  The @ key.
    /// </summary>
    At,

    /// <summary>
    ///  The ] key.
    /// </summary>
    CloseBracket,

    /// <summary>
    ///  The &gt; key.
    /// </summary>
    GreaterThan = 68,

    /// <summary>
    ///  The right SHIFT.
    /// </summary>
    RightShift,

    /// <summary>
    ///  0, on the numeric pad.
    /// </summary>
    Keypad0,

    /// <summary>
    ///  -, on the numeric pad.
    /// </summary>
    KeypadMinus,

    /// <summary>
    ///  RVS: reverse video on, or with SHIFT off.
    /// </summary>
    Reverse = 72,

    /// <summary>
    ///  The [ key.
    /// </summary>
    OpenBracket,

    /// <summary>
    ///  The space bar.
    /// </summary>
    Space,

    /// <summary>
    ///  The &lt; key.
    /// </summary>
    LessThan,

    /// <summary>
    ///  STOP/RUN: stop a program, or with SHIFT load and run from tape.
    /// </summary>
    Stop,

    /// <summary>
    ///  ., on the numeric pad.
    /// </summary>
    KeypadPeriod = 78,

    /// <summary>
    ///  =, on the numeric pad.
    /// </summary>
    KeypadEquals
}
