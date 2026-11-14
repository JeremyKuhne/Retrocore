// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  What a pointer points to; for a VAR parameter, what it stands for.
    /// </summary>
    /// <param name="pointer">The pointer.</param>
    private sealed class Dereference(Expr pointer) : Designator
    {
        /// <summary>
        ///  Gets the pointer.
        /// </summary>
        public Expr Pointer { get; } = pointer;

        private readonly TypeNode _target = pointer.Type.Target();

        /// <inheritdoc/>
        /// <remarks>
        ///  <para>
        ///   What the pointer points to now: a thing it pointed to may since have become a record's first field.
        ///  </para>
        /// </remarks>
        public override TypeNode Type =>
            Pointer.Type.Find() is { Kind: TypeKind.Pointer, Element: { } element } ? element : _target;
    }
}
