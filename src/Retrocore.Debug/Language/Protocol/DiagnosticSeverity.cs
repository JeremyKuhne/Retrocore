// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Language;

/// <summary>
///  How serious a problem is, with LSP's numbers.
/// </summary>
internal enum DiagnosticSeverity
{
    /// <summary>
    ///  An error.
    /// </summary>
    Error = 1,

    /// <summary>
    ///  A warning.
    /// </summary>
    Warning = 2
}
