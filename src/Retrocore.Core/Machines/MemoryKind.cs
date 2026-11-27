// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines;

/// <summary>
///  What kind of memory backs an address, as static analysis needs to know it.
/// </summary>
public enum MemoryKind
{
    /// <summary>
    ///  Nothing, or what is not known: a read gets no value the analysis can rely on.
    /// </summary>
    None,

    /// <summary>
    ///  Memory a program writes and reads back, including video memory.
    /// </summary>
    Ram,

    /// <summary>
    ///  Memory that reads the same bytes whatever is written to it.
    /// </summary>
    Rom,

    /// <summary>
    ///  Devices: a read may differ from what was written and may have side effects.
    /// </summary>
    Io
}
