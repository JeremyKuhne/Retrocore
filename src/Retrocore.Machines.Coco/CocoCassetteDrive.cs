// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Media.Trs80;

namespace Retrocore.Machines.Coco;

/// <summary>
///  The Color Computer's cassette recorder as a device: a <c>.cas</c> tape played or recorded at 1500 baud.
/// </summary>
public sealed class CocoCassetteDrive : ITapeDrive
{
    private readonly CocoCassette _cassette;
    private readonly CocoBus _bus;
    private CassetteImage? _tape;
    private string _label = "";

    /// <summary>
    ///  Builds the device over the bus's cassette.
    /// </summary>
    /// <param name="bus">The bus, whose PIA 1 runs the motor.</param>
    internal CocoCassetteDrive(CocoBus bus)
    {
        _bus = bus;
        _cassette = bus.Cassette;
        Info = new()
        {
            Name = "Cassette",
            Description = "Cassette recorder, 1500 baud",
            Controller = "PIA 1: PA0 reads the tape, the DAC writes it, and CA2 runs the motor",
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
    ///  Gets the tape in the recorder, or null.
    /// </summary>
    public CassetteImage? Tape => _cassette.Mode == TapeMode.Stopped ? null : _tape;

    /// <inheritdoc/>
    public MediaState? Media
    {
        get
        {
            if (Tape is not { } tape) { return null; }
            bool recording = _cassette.Mode == TapeMode.Recording;
            return new(_label, "CAS", WriteProtected: !recording, Changed: recording && tape.Bytes.Count != 0);
        }
    }

    /// <inheritdoc/>
    public DeviceActivity Activity => !_bus.CassetteMotor || _cassette.Mode == TapeMode.Stopped
        ? DeviceActivity.Idle
        : _cassette.Mode == TapeMode.Recording ? DeviceActivity.Writing : DeviceActivity.Reading;

    /// <inheritdoc/>
    public TapeTransport Transport => new(
        _bus.CassetteMotor,
        _cassette.Mode,
        _cassette.Position,
        _tape?.Bytes.Count ?? 0);

    /// <summary>
    ///  Puts a tape in and presses PLAY.
    /// </summary>
    /// <param name="tape">The tape.</param>
    /// <param name="label">Its name, for display.</param>
    public void Play(CassetteImage tape, string label)
    {
        _cassette.Play(tape);
        _tape = tape;
        _label = label;
    }

    /// <summary>
    ///  Puts a tape in and presses RECORD.
    /// </summary>
    /// <param name="tape">The tape, which recording appends to.</param>
    /// <param name="label">Its name, for display.</param>
    public void Record(CassetteImage tape, string label)
    {
        _cassette.Record(tape);
        _tape = tape;
        _label = label;
    }

    /// <summary>
    ///  Takes the tape out.
    /// </summary>
    /// <returns>The tape, or null.</returns>
    public CassetteImage? Eject()
    {
        CassetteImage? tape = Tape;
        _cassette.Stop();
        _tape = null;
        _label = "";
        return tape;
    }
}
