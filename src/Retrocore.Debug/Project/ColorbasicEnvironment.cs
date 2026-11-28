// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media.Trs80;
using System.Text.Json.Nodes;

namespace Retrocore.Debug.Project;

/// <summary>
///  The <c>colorbasic</c> environment: a Color Computer program on a cassette, which Color BASIC's <c>CLOADM</c> loads
///  and <c>EXEC</c> starts.
/// </summary>
/// <remarks>
///  <para>
///   The tape, <c>&lt;name&gt;.cas</c>, is one machine-language file (<see cref="CocoTape"/>): the program's bytes from
///   its load address, under the project's name in capitals cut to eight, with its entry as the address <c>EXEC</c>
///   starts. A launch puts it in the cassette recorder, waits for BASIC's <c>OK</c>, types <c>CLOADM"&lt;NAME&gt;"</c>,
///   and once the program has loaded and the tape has stopped, <c>EXEC</c>, which jumps to its entry; the program goes
///   back to BASIC with <c>RTS</c>. <c>"image": false</c> leaves the tape out, and the binary holds the bytes from the
///   load address.
///  </para>
/// </remarks>
internal sealed class ColorbasicEnvironment : TargetEnvironment
{
    /// <inheritdoc/>
    internal override string Name => "colorbasic";

    /// <inheritdoc/>
    internal override string NoFiles => "the 'colorbasic' environment puts only its program on its tape, so it takes no 'files'";

    /// <inheritdoc/>
    internal override bool BuildsImage => true;

    /// <inheritdoc/>
    internal override bool BootsImage => true;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The tape plays at 1500 baud, about 180 bytes a second of the machine's time (a fast cassette only runs the
    ///   host faster), so even 32K plays in about three of the machine's minutes; a launch that has not started the
    ///   program in ten has failed, such as at an I/O error.
    ///  </para>
    /// </remarks>
    internal override int BootSeconds => 600;

    /// <inheritdoc/>
    internal override IReadOnlyList<string> Extensions { get; } = [".cas"];

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The launch puts the tape in itself and boots BASIC from the machine's ROMs, so a target cannot give a cassette,
    ///   a cartridge, disks or a disk controller, which would start Disk BASIC: that is the <c>diskbasic</c>
    ///   environment. Nor can a CoCo 1 or 2 target leave out Extended BASIC, whose graphics pages and program the maps
    ///   place it above.
    ///  </para>
    /// </remarks>
    internal override void Launch(ProjectTarget target, JsonObject launch)
    {
        // The maps place the program above Extended BASIC's graphics pages and program, which Color BASIC alone, on a
        // CoCo 1 or 2 without Extended BASIC, puts elsewhere; the CoCo 3's one ROM always has it.
        if (target.Machine.Id != "coco3" && launch.String("extendedBasic") is "none")
        {
            throw new ProjectException(
                $"{target.Project.File}: target {target.Name}: a colorbasic target runs under Extended Color BASIC, whose memory its maps give, so its options and its launch cannot give 'extendedBasic' none.");
        }

        foreach (string option in (string[])["cassette", "cartridge", "disks", "diskController"])
        {
            if (launch.ContainsKey(option))
            {
                string why = option is "cassette" or "cartridge"
                    ? "loads its own tape with CLOADM under Color BASIC"
                    : "boots Color BASIC with no disk controller, as Disk BASIC is the diskbasic environment";

                throw new ProjectException(
                    $"{target.Project.File}: target {target.Name}: a colorbasic target {why}, so its options and its launch cannot give '{option}'.");
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
        File.WriteAllBytes(tape, CocoTape.Write(name, start, bytes, build.Entry));
        return new(File: null, FileKind: null, tape, "Color Computer tape (CAS)", $"CLOADM\"{name}\", then EXEC once it has loaded");
    }

    /// <summary>
    ///  Gets the name of a target's program on its tape: its project's name in capitals, its letters and digits from a
    ///  letter, cut to eight.
    /// </summary>
    /// <param name="target">The target.</param>
    /// <returns>The name, or <c>PROGRAM</c> when none of the project's name is left.</returns>
    internal static string ProgramName(ProjectTarget target)
    {
        string name = new([.. target.Project.Name.ToUpperInvariant().Where(char.IsAsciiLetterOrDigit)]);
        name = name.TrimStart('0', '1', '2', '3', '4', '5', '6', '7', '8', '9');
        return name.Length == 0 ? "PROGRAM" : name[..Math.Min(name.Length, CocoTape.NameLength)];
    }
}
