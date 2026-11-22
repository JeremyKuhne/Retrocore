// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  Where an <c>ignore=</c> exclusion applies.
/// </summary>
public enum DocumentationExclusionScope
{
    /// <summary>
    ///  The whole file, from its first line's pragma.
    /// </summary>
    File,

    /// <summary>
    ///  One line of code, from its trailing plain comment.
    /// </summary>
    Line,

    /// <summary>
    ///  The <c>;;</c> block below a plain comment line.
    /// </summary>
    Comment
}
