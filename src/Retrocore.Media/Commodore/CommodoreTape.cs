// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers.Binary;

namespace Retrocore.Media.Commodore;

/// <summary>
///  A Commodore cassette tape as the Datasette's read line sees it: a run of pulses, each a full square wave from one
///  falling edge to the next, measured in microseconds.
/// </summary>
/// <remarks>
///  <para>
///   Commodore's tape format writes each bit as a pair of pulses of three lengths, short, medium and long (about
///   2840, 1953 and 1488 Hz). A pause is one long pulse. A microsecond is a cycle of the PET's 1 MHz clock.
///  </para>
/// </remarks>
public sealed class CommodoreTape : IMedium
{
    /// <summary>
    ///  The <see cref="MediumSnapshot.Kind"/> of a tape's snapshot, whose image is each pulse's length in microseconds,
    ///  four bytes, low first, so it holds every pulse whatever an image format could.
    /// </summary>
    public const string SnapshotKind = "commodore-tape-pulses";

    private readonly List<int> _pulses;
    private bool _writeProtected;

    /// <summary>
    ///  Creates a blank tape.
    /// </summary>
    public CommodoreTape() => _pulses = [];

    /// <summary>
    ///  Creates a tape of pulses.
    /// </summary>
    /// <param name="pulses">Each pulse's length in microseconds, at least 1.</param>
    public CommodoreTape(IEnumerable<int> pulses)
    {
        _pulses = [.. pulses];
        if (_pulses.Exists(pulse => pulse < 1))
        {
            throw new ArgumentException("A pulse lasts at least 1 µs.", nameof(pulses));
        }
    }

    /// <summary>
    ///  Gets the pulses, in microseconds.
    /// </summary>
    public IReadOnlyList<int> Pulses => _pulses;

    /// <summary>
    ///  Gets the tape's length in microseconds.
    /// </summary>
    public long Duration
    {
        get
        {
            long total = 0;
            foreach (int pulse in _pulses) { total += pulse; }
            return total;
        }
    }

    /// <inheritdoc/>
    public long Version { get; private set; }

    /// <summary>
    ///  Gets whether recording has changed the tape since it was loaded or last saved.
    /// </summary>
    public bool IsDirty { get; private set; }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   A cassette is protected when its record tab is broken off: the Datasette's RECORD key will not go down.
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
    ///  Records a pulse at a place on the tape, replacing what was there from that pulse on, as a recording head
    ///  erases ahead of it.
    /// </summary>
    /// <param name="index">The pulse's place, at most <see cref="Pulses"/>' count.</param>
    /// <param name="microseconds">Its length.</param>
    public void Record(int index, int microseconds)
    {
        ArgumentOutOfRangeException.ThrowIfGreaterThan(index, _pulses.Count);
        ArgumentOutOfRangeException.ThrowIfLessThan(microseconds, 1);
        if (_writeProtected) { throw new InvalidOperationException("The tape is write protected."); }
        if (index < _pulses.Count) { _pulses.RemoveRange(index, _pulses.Count - index); }
        _pulses.Add(microseconds);
        IsDirty = true;
        Version++;
    }

    /// <inheritdoc/>
    public MediumSnapshot Snapshot()
    {
        byte[] image = new byte[_pulses.Count * 4];
        for (int i = 0; i < _pulses.Count; i++)
        {
            BinaryPrimitives.WriteInt32LittleEndian(image.AsSpan(i * 4), _pulses[i]);
        }

        return new(SnapshotKind, Version, _writeProtected, image);
    }

    /// <summary>
    ///  Reads a tape back from its snapshot's image.
    /// </summary>
    /// <param name="image">The image of a <see cref="SnapshotKind"/> snapshot.</param>
    /// <returns>The tape.</returns>
    /// <exception cref="InvalidDataException">
    ///  The image is not a whole number of pulses, or has one under 1 µs.
    /// </exception>
    public static CommodoreTape FromSnapshot(ReadOnlySpan<byte> image)
    {
        if (image.Length % 4 != 0) { throw new InvalidDataException("A tape's snapshot is four bytes a pulse."); }
        int[] pulses = new int[image.Length / 4];
        for (int i = 0; i < pulses.Length; i++)
        {
            pulses[i] = BinaryPrimitives.ReadInt32LittleEndian(image[(i * 4)..]);
            if (pulses[i] < 1) { throw new InvalidDataException("A tape's snapshot has a pulse under 1 µs."); }
        }

        return new(pulses);
    }

    /// <summary>
    ///  Records that the tape was saved to an image that holds all of it.
    /// </summary>
    public void MarkSaved() => IsDirty = false;

    /// <summary>
    ///  Records that the tape differs from its image, as after a save that could not hold all of it.
    /// </summary>
    public void MarkChanged() => IsDirty = true;
}
