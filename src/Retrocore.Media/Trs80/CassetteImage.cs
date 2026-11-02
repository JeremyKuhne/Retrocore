// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Trs80;

/// <summary>
///  A CAS cassette image: the bytes on the tape in order, most significant bit first, leader included.
/// </summary>
/// <remarks>
///  <para>
///   Level II tapes run at 500 baud and Level I tapes at 250; the image itself does not say which.
///  </para>
/// </remarks>
public sealed class CassetteImage
{
    private readonly List<byte> _bytes;

    /// <summary>
    ///  Creates a blank tape.
    /// </summary>
    public CassetteImage() => _bytes = [];

    /// <summary>
    ///  Wraps an image's bytes.
    /// </summary>
    /// <param name="bytes">The bytes, copied.</param>
    public CassetteImage(ReadOnlySpan<byte> bytes) => _bytes = [.. bytes];

    /// <summary>
    ///  Gets the bytes on the tape.
    /// </summary>
    public IReadOnlyList<byte> Bytes => _bytes;

    /// <summary>
    ///  Appends a recorded byte.
    /// </summary>
    /// <param name="value">The byte.</param>
    public void Append(byte value) => _bytes.Add(value);

    /// <summary>
    ///  Gets the file's bytes.
    /// </summary>
    /// <returns>A copy.</returns>
    public byte[] ToArray() => [.. _bytes];
}
