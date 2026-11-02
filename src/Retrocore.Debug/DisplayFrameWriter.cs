// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

/// <summary>
///  Writes a <c>retro/frame</c> body as UTF-8 JSON, with the video's pixels encoded as base64 straight from their
///  bytes, so a frame needs no string or JSON object the size of its picture.
/// </summary>
internal static class DisplayFrameWriter
{
    private const string Video = "video";
    private const string Pixels = "pixels";

    /// <summary>
    ///  Writes the frame: the display state as it is, with <c>video.pixels</c> added when there are pixels.
    /// </summary>
    /// <param name="writer">Where the body goes.</param>
    /// <param name="state">The display state, without pixels.</param>
    /// <param name="pixels">
    ///  The video's RGBA pixels, or none when the picture has not changed since the last frame sent.
    /// </param>
    internal static void Write(Utf8JsonWriter writer, JsonObject state, ReadOnlySpan<byte> pixels)
    {
        writer.WriteStartObject();
        foreach ((string name, JsonNode? value) in state)
        {
            if (name != Video || value is not JsonObject video)
            {
                Property(writer, name, value);
                continue;
            }

            writer.WriteStartObject(Video);
            foreach ((string part, JsonNode? partValue) in video) { Property(writer, part, partValue); }
            if (!pixels.IsEmpty) { writer.WriteBase64String(Pixels, pixels); }
            writer.WriteEndObject();
        }

        writer.WriteEndObject();
    }

    // The small parts of the frame, as they are.
    private static void Property(Utf8JsonWriter writer, string name, JsonNode? value)
    {
        writer.WritePropertyName(name);
        if (value is null)
        {
            writer.WriteNullValue();
        }
        else
        {
            value.WriteTo(writer);
        }
    }
}
