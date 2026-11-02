// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug;

/// <summary>
///  Builds JSON arrays from sequences without reflection, so the debug host can be compiled ahead of time: each
///  overload converts its element type the way <see cref="JsonNode"/>'s implicit conversions do.
/// </summary>
internal static class JsonNodes
{
    /// <summary>
    ///  Makes an array of nodes.
    /// </summary>
    /// <param name="items">The nodes, each not yet in another tree.</param>
    /// <returns>The array.</returns>
    internal static JsonArray ToJsonArray(this IEnumerable<JsonNode?> items) => [.. items];

    /// <summary>
    ///  Makes an array of strings.
    /// </summary>
    /// <param name="items">The strings.</param>
    /// <returns>The array.</returns>
    internal static JsonArray ToJsonArray(this IEnumerable<string?> items) => [.. items.Select(item => (JsonNode?)item)];

    /// <summary>
    ///  Makes an array of numbers.
    /// </summary>
    /// <param name="items">The numbers.</param>
    /// <returns>The array.</returns>
    internal static JsonArray ToJsonArray(this IEnumerable<int> items) => [.. items.Select(item => (JsonNode?)item)];

    /// <summary>
    ///  Makes an array of numbers.
    /// </summary>
    /// <param name="items">The numbers.</param>
    /// <returns>The array.</returns>
    internal static JsonArray ToJsonArray(this IEnumerable<long> items) => [.. items.Select(item => (JsonNode?)item)];
}
