// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  An anticipated assembly error carrying the diagnostic position used by its current layer.
/// </summary>
/// <remarks>
///  <para>
///   The shared compiler uses model statement indices. Its facade resolves those to source locations;
///   generator adapters then use physical source lines when producing build diagnostics.
///  </para>
/// </remarks>
internal sealed class AssemblyError : Exception
{
    /// <summary>
    ///  Creates an assembly diagnostic.
    /// </summary>
    /// <param name="line">The zero-based model statement index or adapter source line.</param>
    /// <param name="message">The actionable error.</param>
    internal AssemblyError(int line, string message) : base(message) => Line = line;

    /// <summary>
    ///  Gets the model statement index or physical source line expected by the receiving layer.
    /// </summary>
    internal int Line { get; }
}
