// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text.RegularExpressions;
using Retrocore.Assembler;
using Retrocore.Basic;
using Retrocore.Cpu.M6502;
using Retrocore.Media;

namespace Retrocore.DiskTool;

/// <summary>
///  Builds DOS disk images from the SDK's DOS sources and files on the host.
/// </summary>
internal static partial class DosDiskBuilder
{
    private const string HelloName = "HELLO";
    private const int MasterOrigin = 0x1B00;
    private const int MasterSize = 0x2500;
    private const int RunningOrigin = 0x9D00;
    private const int RunningSize = 0x2300;
    private const int AppleSoftStart = 0x0801;

    /// <summary>
    ///  Builds a disk image.
    /// </summary>
    /// <param name="options">What to put on it.</param>
    /// <returns>The image, in the format <see cref="DosDiskOptions.Format"/> names.</returns>
    /// <exception cref="ArgumentException">An option or file is not valid.</exception>
    /// <exception cref="InvalidDataException">The DOS sources or a BASIC listing has errors.</exception>
    public static byte[] Build(DosDiskOptions options)
    {
        if (options.Year is not (1983 or 1980)) { throw new ArgumentException("The year must be 1983 or 1980."); }
        if (options.Volume is < 1 or > 254) { throw new ArgumentException("The volume must be 1 to 254."); }

        bool thirteen = options.Dos switch
        {
            "3.3" => false,
            "3.2" => true,
            _ => throw new ArgumentException("The DOS must be 3.3 or 3.2.")
        };

        string format = options.Format.ToLowerInvariant();
        if (thirteen ? format is not (".d13" or ".woz") : format is not (".dsk" or ".do" or ".woz"))
        {
            throw new ArgumentException(thirteen
                ? "A DOS 3.2 disk is written as .d13 or .woz."
                : "A DOS 3.3 disk is written as .dsk, .do or .woz.");
        }

        List<DosFile> files = options.Files is null ? [] : ReadFolder(options.Files);
        AddHello(files, options.Run);

        string sources = Path.Join(options.Sources ?? AppContext.BaseDirectory, "Dos");
        byte[] dos = AssembleDos(Path.Join(sources, thirteen ? "Dos32.asm" : "Dos33.asm"), options.Master, options.Year);
        byte[] tracks = thirteen ? DosDisk.Dos32Tracks(dos) : DosDisk.Dos33Tracks(dos);
        byte[] disk = DosDisk.Create(tracks, files, thirteen ? 13 : 16, (byte)options.Volume);
        if (format != ".woz") { return disk; }

        return thirteen
            ? SectorDiskConverter.ConvertThirteenSector(disk).Export()
            : SectorDiskConverter.Convert(disk, proDosOrder: false).Export();
    }

    /// <summary>
    ///  Assembles DOS: the System Master's image at $1B00, or DOS where it runs at $9D00.
    /// </summary>
    /// <param name="path">The <c>Dos33.asm</c> or <c>Dos32.asm</c> source.</param>
    /// <param name="master">Whether to build the master's image.</param>
    /// <param name="year">1983 or 1980.</param>
    /// <returns>The bytes.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    public static byte[] AssembleDos(string path, bool master, int year)
    {
        string full = Path.GetFullPath(path);
        AssemblyOptions assembly = new(
            ProcessorVariant.Mos6502,
            master ? MasterOrigin : RunningOrigin,
            master ? MasterSize : RunningSize)
        {
            SourceResolver = new FileAssemblySourceResolver(),
            PredefinedSymbols = new Dictionary<string, long> { ["MASTER"] = master ? 1 : 0, ["YEAR"] = year }
        };

        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource(File.ReadAllText(full), full), assembly);
        return result.Success
            ? result.Sections[0].Bytes.ToArray()
            : throw new InvalidDataException(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic => diagnostic.Message)));
    }

    /// <summary>
    ///  Reads the files in a folder, in name order.
    /// </summary>
    /// <param name="folder">The folder.</param>
    /// <returns>The files.</returns>
    /// <exception cref="ArgumentException">A file's kind can't be told from its name.</exception>
    public static List<DosFile> ReadFolder(string folder) =>
        [.. Directory.GetFiles(folder).Order(StringComparer.OrdinalIgnoreCase).Select(ReadFile)];

    /// <summary>
    ///  Reads one file: an AppleSoft listing (<c>.bas</c>), a text file (<c>.txt</c>), or a file named in CiderPress
    ///  II's style, <c>NAME#TTAAAA</c>, with its ProDOS type and auxiliary type in hex.
    /// </summary>
    /// <param name="path">The file.</param>
    /// <returns>The DOS file.</returns>
    /// <exception cref="ArgumentException">The file's kind can't be told from its name.</exception>
    public static DosFile ReadFile(string path)
    {
        string fileName = Path.GetFileName(path);
        string extension = Path.GetExtension(path).ToLowerInvariant();
        string stem = Path.GetFileNameWithoutExtension(path);
        if (extension == ".bas") { return DosFile.AppleSoft(stem, Tokenize(File.ReadAllText(path), path)); }
        if (extension == ".txt") { return DosFile.Text(stem, File.ReadAllText(path)); }

        Match match = TypedName().Match(fileName);
        if (!match.Success)
        {
            throw new ArgumentException($"{fileName}: name a file NAME.bas, NAME.txt or NAME#TTAAAA.");
        }

        string name = match.Groups["name"].Value;
        int type = int.Parse(match.Groups["type"].Value, NumberStyles.HexNumber, CultureInfo.InvariantCulture);
        int aux = match.Groups["aux"].Success
            ? int.Parse(match.Groups["aux"].Value, NumberStyles.HexNumber, CultureInfo.InvariantCulture)
            : 0;

        byte[] data = File.ReadAllBytes(path);
        return type switch
        {
            0x04 => new DosFile(name, DosFileType.Text, data),
            0x06 => DosFile.Binary(name, aux, data),
            0xFA => DosFile.IntegerBasic(name, data),
            0xFC => DosFile.AppleSoft(name, data),
            _ => throw new ArgumentException($"{fileName}: DOS has no file type for ProDOS type ${type:X2}.")
        };
    }

    // Adds a greeting program: one that runs the named file, or an empty one when the files have none.
    private static void AddHello(List<DosFile> files, string? run)
    {
        bool hasHello = files.Exists(file => file.Name.Equals(HelloName, StringComparison.OrdinalIgnoreCase));
        if (run is null)
        {
            if (!hasHello) { files.Insert(0, DosFile.AppleSoft(HelloName, Tokenize("10 REM\n", HelloName))); }
            return;
        }

        if (hasHello) { throw new ArgumentException("The files already have a HELLO; leave out --run."); }

        DosFile target = files.Find(file => file.Name.Equals(run, StringComparison.OrdinalIgnoreCase))
            ?? throw new ArgumentException($"There is no file named {run} to run.");

        string command = target.Type == DosFileType.Binary ? "BRUN" : "RUN";
        files.Insert(0, DosFile.AppleSoft(HelloName, Tokenize($"10 PRINT CHR$(4);\"{command} {target.Name}\"\n", HelloName)));
    }

    // Tokenizes an AppleSoft listing as it sits in memory from $0801.
    private static byte[] Tokenize(string text, string path)
    {
        BasicParseResult parsed = BasicProgram.Parse(text, BasicDialect.AppleSoft, path);
        BasicProgram program = parsed.Program
            ?? throw new InvalidDataException($"{path}: the AppleSoft listing has errors.");

        return program.ToImage(AppleSoftStart);
    }

    [GeneratedRegex(@"^(?<name>.+)#(?<type>[0-9A-Fa-f]{2})(?<aux>[0-9A-Fa-f]{4})?$")]
    private static partial Regex TypedName();
}
