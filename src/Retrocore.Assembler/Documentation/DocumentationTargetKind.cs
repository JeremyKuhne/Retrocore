// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  What a link resolved to.
/// </summary>
public enum DocumentationTargetKind
{
    /// <summary>
    ///  Nothing; the link renders as plain text.
    /// </summary>
    Unresolved,

    /// <summary>
    ///  More than one definition at the same lookup step.
    /// </summary>
    Ambiguous,

    /// <summary>
    ///  A documented definition, or a file or free-standing topic.
    /// </summary>
    Topic,

    /// <summary>
    ///  A symbol the assembly defines without documentation.
    /// </summary>
    Symbol,

    /// <summary>
    ///  An assembler directive, such as <c>.repeat</c>.
    /// </summary>
    Directive,

    /// <summary>
    ///  An instruction mnemonic.
    /// </summary>
    Instruction,

    /// <summary>
    ///  A web address.
    /// </summary>
    Url,

    /// <summary>
    ///  A documentation file in the repository (<c>doc:path</c>).
    /// </summary>
    Document
}
