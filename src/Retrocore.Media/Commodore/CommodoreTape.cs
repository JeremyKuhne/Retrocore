// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

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
    ///  The <see cref="MediumSnapshot.Kind"/> of a tape's snapshot, whose image is a TAP version 1 file.
    /// </summary>
    public const string SnapshotKind = "commodore-tape";

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
    public MediumSnapshot Snapshot() => new(SnapshotKind, Version, _writeProtected, TapFormat.Write(_pulses));

    /// <summary>
    ///  Records that the tape was saved to an image that holds all of it.
    /// </summary>
    public void MarkSaved() => IsDirty = false;

    /// <summary>
    ///  Records that the tape differs from its image, as after a save that could not hold all of it.
    /// </summary>
    public void MarkChanged() => IsDirty = true;
}
