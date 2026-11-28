// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media.Trs80;
using System.Text.Json.Nodes;

namespace Retrocore.Debug.Project;

/// <summary>
///  The <c>diskbasic</c> environment: a Color Computer program as a machine-language file on an RS-DOS disk, which
///  Disk BASIC's <c>LOADM</c> loads and <c>EXEC</c> starts.
/// </summary>
/// <remarks>
///  <para>
///   The disk, <c>&lt;name&gt;.dsk</c>, is a JVC image of 35 tracks (<see cref="RsDosDisk"/>): the program as
///   <c>&lt;NAME&gt;.BIN</c>, the project's name in capitals cut to eight, in Disk BASIC's binary format, its bytes from
///   the load address as one block and its entry as the address <c>EXEC</c> starts; and the target's <c>files</c>,
///   each a binary data file (type 1) by its <c>name</c>, or its file name in capitals, as <c>NAME.EXT</c>, which keeps
///   no load address and holds at least a byte. A launch fits the disk controller with Disk BASIC, from the SDK's
///   sources or the dumps the launch's ROM folder gives, puts the disk in drive 0, and at BASIC's
///   <c>OK</c> types <c>LOADM"&lt;NAME&gt;"</c> and, once the program is in, <c>EXEC</c>, which jumps to its entry;
///   the program goes back to BASIC with <c>RTS</c>. <c>"image": false</c> leaves the disk out, and the binary holds
///   the bytes from the load address.
///  </para>
/// </remarks>
internal sealed class DiskbasicEnvironment : TargetEnvironment
{
    /// <summary>
    ///  The extension of the program's file, which <c>LOADM</c> takes when a name gives none.
    /// </summary>
    internal const string Extension = "BIN";

    /// <inheritdoc/>
    internal override string Name => "diskbasic";

    /// <inheritdoc/>
    internal override bool TakesFiles => true;

    /// <inheritdoc/>
    internal override bool BuildsImage => true;

    /// <inheritdoc/>
    internal override bool BootsImage => true;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Disk BASIC starts and LOADM loads the program from the disk; a launch that has not started it in 60 of the
    ///   machine's seconds has failed, such as at a disk error.
    ///  </para>
    /// </remarks>
    internal override int BootSeconds => 60;

    /// <inheritdoc/>
    internal override IReadOnlyList<string> Extensions { get; } = [".dsk"];

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The launch fits the disk controller and puts its own disk in drive 0, so a target cannot give disks, the disk
    ///   controller, a cassette or a cartridge, nor, on a CoCo 1 or 2, leave out Extended BASIC, whose graphics pages
    ///   the maps place the program above.
    ///  </para>
    /// </remarks>
    internal override void Launch(ProjectTarget target, JsonObject launch)
    {
        string where = $"{target.Project.File}: target {target.Name}";
        if (target.Machine.Id != "coco3" && launch.String("extendedBasic") is "none")
        {
            throw new ProjectException(
                $"{where}: a diskbasic target runs under Disk Extended Color BASIC, whose memory its maps give, so its options and its launch cannot give 'extendedBasic' none.");
        }

        foreach (string option in (string[])["disks", "diskController", "cassette", "cartridge"])
        {
            if (launch.ContainsKey(option))
            {
                string why = option switch
                {
                    "disks" or "diskController" => "boots Disk BASIC with its own disk in drive 0",
                    "cartridge" => "boots Disk BASIC from the cartridge port, which a cartridge would take over",
                    _ => "loads its program from its disk under Disk BASIC"
                };

                throw new ProjectException(
                    $"{where}: a diskbasic target {why}, so its options and its launch cannot give '{option}'.");
            }
        }

        launch["diskController"] = true;
    }

    /// <inheritdoc/>
    internal override TargetMedia Write(TargetBuild build)
    {
        ProjectTarget target = build.Target;
        string name = ProgramName(target);
        if (!target.BuildsImage)
        {
            return new(File: null, FileKind: null, Image: null, ImageKind: null, "the binary is the program's bytes from its load address");
        }

        (int start, byte[] bytes) = ProjectBuild.Image(build);
        List<(string Name, string Extension, byte Type, bool Ascii, byte[] Bytes)> files =
        [
            (name, Extension, RsDosDisk.MachineLanguage, false, RsDosDisk.MachineLanguageFile([(start, bytes)], build.Entry))
        ];

        HashSet<string> names = [with(StringComparer.Ordinal), RsDosDisk.Shown(name, Extension)];
        foreach (TargetFile data in target.Files)
        {
            string full = data.Name ?? Path.GetFileName(data.Path).ToUpperInvariant();
            if (data.Address is not null)
            {
                throw new ProjectException(
                    $"{target.Project.File}: target {target.Name}: {full} goes on the disk as a data file, which keeps no load address, so it cannot give 'address'.");
            }

            int dot = full.IndexOf('.', StringComparison.Ordinal);
            (string file, string extension) = dot < 0 ? (full, "") : (full[..dot], full[(dot + 1)..]);
            if (!RsDosDisk.IsName(file, 8) || !(extension.Length == 0 || RsDosDisk.IsName(extension, 3)))
            {
                throw new ProjectException(
                    $"{target.Project.File}: target {target.Name}: '{full}' is not a name the SDK puts on an RS-DOS disk, 1 to 8 capital letters and digits from a letter, then an extension of up to 3, also from a letter; give its file a 'name'.");
            }

            if (!names.Add(RsDosDisk.Shown(file, extension)))
            {
                throw new ProjectException($"{target.Project.File}: target {target.Name}: two files on the disk are named {RsDosDisk.Shown(file, extension)}.");
            }

            byte[] contents = File.ReadAllBytes(data.Path);
            if (contents.Length == 0)
            {
                throw new ProjectException($"{target.Project.File}: target {target.Name}: {full} is empty, and a file on the disk holds at least a byte.");
            }

            files.Add((file, extension, RsDosDisk.Data, false, contents));
        }

        byte[] image;
        try
        {
            image = RsDosDisk.Create(files);
        }
        // The names and contents are checked above, so only the disk's room is left to fail.
        catch (InvalidOperationException exception)
        {
            throw new ProjectException($"{target.Project.File}: target {target.Name}: its files do not fit on an RS-DOS disk: {exception.Message}");
        }

        string disk = Beside(build, ".dsk");
        File.WriteAllBytes(disk, image);
        return new(File: null, FileKind: null, disk, "RS-DOS disk (JVC)", $"LOADM\"{name}\" from drive 0, then EXEC");
    }

    /// <summary>
    ///  Gets the name of a target's program on its disk: its project's name in capitals, its letters and digits from a
    ///  letter, cut to eight.
    /// </summary>
    /// <param name="target">The target.</param>
    /// <returns>The name, or <c>PROGRAM</c> when none of the project's name is left.</returns>
    internal static string ProgramName(ProjectTarget target) => ColorbasicEnvironment.ProgramName(target);
}
