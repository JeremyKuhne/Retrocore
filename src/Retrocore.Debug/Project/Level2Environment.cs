// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media.Trs80;
using System.Text.Json.Nodes;

namespace Retrocore.Debug.Project;

/// <summary>
///  The <c>level2</c> environment: a TRS-80 Model I or Model III program on a Level II <c>SYSTEM</c> tape, which the
///  ROM's <c>SYSTEM</c> command loads and <c>/</c> starts.
/// </summary>
/// <remarks>
///  <para>
///   The tape, <c>&lt;name&gt;.cas</c>, is a 500 baud CAS image (<see cref="SystemTape"/>): the program's bytes from
///   its load address, in blocks of 256, under the project's name in capitals, cut to six, and its entry address. A
///   launch puts it in the cassette recorder, answers the ROM's start-up questions (the Model III's <c>Cass?</c> with
///   <c>L</c>, for 500 baud, and <c>MEMORY SIZE?</c> with Return), types <c>SYSTEM</c>, the tape's name, and once the
///   program has loaded, <c>/</c>, which jumps to its entry. <c>"image": false</c> leaves the tape out, and the binary
///   holds the bytes from the load address.
///  </para>
/// </remarks>
internal sealed class Level2Environment : TargetEnvironment
{
    /// <inheritdoc/>
    internal override string Name => "level2";

    /// <inheritdoc/>
    internal override string NoFiles => "the 'level2' environment puts only its program on its tape, so it takes no 'files'";

    /// <inheritdoc/>
    internal override bool BuildsImage => true;

    /// <inheritdoc/>
    internal override bool BootsImage => true;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The tape plays at 500 baud, about 60 bytes a second of the machine's time (a fast cassette only runs the
    ///   host faster), so the largest program a 48K machine holds, 47K, plays for about 800 of the machine's seconds;
    ///   a launch that has not started the program in twenty minutes of the machine's time has failed, such as at a tape
    ///   error.
    ///  </para>
    /// </remarks>
    internal override int BootSeconds => 1200;

    /// <inheritdoc/>
    internal override IReadOnlyList<string> Extensions { get; } = [".cas"];

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The launch puts the tape in itself, so a target cannot give <c>cassette</c>; and it boots with no disk, so the
    ///   ROM starts in BASIC rather than waiting for one.
    ///  </para>
    /// </remarks>
    internal override void Launch(ProjectTarget target, JsonObject launch)
    {
        foreach (string option in (string[])["cassette", "disks", "diskController"])
        {
            if (launch.ContainsKey(option))
            {
                string why = option == "cassette"
                    ? "loads its own tape with SYSTEM"
                    : "boots with no disk controller, for the ROM to start in BASIC";

                throw new ProjectException(
                    $"{target.Project.File}: target {target.Name}: a level2 target {why}, so its options and its launch cannot give '{option}'.");
            }
        }
    }

    /// <inheritdoc/>
    internal override TargetMedia Write(TargetBuild build)
    {
        string name = ProgramName(build.Target);
        if (!build.Target.BuildsImage)
        {
            return new(File: null, FileKind: null, Image: null, ImageKind: null, "the binary is the program's bytes from its load address");
        }

        (int start, byte[] bytes) = ProjectBuild.Image(build);
        string tape = Beside(build, ".cas");
        File.WriteAllBytes(tape, SystemTape.Write(name, start, bytes, build.Entry));
        return new(File: null, FileKind: null, tape, "SYSTEM tape (CAS)", $"SYSTEM, then {name} at the *? prompt, then / once it has loaded");
    }

    /// <summary>
    ///  Gets the name of a target's program on its tape: its project's name in capitals, its letters and digits from a
    ///  letter, cut to six.
    /// </summary>
    /// <param name="target">The target.</param>
    /// <returns>The name, or <c>PROG</c> when none of the project's name is left.</returns>
    internal static string ProgramName(ProjectTarget target)
    {
        string name = new([.. target.Project.Name.ToUpperInvariant().Where(char.IsAsciiLetterOrDigit)]);
        name = name.TrimStart('0', '1', '2', '3', '4', '5', '6', '7', '8', '9');
        return name.Length == 0 ? "PROG" : name[..Math.Min(name.Length, SystemTape.NameLength)];
    }
}
