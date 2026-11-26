// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple1;

namespace Retrocore.Debug.Project;

/// <summary>
///  The <c>wozmon</c> environment: an Apple-1 program typed in at the Woz Monitor as hex, or read from the cassette
///  interface's tape, and started with <c>R</c> at its entry.
/// </summary>
/// <remarks>
///  <para>
///   Its file is the hex to type, <c>&lt;name&gt;.hex</c> (<see cref="WozMonitorHex.ToText"/>): lines that store the
///   program's bytes from its load address, then the line that runs it at its entry. Its image is the ACI tape of the
///   same bytes, <c>&lt;name&gt;.wav</c>, which <c>C100R</c> and then <c>start.endR</c> read; <c>"image": false</c>
///   leaves the tape out. A launch loads the binary as if its hex had been typed, and starts at its entry as
///   <c>R</c> would, as a <c>bare</c> one does.
///  </para>
/// </remarks>
internal sealed class WozmonEnvironment : TargetEnvironment
{
    /// <inheritdoc/>
    internal override string Name => "wozmon";

    /// <inheritdoc/>
    internal override bool BuildsImage => true;

    /// <inheritdoc/>
    internal override TargetMedia Write(TargetBuild build)
    {
        (int start, byte[] bytes) = ProjectBuild.Image(build);
        int end = start + bytes.Length - 1;
        string hex = Beside(build, ".hex");
        File.WriteAllText(hex, WozMonitorHex.ToText(bytes, (ushort)start, (ushort)build.Entry));

        string? tape = null;
        if (build.Target.BuildsImage)
        {
            tape = Beside(build, ".wav");
            File.WriteAllBytes(tape, Apple1Tape.FromData(bytes).ToWave());
        }

        string note = tape is null
            ? $"type it at the Woz Monitor's prompt"
            : $"type it at the Woz Monitor's prompt, or play the tape after C100R and {start:X4}.{end:X4}R, then {build.Entry:X4}R";

        return new(hex, "Woz Monitor hex", tape, tape is null ? null : "ACI tape", note);
    }
}
