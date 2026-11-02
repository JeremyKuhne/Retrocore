// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Tests;

/// <summary>
///  Owned Merlin32 bytes and original source-name symbols.
/// </summary>
/// <param name="bytes">The raw object bytes.</param>
/// <param name="symbols">The emitted symbol values.</param>
internal sealed class MerlinAssembly(byte[] bytes, IReadOnlyDictionary<string, long> symbols)
{
    /// <summary>
    ///  Gets object bytes.
    /// </summary>
    internal byte[] Bytes { get; } = bytes;

    /// <summary>
    ///  Gets original symbol spellings.
    /// </summary>
    internal IReadOnlyDictionary<string, long> Symbols { get; } = symbols;
}
