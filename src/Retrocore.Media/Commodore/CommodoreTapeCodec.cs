// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Commodore;

/// <summary>
///  Writes a Commodore tape as a TAP image for the machine that records it, which holds every pulse to the
///  microsecond up to about 16 seconds, or a WAV file, whose pulses are rounded to its samples. Neither keeps the
///  record tab; each lists what it cannot hold.
/// </summary>
public sealed class CommodoreTapeCodec : IImageCodec
{
    /// <summary>
    ///  Creates a codec.
    /// </summary>
    /// <param name="format"><c>TAP</c> or <c>WAV</c>.</param>
    /// <param name="machine">A TAP header's machine byte, such as <see cref="TapFormat.PetMachine"/>.</param>
    /// <param name="video">
    ///  A TAP header's video byte, <see cref="TapFormat.Pal"/> or <see cref="TapFormat.Ntsc"/>.
    /// </param>
    public CommodoreTapeCodec(string format = "TAP", byte machine = TapFormat.PetMachine, byte video = TapFormat.Pal)
    {
        Format = format is "TAP" or "WAV"
            ? format
            : throw new ArgumentException("A Commodore tape is written as TAP or WAV.", nameof(format));

        Machine = machine;
        Video = video;
    }

    /// <inheritdoc/>
    public string Format { get; }

    /// <summary>
    ///  Gets the TAP header's machine byte, whose clock the image counts in.
    /// </summary>
    public byte Machine { get; }

    /// <summary>
    ///  Gets the TAP header's video byte.
    /// </summary>
    public byte Video { get; }

    /// <summary>
    ///  Reads a tape image, TAP or WAV, by its contents.
    /// </summary>
    /// <param name="image">The file's bytes.</param>
    /// <returns>The tape, and the codec that writes it back, for the machine a TAP image names.</returns>
    /// <exception cref="InvalidDataException">The file is neither.</exception>
    public static (CommodoreTape Tape, CommodoreTapeCodec Codec) Load(ReadOnlySpan<byte> image)
    {
        if (TapFormat.IsTap(image)) { return (TapFormat.Read(image), new("TAP", image[13], image[14])); }
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

        int longest = TapFormat.Longest(Machine, Video);
        byte[] image = TapFormat.Write(tape.Pulses, Machine, Video);
        int longer = 0;
        int rounded = 0;
        IReadOnlyList<int> written = TapFormat.Read(image).Pulses;
        for (int i = 0; i < tape.Pulses.Count; i++)
        {
            if (tape.Pulses[i] > longest) { longer++; }
            else if (written[i] != tape.Pulses[i]) { rounded++; }
        }

        List<string> losses = [];
        if (longer != 0)
        {
            losses.Add($"{longer} pause{(longer == 1 ? "" : "s")} longer than {longest / 1e6:0.######} s, the longest "
                + "a TAP image holds, shortened to that.");
        }

        if (rounded != 0)
        {
            losses.Add($"{rounded} pulse{(rounded == 1 ? "" : "s")} rounded to the image's clock cycles.");
        }

        return new(image, losses);
    }
}
