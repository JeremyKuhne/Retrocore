// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  How a subroutine treats the bytes after a JSR that calls it.
/// </summary>
public enum AnalysisCallKind : byte
{
    /// <summary>
    ///  The subroutine never returns to its caller, so flow tracing stops after the JSR.
    /// </summary>
    NoReturn,

    /// <summary>
    ///  A fixed number of inline argument bytes follows the JSR, and execution resumes after them.
    /// </summary>
    /// <remarks>Example: a ProDOS MLI call, whose JSR is followed by a command byte and a parameter pointer.</remarks>
    InlineBytes,

    /// <summary>
    ///  A zero-terminated inline string follows the JSR, and execution resumes after its terminator.
    /// </summary>
    InlineZeroTerminated
}
