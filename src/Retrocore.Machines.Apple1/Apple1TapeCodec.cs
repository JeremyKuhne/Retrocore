// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;

namespace Retrocore.Machines.Apple1;

/// <summary>
///  Writes an Apple-1 tape as a 16-bit mono WAV file at 44.1 kHz, which moves each change of level to its sample.
/// </summary>
/// <remarks>
///  <para>
///   The rounding is within a sample, about 23 cycles, of half cycles that the ACI tells apart by hundreds, so the R
///   command reads a saved recording as it read the tape: the save is guest-equivalent and says so as a note, not a
///   loss. The recovery journal keeps the half cycles themselves (<see cref="Apple1Tape.SnapshotKind"/>).
///  </para>
/// </remarks>
public sealed class Apple1TapeCodec : IImageCodec
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
        if (snapshot.Kind != Apple1Tape.SnapshotKind)
        {
            throw new ArgumentException($"A {Name} file holds an Apple-1 tape here, not a {snapshot.Kind} snapshot.", nameof(snapshot));
        }

        return new(Apple1Tape.FromSnapshot(snapshot.Image.Span).ToWave(), [])
        {
            Notes = ["Each change of level moves to the start of its 1/44,100 s sample, which the ACI reads the same."]
        };
    }
}
