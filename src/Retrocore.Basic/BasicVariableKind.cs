// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  What a BASIC variable holds.
/// </summary>
public enum BasicVariableKind
{
    /// <summary>
    ///  A number in the dialect's float: AppleSoft's five bytes, or Business BASIC's four.
    /// </summary>
    Real,

    /// <summary>
    ///  A 16-bit integer, named with %.
    /// </summary>
    Integer,

    /// <summary>
    ///  A string, named with $.
    /// </summary>
    String,

    /// <summary>
    ///  A Level II single-precision number, a four-byte float, named with ! or by default.
    /// </summary>
    Single,

    /// <summary>
    ///  A Level II double-precision number, an eight-byte float, named with #.
    /// </summary>
    Double,

    /// <summary>
    ///  An AppleSoft or Business BASIC DEF FN function.
    /// </summary>
    Function,

    /// <summary>
    ///  A Business BASIC long integer, eight bytes, named with &amp;.
    /// </summary>
    Long
}
