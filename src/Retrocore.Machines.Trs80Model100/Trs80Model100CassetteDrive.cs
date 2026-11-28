// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Media;

namespace Retrocore.Machines.Trs80Model100;

/// <summary>
///  The cassette recorder on the Model 100's tape port.
/// </summary>
public sealed class Trs80Model100CassetteDrive : ITapeDrive, IMediumSlot
{
    private readonly Trs80Model100Cassette _cassette;
    private Trs80Model100Tape? _tape;
    private string _label = "";

    /// <summary>
    ///  Creates the drive.
    /// </summary>
    /// <param name="cassette">The cassette port.</param>
    internal Trs80Model100CassetteDrive(Trs80Model100Cassette cassette)
    {
        _cassette = cassette;
        Info = new()
        {
            Name = "Cassette",
            Description = "Cassette recorder",
            Controller = "SOD and SID, with the motor on port $E0 bit 3",
            Formats = ["wav"],
            SaveFormats = ["wav"],
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
    ///  Gets the tape, or null.
    /// </summary>
    public Trs80Model100Tape? Tape => _cassette.Mode == TapeMode.Stopped ? null : _tape;

    /// <inheritdoc/>
    /// <remarks>A tape that plays is protected; one that records has changed once it holds a half cycle.</remarks>
    public MediaState? Media
    {
        get
        {
            if (Tape is not { } tape) { return null; }
            bool recording = _cassette.Mode == TapeMode.Recording;
            return new(_label, "WAV", WriteProtected: !recording, Changed: tape.IsDirty);
        }
    }

    /// <inheritdoc/>
    public DeviceActivity Activity => (_cassette.Mode, _cassette.Motor) switch
    {
        (TapeMode.Recording, true) => DeviceActivity.Writing,
        (TapeMode.Playing, true) when !_cassette.AtEnd => DeviceActivity.Reading,
        _ => DeviceActivity.Idle
    };

    /// <inheritdoc/>
    public TapeTransport Transport => new(_cassette.Motor, _cassette.Mode, _cassette.Position, _cassette.Length);

    /// <summary>
    ///  Loads a tape to play from its start.
    /// </summary>
    /// <param name="tape">The tape.</param>
    /// <param name="label">What the host calls it, such as its file's path.</param>
    public void Play(Trs80Model100Tape tape, string label)
    {
        _cassette.Play(tape);
        _tape = tape;
        _label = label;
        MountGeneration = MountGenerations.Next();
    }

    /// <summary>
    ///  Loads a tape to record onto.
    /// </summary>
    /// <param name="tape">The tape, which receives what the machine records.</param>
    /// <param name="label">What the host calls it, such as the path it will be saved to.</param>
    public void Record(Trs80Model100Tape tape, string label)
    {
        _cassette.Record(tape);
        _tape = tape;
        _label = label;
        MountGeneration = MountGenerations.Next();
    }

    /// <summary>
    ///  Stops the deck and ejects the tape.
    /// </summary>
    /// <returns>The tape, or null when the deck was empty.</returns>
    public Trs80Model100Tape? Eject()
    {
        Trs80Model100Tape? tape = Tape;
        _cassette.Stop();
        _tape = null;
        _label = "";
        MountGeneration = MountGenerations.Next();
        return tape;
    }

    /// <inheritdoc/>
    IMedium? IMediumSlot.Medium => Tape;

    /// <inheritdoc/>
    public int MountGeneration { get; private set; } = MountGenerations.Next();

    /// <inheritdoc/>
    public void Saved(string label, string format, bool whole)
    {
        if (Tape is not { } tape) { throw new InvalidOperationException("There is no tape in the recorder."); }
        _label = label;
        if (whole) { tape.MarkSaved(); } else { tape.MarkChanged(); }
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The tape plays from its start, as a recording put back from the recovery journal or for Undo is there to be
    ///   read; it keeps its changes until it is saved.
    ///  </para>
    /// </remarks>
    public void Mount(IMedium medium, string label, string format) =>
        Play(medium as Trs80Model100Tape ?? throw new ArgumentException($"{Info.Name} does not take a {medium?.GetType().Name}.", nameof(medium)), label);

    /// <inheritdoc/>
    public IMedium? Unmount() => Eject();
}
