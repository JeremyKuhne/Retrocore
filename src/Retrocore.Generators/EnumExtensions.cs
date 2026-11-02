// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace System;

/// <summary>
///  Supplies generic enum validation only to the .NET Standard generator compilation.
/// </summary>
internal static class EnumExtensions
{
    extension(Enum)
    {
        /// <summary>
        ///  Determines whether the enum declares a constant with the specified value.
        /// </summary>
        /// <typeparam name="TEnum">The enum type.</typeparam>
        /// <param name="value">The value to check.</param>
        /// <returns>Whether the value is a declared enum constant.</returns>
        internal static bool IsDefined<TEnum>(TEnum value)
            where TEnum : struct, Enum => Enum.IsDefined(typeof(TEnum), value);
    }
}
