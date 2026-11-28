// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Machines.Trs80Model100;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

internal sealed partial class Trs80Model100DebugTarget
{
    private DebugAudioSink? _sound;
    private string _soundMode = "off";

    /// <summary>
    ///  Gets or sets whether the machine runs as fast as it can while the cassette's motor moves a tape.
    /// </summary>
    internal bool FastCassette { get; set; } = true;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The machine runs as fast as it can while the motor moves a tape that plays or records, unless the launch asks
    ///   not to.
    ///  </para>
    /// </remarks>
    public bool Accelerated => FastCassette && _machine.Bus.CassetteDrive.Activity != DeviceActivity.Idle;

    /// <inheritdoc/>
    public void DeviceAction(IDevice device, string action, JsonObject args)
    {
        string? path = args.String("path");
        switch (device, action)
        {
            case (Trs80Model100CassetteDrive, "insert"):
                Insert(path ?? throw new ArgumentException("path is required."));
                break;
            case (Trs80Model100CassetteDrive cassette, "record"):
                // The recording's file is written blank first, so a bad path leaves the tape in the recorder.
                Trs80Model100Tape blank = new();
                string full = TapeMedia.Record(path, blank, new Trs80Model100TapeCodec());
                cassette.Eject();
                cassette.Record(blank, full);
                break;
            case (Trs80Model100CassetteDrive cassette, "eject"):
                cassette.Eject();
                break;
            default:
                throw new ArgumentException($"{device.Info.Name} does not support {action}.");
        }
    }

    /// <inheritdoc/>
    public JsonObject? TakeAudio()
    {
        if (_sound is null) { return null; }
        _machine.Bus.Audio.Flush();
        return _sound.Take() is { } samples
            ? new JsonObject { ["rate"] = _sound.SampleRate, ["channels"] = _sound.Channels, ["samples"] = samples }
            : null;
    }

    /// <inheritdoc/>
    public IEnumerable<(string Event, JsonObject Body)> StatusEvents()
    {
        yield return ("retro/media", MediaState());
    }

    /// <summary>
    ///  Puts a WAV file's tape in the recorder, to play once the ROM runs the motor.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The new tape is read before the one in the recorder comes out, so a file that cannot be read leaves it in. A
    ///   changed recording in the recorder is asked about first, as a changed disk is (<see cref="MediaActions"/>).
    ///  </para>
    /// </remarks>
    /// <param name="path">The WAV file.</param>
    /// <exception cref="ArgumentException">The file does not exist.</exception>
    /// <exception cref="InvalidDataException">The file is not an 8 or 16-bit PCM WAV file.</exception>
    internal void Insert(string path)
    {
        string full = Path.GetFullPath(path);
        if (!File.Exists(full)) { throw new ArgumentException($"The tape {full} does not exist."); }
        byte[] bytes = File.ReadAllBytes(full);
        Trs80Model100Tape tape = Trs80Model100Tape.FromWave(bytes);
        MediaActions.Register(tape, full, new Trs80Model100TapeCodec(), bytes);
        _machine.Bus.CassetteDrive.Eject();
        _machine.Bus.CassetteDrive.Play(tape, full);
    }

    /// <summary>
    ///  Sets the sound: <c>off</c> attaches no sink, <c>speaker</c> plays the buzzer.
    /// </summary>
    /// <param name="mode">The mode.</param>
    /// <exception cref="ArgumentException">The mode is neither.</exception>
    internal void SetSound(string mode)
    {
        Trs80Model100Audio audio = _machine.Bus.Audio;
        DebugAudioSink? sound = mode switch
        {
            "off" => null,
            "speaker" => new DebugAudioSink(channels: 1, audio.SampleRate),
            _ => throw new ArgumentException("sound must be off or speaker.")
        };

        _sound = sound;
        audio.Sink = sound;
        _soundMode = mode;
    }

    // retro/media: inserts, records and ejects the cassette's tapes.
    private JsonObject Media(JsonObject args)
    {
        string action = args.String("action") ?? throw new ArgumentException("action is required.");
        if ((args.String("device") ?? "cassette") != "cassette")
        {
            throw new ArgumentException("The Model 100's only media is the cassette's tape.");
        }

        // A changed recording is held back, as from retro/device, so an older client cannot lose it. One let go of is
        // ejected or replaced through the host, which keeps it for Undo.
        Trs80Model100CassetteDrive drive = _machine.Bus.CassetteDrive;
        JsonObject? answer = MediaActions.Device(drive, action, args, (what, with) => DeviceAction(drive, what, with));
        if (answer is null)
        {
            DeviceAction(drive, action, args);
        }
        else if (answer.String("outcome") != "discarded")
        {
            return answer;
        }

        return MediaState();
    }

    private JsonObject MediaState()
    {
        Trs80Model100CassetteDrive drive = _machine.Bus.CassetteDrive;
        JsonObject cassette = new()
        {
            ["path"] = drive.Media?.Label,
            ["recording"] = drive.Transport.Mode == TapeMode.Recording,
            ["motor"] = drive.Transport.Motor,
            ["atEnd"] = _machine.Bus.Cassette.AtEnd
        };

        return new JsonObject { ["cassette"] = cassette };
    }
}
