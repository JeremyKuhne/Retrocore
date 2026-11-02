// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Runtime.CompilerServices;

namespace System;

/// <summary>
///  Provides the null guard absent from .NET Standard, using PolySharp's compiler attributes.
/// </summary>
internal static class ArgumentNullExtensions
{
    extension(ArgumentNullException)
    {
        /// <summary>
        ///  Throws when the argument is null.
        /// </summary>
        /// <param name="argument">The reference to validate.</param>
        /// <param name="paramName">The caller's parameter name.</param>
        internal static void ThrowIfNull(
            [NotNull] object? argument,
            [CallerArgumentExpression(nameof(argument))] string? paramName = null)
        {
            if (argument is null)
            {
                throw new ArgumentNullException(paramName);
            }
        }
    }
}
