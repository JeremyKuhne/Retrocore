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
    private readonly bool _level1;
    private readonly string _rom;
    private readonly bool _romSwitches;
    private CassetteImage? _tape;
    private string _label = "";
    private CassetteContents _contents;

    /// <summary>
    ///  Creates the drive.
    /// </summary>
    /// <param name="cassette">The cassette interface.</param>
    /// <param name="baud">The ROM's rate: 500 for Level II, 250 for Level I.</param>
    /// <param name="motorPort">Where the motor relay is driven.</param>
    /// <param name="rom">The ROM, as a warning names it, such as <c>Level II</c> or <c>the Model 4's ROM</c>.</param>
    /// <param name="romSwitches">Whether the machine's launch can switch it to the other Level's ROM.</param>
    /// <param name="highSpeed">
    ///  Whether the ROM also plays and records 1500 baud tapes, as the Model III's and Model 4's do.
    /// </param>
    internal Trs80CassetteDrive(Trs80Cassette cassette, int baud, string motorPort, string rom, bool romSwitches, bool highSpeed = false)
    {
        _cassette = cassette;
        _level1 = baud == 250;
        _rom = rom;
        _romSwitches = romSwitches;
        Info = new()
        {
            Name = "Cassette",
            Description = highSpeed ? $"Cassette recorder, {baud} or 1500 baud" : $"Cassette recorder, {baud} baud",
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
            return new(_label, "CAS", WriteProtected: !recording, Changed: recording && _cassette.Length != 0)
            {
                Contents = recording ? null : Describe(_contents),
                Warning = recording ? null : Warning(_contents)
            };
        }
    }

    /// <summary>
    ///  Gets what the tape in the deck holds, as its first recording says; unknown for a recording or no tape.
    /// </summary>
    public CassetteContents Contents => Tape is null || _cassette.Mode == TapeMode.Recording ? CassetteContents.Unknown : _contents;

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
        _contents = CassetteFormat.Detect(tape.Bytes);
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
        _contents = CassetteContents.Unknown;
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

    private static string? Describe(CassetteContents contents) => contents switch
    {
        CassetteContents.Level1 => "Level I tape (250 baud)",
        CassetteContents.Level2Basic => "Level II BASIC program (500 baud)",
        CassetteContents.Level2System => "Level II SYSTEM tape (500 baud)",
        _ => null
    };

    // Neither Level's ROM reads the other's tapes: Level I's are 250 baud, Level II's 500.
    private string? Warning(CassetteContents contents) => (contents, _level1) switch
    {
        (CassetteContents.Level1, false) => $"This tape was recorded by Level I BASIC (250 baud); {_rom} can't read it. "
            + (_romSwitches ? "Switch the ROM to Level I." : "Play it on a Model I or Model III with the ROM set to Level I."),
        (CassetteContents.Level2Basic, true) => "This tape was recorded by Level II BASIC (500 baud); Level I can't read it. "
            + "Switch the ROM to Level II.",
        (CassetteContents.Level2System, true) => "This is a Level II SYSTEM tape (500 baud); Level I can't read it. "
            + "Switch the ROM to Level II.",
        _ => null
    };
}
