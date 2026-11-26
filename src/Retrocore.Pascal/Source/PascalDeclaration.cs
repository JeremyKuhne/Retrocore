// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal.Source;

/// <summary>
///  A name the source declares, where, and what documents it.
/// </summary>
public sealed class PascalDeclaration
{
    /// <summary>
    ///  Creates a declaration.
    /// </summary>
    /// <param name="name">The name, as written.</param>
    /// <param name="kind">What it declares.</param>
    /// <param name="token">The name's token.</param>
    /// <param name="scope">The scope it is declared in.</param>
    internal PascalDeclaration(string name, PascalDeclarationKind kind, PascalToken token, PascalScope scope)
    {
        Name = name;
        Kind = kind;
        Token = token;
        Scope = scope;
    }

    /// <summary>
    ///  Gets the name, as written.
    /// </summary>
    public string Name { get; }

    /// <summary>
    ///  Gets what it declares.
    /// </summary>
    public PascalDeclarationKind Kind { get; }

    /// <summary>
    ///  Gets the name's token.
    /// </summary>
    public PascalToken Token { get; }

    /// <summary>
    ///  Gets the scope it is declared in: a routine's, the program's, or a record's for a field.
    /// </summary>
    public PascalScope Scope { get; }

    /// <summary>
    ///  Gets a routine's own scope, with its parameters and locals; null for anything else.
    /// </summary>
    public PascalScope? Body { get; internal set; }

    /// <summary>
    ///  Gets its documentation comment, or null.
    /// </summary>
    public PascalDocComment? Doc { get; internal set; }

    /// <summary>
    ///  Gets whether it is a segment procedure or function.
    /// </summary>
    public bool IsSegment { get; internal set; }

    /// <summary>
    ///  Gets whether it is declared in a unit's interface part, whose text the unit's code file keeps.
    /// </summary>
    public bool IsInterface { get; internal set; }

    /// <summary>
    ///  Gets whether it is a routine declared <c>FORWARD</c> or <c>EXTERNAL</c>, or in a unit's interface, so that its
    ///  body is elsewhere.
    /// </summary>
    public bool IsHeadingOnly { get; internal set; }

    /// <summary>
    ///  Gets the key the Compiler reads of its name.
    /// </summary>
    public string Key => PascalNames.Key(Name);

    /// <summary>
    ///  Gets whether the code file keeps its name, so that it can't be renamed: the program, a unit, a segment, or a
    ///  unit's interface.
    /// </summary>
    public bool NameIsKept =>
        Kind is PascalDeclarationKind.Program or PascalDeclarationKind.Unit
            || IsSegment
            || IsInterface;

    /// <summary>
    ///  Gets its name qualified by the routines and records it is declared in, as a link writes it
    ///  (<c>Outer.Inner</c>).
    /// </summary>
    public string QualifiedName => Scope.Path is { Length: > 0 } path ? $"{path}.{Name}" : Name;

    /// <inheritdoc/>
    public override string ToString() => $"{Kind} {QualifiedName}";
}
