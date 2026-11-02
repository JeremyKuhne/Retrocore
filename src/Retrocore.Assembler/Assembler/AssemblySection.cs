// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  An immutable owned, absolute output region.
/// </summary>
public sealed class AssemblySection
{
    /// <summary>
    ///  Creates a resolved section.
    /// </summary>
    /// <param name="name">The section name.</param>
    /// <param name="origin">The address.</param>
    /// <param name="bytes">Owned emitted storage.</param>
    internal AssemblySection(string name, int origin, byte[] bytes)
        : this(name, origin, origin, bytes.Length, bytes)
    {
    }

    /// <summary>
    ///  Creates a section with independent load, run and memory-size metadata.
    /// </summary>
    /// <param name="name">The section name.</param>
    /// <param name="origin">The load address.</param>
    /// <param name="runOrigin">The initial logical address.</param>
    /// <param name="size">The occupied memory size, including no-output storage.</param>
    /// <param name="bytes">Owned file output.</param>
    internal AssemblySection(string name, int origin, int runOrigin, int size, byte[] bytes)
    {
        Name = name;
        Origin = origin;
        Bytes = bytes;
        RunOrigin = runOrigin;
        Size = size;
    }

    /// <summary>
    ///  Gets the section name: <c>.text</c> for the options' section, or the name a <c>.section</c> declared.
    /// </summary>
    public string Name { get; }

    /// <summary>
    ///  Gets the load address.
    /// </summary>
    public int Origin { get; }

    /// <summary>
    ///  Gets the initial logical CPU address.
    /// </summary>
    public int RunOrigin { get; }

    /// <summary>
    ///  Gets occupied memory size, which may exceed file output size for BSS.
    /// </summary>
    public int Size { get; }

    /// <summary>
    ///  Gets emitted bytes, including declared padding; empty for a no-output section.
    /// </summary>
    public ReadOnlyMemory<byte> Bytes { get; }
}
