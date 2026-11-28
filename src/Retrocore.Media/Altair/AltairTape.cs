// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Altair;

/// <summary>
///  An Altair cassette tape: the bytes the 88-ACR sends and receives, in order, as a TAP image holds them.
/// </summary>
/// <remarks>
///  <para>
///   The 88-ACR is a serial port with a modem between it and the recorder, so the tape is its bytes and nothing else:
///   a recording appends each byte as the port sends it, and the tape's snapshot is its TAP image.
///  </para>
/// </remarks>
public sealed class AltairTape : IMedium
{
    /// <summary>
    ///  The <see cref="MediumSnapshot.Kind"/> of a tape's snapshot, whose image is a TAP file.
    /// </summary>
    public const string SnapshotKind = "altair-tap";

    private readonly List<byte> _bytes;
    private bool _writeProtected;

    /// <summary>
    ///  Creates a blank tape.
    /// </summary>
    public AltairTape() => _bytes = [];

    /// <summary>
    ///  Creates a tape of a TAP image's bytes.
    /// </summary>
    /// <param name="bytes">The bytes, copied.</param>
    public AltairTape(ReadOnlySpan<byte> bytes) => _bytes = [.. bytes];

    /// <summary>
    ///  Gets the bytes on the tape.
    /// </summary>
    public IReadOnlyList<byte> Bytes => _bytes;

    /// <inheritdoc/>
    public long Version { get; private set; }

    /// <inheritdoc/>
    public bool IsDirty { get; private set; }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   TAP keeps no record tab, so the lock lasts only as long as the session.
    ///  </para>
    /// </remarks>
    public bool IsWriteProtected
    {
        get => _writeProtected;
        set
        {
            if (value == _writeProtected) { return; }
            _writeProtected = value;
            Version++;
        }
    }

    /// <summary>
    ///  Appends a recorded byte.
    /// </summary>
    /// <param name="value">The byte.</param>
    public void Append(byte value)
    {
        _bytes.Add(value);
        Version++;
        IsDirty = true;
    }

    /// <summary>
    ///  Gets the TAP image's bytes.
    /// </summary>
    /// <returns>A copy.</returns>
    public byte[] ToArray() => [.. _bytes];

    /// <inheritdoc/>
    public MediumSnapshot Snapshot() => new(SnapshotKind, Version, _writeProtected, ToArray());

    /// <inheritdoc/>
    public void MarkSaved() => IsDirty = false;

    /// <inheritdoc/>
    public void MarkChanged() => IsDirty = true;
}
