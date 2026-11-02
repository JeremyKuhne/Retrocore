// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  How serious a problem in BASIC text is.
/// </summary>
public enum BasicSeverity
{
    /// <summary>
    ///  The program can still be stored, as BASIC would store it.
    /// </summary>
    Warning,

    /// <summary>
    ///  The program cannot be stored.
    /// </summary>
    Error
}
