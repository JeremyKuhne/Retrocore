// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  What a documentation topic describes.
/// </summary>
public enum DocumentationKind
{
    /// <summary>
    ///  A source file, from its leading comment.
    /// </summary>
    File,

    /// <summary>
    ///  Code: a label followed by an instruction.
    /// </summary>
    Routine,

    /// <summary>
    ///  Data: a label followed by data.
    /// </summary>
    Table,

    /// <summary>
    ///  An equate.
    /// </summary>
    Constant,

    /// <summary>
    ///  A reassignable <c>.set</c> variable.
    /// </summary>
    Variable,

    /// <summary>
    ///  A macro.
    /// </summary>
    Macro,

    /// <summary>
    ///  An enumeration.
    /// </summary>
    Enum,

    /// <summary>
    ///  A structure or union.
    /// </summary>
    Struct,

    /// <summary>
    ///  A scope or procedure.
    /// </summary>
    Scope,

    /// <summary>
    ///  A textual <c>.define</c>.
    /// </summary>
    Definition,

    /// <summary>
    ///  A member of an enumeration or field of a structure.
    /// </summary>
    Member,

    /// <summary>
    ///  A free-standing topic with an explicit keyword line, such as <c>Group: Title</c>.
    /// </summary>
    Topic
}
