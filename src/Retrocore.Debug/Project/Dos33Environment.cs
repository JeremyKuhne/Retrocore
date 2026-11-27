// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using Retrocore.Media;
using System.Text.Json.Nodes;

namespace Retrocore.Debug.Project;

/// <summary>
///  The <c>dos33</c> environment: an Apple II program as a B file on a DOS 3.3 disk, whose <c>HELLO</c> starts it
///  as the disk boots.
/// </summary>
/// <remarks>
///  <para>
///   The disk, <c>&lt;name&gt;.dsk</c> in DOS 3.3's sector order, holds DOS 3.3 (1983) as <c>INIT</c> writes it on a
///   48K machine, built from the SDK's sources; <c>HELLO</c>, in the machine's BASIC; the program, a B file at its load
///   address named for the project in capitals; and the target's <c>files</c>, each a B file at its <c>address</c>, or
///   <c>$0000</c> when it gives none, for a program to <c>BLOAD</c> with <c>,A</c>. <c>HELLO</c> <c>BRUN</c>s the
///   program when its entry is its first byte, and otherwise <c>BLOAD</c>s it and <c>CALL</c>s its entry.
///   <c>"image": false</c> leaves the disk out, and the binary holds what the B file would, the bytes from its load
///   address. A launch boots the disk.
///  </para>
/// </remarks>
internal sealed class Dos33Environment : TargetEnvironment
{
    /// <summary>
    ///  The most characters a DOS 3.3 file name has.
    /// </summary>
    internal const int NameLength = 30;

    /// <inheritdoc/>
    internal override string Name => "dos33";

    /// <inheritdoc/>
    internal override bool TakesFiles => true;

    /// <inheritdoc/>
    internal override bool BuildsImage => true;

    /// <inheritdoc/>
    internal override bool BootsImage => true;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   DOS boots and HELLO starts the program in a few of the machine's seconds; a launch that has not started it in
    ///   30 has failed, such as at a DOS error.
    ///  </para>
    /// </remarks>
    internal override int BootSeconds => 30;

    /// <inheritdoc/>
    internal override IReadOnlyList<string> Extensions { get; } = [".dsk"];

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The disk goes in slot 6's Disk II, the SDK's firmware's, and the machine boots it as it powers on. The Apple II
    ///   does that with the Autostart ROM, which the launch gives it: its original Monitor stops at its prompt.
    ///  </para>
    /// </remarks>
    internal override void Launch(ProjectTarget target, JsonObject launch)
    {
        if (target.Machine.Id == "apple2-ii")
        {
            if (launch.String("monitor") is "original")
            {
                throw new ProjectException(
                    $"{target.Project.File}: target {target.Name}: a dos33 target boots its disk as the machine powers on, which the Apple II's original Monitor does not do; leave out 'monitor', or give 'autostart'.");
            }

            launch["monitor"] = "autostart";
        }

        // The launch holds the target's options and the launch configuration's own attributes.
        foreach (string option in (string[])["diskImage", "diskController", "diskBootRom", "diskSequencerRom", "sequencerLayout", "diskSectors"])
        {
            if (launch.ContainsKey(option))
            {
                throw new ProjectException(
                    $"{target.Project.File}: target {target.Name}: a dos33 target boots its own disk in slot 6's 16-sector Disk II, so its options and its launch cannot give '{option}'.");
            }
        }

        launch["diskController"] = "diskII";
    }

    /// <inheritdoc/>
    internal override TargetMedia Write(TargetBuild build)
    {
        string program = ProgramName(build.Target);
        if (!build.Target.BuildsImage)
        {
            return new(File: null, FileKind: null, Image: null, ImageKind: null, $"the binary is the B file {program}, which loads at its first address");
        }

        string disk = Beside(build, ".dsk");
        File.WriteAllBytes(disk, Disk(build));
        return new(File: null, FileKind: null, disk, "DOS 3.3 disk", $"boot the disk, and HELLO starts {program}");
    }

    /// <summary>
    ///  Builds a target's DOS 3.3 disk.
    /// </summary>
    /// <param name="build">The build.</param>
    /// <returns>The disk's 143,360 bytes, in DOS 3.3's sector order.</returns>
    /// <exception cref="ProjectException">
    ///  A file's name is not a DOS 3.3 name, two files share a name, or the files do not fit on the disk.
    /// </exception>
    /// <exception cref="IOException">A file cannot be read.</exception>
    /// <exception cref="UnauthorizedAccessException">A file cannot be read.</exception>
    internal static byte[] Disk(TargetBuild build)
    {
        ProjectTarget target = build.Target;
        (int start, byte[] bytes) = ProjectBuild.Image(build);
        string program = ProgramName(target);
        if (program == "HELLO")
        {
            throw new ProjectException(
                $"{target.Project.File}: target {target.Name}: the program would be HELLO on the disk, the name of the program that starts it; give the project another 'name'.");
        }

        // HELLO is in the machine's own BASIC: Integer BASIC on the Apple II, which has no CHR$, so its Ctrl-D is in
        // the string, as the escape {$84}.
        bool integer = target.Machine.Id == "apple2-ii";
        string command = build.Entry == start ? $"BRUN {program}" : $"BLOAD {program}";
        // Integer BASIC's numbers run from -32767 to 32767, so CALL takes an address from $8000 as a negative one, and
        // $8000 itself as the sum Integer BASIC makes of -32767 and -1.
        string address = !integer || build.Entry <= short.MaxValue
            ? $"{build.Entry}"
            : build.Entry == 0x8000 ? "-32767-1" : $"{build.Entry - 0x10000}";

        string call = build.Entry == start ? "" : $":CALL {address}";
        string text = integer
            ? $"10 PRINT \"{{$84}}{command}\"{call}\n"
            : $"10 PRINT CHR$(4);\"{command}\"{call}\n";

        BasicProgram hello = BasicProgram.Parse(text, integer ? BasicDialect.Integer : BasicDialect.AppleSoft).Program
            ?? throw new ProjectException($"{target.Project.File}: target {target.Name}: the greeting program does not parse.");

        List<DosFile> files =
        [
            integer ? DosFile.IntegerBasic("HELLO", hello.ToImage()) : DosFile.AppleSoft("HELLO", hello.ToImage(address: 0x0801)),
            DosFile.Binary(program, start, bytes)
        ];

        HashSet<string> names = [with(StringComparer.Ordinal), "HELLO", program];
        foreach (TargetFile file in target.Files)
        {
            string name = file.Name ?? Path.GetFileName(file.Path).ToUpperInvariant();
            if (!IsName(name))
            {
                throw new ProjectException(
                    $"{target.Project.File}: target {target.Name}: '{name}' is not a DOS 3.3 file name, 1 to {NameLength} characters from a capital letter with no comma; give its file a 'name'.");
            }

            if (!names.Add(name))
            {
                throw new ProjectException($"{target.Project.File}: target {target.Name}: two files on the disk are named {name}.");
            }

            files.Add(DosFile.Binary(name, file.Address ?? 0, File.ReadAllBytes(file.Path)));
        }

        byte[] dos = SdkModules.AssembleDos(SdkModules.DosPath("Dos33.asm"), master: false).Sections[0].Bytes.ToArray();
        try
        {
            return DosDisk.Create(DosDisk.Dos33Tracks(dos), files);
        }
        catch (ArgumentException exception)
        {
            throw new ProjectException($"{target.Project.File}: target {target.Name}: its files do not fit on a DOS 3.3 disk: {exception.Message}");
        }
    }

    /// <summary>
    ///  Gets the name of a target's program on its disk: its project's name in capitals, its letters, digits and dots.
    /// </summary>
    /// <param name="target">The target.</param>
    /// <returns>The name, or <c>PROGRAM</c> when that does not start with a letter.</returns>
    internal static string ProgramName(ProjectTarget target) => ProgramName(target.Project.Name);

    /// <summary>
    ///  Gets the name a project's program has on its targets' disks: its name in capitals, its letters, digits and dots.
    /// </summary>
    /// <param name="projectName">The project's name.</param>
    /// <returns>The name, or <c>PROGRAM</c> when that does not start with a letter.</returns>
    internal static string ProgramName(string projectName)
    {
        string name = new([.. projectName.ToUpperInvariant().Where(character => character is (>= 'A' and <= 'Z') or (>= '0' and <= '9') or '.')]);
        return name.Length == 0 || !char.IsAsciiLetter(name[0]) ? "PROGRAM" : name[..Math.Min(name.Length, NameLength)];
    }

    // A DOS 3.3 file name: 1 to 30 printable characters from a capital letter, with no comma, which ends a name in a
    // command.
    private static bool IsName(string name) =>
        name.Length is > 0 and <= NameLength
            && char.IsAsciiLetterUpper(name[0])
            && name.All(character => character is >= ' ' and < '\u007F' and not ',');
}
