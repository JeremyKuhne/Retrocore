// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media.Acorn;
using System.Text.Json.Nodes;

namespace Retrocore.Debug.Project;

/// <summary>
///  The <c>dfs</c> environment: a BBC Micro program as a <c>*RUN</c> file on an Acorn DFS disk, whose <c>!BOOT</c> runs
///  it when SHIFT-BREAK boots the disk.
/// </summary>
/// <remarks>
///  <para>
///   The disk, <c>&lt;name&gt;.ssd</c>, one side of 80 tracks, holds the program as <c>$.&lt;NAME&gt;</c>, the project's name
///   in capitals cut to the DFS's seven characters, loading at its load address and running at its entry; the target's
///   <c>files</c>, each at its <c>address</c> or <c>&amp;0000</c>, for a program to load with OSFILE at an address of
///   its own; and <c>$.!BOOT</c>, <c>*RUN &lt;NAME&gt;</c>, with the disk's boot option set to <c>*EXEC</c> it. A file's
///   name is <c>D.NAME</c>, in directory <c>D</c>, or <c>NAME</c> in <c>$</c>. The same files go on a UEF tape,
///   <c>&lt;name&gt;.uef</c>, for the tape filing system, at 1200 baud, each named <c>D.NAME</c>, or <c>NAME</c> for
///   <c>$</c>. <c>"image": false</c> leaves both out. A launch
///   boots the disk, holding SHIFT as the machine powers on.
///  </para>
/// </remarks>
internal sealed class DfsEnvironment : TargetEnvironment
{
    // The most characters a DFS file name has, without its directory.
    private const int NameLength = 7;

    /// <inheritdoc/>
    internal override string Name => "dfs";

    /// <inheritdoc/>
    internal override bool TakesFiles => true;

    /// <inheritdoc/>
    internal override bool BuildsImage => true;

    /// <inheritdoc/>
    internal override bool BootsImage => true;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The MOS and the DFS start, and the DFS loads and runs the program, in a few of the machine's seconds; a launch
    ///   that has not started it in 30 has failed, such as at a filing system's error.
    ///  </para>
    /// </remarks>
    internal override int BootSeconds => 30;

    /// <inheritdoc/>
    internal override IReadOnlyList<string> Extensions { get; } = [".ssd", ".uef"];

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The disk goes in drive 0 of the disk interface, which the launch fits, and the machine boots it with SHIFT
    ///   held from power-on, as SHIFT-BREAK does.
    ///  </para>
    /// </remarks>
    internal override void Launch(ProjectTarget target, JsonObject launch)
    {
        foreach (string option in (string[])["disks", "boot", "diskInterface"])
        {
            if (launch.ContainsKey(option))
            {
                throw new ProjectException(
                    $"{target.Project.File}: target {target.Name}: a dfs target boots its own disk in drive 0, so its options and its launch cannot give '{option}'.");
            }
        }

        launch["diskInterface"] = true;
        launch["boot"] = true;
    }

    /// <inheritdoc/>
    internal override TargetMedia Write(TargetBuild build)
    {
        string program = ProgramName(build.Target);
        if (!build.Target.BuildsImage)
        {
            return new(File: null, FileKind: null, Image: null, ImageKind: null, $"the binary is the *RUN file {program}, from its load address");
        }

        (List<AcornDfsFile> files, AcornDfsDisk disk) = Disk(build);
        string ssd = Beside(build, ".ssd");
        File.WriteAllBytes(ssd, disk.ToImage());
        string uef = Beside(build, ".uef");
        File.WriteAllBytes(uef, AcornTapeBuilder.BuildUef(TapeFiles(files)));
        return new(uef, "UEF tape, for *TAPE and *RUN", ssd, "DFS disk", $"SHIFT-BREAK boots the disk, and !BOOT runs {program}");
    }

    /// <summary>
    ///  Builds a target's DFS disk.
    /// </summary>
    /// <param name="build">The build.</param>
    /// <returns>
    ///  The program and data files, as the disk holds them, and the disk with them and its <c>!BOOT</c>.
    /// </returns>
    /// <exception cref="ProjectException">
    ///  A file's name is not a DFS name, two files share a name, or the files do not fit on the disk.
    /// </exception>
    /// <exception cref="IOException">A file cannot be read.</exception>
    /// <exception cref="UnauthorizedAccessException">A file cannot be read.</exception>
    internal static (List<AcornDfsFile> Files, AcornDfsDisk Disk) Disk(TargetBuild build)
    {
        ProjectTarget target = build.Target;
        string where = $"{target.Project.File}: target {target.Name}";
        (int start, byte[] bytes) = ProjectBuild.Image(build);
        string program = ProgramName(target);
        List<AcornDfsFile> files = [new('$', program, (uint)start, (uint)build.Entry, bytes)];
        foreach (TargetFile file in target.Files)
        {
            string given = file.Name ?? Path.GetFileNameWithoutExtension(file.Path).ToUpperInvariant();
            string name = given;
            char directory = '$';
            if (name.Length > 2 && name[1] == '.')
            {
                directory = name[0];
                name = name[2..];
            }

            if (name.Length is 0 or > NameLength || !name.All(AcornDfsFile.IsNameCharacter) || !AcornDfsFile.IsNameCharacter(directory))
            {
                throw new ProjectException(
                    $"{where}: '{given}' is not a DFS file name, D.NAME or NAME with 1 to {NameLength} printable characters, none a space or . : \" # *; give its file a 'name'.");
            }

            AcornDfsFile added = new(directory, name, (uint)(file.Address ?? 0), ExecutionAddress: 0, File.ReadAllBytes(file.Path));

            // The DFS compares names and directories without case.
            bool Same(AcornDfsFile known) => char.ToUpperInvariant(known.Directory) == char.ToUpperInvariant(added.Directory)
                && string.Equals(known.Name, added.Name, StringComparison.OrdinalIgnoreCase);

            if (files.Any(Same) || (added.Directory == '$' && string.Equals(added.Name, AcornDfsDisk.BootFileName, StringComparison.OrdinalIgnoreCase)))
            {
                throw new ProjectException($"{where}: two files on the disk are named {char.ToUpperInvariant(added.Directory)}.{added.Name.ToUpperInvariant()}.");
            }

            files.Add(added);
        }

        AcornDfsDisk disk = AcornDfsDisk.Create(tracks: 80);
        disk.Title = Title(target);
        try
        {
            disk.AddRange(files);
            disk.AddBootFile($"*RUN {program}");
        }
        catch (Exception exception) when (exception is InvalidOperationException or ArgumentException)
        {
            // A full catalogue or disk, or a file too long or at an address the catalogue cannot record.
            throw new ProjectException($"{where}: its files do not fit on a DFS disk: {exception.Message}");
        }

        return (files, disk);
    }

    /// <summary>
    ///  Gets the files a target's tape holds: the disk's, each named <c>D.NAME</c>, or the bare <c>NAME</c> for one in
    ///  <c>$</c>, so a program loads one under <c>*TAPE</c> by that name.
    /// </summary>
    /// <param name="files">The disk's files.</param>
    /// <returns>The tape's files.</returns>
    internal static IEnumerable<AcornTapeFile> TapeFiles(IEnumerable<AcornDfsFile> files) =>
        files.Select(file => new AcornTapeFile(
            file.Directory == '$' ? file.Name : $"{file.Directory}.{file.Name}", file.LoadAddress, file.ExecutionAddress, file.Data));

    /// <summary>
    ///  Gets the name of a target's program on its disk: its project's name in capitals, the characters a DFS name
    ///  takes, cut to seven.
    /// </summary>
    /// <param name="target">The target.</param>
    /// <returns>The name, or <c>PROGRAM</c> when none of the project's name is left.</returns>
    internal static string ProgramName(ProjectTarget target)
    {
        string name = new([.. target.Project.Name.ToUpperInvariant().Where(character => character != '.' && AcornDfsFile.IsNameCharacter(character))]);
        return name.Length == 0 ? "PROGRAM" : name[..Math.Min(name.Length, NameLength)];
    }

    // The disk's title: the project's name in capitals, in the characters a title takes, cut to twelve.
    private static string Title(ProjectTarget target)
    {
        string title = new([.. target.Project.Name.ToUpperInvariant().Where(character => character is > ' ' and < '\u007F')]);
        return title[..Math.Min(title.Length, AcornDfsDisk.MaximumTitleLength)];
    }
}
