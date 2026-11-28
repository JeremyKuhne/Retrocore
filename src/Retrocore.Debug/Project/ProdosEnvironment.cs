// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;
using System.Text.Json.Nodes;

namespace Retrocore.Debug.Project;

/// <summary>
///  The <c>prodos</c> environment: an Apple II program as a ProDOS system file, <c>&lt;NAME&gt;.SYSTEM</c>, on a disk
///  with ProDOS 2.4.3, which ProDOS loads at <c>$2000</c> and starts at its first byte as the disk boots.
/// </summary>
/// <remarks>
///  <para>
///   ProDOS is not an SDK source, so the disk is built from ProDOS 2.4.3's own disk, found by its hash
///   (<see cref="BootMedia"/>): its boot blocks and its <c>PRODOS</c> file, then the program as a SYS file (type
///   <c>$FF</c>) loading at <c>$2000</c>, named for the project, and the target's <c>files</c>, each a BIN file (type
///   <c>$06</c>) whose aux type is its <c>address</c>, or 0, for a program to read with the MLI's OPEN and READ. ProDOS
///   runs the volume's first system file whose name ends <c>.SYSTEM</c>, the program, as it starts, at <c>$2000</c>, so the program's entry is its
///   first byte, or its first byte is a <c>JMP</c>, as under SOS. The disk is <c>&lt;name&gt;.po</c>, in ProDOS's
///   block order, and the binary is the SYS file's bytes. Without ProDOS 2.4.3 the build writes the binary and leaves
///   the disk out, saying what it needs, and a launch fails naming it. <c>"image": false</c> leaves the disk out. A
///   launch boots the disk in slot 6, drive 1.
///  </para>
/// </remarks>
internal sealed class ProdosEnvironment : TargetEnvironment
{
    /// <summary>
    ///  The boot media set the disk is built from.
    /// </summary>
    internal const string BootSet = "prodos-2.4.3";

    /// <summary>
    ///  Where ProDOS loads a system file, and starts it.
    /// </summary>
    internal const int LoadAddress = 0x2000;

    /// <summary>
    ///  ProDOS's file type of a system file, which it runs as it starts: SYS.
    /// </summary>
    internal const int SystemType = 0xFF;

    /// <summary>
    ///  ProDOS's file type of a binary file, which the target's files are: BIN.
    /// </summary>
    internal const int BinaryType = 0x06;

    /// <summary>
    ///  The name a system file ends in, which ProDOS looks for as it starts.
    /// </summary>
    internal const string SystemSuffix = ".SYSTEM";

    // ProDOS's own file on its disk, which its boot blocks load.
    private const string ProDosFile = "PRODOS";

    // The most characters a ProDOS name has.
    private const int NameLength = 15;

    /// <inheritdoc/>
    internal override string Name => "prodos";

    /// <inheritdoc/>
    internal override bool TakesFiles => true;

    /// <inheritdoc/>
    internal override bool BuildsImage => true;

    /// <inheritdoc/>
    internal override bool BootsImage => true;

    /// <inheritdoc/>
    internal override bool TakesBootImage => true;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   ProDOS boots and starts the program in a few of the machine's seconds; a launch that has not started it in 30
    ///   has failed, such as at ProDOS's error.
    ///  </para>
    /// </remarks>
    internal override int BootSeconds => 30;

    /// <inheritdoc/>
    internal override IReadOnlyList<string> Extensions { get; } = [".po"];

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The disk goes in slot 6's Disk II, the SDK's firmware's, which boots it as the machine powers on. ProDOS needs
    ///   64K: the II Plus's language card, in slot 0, which its launch has by default, and the IIe's own. The launch
    ///   fails, naming ProDOS 2.4.3, when the build found no ProDOS to put on the disk.
    ///  </para>
    /// </remarks>
    internal override void Launch(ProjectTarget target, JsonObject launch)
    {
        string where = $"{target.Project.File}: target {target.Name}";
        if (target.Machine.Id == "apple2-iiplus" && launch.String("slot0") is { } slot0 && slot0 != "languageCard")
        {
            throw new ProjectException(
                $"{where}: ProDOS needs 64K, which the II Plus has with its language card in slot 0, so a prodos target's options and its launch cannot give 'slot0' {slot0}.");
        }

        foreach (string option in (string[])["diskImage", "diskController", "diskBootRom", "diskSequencerRom", "sequencerLayout", "diskSectors"])
        {
            if (launch.ContainsKey(option))
            {
                throw new ProjectException(
                    $"{where}: a prodos target boots its own disk in slot 6's 16-sector Disk II, so its options and its launch cannot give '{option}'.");
            }
        }

        if (target.BuildsImage && Find(target) is null)
        {
            BootMediaSet set = BootMedia.Named(SdkModules.SdkDirectory, BootSet);
            throw new ProjectException($"{where}: it boots its ProDOS disk, but {BootMedia.Missing(set, BootMedia.Roots(set, target.BootImage))}.");
        }

        launch["diskController"] = "diskII";
    }

    /// <inheritdoc/>
    protected override IEnumerable<string> OwnProblems(ProjectTarget target)
    {
        if (target.BootImage is { } folder && !Directory.Exists(folder))
        {
            yield return $"its 'bootImage', {folder}, is not a folder of ProDOS 2.4.3's disk";
        }
    }

    /// <inheritdoc/>
    internal override TargetMedia Write(TargetBuild build)
    {
        ProjectTarget target = build.Target;
        string program = ProgramName(target);
        (int start, byte[] bytes) = SystemProgram(build);
        if (!target.BuildsImage)
        {
            return new(File: null, FileKind: null, Image: null, ImageKind: null, $"the binary is the system file {program}, which ProDOS loads at ${start:X4}");
        }

        if (Find(target) is not { } system)
        {
            BootMediaSet set = BootMedia.Named(SdkModules.SdkDirectory, BootSet);
            return new(File: null, FileKind: null, Image: null, ImageKind: null,
                $"no disk: {BootMedia.Missing(set, BootMedia.Roots(set, target.BootImage))}. The binary is the system file {program}");
        }

        string disk = Beside(build, ".po");
        File.WriteAllBytes(disk, Disk(build, File.ReadAllBytes(system)));
        return new(File: null, FileKind: null, disk, "ProDOS disk", $"boot the disk, and ProDOS starts {program}");
    }

    /// <summary>
    ///  Builds a target's ProDOS disk from ProDOS's own: its boot blocks and <c>PRODOS</c>, then the program as its
    ///  system file, then the target's files.
    /// </summary>
    /// <param name="build">The build.</param>
    /// <param name="system">ProDOS 2.4.3's disk, in ProDOS order.</param>
    /// <returns>The disk's 143,360 bytes, in ProDOS order.</returns>
    /// <exception cref="ProjectException">
    ///  ProDOS's disk has no <c>PRODOS</c>, a file's name is not a ProDOS name or is taken, or the files do not fit.
    /// </exception>
    /// <exception cref="IOException">A file cannot be read.</exception>
    /// <exception cref="UnauthorizedAccessException">A file cannot be read.</exception>
    internal static byte[] Disk(TargetBuild build, byte[] system)
    {
        ProjectTarget target = build.Target;
        string where = $"{target.Project.File}: target {target.Name}";
        (int start, byte[] bytes) = SystemProgram(build);
        string program = ProgramName(target);
        SosVolumeBuilder builder = new(SosEnvironment.VolumeName(target));
        try
        {
            SosVolume source = SosVolume.Read(system, proDosOrder: true);
            builder.BootFrom(source);
            builder.Add(source, ProDosFile);
        }
        catch (Exception exception) when (exception is InvalidDataException or FileNotFoundException)
        {
            throw new ProjectException($"{where}: ProDOS's disk cannot be read: {exception.Message}");
        }

        HashSet<string> names = [with(StringComparer.OrdinalIgnoreCase), ProDosFile, program];
        try
        {
            builder.Add(program, SystemType, start, bytes);
            foreach (TargetFile data in target.Files)
            {
                string name = data.Name ?? Path.GetFileName(data.Path).ToUpperInvariant();
                if (!IsName(name))
                {
                    throw new ProjectException(
                        $"{where}: '{name}' is not a ProDOS file name, 1 to {NameLength} letters, digits and periods from a letter; give its file a 'name'.");
                }

                if (!names.Add(name))
                {
                    throw new ProjectException($"{where}: two files on the disk are named {name.ToUpperInvariant()}.");
                }

                builder.Add(name, BinaryType, data.Address ?? 0, File.ReadAllBytes(data.Path));
            }
        }
        catch (Exception exception) when (exception is ArgumentException or InvalidOperationException)
        {
            throw new ProjectException($"{where}: its files do not fit on a ProDOS disk: {exception.Message}");
        }

        return builder.Build(proDosOrder: true);
    }

    /// <summary>
    ///  Gets a target's program as ProDOS loads it: its load address, which must be <c>$2000</c>, and its bytes,
    ///  checked to start at its entry or with a <c>JMP</c>.
    /// </summary>
    /// <param name="build">The build.</param>
    /// <returns>The load address and the bytes.</returns>
    /// <exception cref="ProjectException">
    ///  The program does not load at <c>$2000</c>, or neither starts at its entry nor with a <c>JMP</c>.
    /// </exception>
    internal static (int Start, byte[] Bytes) SystemProgram(TargetBuild build)
    {
        (int start, byte[] bytes) = ProjectBuild.Image(build);
        string where = $"{build.Target.Project.File}: target {build.Target.Name}";
        if (start != LoadAddress)
        {
            throw new ProjectException(
                $"{where}: ProDOS loads a system file at ${LoadAddress:X4}, but the program starts at ${start:X4}; place it at ${LoadAddress:X4}.");
        }

        bool jumps = bytes.Length >= 3 && bytes[0] == SosEnvironment.Jump;
        return build.Entry == start || jumps
            ? (start, bytes)
            : throw new ProjectException(
                $"{where}: ProDOS starts a system file at its first byte, ${start:X4}, but the entry is ${build.Entry:X4}; start the program at its entry, or with jmp on to it.");
    }

    /// <summary>
    ///  Gets the name of a target's program on its disk: its project's name in capitals, its letters, digits and
    ///  periods, from a letter, cut to eight, then <c>.SYSTEM</c>.
    /// </summary>
    /// <param name="target">The target.</param>
    /// <returns>The name, such as <c>ADVENTUR.SYSTEM</c>.</returns>
    internal static string ProgramName(ProjectTarget target)
    {
        string name = SosEnvironment.VolumeName(target);
        return name[..Math.Min(name.Length, NameLength - SystemSuffix.Length)] + SystemSuffix;
    }

    // The disk of ProDOS 2.4.3, found by its hash, or null.
    private static string? Find(ProjectTarget target)
    {
        BootMediaSet set = BootMedia.Named(SdkModules.SdkDirectory, BootSet);
        return BootMedia.Find(set, BootMedia.Roots(set, target.BootImage))?.Values.Single();
    }

    // A ProDOS file name: 1 to 15 letters, digits and periods, starting with a letter.
    private static bool IsName(string name) =>
        name.Length is > 0 and <= NameLength
            && char.IsAsciiLetter(name[0])
            && name.All(character => char.IsAsciiLetterOrDigit(character) || character == '.');
}
