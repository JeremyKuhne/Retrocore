// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;

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
///   A tape image is its bytes in order, the <c>.tap</c> files Altair emulators and the MITS tape archives use.
///  </para>
/// </remarks>
public sealed class AltairCassette : ITapeDrive
{
    private readonly AltairSio _acr;
    private readonly List<byte> _tape = [];
    private TapeMode _mode;
    private int _position;
    private int _cycles;
    private string _label = "";
    private bool _changed;

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
            Operations = MediaOperations.Insert | MediaOperations.Eject | MediaOperations.Record
        };
    }

    /// <inheritdoc/>
    public string Id => "cassette";

    /// <inheritdoc/>
    public DeviceKind Kind => DeviceKind.TapeDrive;

    /// <inheritdoc/>
    public DeviceInfo Info { get; }

    /// <summary>
    ///  Gets the tape's bytes, empty when the recorder is empty.
    /// </summary>
    public byte[] Tape => [.. _tape];

    /// <summary>
    ///  Gets whether a tape that plays has no bytes left.
    /// </summary>
    public bool AtEnd => _mode == TapeMode.Playing && _position >= _tape.Count;

    /// <inheritdoc/>
    /// <remarks>A tape that plays is protected; one that records has changed once it holds a byte.</remarks>
    public MediaState? Media => _mode == TapeMode.Stopped
        ? null
        : new(_label, "TAP", WriteProtected: _mode == TapeMode.Playing, Changed: _changed);

    /// <inheritdoc/>
    public DeviceActivity Activity => _mode switch
    {
        TapeMode.Recording => DeviceActivity.Writing,
        TapeMode.Playing when !AtEnd => DeviceActivity.Reading,
        _ => DeviceActivity.Idle
    };

    /// <inheritdoc/>
    public TapeTransport Transport => new(_mode != TapeMode.Stopped, _mode, _position, _tape.Count);

    /// <summary>
    ///  Loads a tape and plays it from the start.
    /// </summary>
    /// <param name="tape">The tape's bytes.</param>
    /// <param name="label">What the host calls it, such as its file's path.</param>
    public void Play(ReadOnlySpan<byte> tape, string label)
    {
        Load(tape, label);
        _mode = TapeMode.Playing;
    }

    /// <summary>
    ///  Loads a blank tape to record onto.
    /// </summary>
    /// <param name="label">What the host calls it, such as the path it will be saved to.</param>
    public void Record(string label)
    {
        Load([], label);
        _mode = TapeMode.Recording;
    }

    /// <summary>
    ///  Stops the recorder and takes the tape out.
    /// </summary>
    /// <returns>The tape's bytes, or null when the recorder was empty.</returns>
    public byte[]? Eject()
    {
        byte[]? tape = _mode == TapeMode.Stopped ? null : [.. _tape];
        Load([], "");
        _mode = TapeMode.Stopped;
        return tape;
    }

    /// <summary>
    ///  Advances one CPU cycle: a tape that plays delivers its next byte each character time.
    /// </summary>
    internal void Tick()
    {
        if (_mode != TapeMode.Playing || _position >= _tape.Count) { return; }
        if (++_cycles < _acr.CyclesPerCharacter) { return; }
        _cycles = 0;
        _acr.Receive(_tape[_position++]);
    }

    private void Load(ReadOnlySpan<byte> tape, string label)
    {
        _tape.Clear();
        _tape.AddRange(tape);
        _position = 0;
        _cycles = 0;
        _label = label;
        _changed = false;
    }

    // The 88-ACR sent a byte: a tape that records takes it.
    private void Record(byte value)
    {
        if (_mode != TapeMode.Recording) { return; }
        _tape.Add(value);
        _position = _tape.Count;
        _changed = true;
    }
}
