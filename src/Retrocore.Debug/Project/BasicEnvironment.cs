// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media.Commodore;
using System.Text.Json.Nodes;

namespace Retrocore.Debug.Project;

/// <summary>
///  The <c>basic</c> environment: a PET program as a PRG whose BASIC line <c>SYS</c>es it, loaded from a tape, or from
///  a 4040 disk when the drive's ROMs are found, and started with <c>RUN</c>.
/// </summary>
/// <remarks>
///  <para>
///   Its file, <c>&lt;name&gt;.prg</c>, loads at BASIC's start, <c>$0401</c>: the line <c>10 SYS&lt;entry&gt;</c>, then
///   zeros to the map's load address, <c>$0410</c>, then the program. It goes on a TAP tape, <c>&lt;name&gt;.tap</c>,
///   which plays from the SDK's sources alone, and on a CBM DOS 2 disk for the 4040, <c>&lt;name&gt;.d64</c>, each
///   under the name <see cref="ProgramName"/> gives. A launch boots the tape: it types <c>LOAD</c> at BASIC's prompt with
///   PLAY down, and <c>RUN</c> once the program has loaded. A target whose <c>image</c> gives <c>"boot": "disk"</c>
///   boots the disk instead, in unit 8's drive 0, with <c>LOAD"&lt;NAME&gt;",8</c>; that needs the 4040's ROMs, which
///   the launch finds by their hashes (<see cref="BootMedia"/>). <c>"image": false</c> leaves the tape and the disk
///   out.
///  </para>
/// </remarks>
internal sealed class BasicEnvironment : TargetEnvironment
{
    /// <summary>
    ///  The boot media set of the drive the disk boots in.
    /// </summary>
    internal const string DriveRoms = "c4040";

    /// <summary>
    ///  The disk's ID, which CBM DOS writes beside its name.
    /// </summary>
    internal const string DiskId = "RC";

    // The most characters a CBM file name, and a tape's, has.
    private const int NameLength = 16;

    /// <inheritdoc/>
    internal override string Name => "basic";

    /// <inheritdoc/>
    internal override string NoFiles => "the 'basic' environment puts only its program on its tape and disk, so it takes no 'files'";

    /// <inheritdoc/>
    internal override bool BuildsImage => true;

    /// <inheritdoc/>
    internal override bool BootsImage => true;

    /// <inheritdoc/>
    internal override IReadOnlyList<string> Boots { get; } = ["tape", "disk"];

    /// <inheritdoc/>
    internal override bool TakesBootImage => true;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   A tape plays about 56 of the program's bytes a second, as each block is written twice, so the largest program
    ///   a 32K PET holds, 31K, plays for nearly ten of the machine's minutes; a launch that has not started the program
    ///   in twenty has failed, such as at a tape or disk error.
    ///  </para>
    /// </remarks>
    internal override int BootSeconds => 1200;

    /// <inheritdoc/>
    internal override IReadOnlyList<string> Extensions { get; } = [".prg", ".tap", ".d64"];

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The tape goes in cassette 1 with PLAY down. The disk goes in unit 8, connected for the launch, with the 4040's
    ///   ROMs found by their hashes in the target's <c>bootImage</c>, the launch's <c>romDirectory</c>,
    ///   <c>RETROCORE_PET_ROMS</c> and <c>RETROCORE_CACHE</c>, and copied to <c>obj/&lt;target&gt;/media/c4040/</c>
    ///   under their usual names; a launch that gives <c>driveRomDirectory</c> takes the ROMs from there instead. BASIC
    ///   1's PET, whose IEEE-488 routines stop disk drives working, boots only its tape.
    ///  </para>
    /// </remarks>
    internal override void Launch(ProjectTarget target, JsonObject launch)
    {
        string where = $"{target.Project.File}: target {target.Name}";
        foreach (string option in (string[])["cassette1", "disks", "diskUnits", "diskModel"])
        {
            if (launch.ContainsKey(option))
            {
                throw new ProjectException(
                    $"{where}: a basic target boots its own tape or disk, so its options and its launch cannot give '{option}'.");
            }
        }

        if (target.ImageBoot != "disk") { return; }
        if (target.Machine.Id == "pet2001")
        {
            throw new ProjectException(
                $"{where}: it boots its 4040 disk, but BASIC 1's IEEE-488 routines have the bug that stops disk drives working; boot the tape, or target a PET with BASIC 2 or 4.");
        }

        if (target.BootImage is { } folder && !Directory.Exists(folder))
        {
            throw new ProjectException($"{where}: its 'bootImage', {folder}, is not a folder of the 4040's ROMs.");
        }

        launch["diskUnits"] = new JsonArray(8);
        if (launch.String("driveRomDirectory") is { Length: > 0 }) { return; }

        BootMediaSet set = BootMedia.Named(SdkModules.SdkDirectory, DriveRoms);
        List<string> roots = BootMedia.Roots(set, target.BootImage, launch.String("romDirectory"));
        Dictionary<string, string> found = BootMedia.Find(set, roots)
            ?? throw new ProjectException($"{where}: it boots its 4040 disk, but {BootMedia.Missing(set, roots)}.");

        launch["driveRomDirectory"] = BootMedia.Gather(set, found, Path.Join(target.Project.Intermediate, target.Name, "media"));
    }

    /// <inheritdoc/>
    internal override TargetMedia Write(TargetBuild build)
    {
        ProjectTarget target = build.Target;
        string name = ProgramName(target);
        byte[] prg = Program(build);
        string file = Beside(build, ".prg");
        File.WriteAllBytes(file, prg);
        if (!target.BuildsImage)
        {
            return new(file, "PRG", Image: null, ImageKind: null, "load it as a program file, and RUN it");
        }

        string tap = Beside(build, ".tap");
        File.WriteAllBytes(tap, PetSysProgram.ToTap(name, prg));
        CbmDosDisk disk = CbmDosDisk.Format(name, DiskId);
        disk.AddProgram(name, prg);
        string d64 = Beside(build, ".d64");
        File.WriteAllBytes(d64, disk.ToD64());
        return target.ImageBoot == "disk"
            ? new(file, "PRG", d64, "4040 disk (D64)", $"LOAD\"{name}\",8 and RUN, in a 4040 with its ROMs; the tape is {Path.GetFileName(tap)}")
            : new(file, "PRG", tap, "PET tape (TAP)", $"LOAD and RUN from the tape; the 4040 disk is {Path.GetFileName(d64)}");
    }

    /// <summary>
    ///  Builds a target's program file: BASIC's line that SYSes its entry, then zeros to its load address, then its
    ///  bytes, behind the load address <c>$0401</c>.
    /// </summary>
    /// <param name="build">The build.</param>
    /// <returns>The PRG's bytes.</returns>
    /// <exception cref="ProjectException">The program starts before the BASIC line ends.</exception>
    internal static byte[] Program(TargetBuild build)
    {
        (int start, byte[] bytes) = ProjectBuild.Image(build);
        byte[] stub = PetSysProgram.Stub(build.Entry);
        int end = PetSysProgram.StubEnd(build.Entry);
        if (start < end)
        {
            throw new ProjectException(
                $"{build.Target.Project.File}: target {build.Target.Name}: the program starts at ${start:X4}, inside the BASIC line that SYSes it, which ends at ${end - 1:X4}.");
        }

        byte[] prg = new byte[2 + start + bytes.Length - PetSysProgram.BasicStart];
        stub.CopyTo(prg, 0);
        bytes.CopyTo(prg, 2 + start - PetSysProgram.BasicStart);
        return prg;
    }

    /// <summary>
    ///  Gets the name of a target's program on its tape and disk: its project's name in capitals, its letters, digits,
    ///  <c>-</c> and <c>.</c>, which CBM DOS takes in a name and a PET's keyboard types, cut to 16.
    /// </summary>
    /// <param name="target">The target.</param>
    /// <returns>The name, or <c>PROGRAM</c> when none of the project's name is left.</returns>
    internal static string ProgramName(ProjectTarget target)
    {
        string name = new([.. target.Project.Name.ToUpperInvariant().Where(character => character is (>= 'A' and <= 'Z') or (>= '0' and <= '9') or '-' or '.')]);
        return name.Length == 0 ? "PROGRAM" : name[..Math.Min(name.Length, NameLength)];
    }
}
