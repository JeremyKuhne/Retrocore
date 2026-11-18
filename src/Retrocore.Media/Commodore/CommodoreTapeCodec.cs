// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Commodore;

/// <summary>
///  Writes a Commodore tape as a TAP image, which holds every pulse to the microsecond up to about 16.8 seconds, or a
///  WAV file, whose pulses are rounded to its samples. Neither keeps the record tab; each lists what it cannot hold.
/// </summary>
/// <param name="format"><c>TAP</c> or <c>WAV</c>.</param>
public sealed class CommodoreTapeCodec(string format = "TAP") : IImageCodec
{
    /// <inheritdoc/>
    public string Format { get; } = format is "TAP" or "WAV"
        ? format
        : throw new ArgumentException("A Commodore tape is written as TAP or WAV.", nameof(format));

    /// <summary>
    ///  Reads a tape image, TAP or WAV, by its contents.
    /// </summary>
    /// <param name="image">The file's bytes.</param>
    /// <returns>The tape, and the codec that writes it back.</returns>
    /// <exception cref="InvalidDataException">The file is neither.</exception>
    public static (CommodoreTape Tape, CommodoreTapeCodec Codec) Load(ReadOnlySpan<byte> image)
    {
        if (TapFormat.IsTap(image)) { return (TapFormat.Read(image), new("TAP")); }
        if (CommodoreWave.IsWave(image)) { return (CommodoreWave.Read(image), new("WAV")); }
        throw new InvalidDataException("The file is neither a TAP image nor a WAV recording.");
    }

    /// <inheritdoc/>
    public EncodedImage Encode(MediumSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        if (snapshot.Kind != CommodoreTape.SnapshotKind)
        {
            throw new ArgumentException($"A {Format} image holds a Commodore tape, not a {snapshot.Kind} snapshot.", nameof(snapshot));
        }

        // Neither format keeps a record tab, as bare block images keep no lock.
        CommodoreTape tape = CommodoreTape.FromSnapshot(snapshot.Image.Span);
        if (Format == "WAV")
        {
            return new(CommodoreWave.Write(tape.Pulses), ["Each pulse's length, to the nearest 1/44,100 second."]);
        }

        int longer = 0;
        foreach (int pulse in tape.Pulses) { if (pulse > TapFormat.LongestPulse) { longer++; } }
        return new(TapFormat.Write(tape.Pulses), longer == 0
            ? []
            : [$"{longer} pause{(longer == 1 ? "" : "s")} longer than {TapFormat.LongestPulse / 1e6:0.######} s, the longest "
                + $"a TAP image holds, shortened to that."]);
    }
}
