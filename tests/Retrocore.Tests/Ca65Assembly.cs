// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;

namespace Retrocore.Tests;

/// <summary>
///  Owned reference output, with symbols read by the debugger's ld65 parser.
/// </summary>
/// <param name="bytes">The linked file bytes.</param>
/// <param name="symbols">The linked labels and constants.</param>
/// <param name="qualifiedSymbols">The scope-preserving symbol values.</param>
internal sealed class Ca65Assembly(byte[] bytes, SymbolTable symbols, IReadOnlyDictionary<string, long> qualifiedSymbols)
{
    /// <summary>
    ///  Gets the linked file bytes, without BSS.
    /// </summary>
    internal byte[] Bytes { get; } = bytes;

    /// <summary>
    ///  Gets the linked debug metadata.
    /// </summary>
    internal SymbolTable Symbols { get; } = symbols;

    /// <summary>
    ///  Gets case-sensitive symbols without collapsing their lexical scopes.
    /// </summary>
    internal IReadOnlyDictionary<string, long> QualifiedSymbols { get; } = qualifiedSymbols;

    /// <summary>
    ///  Requires exact file bytes and a nonempty set of reference symbols.
    /// </summary>
    /// <param name="actualBytes">The assembler's file output.</param>
    /// <param name="actualSymbols">The symbols to compare against ld65.</param>
    internal void AssertMatches(ReadOnlySpan<byte> actualBytes, IReadOnlyDictionary<string, long> actualSymbols)
    {
        Assert.IsNotEmpty(Bytes, "The reference must emit bytes.");
        Assert.IsNotEmpty(actualSymbols, "A differential test must compare symbols as well as bytes.");
        Assert.AreEqual(Bytes.Length, actualBytes.Length, "The linked file lengths differ.");
        for (int offset = 0; offset < Bytes.Length; offset++)
        {
            Assert.AreEqual(Bytes[offset], actualBytes[offset], $"Linked bytes differ at file offset ${offset:X4}.");
        }

        foreach ((string name, long value) in actualSymbols)
        {
            Assert.AreEqual(Symbols.Resolve(name), value, $"Linked symbol '{name}' differs.");
        }
    }
}
