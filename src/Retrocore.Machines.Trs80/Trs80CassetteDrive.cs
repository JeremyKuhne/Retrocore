// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Media.Trs80;

namespace Retrocore.Machines.Trs80;

/// <summary>
///  The cassette recorder on the cassette port.
/// </summary>
public sealed class Trs80CassetteDrive : ITapeDrive
{
    private readonly Trs80Cassette _cassette;
    private CassetteImage? _tape;
    private string _label = "";

    /// <summary>
    ///  Creates the drive.
    /// </summary>
    /// <param name="cassette">The cassette interface.</param>
    /// <param name="baud">The ROM's rate: 500 for Level II, 250 for Level I.</param>
    /// <param name="motorPort">Where the motor relay is driven.</param>
    internal Trs80CassetteDrive(Trs80Cassette cassette, int baud, string motorPort = "$FF")
    {
        _cassette = cassette;
        Info = new()
        {
            Name = "Cassette",
            Description = $"Cassette recorder, {baud} baud",
            Controller = $"the cassette port, with the motor relay on port {motorPort}",
            Formats = ["cas"],
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
    ///  Gets the tape, or null.
    /// </summary>
    public CassetteImage? Tape => _cassette.Mode == TapeMode.Stopped ? null : _tape;

    /// <inheritdoc/>
    /// <remarks>A tape that plays is protected; one that records has changed once it holds a byte.</remarks>
    public MediaState? Media
    {
        get
        {
            if (Tape is null) { return null; }
            bool recording = _cassette.Mode == TapeMode.Recording;
            return new(_label, "CAS", WriteProtected: !recording, Changed: recording && _cassette.Length != 0);
        }
    }

    /// <inheritdoc/>
    public DeviceActivity Activity => !_cassette.MotorOn || _cassette.Mode == TapeMode.Stopped
        ? DeviceActivity.Idle
        : _cassette.Mode == TapeMode.Recording ? DeviceActivity.Writing : DeviceActivity.Reading;

    /// <inheritdoc/>
    public TapeTransport Transport => new(_cassette.MotorOn, _cassette.Mode, _cassette.Position, _cassette.Length);

    /// <summary>
    ///  Loads a tape to play from the start.
    /// </summary>
    /// <param name="tape">The tape.</param>
    /// <param name="label">What the host calls it, such as its image's path.</param>
    public void Play(CassetteImage tape, string label)
    {
        _cassette.Play(tape);
        _tape = tape;
        _label = label;
    }

    /// <summary>
    ///  Loads a blank tape to record onto.
    /// </summary>
    /// <param name="tape">The tape, which receives what the machine records.</param>
    /// <param name="label">What the host calls it, such as the path it will be saved to.</param>
    public void Record(CassetteImage tape, string label)
    {
        _cassette.Record(tape);
        _tape = tape;
        _label = label;
    }

    /// <summary>
    ///  Stops the deck, finishing a recording, and ejects the tape.
    /// </summary>
    /// <returns>The tape, or null when the deck was empty.</returns>
    public CassetteImage? Eject()
    {
        CassetteImage? tape = Tape;
        _cassette.Stop();
        _tape = null;
        _label = "";
        return tape;
    }
}
