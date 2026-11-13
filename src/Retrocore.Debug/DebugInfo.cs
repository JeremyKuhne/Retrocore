// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  The debug modules of a session: the program and the SDK's ROM sources, each tied to the memory it runs from.
/// </summary>
internal sealed class DebugInfo
{
    private readonly List<IDebugModule> _modules = [];

    /// <summary>
    ///  Gets the modules, searched in the order they were added.
    /// </summary>
    internal IReadOnlyList<IDebugModule> Modules => _modules;

    /// <summary>
    ///  Adds a module.
    /// </summary>
    /// <param name="module">The module.</param>
    internal void Add(IDebugModule module) => _modules.Add(module);

    /// <summary>
    ///  Tests whether a module describes the memory an address reads under the current memory map.
    /// </summary>
    /// <param name="module">The module.</param>
    /// <param name="memory">The machine's memory.</param>
    /// <param name="address">The address.</param>
    /// <returns>Whether the module applies.</returns>
    internal static bool Active(IDebugModule module, IDebugMemory memory, ushort address) =>
        module.Area is not { } area || area.Equals(memory.ReadArea(address));

    /// <summary>
    ///  Gets the source behind an address from the first module that applies to it.
    /// </summary>
    /// <param name="memory">The machine's memory.</param>
    /// <param name="address">The address.</param>
    /// <returns>The position, or null when no module describes the code there.</returns>
    internal DebugPosition? Position(IDebugMemory memory, ushort address)
    {
        foreach (IDebugModule module in _modules)
        {
            if (Active(module, memory, address) && module.Position(memory, address) is { } position)
            {
                return position;
            }
        }

        return null;
    }

    /// <summary>
    ///  Resolves a symbol: from the first module whose code is where the symbol names, installed and mapped, else from
    ///  the first module that defines it.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A card's firmware that works in any slot is a module for each slot, so its routines resolve to the slot the
    ///   card is in.
    ///  </para>
    /// </remarks>
    /// <param name="name">The name.</param>
    /// <param name="memory">The machine's memory, or null to take the first module that defines the name.</param>
    /// <returns>The value.</returns>
    /// <exception cref="FormatException">No module defines the name.</exception>
    internal long Resolve(string name, IDebugMemory? memory = null)
    {
        long? first = null;
        foreach (IDebugModule module in _modules)
        {
            if (!module.TryResolve(name, out long value)) { continue; }
            if (memory is null) { return value; }
            first ??= value;
            if (value is >= 0 and <= ushort.MaxValue
                && Active(module, memory, (ushort)value)
                && module.Position(memory, (ushort)value) is not null)
            {
                return value;
            }
        }

        return first ?? throw new FormatException($"Unknown label '{name}'.");
    }

    /// <summary>
    ///  Gets the closest preceding label from the module that applies at an address.
    /// </summary>
    /// <param name="memory">The machine's memory.</param>
    /// <param name="address">The address.</param>
    /// <returns>The label, or null.</returns>
    internal string? Label(IDebugMemory memory, ushort address)
    {
        foreach (IDebugModule module in _modules)
        {
            if (Active(module, memory, address) && module.Position(memory, address) is not null)
            {
                return module.Label(address);
            }
        }

        return null;
    }
}
