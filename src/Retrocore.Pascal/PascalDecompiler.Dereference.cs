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

        /// <summary>
        ///  Gets the type of its own that what a word points to has here, where the code reads it as what its other
        ///  dereferences cannot be, bits where they are bytes or the other way round: a word used both ways has it as
        ///  another variant's pointer.
        /// </summary>
        public TypeNode? View { get; private set; }

        /// <summary>
        ///  Gives what the pointer points to here a type of its own: one of the word's other views that can be it, or a
        ///  new one, which the word keeps.
        /// </summary>
        /// <param name="fits">Whether one of the word's views can be it.</param>
        /// <returns>The view.</returns>
        public TypeNode Split(Func<TypeNode, bool> fits)
        {
            TypeNode word = Pointer.Type.Find();
            word.Views ??= [];
            View = word.Views.FirstOrDefault(fits);
            if (View is null)
            {
                View = new TypeNode();
                word.Views.Add(View);
            }

            return View;
        }

        /// <inheritdoc/>
        /// <remarks>
        ///  <para>
        ///   What the pointer points to now: a thing it pointed to may since have become a record's first field.
        ///  </para>
        /// </remarks>
        public override TypeNode Type => View?.Find() ?? Pointed();

        private TypeNode Pointed() =>
            Pointer.Type.Find() is { Kind: TypeKind.Pointer, Element: { } element } ? element : _target;
    }
}
