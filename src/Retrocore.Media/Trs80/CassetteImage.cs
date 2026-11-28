// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Trs80;

/// <summary>
///  A CAS cassette image: the bytes on the tape in order, most significant bit first, leader included.
/// </summary>
/// <remarks>
///  <para>
///   Level II tapes run at 500 baud and Level I tapes at 250; the image itself does not say which, though its first
///   recording's header shows which BASIC wrote it (<see cref="CassetteFormat"/>). The Color Computer's tapes are CAS
///   too, at 1500 baud, least significant bit first.
///  </para>
///  <para>
///   A tape is a medium: what a recorder records onto it is a change, saved like a disk's. A recorder that holds bits
///   until the motor stops, as the TRS-80's does, says so as it hears each (<see cref="Heard"/>), and its
///   <see cref="Recorder"/> gives the bytes they make, which the snapshot adds without the recorder stopping.
///  </para>
/// </remarks>
public sealed class CassetteImage : IMedium
{
    /// <summary>
    ///  The <see cref="MediumSnapshot.Kind"/> of a tape's snapshot, whose image is a CAS file.
    /// </summary>
    public const string SnapshotKind = "cas";

    private readonly List<byte> _bytes;
    private bool _writeProtected;

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
    ///  Gets the bytes on the tape, without those a recorder still holds.
    /// </summary>
    public IReadOnlyList<byte> Bytes => _bytes;

    /// <inheritdoc/>
    public long Version { get; private set; }

    /// <inheritdoc/>
    public bool IsDirty { get; private set; }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   CAS keeps no record tab, so the lock lasts only as long as the session.
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
    ///  Gets or sets the recorder recording onto the tape that holds bits it has not yet appended, or null.
    /// </summary>
    public ICassetteRecorder? Recorder { get; set; }

    /// <summary>
    ///  Appends a recorded byte.
    /// </summary>
    /// <param name="value">The byte.</param>
    public void Append(byte value)
    {
        _bytes.Add(value);
        Changed();
    }

    /// <summary>
    ///  Records that the recorder heard a bit it holds, which changes the tape though no byte is appended yet.
    /// </summary>
    public void Heard() => Changed();

    /// <summary>
    ///  Gets the file's bytes, without those a recorder still holds.
    /// </summary>
    /// <returns>A copy.</returns>
    public byte[] ToArray() => [.. _bytes];

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The image is the CAS file with the bytes the recorder's held bits make, as stopping it now would append them;
    ///   the recorder keeps them, so the machine sees nothing of it.
    ///  </para>
    /// </remarks>
    public MediumSnapshot Snapshot()
    {
        IReadOnlyList<byte> held = Recorder?.Buffered() ?? [];
        byte[] image = new byte[_bytes.Count + held.Count];
        _bytes.CopyTo(image);
        for (int i = 0; i < held.Count; i++) { image[_bytes.Count + i] = held[i]; }
        return new(SnapshotKind, Version, _writeProtected, image);
    }

    /// <inheritdoc/>
    public void MarkSaved() => IsDirty = false;

    /// <inheritdoc/>
    public void MarkChanged() => IsDirty = true;

    private void Changed()
    {
        Version++;
        IsDirty = true;
    }
}
