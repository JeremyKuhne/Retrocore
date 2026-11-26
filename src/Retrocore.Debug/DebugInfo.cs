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

    // The modules that may describe each address, in order, found when an address is first looked up: a lookup
    // follows every instruction, and most modules cover few addresses.
    private IDebugModule[]?[]? _covering;

    /// <summary>
    ///  Gets the modules, searched in the order they were added.
    /// </summary>
    internal IReadOnlyList<IDebugModule> Modules => _modules;

    /// <summary>
    ///  Adds a module.
    /// </summary>
    /// <param name="module">The module.</param>
    internal void Add(IDebugModule module)
    {
        _modules.Add(module);
        _covering = null;
    }

    // The modules that cover an address, in the order they were added.
    private IDebugModule[] Covering(ushort address)
    {
        IDebugModule[]?[] covering = _covering ??= new IDebugModule[]?[ushort.MaxValue + 1];
        if (covering[address] is { } found) { return found; }
        List<IDebugModule>? modules = null;
        foreach (IDebugModule module in _modules)
        {
            if (module.Covers(address)) { (modules ??= []).Add(module); }
        }

        return covering[address] = modules is null ? [] : [.. modules];
    }

    /// <summary>
    ///  Gets or sets the launch's hints file, whose names win over the modules' in expressions, as they do when
    ///  disassembling.
    /// </summary>
    internal MemoryHints Hints { get; set; } = MemoryHints.Empty;

    /// <summary>
    ///  Tests whether a module describes the memory an address reads under the current memory map.
    /// </summary>
    /// <param name="module">The module.</param>
    /// <param name="memory">The machine's memory.</param>
    /// <param name="address">The address.</param>
    /// <returns>Whether the module applies.</returns>
    internal static bool Active(IDebugModule module, IDebugMemory memory, ushort address) =>
        module.Area is not { } area || area.Equals(memory.ReadArea(address));

    // Whether a module applies, reading the address's area only for the first module that names one: a lookup
    // searches many modules, and reading the area boxes it.
    private static bool Active(IDebugModule module, IDebugMemory memory, ushort address, ref Enum? read) =>
        module.Area is not { } area || area.Equals(read ??= memory.ReadArea(address));

    /// <summary>
    ///  Gets the source behind an address from the first module that applies to it.
    /// </summary>
    /// <param name="memory">The machine's memory.</param>
    /// <param name="address">The address.</param>
    /// <returns>The position, or null when no module describes the code there.</returns>
    internal DebugPosition? Position(IDebugMemory memory, ushort address)
    {
        Enum? read = null;
        foreach (IDebugModule module in Covering(address))
        {
            if (Active(module, memory, address, ref read) && module.Position(memory, address) is { } position)
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
    ///  <para>
    ///   A name the hints file gives in the space wins, as its names do over the sources' in the listing.
    ///  </para>
    /// </remarks>
    /// <param name="name">The name.</param>
    /// <param name="memory">The machine's memory, or null to take the first module that defines the name.</param>
    /// <param name="space">
    ///  The hints file's space the name is looked for in first: a bank's name, or empty for memory as the CPU maps it.
    /// </param>
    /// <returns>The value.</returns>
    /// <exception cref="FormatException">Neither the hints file nor any module defines the name.</exception>
    internal long Resolve(string name, IDebugMemory? memory = null, string space = "")
    {
        foreach ((int address, string named) in Hints.Names(space))
        {
            if (string.Equals(named, name, StringComparison.Ordinal)) { return address; }
        }

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
        Enum? read = null;
        foreach (IDebugModule module in Covering(address))
        {
            if (Active(module, memory, address, ref read) && module.Position(memory, address) is not null)
            {
                return module.Label(address);
            }
        }

        return null;
    }
}
