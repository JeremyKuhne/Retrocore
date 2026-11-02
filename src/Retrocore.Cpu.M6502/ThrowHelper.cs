// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.ComponentModel;

namespace Retrocore;

/// <summary>
///  Helpers for reporting invalid arguments.
/// </summary>
internal static class ThrowHelper
{
    /// <summary>
    ///  Throws for an invalid enumeration argument.
    /// </summary>
    /// <typeparam name="T">The enumeration type.</typeparam>
    /// <param name="argument">The invalid value.</param>
    /// <param name="paramName">The argument name.</param>
    [DoesNotReturn]
    public static void ThrowInvalidEnum<T>(T argument, [CallerArgumentExpression(nameof(argument))] string? paramName = null)
        where T : struct, Enum
    {
        ThrowInvalidEnum(paramName, argument, typeof(T));
    }

    [DoesNotReturn]
    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void ThrowInvalidEnum<T>(string? paramName, T value, Type type)
        where T : struct, Enum
    {
        throw new InvalidEnumArgumentException(paramName, (int)(long)(object)value, type);
    }
}
