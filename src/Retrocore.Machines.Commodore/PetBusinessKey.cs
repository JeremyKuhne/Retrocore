// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Commodore;

/// <summary>
///  A key on the PET's business keyboard, numbered by its place in the matrix: row times 8 plus the port B bit it
///  pulls low.
/// </summary>
/// <remarks>
///  <para>
///   The business keyboard is a typewriter's: the digits are on the top row with their symbols shifted, the letters
///   type capitals in the graphics set, and the numeric pad has no symbols. It is wired to the same ten rows as the
///   graphics keyboard, in other places. Its editor's key table, at <c>$E60B</c> in 901474-02, reads the rows from 9
///   down and each row's bits from 7 down. SHIFT LOCK holds the left SHIFT's place.
///  </para>
/// </remarks>
public enum PetBusinessKey : byte
{
    /// <summary>
    ///  The 2 key; with SHIFT, ".
    /// </summary>
    Digit2 = 0,

    /// <summary>
    ///  The 5 key; with SHIFT, %.
    /// </summary>
    Digit5,

    /// <summary>
    ///  The 8 key; with SHIFT, (.
    /// </summary>
    Digit8,

    /// <summary>
    ///  The - key; with SHIFT, =.
    /// </summary>
    Minus,

    /// <summary>
    ///  8, on the numeric pad.
    /// </summary>
    Keypad8,

    /// <summary>
    ///  The cursor right key; with SHIFT, left.
    /// </summary>
    CursorRight,

    /// <summary>
    ///  The 1 key; with SHIFT, !.
    /// </summary>
    Digit1 = 8,

    /// <summary>
    ///  The 4 key; with SHIFT, $.
    /// </summary>
    Digit4,

    /// <summary>
    ///  The 7 key; with SHIFT, '.
    /// </summary>
    Digit7,

    /// <summary>
    ///  0, on the numeric pad.
    /// </summary>
    Keypad0,

    /// <summary>
    ///  7, on the numeric pad.
    /// </summary>
    Keypad7,

    /// <summary>
    ///  The ↑ key.
    /// </summary>
    UpArrow,

    /// <summary>
    ///  9, on the numeric pad.
    /// </summary>
    Keypad9 = 15,

    /// <summary>
    ///  ESC.
    /// </summary>
    Escape = 16,

    /// <summary>
    ///  The S key.
    /// </summary>
    S,

    /// <summary>
    ///  The F key.
    /// </summary>
    F,

    /// <summary>
    ///  The H key.
    /// </summary>
    H,

    /// <summary>
    ///  The ] key.
    /// </summary>
    CloseBracket,

    /// <summary>
    ///  The K key.
    /// </summary>
    K,

    /// <summary>
    ///  The ; key; with SHIFT, +.
    /// </summary>
    Semicolon,

    /// <summary>
    ///  5, on the numeric pad.
    /// </summary>
    Keypad5,

    /// <summary>
    ///  The A key.
    /// </summary>
    A = 24,

    /// <summary>
    ///  The D key.
    /// </summary>
    D,

    /// <summary>
    ///  The G key.
    /// </summary>
    G,

    /// <summary>
    ///  The J key.
    /// </summary>
    J,

    /// <summary>
    ///  RETURN.
    /// </summary>
    Return,

    /// <summary>
    ///  The L key.
    /// </summary>
    L,

    /// <summary>
    ///  The @ key.
    /// </summary>
    At,

    /// <summary>
    ///  6, on the numeric pad.
    /// </summary>
    Keypad6,

    /// <summary>
    ///  TAB.
    /// </summary>
    Tab = 32,

    /// <summary>
    ///  The W key.
    /// </summary>
    W,

    /// <summary>
    ///  The R key.
    /// </summary>
    R,

    /// <summary>
    ///  The Y key.
    /// </summary>
    Y,

    /// <summary>
    ///  The \ key.
    /// </summary>
    Backslash,

    /// <summary>
    ///  The I key.
    /// </summary>
    I,

    /// <summary>
    ///  The P key.
    /// </summary>
    P,

    /// <summary>
    ///  INST/DEL: delete the character left of the cursor, or with SHIFT insert a space.
    /// </summary>
    Delete,

    /// <summary>
    ///  The Q key.
    /// </summary>
    Q = 40,

    /// <summary>
    ///  The E key.
    /// </summary>
    E,

    /// <summary>
    ///  The T key.
    /// </summary>
    T,

    /// <summary>
    ///  The U key.
    /// </summary>
    U,

    /// <summary>
    ///  The cursor down key; with SHIFT, up.
    /// </summary>
    CursorDown,

    /// <summary>
    ///  The O key.
    /// </summary>
    O,

    /// <summary>
    ///  The [ key.
    /// </summary>
    OpenBracket,

    /// <summary>
    ///  4, on the numeric pad.
    /// </summary>
    Keypad4,

    /// <summary>
    ///  The left SHIFT, and SHIFT LOCK.
    /// </summary>
    LeftShift = 48,

    /// <summary>
    ///  The C key.
    /// </summary>
    C,

    /// <summary>
    ///  The B key.
    /// </summary>
    B,

    /// <summary>
    ///  The . key; with SHIFT, &gt;.
    /// </summary>
    Period,

    /// <summary>
    ///  ., on the numeric pad.
    /// </summary>
    KeypadPeriod,

    /// <summary>
    ///  The right SHIFT.
    /// </summary>
    RightShift = 54,

    /// <summary>
    ///  3, on the numeric pad.
    /// </summary>
    Keypad3,

    /// <summary>
    ///  The Z key.
    /// </summary>
    Z = 56,

    /// <summary>
    ///  The V key.
    /// </summary>
    V,

    /// <summary>
    ///  The N key.
    /// </summary>
    N,

    /// <summary>
    ///  The , key; with SHIFT, &lt;.
    /// </summary>
    Comma,

    /// <summary>
    ///  The 0 key.
    /// </summary>
    Digit0,

    /// <summary>
    ///  REPEAT, which repeats the key held with it.
    /// </summary>
    Repeat = 62,

    /// <summary>
    ///  2, on the numeric pad.
    /// </summary>
    Keypad2,

    /// <summary>
    ///  OFF/RVS: reverse video on, or with SHIFT off.
    /// </summary>
    Reverse = 64,

    /// <summary>
    ///  The X key.
    /// </summary>
    X,

    /// <summary>
    ///  The space bar.
    /// </summary>
    Space,

    /// <summary>
    ///  The M key.
    /// </summary>
    M,

    /// <summary>
    ///  CLR/HOME: home the cursor, or with SHIFT clear the screen.
    /// </summary>
    Home,

    /// <summary>
    ///  The / key; with SHIFT, ?.
    /// </summary>
    Slash = 70,

    /// <summary>
    ///  1, on the numeric pad.
    /// </summary>
    Keypad1,

    /// <summary>
    ///  The ← key, which BASIC reads as <c>_</c>.
    /// </summary>
    LeftArrow = 72,

    /// <summary>
    ///  The 3 key; with SHIFT, #.
    /// </summary>
    Digit3,

    /// <summary>
    ///  The 6 key; with SHIFT, &amp;.
    /// </summary>
    Digit6,

    /// <summary>
    ///  The 9 key; with SHIFT, ).
    /// </summary>
    Digit9,

    /// <summary>
    ///  STOP/RUN: stop a program, or with SHIFT load and run from tape.
    /// </summary>
    Stop,

    /// <summary>
    ///  The : key; with SHIFT, *.
    /// </summary>
    Colon
}
