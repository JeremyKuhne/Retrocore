// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;
using System.Text.Json.Nodes;

namespace Retrocore.Debug.Project;

/// <summary>
///  The <c>sos</c> environment: an Apple III program as SOS.INTERP on a SOS 1.3 boot disk built from the SDK's
///  sources, which SOS loads at a fixed address and starts at its first byte.
/// </summary>
/// <remarks>
///  <para>
///   Its file, <c>&lt;name&gt;.interp</c>, is the program as SOS.INTERP: its header and the bytes from the map's load
///   address, <c>$2000</c>, in the system bank. SOS starts an interpreter at its first byte, so the program's entry is
///   its first byte, or its first byte is a <c>JMP</c> on to code that reaches its entry, where a launch stops. The disk, <c>&lt;name&gt;.dsk</c> in DOS order,
///   holds the SDK's boot loader, SOS.KERNEL, a SOS.DRIVER with the console's driver, the program as SOS.INTERP, and
///   the target's <c>files</c>, each a BIN file (type <c>$06</c>) whose aux type is its <c>address</c>, or 0, for a
///   program to read with SOS's OPEN and READ. The volume is named for the project. <c>"image": false</c> leaves the
///   disk out. A launch boots the disk in the built-in drive, <c>.D1</c>, as the machine powers on.
///  </para>
/// </remarks>
internal sealed class SosEnvironment : TargetEnvironment
{
    /// <summary>
    ///  The SOS file type of a binary file, which the target's files are.
    /// </summary>
    internal const int BinaryType = 0x06;

    /// <summary>
    ///  The 6502's <c>JMP</c>, which may start a program whose entry is not its first byte.
    /// </summary>
    internal const byte Jump = 0x4C;

    // The most characters a SOS name has.
    private const int NameLength = 15;

    /// <inheritdoc/>
    internal override string Name => "sos";

    /// <inheritdoc/>
    internal override bool TakesFiles => true;

    /// <inheritdoc/>
    internal override bool BuildsImage => true;

    /// <inheritdoc/>
    internal override bool BootsImage => true;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The boot ROM reads the loader, which loads SOS, its driver and the interpreter, in several of the machine's
    ///   seconds; a launch that has not started the program in sixty has failed, such as at SOS's error.
    ///  </para>
    /// </remarks>
    internal override int BootSeconds => 60;

    /// <inheritdoc/>
    internal override IReadOnlyList<string> Extensions { get; } = [".interp", ".dsk"];

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The disk goes in the built-in drive, <c>.D1</c>, which the boot ROM boots.
    ///  </para>
    /// </remarks>
    internal override void Launch(ProjectTarget target, JsonObject launch)
    {
        if (launch.ContainsKey("disks"))
        {
            throw new ProjectException(
                $"{target.Project.File}: target {target.Name}: a sos target boots its own disk in .D1, so its options and its launch cannot give 'disks'.");
        }
    }

    /// <inheritdoc/>
    internal override TargetMedia Write(TargetBuild build)
    {
        ProjectTarget target = build.Target;
        (int start, byte[] bytes) = Interpreter(build);
        string file = Beside(build, ".interp");
        File.WriteAllBytes(file, SosInterpreterFile.Write(start, bytes));
        if (!target.BuildsImage)
        {
            return new(file, "SOS.INTERP", Image: null, ImageKind: null, "put it on a SOS disk as SOS.INTERP");
        }

        SosVolumeBuilder builder;
        try
        {
            builder = Apple3SdkModules.BuildSosBootDisk(directory: null, VolumeName(target), start, bytes);
        }
        catch (Exception exception) when (exception is ArgumentException or InvalidDataException or FileNotFoundException)
        {
            throw new ProjectException($"{target.Project.File}: target {target.Name}: its SOS boot disk cannot be built: {exception.Message}");
        }

        HashSet<string> names = [with(StringComparer.OrdinalIgnoreCase), "SOS.KERNEL", "SOS.DRIVER", "SOS.INTERP"];
        foreach (TargetFile data in target.Files)
        {
            string name = data.Name ?? Path.GetFileName(data.Path).ToUpperInvariant();
            if (!IsName(name))
            {
                throw new ProjectException(
                    $"{target.Project.File}: target {target.Name}: '{name}' is not a SOS file name, 1 to {NameLength} letters, digits and periods from a letter; give its file a 'name'.");
            }

            if (!names.Add(name))
            {
                throw new ProjectException($"{target.Project.File}: target {target.Name}: two files on the disk are named {name.ToUpperInvariant()}.");
            }

            try
            {
                builder.Add(name, BinaryType, data.Address ?? 0, File.ReadAllBytes(data.Path));
            }
            catch (Exception exception) when (exception is ArgumentException or InvalidOperationException or IOException)
            {
                throw new ProjectException($"{target.Project.File}: target {target.Name}: its files do not fit on a SOS disk: {exception.Message}");
            }
        }

        string disk = Beside(build, ".dsk");
        File.WriteAllBytes(disk, builder.Build(proDosOrder: false));
        return new(file, "SOS.INTERP", disk, "SOS boot disk", "boot the disk in .D1, and SOS starts the program");
    }

    /// <summary>
    ///  Gets a target's program as SOS loads it: its load address and bytes, checked to start at its entry or with a
    ///  <c>JMP</c>, which a program whose entry is elsewhere goes on from.
    /// </summary>
    /// <param name="build">The build.</param>
    /// <returns>The load address and the bytes.</returns>
    /// <exception cref="ProjectException">The program neither starts at its entry nor with a <c>JMP</c>.</exception>
    internal static (int Start, byte[] Bytes) Interpreter(TargetBuild build)
    {
        (int start, byte[] bytes) = ProjectBuild.Image(build);
        bool jumps = bytes.Length >= 3 && bytes[0] == Jump;
        return build.Entry == start || jumps
            ? (start, bytes)
            : throw new ProjectException(
                $"{build.Target.Project.File}: target {build.Target.Name}: SOS starts an interpreter at its first byte, ${start:X4}, but the entry is ${build.Entry:X4}; start the program at its entry, or with jmp on to it.");
    }

    /// <summary>
    ///  Gets a target's volume name: its project's name in capitals, its letters, digits and periods, from a letter, cut
    ///  to fifteen.
    /// </summary>
    /// <param name="target">The target.</param>
    /// <returns>The name, or <c>PROGRAM</c> when none of the project's name is left.</returns>
    internal static string VolumeName(ProjectTarget target)
    {
        string name = new([.. target.Project.Name.ToUpperInvariant().Where(character => character is (>= 'A' and <= 'Z') or (>= '0' and <= '9') or '.')]);
        name = name.TrimStart('.', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9');
        return name.Length == 0 ? "PROGRAM" : name[..Math.Min(name.Length, NameLength)];
    }

    // A SOS file name: 1 to 15 letters, digits and periods, starting with a letter.
    private static bool IsName(string name) =>
        name.Length is > 0 and <= NameLength
            && char.IsAsciiLetter(name[0])
            && name.All(character => char.IsAsciiLetterOrDigit(character) || character == '.');
}
