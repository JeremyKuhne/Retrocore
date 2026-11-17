// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A string expression the compiler builds in a temporary: CONCAT or COPY.
    /// </summary>
    /// <param name="name">The function's name.</param>
    /// <param name="arguments">Its arguments.</param>
    private sealed class StringFunction(string name, List<Expr> arguments) : Expr
    {
        /// <summary>
        ///  Gets the function's name.
        /// </summary>
        public string Name { get; } = name;

        /// <summary>
        ///  Gets its arguments.
        /// </summary>
        public List<Expr> Arguments { get; } = arguments;

        /// <inheritdoc/>
        public override TypeNode Type { get; } = TypeNode.Of(TypeKind.String);
    }
}
