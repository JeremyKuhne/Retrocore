// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Documentation;
using Retrocore.Isa;

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
    ///  Gets the module's labels: the names it gives addresses, not its constants.
    /// </summary>
    IEnumerable<(string Name, long Value)> Labels { get; }

    /// <summary>
    ///  Gets the module's constants that its instructions address memory through, such as a zero-page equate that
    ///  <c>STA CH</c> stores to, with the CPU whose instructions do, so a memory view can name those bytes.
    /// </summary>
    IEnumerable<(string Name, long Value, IsaDescription Cpu)> AddressConstants => [];

    /// <summary>
    ///  Gets whether memory holds the module's code now, so its <see cref="AddressConstants"/> name what it uses: a
    ///  card's firmware is not there without the card, nor a ROM with RAM mapped over it.
    /// </summary>
    /// <param name="memory">The machine's memory.</param>
    /// <returns>Whether any of its code is in memory.</returns>
    bool InMemory(IDebugMemory memory) => true;

    /// <summary>
    ///  Gets where the statements the module makes data, such as <c>.byte</c>, start, which positions describe.
    /// </summary>
    IEnumerable<ushort> DataStatements => [];

    /// <summary>
    ///  Gets whether the module's label for an address applies to memory now, where the module itself does.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   By default a label applies where memory holds the code the module describes, so a program's labels go once
    ///   other code replaces it.
    ///  </para>
    /// </remarks>
    /// <param name="memory">The machine's memory, for reading the bytes at the address.</param>
    /// <param name="address">The CPU address.</param>
    /// <returns>True when the label names what is at the address now.</returns>
    bool LabelApplies(IDebugMemory memory, ushort address) => Position(memory, address) is not null;

    /// <summary>
    ///  Gets the documentation comments of the module's sources, with its symbol values.
    /// </summary>
    DocumentationSet Documentation { get; }
}
