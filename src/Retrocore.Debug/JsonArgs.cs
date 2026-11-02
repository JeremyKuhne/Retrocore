// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

/// <summary>
///  Reads request arguments, converting as the debug host always has: a number written as a string reads as the
///  number, and a missing or null value reads as null.
/// </summary>
/// <remarks>
///  <para>
///   System.Text.Json's own <see cref="JsonNode.GetValue{T}"/> throws when a value's JSON type differs, where a launch
///   configuration may well say <c>"16"</c> for 16; these keep that working.
///  </para>
/// </remarks>
internal static class JsonArgs
{
    /// <summary>
    ///  Reads a string: text as it is, a number or boolean as its JSON text.
    /// </summary>
    /// <param name="node">The object, or null.</param>
    /// <param name="name">The property.</param>
    /// <returns>The value, or null when it is missing or null.</returns>
    /// <exception cref="ArgumentException">The value is an object or array.</exception>
    internal static string? String(this JsonNode? node, string name) => Scalar(node, name) switch
    {
        null => null,
        { } value when value.GetValueKind() == JsonValueKind.String => value.GetValue<string>(),
        { } value when value.GetValueKind() is JsonValueKind.Number or JsonValueKind.True or JsonValueKind.False =>
            value.ToJsonString(),
        _ => throw new ArgumentException($"{name} must be a string.")
    };

    /// <summary>
    ///  Reads a whole number, from a JSON number or a string holding one.
    /// </summary>
    /// <param name="node">The object, or null.</param>
    /// <param name="name">The property.</param>
    /// <returns>The value, or null when it is missing or null.</returns>
    /// <exception cref="ArgumentException">The value is not a whole number that fits.</exception>
    internal static int? Int(this JsonNode? node, string name) => Long(node, name) switch
    {
        null => null,
        >= int.MinValue and <= int.MaxValue and var value => (int)value,
        _ => throw new ArgumentException($"{name} is out of range.")
    };

    /// <summary>
    ///  Reads a whole number, from a JSON number or a string holding one.
    /// </summary>
    /// <param name="node">The object, or null.</param>
    /// <param name="name">The property.</param>
    /// <returns>The value, or null when it is missing or null.</returns>
    /// <exception cref="ArgumentException">The value is not a whole number.</exception>
    internal static long? Long(this JsonNode? node, string name)
    {
        if (Scalar(node, name) is not { } value) { return null; }

        // A number is read from its JSON text, as a value built in code from an int will not give itself up as a
        // long. A whole number written with a fraction or exponent, such as 16.0, still reads as one.
        string? text = value.GetValueKind() switch
        {
            JsonValueKind.Number => value.ToJsonString(),
            JsonValueKind.String => value.GetValue<string>(),
            _ => null
        };

        if (long.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out long number)) { return number; }
        if (double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out double real)
            && real == Math.Floor(real)
            && real is >= long.MinValue and <= long.MaxValue)
        {
            return (long)real;
        }

        throw new ArgumentException($"{name} must be a whole number.");
    }

    /// <summary>
    ///  Reads a number, from a JSON number or a string holding one.
    /// </summary>
    /// <param name="node">The object, or null.</param>
    /// <param name="name">The property.</param>
    /// <returns>The value, or null when it is missing or null.</returns>
    /// <exception cref="ArgumentException">The value is not a number.</exception>
    internal static double? Double(this JsonNode? node, string name)
    {
        if (Scalar(node, name) is not { } value) { return null; }
        string? text = value.GetValueKind() switch
        {
            JsonValueKind.Number => value.ToJsonString(),
            JsonValueKind.String => value.GetValue<string>(),
            _ => null
        };

        if (double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out double parsed))
        {
            return parsed;
        }

        throw new ArgumentException($"{name} must be a number.");
    }

    /// <summary>
    ///  Reads a boolean, from JSON true or false or a string holding one.
    /// </summary>
    /// <param name="node">The object, or null.</param>
    /// <param name="name">The property.</param>
    /// <returns>The value, or null when it is missing or null.</returns>
    /// <exception cref="ArgumentException">The value is not a boolean.</exception>
    internal static bool? Bool(this JsonNode? node, string name)
    {
        if (Scalar(node, name) is not { } value) { return null; }
        return value.GetValueKind() switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            JsonValueKind.String when bool.TryParse(value.GetValue<string>(), out bool parsed) => parsed,
            _ => throw new ArgumentException($"{name} must be true or false.")
        };
    }

    /// <summary>
    ///  Gets an object property.
    /// </summary>
    /// <param name="node">The object, or null.</param>
    /// <param name="name">The property.</param>
    /// <returns>The object, or null when it is missing or not an object.</returns>
    internal static JsonObject? Object(this JsonNode? node, string name) => (node as JsonObject)?[name] as JsonObject;

    /// <summary>
    ///  Gets an array property.
    /// </summary>
    /// <param name="node">The object, or null.</param>
    /// <param name="name">The property.</param>
    /// <returns>The array, or null when it is missing or not an array.</returns>
    internal static JsonArray? Array(this JsonNode? node, string name) => (node as JsonObject)?[name] as JsonArray;

    // A property's value when it is a scalar: null when the node is not an object, or the value is missing or null.
    private static JsonValue? Scalar(JsonNode? node, string name) => (node as JsonObject)?[name] switch
    {
        null => null,
        JsonValue value when value.GetValueKind() == JsonValueKind.Null => null,
        JsonValue value => value,
        _ => throw new ArgumentException($"{name} must be a value, not an object or array.")
    };
}
