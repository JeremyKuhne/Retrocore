// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  How serious a documentation problem is.
/// </summary>
public enum DocumentationSeverity
{
    /// <summary>
    ///  The documentation is probably wrong or incomplete.
    /// </summary>
    Warning,

    /// <summary>
    ///  The documentation is malformed, such as a comment that documents nothing.
    /// </summary>
    Error
}
