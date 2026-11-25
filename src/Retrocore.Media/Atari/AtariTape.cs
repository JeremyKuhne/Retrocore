// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers.Binary;
using System.Text;

namespace Retrocore.Media.Atari;

/// <summary>
///  An Atari cassette as the 410 recorder's data line sees it: records of bytes, each after a gap of steady mark tone,
///  at a baud rate, and runs of raw tone for what isn't bytes, as <c>.cas</c> files hold them.
/// </summary>
/// <remarks>
///  <para>
///   A <c>.cas</c> file is chunks of a four-character type, a 16-bit length and a 16-bit auxiliary value, all little
///   endian, then the data. <c>FUJI</c> holds a description; <c>baud</c> sets the rate for the records after it (aux);
///   <c>data</c> is a record, aux the gap before it in milliseconds; <c>fsk </c> is raw tone, aux the gap before it and
///   the data 16-bit durations in tenths of a millisecond of alternating space and mark, space first. The 410
///   decodes the tones, mark (5,327 Hz) to a 1 and space (3,995 Hz) to a 0, and each byte is a 0 start bit, the
///   eight bits low first, and a 1 stop bit.
///  </para>
/// </remarks>
public sealed class AtariTape : IMedium
{
    /// <summary>
    ///  The snapshot kind: the tape as a <c>.cas</c> file.
    /// </summary>
    public const string SnapshotKind = "atari-tape";

    /// <summary>
    ///  The standard baud rate, 600.
    /// </summary>
    public const int StandardBaud = 600;

    private readonly List<AtariTapeBlock> _blocks;
    private bool _writeProtected;

    /// <summary>
    ///  Constructs a tape.
    /// </summary>
    /// <param name="blocks">The blocks, in order.</param>
    /// <param name="description">The <c>FUJI</c> description.</param>
    public AtariTape(IEnumerable<AtariTapeBlock>? blocks = null, string description = "")
    {
        _blocks = [.. blocks ?? []];
        Description = description;
    }

    /// <summary>
    ///  Gets the blocks.
    /// </summary>
    public IReadOnlyList<AtariTapeBlock> Blocks => _blocks;

    /// <summary>
    ///  Gets or sets the description in the <c>FUJI</c> chunk.
    /// </summary>
    public string Description { get; set; }

    /// <inheritdoc/>
    public long Version { get; private set; }

    /// <summary>
    ///  Gets whether recording has changed the tape since it was loaded or last saved.
    /// </summary>
    public bool IsDirty { get; private set; }

    /// <inheritdoc/>
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
    ///  Gets the tape's length in seconds.
    /// </summary>
    public double Duration => _blocks.Sum(block => block.Duration);

    /// <summary>
    ///  Reads a <c>.cas</c> file.
    /// </summary>
    /// <param name="image">The file.</param>
    /// <returns>The tape.</returns>
    /// <exception cref="InvalidDataException">The file isn't a <c>.cas</c>.</exception>
    public static AtariTape Load(ReadOnlySpan<byte> image)
    {
        if (image.Length < 8 || !image[..4].SequenceEqual("FUJI"u8))
        {
            throw new InvalidDataException("A .cas file starts with a FUJI chunk.");
        }

        List<AtariTapeBlock> blocks = [];
        string description = "";
        int baud = StandardBaud;
        int offset = 0;
        while (offset + 8 <= image.Length)
        {
            ReadOnlySpan<byte> type = image.Slice(offset, 4);
            int length = BinaryPrimitives.ReadUInt16LittleEndian(image[(offset + 4)..]);
            int aux = BinaryPrimitives.ReadUInt16LittleEndian(image[(offset + 6)..]);
            offset += 8;
            if (offset + length > image.Length) { throw new InvalidDataException("A .cas chunk runs past the end."); }
            ReadOnlySpan<byte> data = image.Slice(offset, length);
            offset += length;
            if (type.SequenceEqual("FUJI"u8))
            {
                description = Encoding.Latin1.GetString(data);
            }
            else if (type.SequenceEqual("baud"u8))
            {
                if (aux != 0) { baud = aux; }
            }
            else if (type.SequenceEqual("data"u8))
            {
                blocks.Add(new(aux, baud, data.ToArray(), Durations: null));
            }
            else if (type.SequenceEqual("fsk "u8))
            {
                ushort[] durations = new ushort[length / 2];
                for (int i = 0; i < durations.Length; i++)
                {
                    durations[i] = BinaryPrimitives.ReadUInt16LittleEndian(data[(i * 2)..]);
                }

                blocks.Add(new(aux, baud, [], durations));
            }
        }

        return new(blocks, description);
    }

    /// <summary>
    ///  Writes the tape as a <c>.cas</c> file, with a <c>baud</c> chunk wherever the rate changes.
    /// </summary>
    /// <returns>The file.</returns>
    public byte[] ToCas()
    {
        using MemoryStream stream = new();
        byte[] description = Encoding.Latin1.GetBytes(Description);
        Chunk(stream, "FUJI"u8, 0, description.AsSpan(0, Math.Min(description.Length, ushort.MaxValue - 3)));
        int baud = 0;
        foreach (AtariTapeBlock block in _blocks)
        {
            if (block.Durations is { } durations)
            {
                byte[] data = new byte[durations.Length * 2];
                for (int i = 0; i < durations.Length; i++)
                {
                    BinaryPrimitives.WriteUInt16LittleEndian(data.AsSpan(i * 2), durations[i]);
                }

                Chunk(stream, "fsk "u8, block.Gap, data);
                continue;
            }

            if (block.Baud != baud)
            {
                baud = block.Baud;
                Chunk(stream, "baud"u8, baud, []);
            }

            Chunk(stream, "data"u8, block.Gap, block.Data);
        }

        return stream.ToArray();
    }

    /// <summary>
    ///  Replaces the blocks from an index on with new ones, as recording over the rest of the tape does.
    /// </summary>
    /// <param name="index">The first block to replace.</param>
    /// <param name="blocks">The new blocks.</param>
    /// <exception cref="InvalidOperationException">The tape is write-protected.</exception>
    public void Record(int index, IEnumerable<AtariTapeBlock> blocks)
    {
        if (_writeProtected) { throw new InvalidOperationException("The tape is write-protected."); }
        _blocks.RemoveRange(index, _blocks.Count - index);
        _blocks.AddRange(blocks);
        IsDirty = true;
        Version++;
    }

    /// <summary>
    ///  Adds a block to the end, as recording does.
    /// </summary>
    /// <param name="block">The block.</param>
    public void Append(AtariTapeBlock block)
    {
        if (_writeProtected) { throw new InvalidOperationException("The tape is write-protected."); }
        _blocks.Add(block);
        IsDirty = true;
        Version++;
    }

    /// <inheritdoc/>
    public MediumSnapshot Snapshot() => new(SnapshotKind, Version, _writeProtected, ToCas());

    /// <summary>
    ///  Records that the tape was saved to an image that holds it.
    /// </summary>
    public void MarkSaved() => IsDirty = false;

    /// <summary>
    ///  Records that the tape differs from its image.
    /// </summary>
    public void MarkChanged() => IsDirty = true;

    // A chunk longer than its 16-bit length holds goes as several, the rest with no gap: the same signal, unbroken.
    // A gap longer than the aux field holds, 65.5 seconds, is cut to the longest it can.
    private static void Chunk(Stream stream, ReadOnlySpan<byte> type, int aux, ReadOnlySpan<byte> data)
    {
        Span<byte> header = stackalloc byte[8];
        type.CopyTo(header);
        do
        {
            // 65,532: whole two-byte durations, and an even number of them, so the next fsk chunk starts on space
            // as the run it continues does.
            int length = Math.Min(data.Length, ushort.MaxValue - 3);
            BinaryPrimitives.WriteUInt16LittleEndian(header[4..], (ushort)length);
            BinaryPrimitives.WriteUInt16LittleEndian(header[6..], (ushort)Math.Clamp(aux, 0, ushort.MaxValue));
            stream.Write(header);
            stream.Write(data[..length]);
            data = data[length..];
            aux = 0;
        }
        while (!data.IsEmpty);
    }
}
