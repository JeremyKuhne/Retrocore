// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal.Source;

/// <summary>
///  A scope: the program's, a routine's, or a record's fields.
/// </summary>
public sealed class PascalScope
{
    /// <summary>
    ///  Creates a scope.
    /// </summary>
    /// <param name="parent">The scope it is in, or null for the outermost.</param>
    /// <param name="owner">The routine or record type it belongs to, or null.</param>
    /// <param name="isRecord">Whether it holds a record's fields.</param>
    internal PascalScope(PascalScope? parent, PascalDeclaration? owner, bool isRecord)
    {
        Parent = parent;
        Owner = owner;
        IsRecord = isRecord;
    }

    /// <summary>
    ///  Gets the scope it is in, or null for the outermost.
    /// </summary>
    public PascalScope? Parent { get; }

    /// <summary>
    ///  Gets the routine or record type it belongs to, or null for the outermost.
    /// </summary>
    public PascalDeclaration? Owner { get; internal set; }

    /// <summary>
    ///  Gets whether it holds a record's fields, which names in code reach only after a <c>.</c> or in a <c>WITH</c>.
    /// </summary>
    public bool IsRecord { get; }

    /// <summary>
    ///  Gets what it declares, in order.
    /// </summary>
    public List<PascalDeclaration> Declarations { get; } = [];

    /// <summary>
    ///  Gets its path, as links qualify names: the routines and named records it is nested in, outermost first, not the
    ///  program. A record type written in a variable's declaration has no name, and the path stops there.
    /// </summary>
    public string Path
    {
        get
        {
            List<string> names = [];
            for (PascalScope? scope = this; scope?.Owner is { } owner; scope = scope.Parent)
            {
                if (owner.Kind is PascalDeclarationKind.Program or PascalDeclarationKind.Unit) { break; }
                names.Add(owner.Name);
            }

            names.Reverse();
            return string.Join('.', names);
        }
    }

    /// <summary>
    ///  Finds what a name means here: its declaration in this scope or the nearest enclosing one, records left out.
    /// </summary>
    /// <param name="name">The name.</param>
    /// <returns>The declaration, or null.</returns>
    public PascalDeclaration? Find(string name)
    {
        string key = PascalNames.Key(name);
        for (PascalScope? scope = this; scope is not null; scope = scope.Parent)
        {
            if (scope.IsRecord) { continue; }
            if (scope.Declarations.FirstOrDefault(declaration => declaration.Key == key) is { } found) { return found; }
        }

        return null;
    }
}
