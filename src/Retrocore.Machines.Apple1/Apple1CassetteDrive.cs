// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;

namespace Retrocore.Machines.Apple1;

/// <summary>
///  The cassette recorder on the Apple Cassette Interface.
/// </summary>
public sealed class Apple1CassetteDrive : ITapeDrive
{
    private readonly Apple1Cassette _cassette;
    private Apple1Tape? _tape;
    private string _label = "";

    /// <summary>
    ///  Creates the drive.
    /// </summary>
    /// <param name="cassette">The cassette interface.</param>
    internal Apple1CassetteDrive(Apple1Cassette cassette)
    {
        _cassette = cassette;
        Info = new()
        {
            Name = "Cassette",
            Description = "Cassette recorder",
            Controller = "the Apple Cassette Interface, $C000-$C1FF",
            Formats = ["wav"],
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
    public Apple1Tape? Tape => _cassette.Mode == TapeMode.Stopped ? null : _tape;

    /// <inheritdoc/>
    /// <remarks>A tape that plays is protected; one that records has changed once it holds a half cycle.</remarks>
    public MediaState? Media
    {
        get
        {
            if (Tape is null) { return null; }
            bool recording = _cassette.Mode == TapeMode.Recording;
            return new(_label, "WAV", WriteProtected: !recording, Changed: recording && _cassette.Length != 0);
        }
    }

    /// <inheritdoc/>
    public DeviceActivity Activity => _cassette.Mode switch
    {
        TapeMode.Recording => DeviceActivity.Writing,
        TapeMode.Playing when !_cassette.AtEnd => DeviceActivity.Reading,
        _ => DeviceActivity.Idle
    };

    /// <inheritdoc/>
    /// <remarks>The interface has no motor control, so the motor runs whenever a tape is loaded.</remarks>
    public TapeTransport Transport =>
        new(_cassette.Mode != TapeMode.Stopped, _cassette.Mode, _cassette.Position, _cassette.Length);

    /// <summary>
    ///  Loads a tape and plays it from the start.
    /// </summary>
    /// <param name="tape">The tape.</param>
    /// <param name="label">What the host calls it, such as its file's path.</param>
    public void Play(Apple1Tape tape, string label)
    {
        _cassette.Play(tape);
        _tape = tape;
        _label = label;
    }

    /// <summary>
    ///  Loads a tape to record onto.
    /// </summary>
    /// <param name="tape">The tape, which receives what the machine records.</param>
    /// <param name="label">What the host calls it, such as the path it will be saved to.</param>
    public void Record(Apple1Tape tape, string label)
    {
        _cassette.Record(tape);
        _tape = tape;
        _label = label;
    }

    /// <summary>
    ///  Stops the deck and ejects the tape.
    /// </summary>
    /// <returns>The tape, or null when the deck was empty.</returns>
    public Apple1Tape? Eject()
    {
        Apple1Tape? tape = Tape;
        _cassette.Stop();
        _tape = null;
        _label = "";
        return tape;
    }
}
