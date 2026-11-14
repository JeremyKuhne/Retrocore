// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text.Json.Nodes;
using Retrocore.Assembler;
using Retrocore.Media;
using Retrocore.Pascal;

namespace Retrocore.Debug;

/// <summary>
///  Lists and copies out the files on an Apple Pascal disk, and lists and disassembles code files.
/// </summary>
/// <remarks>
///  <para>
///   A disk is an Apple II Pascal volume or an Apple III SOS volume, as a <c>.dsk</c>, <c>.po</c> or <c>.woz</c> image.
///  </para>
///  <para>
///   <c>--pascal disassemble code output.asm</c> writes the code file as p-code source (see
///   <see cref="PcodeSourceWriter"/>) and checks it assembles back to the same bytes; <c>--pascal assemble source
///   output.code</c> assembles such a source.
///  </para>
///  <para>
///   <c>--pascal catalog disk [--json]</c> lists the files. <c>--pascal extract disk NAME output [--raw]</c> writes
///   one, a text file as plain text unless <c>--raw</c>. <c>--pascal segments code</c> lists a code file's segments
///   and procedures, and <c>--pascal disassemble code [SEGMENT[.PROCEDURE]]</c> disassembles them: p-code as p-code,
///   and assembled procedures as 6502 code from offset 0. A code file is a file's path, or a disk and the file's
///   name.
///  </para>
///  <para>
///   <c>--pascal sos output NAME [--boot disk] --from disk FILE... [--from disk FILE...]</c> builds a SOS volume
///   named NAME from files on other SOS disks, each keeping its type, and with <c>--boot</c> that disk's boot loader,
///   as Apple III Pascal 1.2's update disks are copied onto 1.1's.
///  </para>
/// </remarks>
internal static partial class PascalCommand
{
    private const string Usage = """
        Usage: --pascal catalog disk [--json]
               --pascal extract disk NAME output [--raw]
               --pascal segments (file.code | disk NAME)
               --pascal disassemble (file.code | disk NAME) [SEGMENT[.PROCEDURE]]
               --pascal disassemble (file.code | disk NAME) [--library L] [--listing L] [--hints file.json] output.asm
               --pascal assemble source.asm output.code
               --pascal sos output.dsk NAME [--boot disk] --from disk FILE... [--from disk FILE...]
               --pascal decompile (file.code | disk NAME) [--library (file | disk NAME)] [--listing (file | disk NAME)] [--hints hints.json] [output.text]
               --pascal compile source.text APPLE1.dsk APPLE2.dsk output.code [listing.text]
               --pascal compare (file.code | disk NAME) (file.code | disk NAME)
        """;

    /// <summary>
    ///  Runs the command.
    /// </summary>
    /// <param name="args">The arguments after <c>--pascal</c>.</param>
    /// <returns>The process exit code.</returns>
    internal static int Run(string[] args)
    {
        try
        {
            return args switch
            {
                ["catalog", string disk, .. string[] rest] => Catalog(disk, rest.Contains("--json")),
                ["extract", string disk, string name, string output, .. string[] rest] => Extract(disk, name, output, rest.Contains("--raw")),
                ["segments", .. string[] rest] when CodeFile(rest, out _) is { } file => Segments(file),
                ["disassemble", .. string[] rest] when rest.Any(IsSource) => DisassembleToSource(rest),
                ["disassemble", .. string[] rest] when CodeFile(rest, out string? which) is { } file => Disassemble(file, which),
                ["assemble", string source, string output] => Assemble(source, output),
                ["sos", string output, string name, .. string[] rest] when rest.Contains("--from") => Sos(output, name, rest),
                ["decompile", .. string[] rest] => Decompile(rest),
                ["compile", string source, string boot, string compiler, string output] => Compile(source, boot, compiler, output, listing: null),
                ["compile", string source, string boot, string compiler, string output, string listing] => Compile(source, boot, compiler, output, listing),
                ["compare", .. string[] rest] when CodeFiles(rest) is var (first, second) => Compare(first, second),
                _ => Fail(Usage, code: 2)
            };
        }
        catch (Exception exception) when (exception is InvalidDataException or IOException or ArgumentException or InvalidOperationException)
        {
            return Fail(exception.Message);
        }
    }

    /// <summary>
    ///  Opens a disk image's volume.
    /// </summary>
    /// <param name="path">The image's path.</param>
    /// <returns>The volume.</returns>
    /// <exception cref="InvalidDataException">The image holds neither a Pascal nor a SOS volume.</exception>
    internal static PascalDisk Open(string path)
    {
        bool proDos = path.EndsWith(".po", StringComparison.OrdinalIgnoreCase);
        byte[] image = File.ReadAllBytes(path);
        if (path.EndsWith(".woz", StringComparison.OrdinalIgnoreCase))
        {
            image = SectorDiskReader.Read(WozDisk.Load(image), proDosOrder: false);
            proDos = false;
        }

        return PascalVolume.IsPascalVolume(image, proDos)
            ? new PascalDisk(PascalVolume.Read(image, proDos))
            : new PascalDisk(SosVolume.Read(image, proDos));
    }

    // A disk image's SOS volume.
    private static SosVolume OpenSos(string path)
    {
        bool proDos = path.EndsWith(".po", StringComparison.OrdinalIgnoreCase);
        byte[] image = File.ReadAllBytes(path);
        if (path.EndsWith(".woz", StringComparison.OrdinalIgnoreCase))
        {
            image = SectorDiskReader.Read(WozDisk.Load(image), proDosOrder: false);
            proDos = false;
        }

        return SosVolume.Read(image, proDos);
    }

    // Builds a SOS volume from other disks' files.
    private static int Sos(string output, string name, string[] args)
    {
        if (!IsDisk(output) || output.EndsWith(".woz", StringComparison.OrdinalIgnoreCase))
        {
            return Fail($"{output} is not a .dsk, .do or .po image.", code: 2);
        }

        SosVolumeBuilder builder = new(name);
        SosVolume? from = null;
        for (int index = 0; index < args.Length; index++)
        {
            switch (args[index])
            {
                case "--boot" when index + 1 < args.Length:
                    builder.BootFrom(OpenSos(args[++index]));
                    break;
                case "--from" when index + 1 < args.Length:
                    from = OpenSos(args[++index]);
                    break;
                case string file when from is not null:
                    builder.Add(from, file);
                    break;
                default:
                    return Fail(Usage, code: 2);
            }
        }

        File.WriteAllBytes(output, builder.Build(output.EndsWith(".po", StringComparison.OrdinalIgnoreCase)));
        Console.WriteLine($"Wrote /{name.ToUpperInvariant()}, {builder.Count} files in {builder.BlocksUsed} of 280 blocks, to {output}.");
        return 0;
    }

    private static bool IsDisk(string path) =>
        Path.GetExtension(path).ToUpperInvariant() is ".DSK" or ".DO" or ".PO" or ".WOZ";

    // A code file from a path, or from a disk and a name; the argument after it names a segment and procedure.
    private static PascalCodeFile? CodeFile(string[] args, out string? which)
    {
        which = null;
        if (args.Length == 0) { return null; }

        byte[] data;
        if (IsDisk(args[0]))
        {
            if (args.Length < 2) { return null; }
            data = Open(args[0]).Read(args[1]);
            which = args.Length > 2 ? args[2] : null;
        }
        else
        {
            data = File.ReadAllBytes(args[0]);
            which = args.Length > 1 ? args[1] : null;
        }

        return PascalCodeFile.Read(data);
    }

    private static bool IsSource(string path) =>
        Path.GetExtension(path).ToUpperInvariant() is ".ASM" or ".S";

    // Writes a code file as p-code source, then assembles the source to check it gives the same bytes.
    private static int DisassembleToSource(string[] args)
    {
        // The options come out first, so the output may come before or after them.
        List<string> input = [.. args];
        byte[]? library = Option(input, "--library");
        byte[]? listing = Option(input, "--listing");
        byte[]? hints = Option(input, "--hints");
        if (input.Count == 0 || !IsSource(input[^1])) { throw new ArgumentException(Usage); }

        string output = input[^1];
        input.RemoveAt(input.Count - 1);
        byte[] data = input switch
        {
            [string disk, string name] when IsDisk(disk) => Open(disk).Read(name),
            [string path] => File.ReadAllBytes(path),
            _ => throw new ArgumentException(Usage)
        };

        // Units are named from the library on the code file's disk unless another is given.
        if (library is null && input is [string onDisk, _] && IsDisk(onDisk))
        {
            PascalDisk disk = Open(onDisk);
            if (disk.Files.Any(file => string.Equals(file.Name, "SYSTEM.LIBRARY", StringComparison.OrdinalIgnoreCase)))
            {
                library = disk.Read("SYSTEM.LIBRARY");
            }
        }

        PcodeSourceOptions options = new()
        {
            Library = library is null ? null : PascalLibrary.Read(library),
            Listing = listing is null ? null : PascalListing.Parse(Text(listing))
        };

        if (hints is not null) { options = Hints(options, hints); }
        PcodeSource source = PcodeSourceWriter.Write(data, options);
        File.WriteAllText(output, source.Text);
        foreach (string note in source.Notes) { Console.WriteLine($"note: {note}"); }

        byte[] assembled = AssembleCodeFile(output);
        int differences = Enumerable.Range(0, Math.Min(data.Length, assembled.Length)).Count(index => data[index] != assembled[index]);
        if (differences == 0 && assembled.Length == data.Length)
        {
            Console.WriteLine($"Wrote {output}; it assembles to the same {data.Length} bytes.");
            return 0;
        }

        int first = Enumerable.Range(0, Math.Min(data.Length, assembled.Length)).FirstOrDefault(index => data[index] != assembled[index]);
        Console.WriteLine($"Wrote {output}, but it assembles to {assembled.Length} bytes for {data.Length}, {differences} differing, the first at ${first:X4}.");
        return 1;
    }

    // An option's file, a host file's path or a disk and a file's name, taken out of the arguments.
    private static byte[]? Option(List<string> args, string option)
    {
        int at = args.IndexOf(option);
        if (at < 0) { return null; }
        if (at + 1 >= args.Count) { throw new ArgumentException($"{option} names no file."); }

        bool disk = IsDisk(args[at + 1]);
        if (disk && at + 2 >= args.Count) { throw new ArgumentException($"{option} names a disk but no file on it."); }
        byte[] data = disk ? Open(args[at + 1]).Read(args[at + 2]) : File.ReadAllBytes(args[at + 1]);
        args.RemoveRange(at, disk ? 3 : 2);
        return data;
    }

    // A text file's text: a Pascal text file's lines, or a host file's as it is.
    private static string Text(byte[] data) =>
        data.Length >= 1024 && data.Length % 1024 == 0 && Array.IndexOf(data, (byte)'\n') < 0
            ? PascalTextFile.Read(data)
            : System.Text.Encoding.ASCII.GetString(data);

    // A hints file: { "names": { "FORMATTE.2": "Format", "FORMATTE.2+$3E": "Return" }, "comments": { ... } }.
    private static PcodeSourceOptions Hints(PcodeSourceOptions options, byte[] data)
    {
        (Dictionary<string, string> names, Dictionary<string, string> comments) = Hints(data);
        return options with { Names = names, Comments = comments };
    }

    // A hints file's names and comments, by key.
    private static (Dictionary<string, string> Names, Dictionary<string, string> Comments) Hints(byte[] data)
    {
        JsonNode root = JsonNode.Parse(data) ?? throw new InvalidDataException("The hints file is empty.");
        return (Strings(root["names"]), Strings(root["comments"]));

        static Dictionary<string, string> Strings(JsonNode? node)
        {
            Dictionary<string, string> values = new(StringComparer.OrdinalIgnoreCase);
            if (node is not JsonObject entries) { return values; }

            foreach ((string key, JsonNode? value) in entries)
            {
                values[key] = value?.GetValue<string>() ?? throw new InvalidDataException($"The hint {key} has no text.");
            }

            return values;
        }
    }

    // Assembles p-code source into a code file.
    private static int Assemble(string source, string output)
    {
        byte[] code = AssembleCodeFile(source);
        File.WriteAllBytes(output, code);
        Console.WriteLine($"Wrote {output}, {code.Length} bytes in {code.Length / 512} blocks.");
        return 0;
    }

    // A code file source's bytes: from address 0, to the last byte it writes.
    private static byte[] AssembleCodeFile(string source)
    {
        AssemblyResult result = SourceBuild.Assemble(source, dialect: null, cpu: "Mos6502", origin: 0, linkerConfiguration: null);
        (int address, ReadOnlyMemory<byte> bytes) = SourceBuild.Emitted(result).Single();
        if (address != 0) { throw new InvalidDataException("A code file's source starts at address 0."); }
        return bytes.ToArray();
    }

    // Two code files, each a path or a disk and a name.
    private static (PascalCodeFile First, PascalCodeFile Second)? CodeFiles(string[] args)
    {
        int split = args.Length > 0 && IsDisk(args[0]) ? 2 : 1;
        return args.Length < split + 1 || CodeFile(args[..split], out _) is not { } first || CodeFile(args[split..], out _) is not { } second
            ? null
            : (first, second);
    }

    // Decompiles a code file to Pascal: from a path or a disk, with its units from a library, by default the
    // SYSTEM.LIBRARY on the code file's disk.
    private static int Decompile(string[] args)
    {
        List<string> rest = [.. args];
        byte[]? library = Option(rest, "--library");
        byte[]? listing = Option(rest, "--listing");
        byte[]? hints = Option(rest, "--hints");

        if (rest.Count == 0) { return Fail(Usage, code: 2); }
        bool onDisk = IsDisk(rest[0]);
        int inputs = onDisk ? 2 : 1;
        if (rest.Count < inputs) { return Fail(Usage, code: 2); }

        byte[] data = onDisk ? Open(rest[0]).Read(rest[1]) : File.ReadAllBytes(rest[0]);
        if (library is null && onDisk)
        {
            PascalDisk disk = Open(rest[0]);
            if (disk.Files.Any(file => string.Equals(file.Name, "SYSTEM.LIBRARY", StringComparison.OrdinalIgnoreCase)))
            {
                library = disk.Read("SYSTEM.LIBRARY");
            }
        }

        PascalDecompilerOptions options = new()
        {
            Library = library is null ? null : PascalLibrary.Read(library),
            Listing = listing is null ? null : PascalListing.Parse(Text(listing))
        };

        if (hints is not null)
        {
            (Dictionary<string, string> names, Dictionary<string, string> comments) = Hints(hints);
            options = options with { Names = names, Comments = comments };
        }

        PascalDecompilation result = PascalDecompiler.Decompile(PascalCodeFile.Read(data), options);
        foreach (string warning in result.Warnings) { Console.Error.WriteLine($"warning: {warning}"); }
        if (rest.Count > inputs)
        {
            File.WriteAllText(rest[inputs], result.Source);
            Console.WriteLine($"Wrote {rest[inputs]}.");
        }
        else
        {
            Console.Write(result.Source);
        }

        return result.Warnings.Count == 0 ? 0 : 1;
    }

    // Compiles a source with Apple Pascal's Compiler on an emulated Apple II.
    private static int Compile(string source, string boot, string compiler, string output, string? listing)
    {
        // A listing the source asks for, (*$L APPLE1:NAME.TEXT*), is read back from APPLE1 to the host.
        string text = File.ReadAllText(source);
        System.Text.RegularExpressions.Match asked = ListingName().Match(text);
        string? listed = listing is not null && asked.Success ? asked.Groups["name"].Value : null;
        if (listing is not null && listed is null)
        {
            return Fail("The source asks for no listing: (*$L APPLE1:NAME.TEXT*).", code: 2);
        }


        (byte[]? code, string screen, string? listingText) = EmulatedPascalCompiler.CompileWithListing(text, boot, compiler, listed);
        if (code is null)
        {
            Console.Error.WriteLine(screen);
            return Fail("The Compiler stopped with an error.");
        }

        File.WriteAllBytes(output, code);
        Console.WriteLine($"Wrote {output}, {code.Length} bytes.");
        if (listing is not null && listingText is not null)
        {
            File.WriteAllText(listing, listingText);
            Console.WriteLine($"Wrote the listing to {listing}.");
        }
        else if (listing is not null)
        {
            // The Compiler writes no listing whose name it cannot make, such as one longer than 15 characters.
            return Fail($"The Compiler wrote no listing {listed}{(listed?.Length > 15 ? ": a file's name is at most 15 characters" : "")}.");
        }

        return 0;
    }

    [System.Text.RegularExpressions.GeneratedRegex(@"\(\*\$L\s*(?:[A-Z0-9]+:)?(?<name>[^*\s]+)\s*\*\)", System.Text.RegularExpressions.RegexOptions.IgnoreCase)]
    private static partial System.Text.RegularExpressions.Regex ListingName();

    // Compares two code files' segments: their dictionary entries and code.
    private static int Compare(PascalCodeFile first, PascalCodeFile second)
    {
        IReadOnlyList<string> differences = PascalCodeComparison.Compare(first, second);
        foreach (string difference in differences) { Console.WriteLine(difference); }
        if (differences.Count == 0) { Console.WriteLine("The code files' segments are the same."); }
        return differences.Count == 0 ? 0 : 1;
    }

    private static int Catalog(string path, bool json)
    {
        PascalDisk disk = Open(path);
        JsonArray entries = [];
        if (!json) { Console.WriteLine(disk.Name); }
        foreach (PascalDiskFile file in disk.Files)
        {
            if (json)
            {
                JsonObject entry = new()
                {
                    ["name"] = file.Name,
                    ["kind"] = file.Kind,
                    ["length"] = file.Length
                };

                if (file.Modified is { } modified)
                {
                    entry["modified"] = modified.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
                }

                entries.Add((JsonNode)entry);
                continue;
            }

            string date = file.Modified?.ToString("dd-MMM-yy", CultureInfo.InvariantCulture) ?? "";
            Console.WriteLine($"  {file.Name,-15} {file.Kind,-8} {file.Length,7} {date}");
        }

        if (json) { Console.WriteLine(entries.ToJsonString()); }
        return 0;
    }

    private static int Extract(string path, string name, string output, bool raw)
    {
        PascalDisk disk = Open(path);
        PascalDiskFile file = disk.Find(name);
        byte[] data = disk.Read(file.Name);
        if (!raw && file.Kind == "Text")
        {
            File.WriteAllText(output, PascalTextFile.Read(data));
            Console.WriteLine($"Wrote the text file {file.Name} to {output}.");
            return 0;
        }

        File.WriteAllBytes(output, data);
        Console.WriteLine($"Wrote {file.Name}, {data.Length} bytes, to {output}.");
        return 0;
    }

    private static int Segments(PascalCodeFile file)
    {
        foreach (PascalSegment segment in file.Segments)
        {
            Console.WriteLine(
                $"{segment.Slot,2} {segment.Name,-8} segment {segment.Number,3}  {segment.Kind,-17} {segment.MachineType,-15} version {segment.Version}  {segment.Length} bytes");

            foreach (PascalProcedure procedure in segment.Procedures)
            {
                string what = procedure.IsNative
                    ? $"assembled, entry ${procedure.Entry:X4}"
                    : $"entry ${procedure.Entry:X4}, exit ${procedure.Exit:X4}, lex {procedure.LexicalLevel}, parameters {procedure.ParameterSize}, data {procedure.DataSize}";

                Console.WriteLine($"     {segment.Name}.{procedure.Index,-3} {what}");
            }
        }

        return 0;
    }

    private static int Disassemble(PascalCodeFile file, string? which)
    {
        string? segmentName = which?.Split('.')[0];
        int? only = which?.Split('.') is [_, string number] ? int.Parse(number, CultureInfo.InvariantCulture) : null;
        bool any = false;
        foreach (PascalSegment segment in file.Segments)
        {
            if (segmentName is not null && !string.Equals(segment.Name, segmentName, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            foreach (PascalProcedure procedure in segment.Procedures)
            {
                if (only is not null && procedure.Index != only) { continue; }

                any = true;
                Console.WriteLine($"; {segment.Name}.{procedure.Index}{(procedure.IsNative ? ", assembled" : "")}");
                if (procedure.IsNative)
                {
                    Native(segment, procedure);
                }
                else
                {
                    foreach (PcodeInstruction instruction in PcodeDisassembler.Disassemble(segment, procedure))
                    {
                        string mark = instruction.Offset == procedure.Exit ? "; exit" : "";
                        Console.WriteLine($"  ${instruction.Offset:X4}  {instruction,-40}{mark}".TrimEnd());
                    }
                }

                Console.WriteLine();
            }
        }

        return any ? 0 : Fail($"No procedure {which} in the code file.");
    }

    // An assembled procedure from its entry to the first of its relocation lists, which sit below its attributes.
    private static void Native(PascalSegment segment, PascalProcedure procedure)
    {
        int end = procedure.Attributes - 2 - (2 * (procedure.Relocations.Count + procedure.Relocations.Sum(list => list.Count)));
        HashSet<int> relocated = [.. procedure.Relocations.SelectMany(list => list)];
        ReadOnlySpan<byte> code = segment.Code;
        int offset = procedure.Entry;
        while (offset < end)
        {
            if (!Disassembler.TryDecode(code[offset..end], (ushort)(offset - procedure.Entry), ProcessorVariant.Mos6502, out DisassembledInstruction instruction))
            {
                Console.WriteLine($"  ${offset:X4}  .byte ${code[offset]:X2}");
                offset++;
                continue;
            }

            bool moves = Enumerable.Range(offset + 1, instruction.Size - 1).Any(relocated.Contains);
            Console.WriteLine($"  ${offset:X4}  {instruction,-40}{(moves ? "; relocated" : "")}".TrimEnd());
            offset += instruction.Size;
        }
    }

    private static int Fail(string message, int code = 1)
    {
        Console.Error.WriteLine(message);
        return code;
    }
}
