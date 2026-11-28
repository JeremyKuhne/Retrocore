// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media.Floppy;
using System.Text.Json.Nodes;

namespace Retrocore.Debug.Project;

/// <summary>
///  The <c>cpm</c> environment: a CP/M 2.2 program as a <c>.COM</c> file, which the CCP loads at <c>$0100</c> and runs
///  when its name is typed at the prompt; so far on the Kaypro II.
/// </summary>
/// <remarks>
///  <para>
///   Its file, <c>&lt;name&gt;.com</c>, is the program's bytes from <c>$0100</c>, where the CCP loads and starts every
///   command, so the program's entry is its first byte, or its first byte is a <c>JP</c> to it. CP/M is not an SDK
///   source, so the disk, <c>&lt;name&gt;.img</c>, is the Kaypro II's CP/M 2.2 system disk, found by its hash
///   (<see cref="BootMedia"/>), with the program added as <c>&lt;NAME&gt;.COM</c> and the target's <c>files</c> under
///   their names (<see cref="CpmDisk"/>). Without the system disk the build writes the program alone and says what it
///   needs, and a launch fails naming it. A launch puts the disk in drive A, and once CP/M shows <c>A&gt;</c>, types
///   the program's name. The Apple II with a SoftCard, the TRS-80 Model 4 and the Altair need a CP/M system disk of
///   their own, which the SDK does not list yet.
///  </para>
/// </remarks>
internal sealed class CpmEnvironment : TargetEnvironment
{
    /// <summary>
    ///  The boot media set the Kaypro II's disk is built from.
    /// </summary>
    internal const string KayproSystem = "cpm22-kaypro2";

    /// <summary>
    ///  Where the CCP loads a command and starts it.
    /// </summary>
    internal const int LoadAddress = 0x0100;

    /// <summary>
    ///  The Z80's <c>JP</c>, the 8080's <c>JMP</c>, which may start a program whose entry is not its first byte.
    /// </summary>
    internal const byte Jump = 0xC3;

    /// <summary>
    ///  The most characters a CP/M file's name has, before its type.
    /// </summary>
    internal const int NameLength = 8;

    // The CCP's built-in commands, which it runs before it looks for a file.
    private static readonly HashSet<string> s_builtIn = [with(StringComparer.Ordinal), "DIR", "ERA", "REN", "SAVE", "TYPE", "USER"];

    /// <inheritdoc/>
    internal override string Name => "cpm";

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
    ///   The Kaypro boots CP/M and the CCP loads the program, which the disk's 4K free keeps small, in a few of the
    ///   machine's seconds; a launch that has not started it in 30 has failed, such as at a disk error.
    ///  </para>
    /// </remarks>
    internal override int BootSeconds => 30;

    /// <inheritdoc/>
    internal override IReadOnlyList<string> Extensions { get; } = [".com", ".img"];

    /// <inheritdoc/>
    protected override IEnumerable<string> OwnProblems(ProjectTarget target)
    {
        if (target.Machine.Id != "kaypro2")
        {
            yield return $"the 'cpm' environment builds only for the Kaypro II yet, whose CP/M system disk the SDK lists; {target.Machine.Id} needs one of its own";
        }

        // The CCP runs its own commands of these names rather than a file's.
        if (s_builtIn.Contains(ProgramName(target)))
        {
            yield return $"its program would be {ProgramName(target)}.COM, which the CCP's own {ProgramName(target)} command stands in for when its name is typed; give the project another 'name'";
        }

        if (target.BootImage is { } folder && !Directory.Exists(folder))
        {
            yield return $"its 'bootImage', {folder}, is not a folder of the Kaypro II's CP/M disk";
        }
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The launch puts its own disk in drive A and types the program's name, so a target cannot give <c>disks</c> or
    ///   <c>command</c>; and it fails, naming the system disk, when the build found none.
    ///  </para>
    /// </remarks>
    internal override void Launch(ProjectTarget target, JsonObject launch)
    {
        string where = $"{target.Project.File}: target {target.Name}";
        foreach (string option in (string[])["disks", "command"])
        {
            if (launch.ContainsKey(option))
            {
                throw new ProjectException(
                    $"{where}: a cpm target boots its own disk in drive A and types its program's name, so its options and its launch cannot give '{option}'.");
            }
        }

        if (target.BuildsImage && Find(target) is null)
        {
            BootMediaSet set = BootMedia.Named(SdkModules.SdkDirectory, KayproSystem);
            throw new ProjectException($"{where}: it boots its CP/M disk, but {BootMedia.Missing(set, BootMedia.Roots(set, target.BootImage))}.");
        }
    }

    /// <inheritdoc/>
    internal override TargetMedia Write(TargetBuild build)
    {
        ProjectTarget target = build.Target;
        string name = ProgramName(target);
        (int start, byte[] bytes) = Command(build);
        string file = Beside(build, ".com");
        File.WriteAllBytes(file, bytes);
        if (!target.BuildsImage)
        {
            return new(file, "CP/M command (.COM)", Image: null, ImageKind: null, $"put it on a CP/M disk as {name}.COM, and type {name} at the prompt");
        }

        if (Find(target) is not { } system)
        {
            BootMediaSet set = BootMedia.Named(SdkModules.SdkDirectory, KayproSystem);
            return new(file, "CP/M command (.COM)", Image: null, ImageKind: null,
                $"no disk: {BootMedia.Missing(set, BootMedia.Roots(set, target.BootImage))}");
        }

        byte[] image = File.ReadAllBytes(system);
        string where = $"{target.Project.File}: target {target.Name}";
        try
        {
            CpmDisk.Add(image, CpmGeometry.KayproII, name, "COM", bytes);
            foreach (TargetFile data in target.Files)
            {
                string full = data.Name ?? Path.GetFileName(data.Path).ToUpperInvariant();
                if (data.Address is not null)
                {
                    throw new ProjectException($"{where}: {full} goes on the CP/M disk as a file, which keeps no load address, so it cannot give 'address'.");
                }

                int dot = full.IndexOf('.', StringComparison.Ordinal);
                (string fileName, string type) = dot < 0 ? (full, "") : (full[..dot], full[(dot + 1)..]);
                if (!CpmDisk.IsName(fileName, 8) || !(type.Length == 0 || CpmDisk.IsName(type, 3)))
                {
                    throw new ProjectException(
                        $"{where}: '{full}' is not a name the SDK puts on a CP/M disk, 1 to 8 capital letters and digits from a letter, then a type of up to 3, also from a letter; give its file a 'name'.");
                }

                CpmDisk.Add(image, CpmGeometry.KayproII, fileName, type, File.ReadAllBytes(data.Path));
            }
        }
        catch (Exception exception) when (exception is ArgumentException or InvalidOperationException)
        {
            // The system disk has 4K free, as its own files fill the rest.
            throw new ProjectException($"{where}: on the CP/M disk: {exception.Message}");
        }

        string disk = Beside(build, ".img");
        File.WriteAllBytes(disk, image);
        return new(file, "CP/M command (.COM)", disk, "Kaypro II CP/M disk", $"boot the disk in drive A, and type {name} at A>");
    }

    /// <summary>
    ///  Gets a target's program as the CCP loads it: its bytes from <c>$0100</c>, checked to start at its entry or with a
    ///  <c>JP</c> to it.
    /// </summary>
    /// <param name="build">The build.</param>
    /// <returns>The load address and the bytes.</returns>
    /// <exception cref="ProjectException">
    ///  The program does not load at <c>$0100</c>, or neither starts at its entry nor with a <c>JP</c> to it.
    /// </exception>
    internal static (int Start, byte[] Bytes) Command(TargetBuild build)
    {
        (int start, byte[] bytes) = ProjectBuild.Image(build);
        string where = $"{build.Target.Project.File}: target {build.Target.Name}";
        if (start != LoadAddress)
        {
            throw new ProjectException($"{where}: the CCP loads a command at ${LoadAddress:X4}, but the program starts at ${start:X4}; place it at ${LoadAddress:X4}.");
        }

        bool jumps = bytes.Length >= 3 && bytes[0] == Jump && (bytes[1] | (bytes[2] << 8)) == build.Entry;
        return build.Entry == start || jumps
            ? (start, bytes)
            : throw new ProjectException(
                $"{where}: the CCP starts a command at its first byte, ${start:X4}, but the entry is ${build.Entry:X4}; start the program at its entry, or with JP to it.");
    }

    /// <summary>
    ///  Gets the name of a target's program on its disk, which is typed to run it: its project's name in capitals, its
    ///  letters and digits from a letter, cut to eight.
    /// </summary>
    /// <param name="target">The target.</param>
    /// <returns>The name, or <c>PROGRAM</c> when none of the project's name is left.</returns>
    internal static string ProgramName(ProjectTarget target)
    {
        string name = new([.. target.Project.Name.ToUpperInvariant().Where(char.IsAsciiLetterOrDigit)]);
        name = name.TrimStart('0', '1', '2', '3', '4', '5', '6', '7', '8', '9');
        return name.Length == 0 ? "PROGRAM" : name[..Math.Min(name.Length, NameLength)];
    }

    // The Kaypro II's CP/M disk, found by its hash, or null.
    private static string? Find(ProjectTarget target)
    {
        BootMediaSet set = BootMedia.Named(SdkModules.SdkDirectory, KayproSystem);
        return BootMedia.Find(set, BootMedia.Roots(set, target.BootImage))?.Values.Single();
    }
}
