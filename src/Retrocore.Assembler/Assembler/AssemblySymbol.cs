// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  An immutable resolved label/constant with export and source metadata.
/// </summary>
public sealed class AssemblySymbol
{
    /// <summary>
    ///  Creates a resolved symbol.
    /// </summary>
    /// <param name="name">The case-sensitive name.</param>
    /// <param name="value">The address or scalar value.</param>
    /// <param name="constant">Whether it is a scalar assignment.</param>
    /// <param name="exported">Whether it was explicitly exported.</param>
    /// <param name="location">The original location, when present.</param>
    internal AssemblySymbol(string name, long value, bool constant, bool exported, AssemblyLocation? location)
    {
        Name = name;
        Value = value;
        IsConstant = constant;
        IsExported = exported;
        Location = location;
    }

    /// <summary>
    ///  Gets the case-sensitive name.
    /// </summary>
    public string Name { get; }

    /// <summary>
    ///  Gets the address or scalar value.
    /// </summary>
    public long Value { get; }

    /// <summary>
    ///  Gets whether the symbol is an assignment.
    /// </summary>
    public bool IsConstant { get; }

    /// <summary>
    ///  Gets whether the symbol is exported.
    /// </summary>
    public bool IsExported { get; }

    /// <summary>
    ///  Gets its real source location, if any.
    /// </summary>
    public AssemblyLocation? Location { get; }
}
