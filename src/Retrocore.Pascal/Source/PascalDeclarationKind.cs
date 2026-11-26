// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal.Source;

/// <summary>
///  What a declaration declares.
/// </summary>
public enum PascalDeclarationKind
{
    /// <summary>
    ///  The program.
    /// </summary>
    Program,

    /// <summary>
    ///  A unit.
    /// </summary>
    Unit,

    /// <summary>
    ///  A procedure.
    /// </summary>
    Procedure,

    /// <summary>
    ///  A function.
    /// </summary>
    Function,

    /// <summary>
    ///  A routine's parameter.
    /// </summary>
    Parameter,

    /// <summary>
    ///  A constant.
    /// </summary>
    Constant,

    /// <summary>
    ///  A type.
    /// </summary>
    Type,

    /// <summary>
    ///  A variable.
    /// </summary>
    Variable,

    /// <summary>
    ///  A record's field.
    /// </summary>
    Field,

    /// <summary>
    ///  A value of an enumerated type.
    /// </summary>
    EnumValue
}
