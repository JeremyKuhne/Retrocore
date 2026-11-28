// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;

namespace Retrocore.Machines.Trs80Model100;

/// <summary>
///  Writes a Model 100 tape as a 16-bit mono WAV file at 44.1 kHz, which rounds each half cycle to its samples.
/// </summary>
/// <remarks>
///  <para>
///   The rounding is within a sample, about 56 cycles, of half cycles of 512 and 1024 that the ROM tells apart, so
///   CLOAD reads a saved recording as it read the tape: the save is guest-equivalent and says so as a note, not a
///   loss. The recovery journal keeps the level and half cycles themselves (<see cref="Trs80Model100Tape.SnapshotKind"/>).
///  </para>
/// </remarks>
public sealed class Trs80Model100TapeCodec : IImageCodec
{
    /// <summary>
    ///  The image format's name.
    /// </summary>
    public const string Name = "WAV";

    /// <inheritdoc/>
    public string Format => Name;

    /// <inheritdoc/>
    public EncodedImage Encode(MediumSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        if (snapshot.Kind != Trs80Model100Tape.SnapshotKind)
        {
            throw new ArgumentException($"A {Name} file holds a Model 100 tape here, not a {snapshot.Kind} snapshot.", nameof(snapshot));
        }

        return new(Trs80Model100Tape.FromSnapshot(snapshot.Image.Span).ToWave(), [])
        {
            Notes = ["Each change of level moves to the start of its 1/44,100 s sample, which the ROM reads the same."]
        };
    }
}
