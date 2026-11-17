// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  Where MBASIC 5.21 for CP/M keeps its state, by Microsoft's names: the same variables, in the same order, as
///  GW-BASIC's MIT-licensed <c>GWDATA.ASM</c> declares them.
/// </summary>
/// <remarks>
///  <para>
///   <c>Mbasic.asm</c>, the SDK's source of <c>MBASIC.COM</c>, defines these too; they are here for the BASIC tools,
///   which work without it.
///  </para>
/// </remarks>
internal static class MbasicMemory
{
    /// <summary>
    ///  The top of the stack, set by CLEAR.
    /// </summary>
    internal const int TOPMEM = 0x0796;

    /// <summary>
    ///  The current line's number, <c>$FFFF</c> for a direct statement.
    /// </summary>
    internal const int CURLIN = 0x0798;

    /// <summary>
    ///  The program's first line.
    /// </summary>
    internal const int TXTTAB = 0x079A;

    /// <summary>
    ///  The highest location string space uses.
    /// </summary>
    internal const int MEMSIZ = 0x0A76;

    /// <summary>
    ///  The first free temporary string descriptor.
    /// </summary>
    internal const int TEMPPT = 0x0A78;

    /// <summary>
    ///  The temporary string descriptors.
    /// </summary>
    internal const int TEMPST = 0x0A7A;

    /// <summary>
    ///  The bottom of the strings in string space.
    /// </summary>
    internal const int FRETOP = 0x0A9B;

    /// <summary>
    ///  The text pointer after a FOR statement.
    /// </summary>
    internal const int ENDFOR = 0x0AA1;

    /// <summary>
    ///  The line READ last took DATA from, for its errors.
    /// </summary>
    internal const int DATLIN = 0x0AA3;

    /// <summary>
    ///  Where NEWSTT saves the text pointer, for RESUME.
    /// </summary>
    internal const int SAVTXT = 0x0AAF;

    /// <summary>
    ///  Where NEWSTT saves the stack pointer, so an error can restore it.
    /// </summary>
    internal const int SAVSTK = 0x0AB1;

    /// <summary>
    ///  The line of the last error.
    /// </summary>
    internal const int ERRLIN = 0x0AB3;

    /// <summary>
    ///  The text pointer of the last error, for RESUME.
    /// </summary>
    internal const int ERRTXT = 0x0AB7;

    /// <summary>
    ///  ON ERROR GOTO's line, 0 for none.
    /// </summary>
    internal const int ONELIN = 0x0AB9;

    /// <summary>
    ///  Nonzero while an ON ERROR routine runs.
    /// </summary>
    internal const int ONEFLG = 0x0ABB;

    /// <summary>
    ///  The line STOP, END or CONTROL-C stopped at.
    /// </summary>
    internal const int OLDLIN = 0x0ABE;

    /// <summary>
    ///  The text pointer CONT goes on from.
    /// </summary>
    internal const int OLDTXT = 0x0AC0;

    /// <summary>
    ///  The simple variables, after the program.
    /// </summary>
    internal const int VARTAB = 0x0AC2;

    /// <summary>
    ///  The arrays, after the simple variables.
    /// </summary>
    internal const int ARYTAB = 0x0AC4;

    /// <summary>
    ///  The end of the arrays.
    /// </summary>
    internal const int STREND = 0x0AC6;

    /// <summary>
    ///  Where READ takes its next DATA.
    /// </summary>
    internal const int DATPTR = 0x0AC8;

    /// <summary>
    ///  Each letter's default type, set by DEFINT, DEFSNG, DEFDBL and DEFSTR: 2, 4, 8 or 3.
    /// </summary>
    internal const int DEFTBL = 0x0ACA;

    /// <summary>
    ///  Nonzero while TRON traces.
    /// </summary>
    internal const int TRCFLG = 0x0BFE;

    /// <summary>
    ///  Where the program starts on a 64K CP/M system with MBASIC's three default file buffers.
    /// </summary>
    internal const int ProgramStart = 0x61CA;
}
