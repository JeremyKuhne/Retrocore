// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Acorn;

/// <summary>
///  An Acorn cassette: the BBC Micro's and the Electron's tones, as the lengths of the half-cycles between the
///  signal's zero crossings.
/// </summary>
/// <remarks>
///  <para>
///   Lengths are in units of 1/4,800 second, a half-cycle of the 2400 Hz high tone. A 1200 Hz half-cycle is 2 units;
///   anything longer is silence, which the serial ULA hears as no tone. At 1200 baud a 1 is two cycles of 2400 Hz
///   and a 0 one cycle of 1200 Hz; at 300 baud a 1 is eight cycles and a 0 four. Every bit either rate can make is
///   whole units, so the tape holds both exactly.
///  </para>
/// </remarks>
public sealed class AcornTape : IMedium
{
    /// <summary>
    ///  The <see cref="MediumSnapshot.Kind"/> of a tape's snapshot, whose image is a UEF file.
    /// </summary>
    public const string SnapshotKind = "acorn-tape";

    /// <summary>
    ///  The units a second holds.
    /// </summary>
    public const int UnitsPerSecond = 4800;

    private readonly List<int> _halfCycles;
    private bool _writeProtected;

    /// <summary>
    ///  Creates a blank tape.
    /// </summary>
    public AcornTape() => _halfCycles = [];

    /// <summary>
    ///  Creates a tape of half-cycles.
    /// </summary>
    /// <param name="halfCycles">Each half-cycle's length in units of 1/4,800 second, at least 1.</param>
    /// <exception cref="ArgumentException">A length is less than 1.</exception>
    public AcornTape(IEnumerable<int> halfCycles)
    {
        _halfCycles = [.. halfCycles];
        if (_halfCycles.Exists(length => length < 1))
        {
            throw new ArgumentException("A half-cycle lasts at least 1/4,800 second.", nameof(halfCycles));
        }
    }

    /// <summary>
    ///  Gets the half-cycles' lengths, in units of 1/4,800 second.
    /// </summary>
    public IReadOnlyList<int> HalfCycles => _halfCycles;

    /// <summary>
    ///  Gets the tape's length in units of 1/4,800 second.
    /// </summary>
    public long Duration
    {
        get
        {
            long total = 0;
            foreach (int length in _halfCycles) { total += length; }
            return total;
        }
    }

    /// <inheritdoc/>
    public long Version { get; private set; }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   A cassette is protected when its record tab is broken off: the recorder's RECORD key will not go down.
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
    ///  Records a half-cycle at a place on the tape, replacing what was there from that place on, as a recording head
    ///  erases ahead of it.
    /// </summary>
    /// <param name="index">The half-cycle's place, at most <see cref="HalfCycles"/>' count.</param>
    /// <param name="length">Its length in units of 1/4,800 second.</param>
    /// <exception cref="InvalidOperationException">The tape is write protected.</exception>
    public void Record(int index, int length)
    {
        ArgumentOutOfRangeException.ThrowIfGreaterThan(index, _halfCycles.Count);
        ArgumentOutOfRangeException.ThrowIfLessThan(length, 1);
        if (_writeProtected) { throw new InvalidOperationException("The tape is write protected."); }
        if (index < _halfCycles.Count) { _halfCycles.RemoveRange(index, _halfCycles.Count - index); }
        _halfCycles.Add(length);
        IsDirty = true;
        Version++;
    }

    /// <inheritdoc/>
    public bool IsDirty { get; private set; }

    /// <inheritdoc/>
    public void MarkSaved() => IsDirty = false;

    /// <inheritdoc/>
    public void MarkChanged() => IsDirty = true;

    /// <inheritdoc/>
    public MediumSnapshot Snapshot() => new(SnapshotKind, Version, _writeProtected, UefFormat.Write(_halfCycles));
}
