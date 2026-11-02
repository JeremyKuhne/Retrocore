// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace System.Collections.Generic;

/// <summary>
///  Supplies dictionary insertion absent from the .NET Standard 2.0 reference surface.
/// </summary>
internal static class DictionaryExtensions
{
    /// <summary>
    ///  Adds a key/value pair only when no equivalent key is already present.
    /// </summary>
    /// <typeparam name="TKey">The key type.</typeparam>
    /// <typeparam name="TValue">The value type.</typeparam>
    /// <param name="dictionary">The target dictionary.</param>
    /// <param name="key">The key, compared using the dictionary's own comparer.</param>
    /// <param name="value">The value to insert.</param>
    /// <returns>Whether the new pair was inserted; an existing value is never replaced.</returns>
    internal static bool TryAdd<TKey, TValue>(this Dictionary<TKey, TValue> dictionary, TKey key, TValue value)
        where TKey : notnull
    {
        if (dictionary.ContainsKey(key)) { return false; }
        dictionary.Add(key, value);
        return true;
    }
}
