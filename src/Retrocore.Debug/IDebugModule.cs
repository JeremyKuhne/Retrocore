// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Documentation;

namespace Retrocore.Debug;

/// <summary>
///  Debug information for one body of code, such as a program or a ROM built from SDK sources.
/// </summary>
internal interface IDebugModule
{
    /// <summary>
    ///  Gets the memory area the code lives in, or null when it applies whatever the memory map selects.
    /// </summary>
    Enum? Area { get; }

    /// <summary>
    ///  Gets the source behind an address, when the module covers it and memory holds the code it describes.
    /// </summary>
    /// <param name="memory">The machine's memory, for reading the bytes at the address.</param>
    /// <param name="address">The CPU address.</param>
    /// <returns>The position, or null.</returns>
    DebugPosition? Position(IDebugMemory memory, ushort address);

    /// <summary>
    ///  Gets the addresses where a breakpoint on a source line stops: each start of that line's code.
    /// </summary>
    /// <param name="path">The full source path.</param>
    /// <param name="line">The one-based line.</param>
    /// <returns>The addresses.</returns>
    IEnumerable<ushort> Entries(string path, int line);

    /// <summary>
    ///  Resolves a symbol.
    /// </summary>
    /// <param name="name">The name, which may be qualified as scope::name.</param>
    /// <param name="value">The value.</param>
    /// <returns>Whether the module defines the name.</returns>
    bool TryResolve(string name, out long value);

    /// <summary>
    ///  Gets the closest label at or before an address.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The label, or null.</returns>
    string? Label(ushort address);

    /// <summary>
    ///  Gets the documentation comments of the module's sources, with its symbol values.
    /// </summary>
    DocumentationSet Documentation { get; }
}
