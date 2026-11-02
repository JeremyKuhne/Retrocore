// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <inheritdoc/>
public sealed partial class Assembler
{
    /// <summary>
    ///  Constructs a native assembler for every instruction set in <see cref="CpuCatalog"/>.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   This runtime-only constructor is excluded from linked generator sources. The generator instead parses
    ///   the same description from its build inputs, avoiding a reference to the assembly it is still generating.
    ///  </para>
    /// </remarks>
    public Assembler() : this(CpuCatalog.InstructionSets) { }
}
