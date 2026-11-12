// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Media;
using Touki.Text;

namespace Retrocore.Debug;

/// <summary>
///  Lists and copies out the files on a DOS 3.3 or 3.2 disk image.
/// </summary>
/// <remarks>
///  <para>
///   <c>--dos catalog disk [--json]</c> lists each file's type, name, sectors and, for a binary file, its load address
///   and length. <c>--dos extract disk "NAME" output [--raw]</c> writes a file: a binary file's bytes without its
///   address and length, a BASIC program without its length (as the debugger's BASIC tools read it), a text file as
///   plain text, or with <c>--raw</c> the sectors as DOS stores them. A <c>.po</c> image is read in ProDOS's sector
///   order; a <c>.d13</c> or other 116,480-byte image is DOS 3.2's 13 sectors a track.
///  </para>
/// </remarks>
internal static class DosCommand
{
    private const string Usage = "Usage: --dos catalog disk [--json] | --dos extract disk \"NAME\" output [--raw]";

    /// <summary>
    ///  Runs the command.
    /// </summary>
    /// <param name="args">The arguments after <c>--dos</c>.</param>
    /// <returns>The process exit code.</returns>
    internal static int Run(string[] args)
    {
        try
        {
            return args switch
            {
                ["catalog", string disk, .. string[] rest] => Catalog(disk, rest.Contains("--json")),
                ["extract", string disk, string name, string output, .. string[] rest] =>
                    Extract(disk, name, output, rest.Contains("--raw")),
                _ => Fail(Usage, code: 2)
            };
        }
        catch (Exception exception) when (exception is InvalidDataException or IOException)
        {
            return Fail(exception.Message);
        }
    }

    /// <summary>
    ///  Reads a disk image's files.
    /// </summary>
    /// <param name="disk">The image's path.</param>
    /// <returns>The files, in catalog order.</returns>
    internal static IReadOnlyList<DosFile> Files(string disk)
    {
        if (disk.EndsWith(".woz", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("A WOZ image holds the disk's bits, not its sectors; use a .dsk, .do, .po or .d13 image.");
        }

        return DosDisk.ReadFiles(File.ReadAllBytes(disk), disk.EndsWith(".po", StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>
    ///  Finds a file by name, as DOS matches it: case-sensitive, ignoring trailing spaces.
    /// </summary>
    /// <param name="disk">The image's path.</param>
    /// <param name="name">The name.</param>
    /// <returns>The file.</returns>
    internal static DosFile Find(string disk, string name)
    {
        IReadOnlyList<DosFile> files = Files(disk);
        return files.FirstOrDefault(file => file.Name == name.TrimEnd())
            ?? throw new InvalidDataException(
                $"No file named \"{name}\" on the disk; it has {string.Join(", ", files.Select(file => $"\"{file.Name}\""))}.");
    }

    private static int Catalog(string disk, bool json)
    {
        JsonArray entries = [];
        foreach (DosFile file in Files(disk))
        {
            int sectors = file.Contents.Length / DosDisk.SectorSize;
            bool binary = file.TryGetBinary(out int address, out ReadOnlyMemory<byte> data);
            if (json)
            {
                JsonObject entry = new()
                {
                    ["name"] = file.Name,
                    ["type"] = Letter(file.Type).ToString(),
                    ["locked"] = file.Locked,
                    ["sectors"] = sectors
                };

                if (binary)
                {
                    entry["address"] = address;
                    entry["length"] = data.Length;
                }

                entries.Add((JsonNode)entry);
                continue;
            }

            string where = binary ? $"  ${address:X4}, {data.Length} bytes (${data.Length:X4})" : "";
            Console.WriteLine($"{(file.Locked ? '*' : ' ')}{Letter(file.Type)} {sectors,3} {file.Name}{where}");
        }

        if (json) { Console.WriteLine(entries.ToJsonString()); }
        return 0;
    }

    private static int Extract(string disk, string name, string output, bool raw)
    {
        DosFile file = Find(disk, name);
        ReadOnlyMemory<byte> bytes = file.Contents;
        string description = $"{file.Contents.Length} bytes as DOS stores them";
        if (!raw && file.TryGetBinary(out int address, out ReadOnlyMemory<byte> data))
        {
            bytes = data;
            description = $"{data.Length} bytes (${data.Length:X4}) that load at ${address:X4}";
        }
        else if (!raw && file.TryGetProgram(out ReadOnlyMemory<byte> program))
        {
            bytes = program;
            description = $"a {program.Length}-byte {(file.Type == DosFileType.AppleSoft ? "AppleSoft" : "Integer BASIC")} program";
        }
        else if (!raw && file.Type == DosFileType.Text)
        {
            File.WriteAllText(output, Text(file.Contents.Span));
            Console.WriteLine($"Wrote the text file \"{file.Name}\" to {output}.");
            return 0;
        }

        File.WriteAllBytes(output, bytes.ToArray());
        Console.WriteLine($"Wrote \"{file.Name}\", {description}, to {output}.");
        return 0;
    }

    // A text file's characters, without bit 7, each return a line ending, up to the first zero.
    private static string Text(ReadOnlySpan<byte> contents)
    {
        using ValueStringBuilder text = new(contents.Length);
        foreach (byte value in contents)
        {
            if (value == 0) { break; }
            text.Append((value & 0x7F) == '\r' ? '\n' : (char)(value & 0x7F));
        }

        return text.ToString();
    }

    private static char Letter(DosFileType type) => type switch
    {
        DosFileType.Text => 'T',
        DosFileType.IntegerBasic => 'I',
        DosFileType.AppleSoft => 'A',
        DosFileType.Binary => 'B',
        DosFileType.TypeS => 'S',
        DosFileType.Relocatable => 'R',
        DosFileType.TypeA => 'a',
        _ => 'b'
    };

    private static int Fail(string message, int code = 1)
    {
        Console.Error.WriteLine(message);
        return code;
    }
}
