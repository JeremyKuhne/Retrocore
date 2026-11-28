// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers;
using System.Globalization;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Unicode;
using Touki.Text;

namespace Retrocore.Debug;

/// <summary>
///  The wire both the Debug Adapter Protocol and the Language Server Protocol use: each message is a
///  <c>Content-Length</c> header, a blank line, and that many bytes of UTF-8 JSON.
/// </summary>
/// <remarks>
///  <para>
///   Messages are read from one thread. Writes may come from any thread; each goes out whole, through a buffer that is
///   kept, so a large message costs no allocation once the buffer has grown to fit it.
///  </para>
/// </remarks>
/// <param name="input">Where messages arrive, such as standard input.</param>
/// <param name="output">Where messages go, such as standard output.</param>
/// <param name="read">An optional cancellable read for the transport.</param>
internal sealed class MessageFraming(Stream input, Stream output, Func<Memory<byte>, CancellationToken, int>? read = null)
{
    private const string LengthHeader = "Content-Length";

    // Base64's + and text such as the Model I's block characters stay as they are: the JSON goes to VS Code, not
    // into HTML.
    private static readonly JsonWriterOptions s_writerOptions = new()
    {
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    private readonly ArrayBufferWriter<byte> _buffer = new();
    private readonly Lock _write = new();
    private readonly byte[] _inputBytes = new byte[4096];
    private int _inputStart;
    private int _inputEnd;

    /// <summary>
    ///  Reads the next message.
    /// </summary>
    /// <param name="cancellation">Cancels a transport read.</param>
    /// <returns>The message, or null at the end of the input.</returns>
    /// <exception cref="JsonException">The message is not a JSON object; the next one can still be read.</exception>
    internal JsonObject? Read(CancellationToken cancellation = default)
    {
        int? length = null;
        while (ReadLine(cancellation) is { } line)
        {
            if (line.Length == 0)
            {
                if (length is not { } count) { continue; }
                byte[] json = new byte[count];
                int copied = 0;
                while (copied < count)
                {
                    if (!Fill(cancellation)) { return null; }
                    int take = Math.Min(count - copied, _inputEnd - _inputStart);
                    _inputBytes.AsSpan(_inputStart, take).CopyTo(json.AsSpan(copied));
                    _inputStart += take;
                    copied += take;
                }

                // A message that is JSON but not an object has nothing to answer, as one that is not JSON.
                return JsonNode.Parse(json) as JsonObject ?? throw new JsonException("The message is not a JSON object.");
            }

            int colon = line.IndexOf(':', StringComparison.Ordinal);
            if (colon > 0 && line[..colon].Trim().Equals(LengthHeader, StringComparison.OrdinalIgnoreCase))
            {
                length = int.Parse(line[(colon + 1)..].Trim(), NumberStyles.None, CultureInfo.InvariantCulture);
            }
        }

        return null;
    }

    /// <summary>
    ///  Writes a message, from any thread.
    /// </summary>
    /// <param name="message">The message.</param>
    internal void Write(JsonNode message) => Write(writer => message.WriteTo(writer));

    /// <summary>
    ///  Writes a message straight to the wire, from any thread; nothing else is written between its parts.
    /// </summary>
    /// <param name="writeMessage">Writes the message: one JSON value.</param>
    internal void Write(Action<Utf8JsonWriter> writeMessage)
    {
        lock (_write)
        {
            _buffer.ResetWrittenCount();
            using (Utf8JsonWriter writer = new(_buffer, s_writerOptions))
            {
                writeMessage(writer);
            }

            ReadOnlySpan<byte> json = _buffer.WrittenSpan;
            Span<byte> header = stackalloc byte[64];
            Utf8.TryWrite(header, CultureInfo.InvariantCulture, $"{LengthHeader}: {json.Length}\r\n\r\n", out int length);
            output.Write(header[..length]);
            output.Write(json);
            output.Flush();
        }
    }

    // A header line without its line ending, or null at the end of the input.
    private string? ReadLine(CancellationToken cancellation)
    {
        using ValueStringBuilder line = new(stackalloc char[64]);
        while (Fill(cancellation))
        {
            int next = _inputBytes[_inputStart++];
            if (next == '\n') { return line.ToString().TrimEnd('\r'); }
            line.Append((char)next);
        }

        return line.Length == 0 ? null : line.ToString();
    }

    private bool Fill(CancellationToken cancellation)
    {
        if (_inputStart < _inputEnd) { return true; }
        cancellation.ThrowIfCancellationRequested();
        _inputStart = 0;
        _inputEnd = read is null ? input.Read(_inputBytes) : read(_inputBytes, cancellation);
        return _inputEnd != 0;
    }
}
