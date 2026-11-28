// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Media;
using Retrocore.Media.Altair;

namespace Retrocore.Machines.Altair;

/// <summary>
///  The cassette recorder on the 88-ACR: a tape of bytes, as the 88-ACR's modem turns the tones back into the
///  characters the 88-SIO sent.
/// </summary>
/// <remarks>
///  <para>
///   The 88-ACR has no motor control, so a tape moves from the moment it goes in. A tape that plays delivers its
///   next byte to the 88-ACR's receiver every character time, 300 baud, whether or not the program is reading: a
///   byte not read before the next arrives is lost, as on a real recorder, so a program starts reading before the
///   tape plays, or skips a leader. A tape that records takes each byte the 88-ACR sends.
///  </para>
///  <para>
///   A tape image is its bytes in order, the <c>.tap</c> files Altair emulators and the MITS tape archives use. A
///   recording is a changed tape (<see cref="AltairTape"/>), saved as a disk is.
///  </para>
/// </remarks>
public sealed class AltairCassette : ITapeDrive, IMediumSlot
{
    private readonly AltairSio _acr;
    private AltairTape? _tape;
    private TapeMode _mode;
    private int _position;
    private int _cycles;
    private string _label = "";

    /// <summary>
    ///  Connects the recorder to the 88-ACR.
    /// </summary>
    /// <param name="acr">The 88-ACR's 88-SIO.</param>
    internal AltairCassette(AltairSio acr)
    {
        _acr = acr;
        _acr.Transmitted = Record;
        Info = new()
        {
            Name = "Cassette",
            Description = "Cassette recorder",
            Controller = "the 88-ACR, ports $06 and $07",
            Formats = ["tap"],
            SaveFormats = ["tap"],
            Operations = MediaOperations.Insert | MediaOperations.Eject | MediaOperations.Record | MediaOperations.Save
        };
    }

    /// <inheritdoc/>
    public string Id => "cassette";

    /// <inheritdoc/>
    public DeviceKind Kind => DeviceKind.TapeDrive;

    /// <inheritdoc/>
    public DeviceInfo Info { get; }

    /// <summary>
    ///  Gets the tape in the recorder, or null.
    /// </summary>
    public AltairTape? Tape => _tape;

    /// <summary>
    ///  Gets whether a tape that plays has no bytes left.
    /// </summary>
    public bool AtEnd => _mode == TapeMode.Playing && _position >= (_tape?.Bytes.Count ?? 0);

    /// <inheritdoc/>
    /// <remarks>
    ///  A tape that plays is protected; one that records has changed once it holds a byte, until it is saved.
    /// </remarks>
    public MediaState? Media => _tape is not { } tape
        ? null
        : new(_label, "TAP", WriteProtected: _mode == TapeMode.Playing, Changed: tape.IsDirty);

    /// <inheritdoc/>
    public DeviceActivity Activity => _mode switch
    {
        TapeMode.Recording => DeviceActivity.Writing,
        TapeMode.Playing when !AtEnd => DeviceActivity.Reading,
        _ => DeviceActivity.Idle
    };

    /// <inheritdoc/>
    public TapeTransport Transport => new(_mode != TapeMode.Stopped, _mode, _position, _tape?.Bytes.Count ?? 0);

    /// <inheritdoc/>
    IMedium? IMediumSlot.Medium => _tape;

    /// <inheritdoc/>
    public int MountGeneration { get; private set; } = MountGenerations.Next();

    /// <summary>
    ///  Loads a tape and plays it from the start.
    /// </summary>
    /// <param name="tape">The tape's bytes.</param>
    /// <param name="label">What the host calls it, such as its file's path.</param>
    public void Play(ReadOnlySpan<byte> tape, string label) => Play(new AltairTape(tape), label);

    /// <summary>
    ///  Loads a tape and plays it from the start.
    /// </summary>
    /// <param name="tape">The tape, which keeps any changes it has.</param>
    /// <param name="label">What the host calls it, such as its file's path.</param>
    public void Play(AltairTape tape, string label)
    {
        ArgumentNullException.ThrowIfNull(tape);
        Load(tape, label, TapeMode.Playing);
    }

    /// <summary>
    ///  Loads a blank tape to record onto.
    /// </summary>
    /// <param name="label">What the host calls it, such as the path it will be saved to.</param>
    public void Record(string label) => Record(new AltairTape(), label);

    /// <summary>
    ///  Loads a tape to record onto, appending what the 88-ACR sends.
    /// </summary>
    /// <param name="tape">The tape.</param>
    /// <param name="label">What the host calls it, such as the path it will be saved to.</param>
    public void Record(AltairTape tape, string label)
    {
        ArgumentNullException.ThrowIfNull(tape);
        Load(tape, label, TapeMode.Recording);
        _position = tape.Bytes.Count;
    }

    /// <summary>
    ///  Stops the recorder and takes the tape out.
    /// </summary>
    /// <returns>The tape, or null when the recorder was empty.</returns>
    public AltairTape? Eject()
    {
        AltairTape? tape = _tape;
        Load(tape: null, "", TapeMode.Stopped);
        return tape;
    }

    /// <inheritdoc/>
    public void Saved(string label, string format, bool whole)
    {
        if (_tape is not { } tape) { throw new InvalidOperationException("There is no tape in the recorder."); }
        _label = label;
        if (whole) { tape.MarkSaved(); } else { tape.MarkChanged(); }
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The tape plays from its start, as a recording put back from the recovery journal or for Undo is there for
    ///   <c>CLOAD</c>; it keeps its changes until it is saved.
    ///  </para>
    /// </remarks>
    public void Mount(IMedium medium, string label, string format) =>
        Play(medium as AltairTape ?? throw new ArgumentException($"{Info.Name} does not take a {medium?.GetType().Name}.", nameof(medium)), label);

    /// <inheritdoc/>
    public IMedium? Unmount() => Eject();

    /// <summary>
    ///  Advances one CPU cycle: a tape that plays delivers its next byte each character time.
    /// </summary>
    internal void Tick()
    {
        if (_mode != TapeMode.Playing || _tape is not { } tape || _position >= tape.Bytes.Count) { return; }
        if (++_cycles < _acr.CyclesPerCharacter) { return; }
        _cycles = 0;
        _acr.Receive(tape.Bytes[_position++]);
    }

    private void Load(AltairTape? tape, string label, TapeMode mode)
    {
        _tape = tape;
        _mode = mode;
        _position = 0;
        _cycles = 0;
        _label = label;
        MountGeneration = MountGenerations.Next();
    }

    // The 88-ACR sent a byte: a tape that records takes it.
    private void Record(byte value)
    {
        if (_mode != TapeMode.Recording || _tape is not { } tape) { return; }
        tape.Append(value);
        _position = tape.Bytes.Count;
    }
}
