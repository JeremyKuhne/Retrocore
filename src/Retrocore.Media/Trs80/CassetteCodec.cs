// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Trs80;

/// <summary>
///  Writes a TRS-80 or Color Computer tape as a CAS image, the bytes on the tape in order, which is all a
///  <see cref="CassetteImage"/> holds.
/// </summary>
/// <remarks>
///  <para>
///   A tape being recorded is written with the bytes its recorder's held bits make so far, as stopping the recorder
///   would append them (<see cref="CassetteImage.Snapshot"/>). CAS keeps no timing and no record tab.
///  </para>
/// </remarks>
public sealed class CassetteCodec : IImageCodec
{
    /// <summary>
    ///  The image format's name.
    /// </summary>
    public const string Name = "CAS";

    /// <inheritdoc/>
    public string Format => Name;

    /// <inheritdoc/>
    public EncodedImage Encode(MediumSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        if (snapshot.Kind != CassetteImage.SnapshotKind)
        {
            throw new ArgumentException($"A {Name} image holds a cassette tape, not a {snapshot.Kind} snapshot.", nameof(snapshot));
        }

        return new(snapshot.Image.ToArray(), []);
    }
}
