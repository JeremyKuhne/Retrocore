// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text.Json;
using Retrocore.Assembler;
using Retrocore.Machines.Apple2;
using Retrocore.Media;
using Touki.Text;

namespace Retrocore.Debug;

/// <summary>
///  Disassembles a 6502 program into native source that assembles back to the same bytes, naming what it uses of
///  the machine by the SDK sources' names.
/// </summary>
/// <remarks>
///  <para>
///   <c>--disassemble input.bin output.asm --origin $0800</c>, or <c>--disassemble --disk image.dsk --file "NAME"
///   output.asm</c> for a binary file on a DOS disk, which gives its own address. <c>--machine</c> (<c>ii</c>,
///   <c>iiplus</c>, <c>iie</c> or <c>iie-enhanced</c>, by default <c>iiplus</c>) picks whose Monitor, firmware and
///   BASIC name addresses; <c>--dos</c> (<c>3.3</c>, <c>3.3-1980</c>, <c>3.2</c> or <c>none</c>, by default
///   <c>3.3</c>) whose DOS does, where it runs in 48K; <c>--cpu</c> the instruction set, by default <c>Mos6502</c>;
///   and <c>--hints</c> a <see cref="DisassemblyHints"/> file.
///  </para>
///  <para>
///   Code is found by following it from the program's first byte and the hints' entry points; bytes it never
///   reaches stay <c>.byte</c>. The command assembles what it wrote and says whether the bytes match, then lists the
///   ranges it left as bytes, which are where hints help.
///  </para>
/// </remarks>
internal static class DisassembleCommand
{
    private const string Usage = """
        Usage: --disassemble input.bin output.asm --origin $0800
               --disassemble --disk image.dsk --file "NAME" output.asm
        Options: --machine ii|iiplus|iie|iie-enhanced  --dos 3.3|3.3-1980|3.2|none  --cpu Mos6502  --hints hints.json
                 --sdk-roms directory (the SDK's ROM sources, by default those beside this host)
        """;

    /// <summary>
    ///  Runs the command.
    /// </summary>
    /// <param name="args">The arguments after <c>--disassemble</c>.</param>
    /// <returns>The process exit code: 0 when the source assembles to the same bytes.</returns>
    internal static int Run(string[] args)
    {
        List<string> positional = [];
        Dictionary<string, string> options = new(StringComparer.OrdinalIgnoreCase);
        for (int index = 0; index < args.Length; index++)
        {
            if (!args[index].StartsWith("--", StringComparison.Ordinal))
            {
                positional.Add(args[index]);
            }
            else if (index + 1 < args.Length)
            {
                options[args[index]] = args[++index];
            }
            else
            {
                return Fail($"{args[index]} needs a value.\n{Usage}", code: 2);
            }
        }

        bool fromDisk = options.ContainsKey("--disk");
        if (positional.Count != (fromDisk ? 1 : 2) || (fromDisk && !options.ContainsKey("--file")))
        {
            return Fail(Usage, code: 2);
        }

        try
        {
            (byte[] image, int origin, string what) = fromDisk
                ? FromDisk(options["--disk"], options["--file"])
                : FromFile(positional[0], options);

            Apple2Model model = Model(options.GetValueOrDefault("--machine") ?? "iiplus");
            string dos = options.GetValueOrDefault("--dos") ?? "3.3";
            ProcessorVariant cpu = Enum.Parse<ProcessorVariant>(options.GetValueOrDefault("--cpu") ?? "Mos6502", ignoreCase: true);
            DisassemblyHints hints = options.TryGetValue("--hints", out string? path) ? DisassemblyHints.Read(path) : new();
            DisassemblyProgram program = new(image, origin, what, cpu, hints);
            string? roms = options.GetValueOrDefault("--sdk-roms");
            Dictionary<ushort, (string Name, string File)> machine = MachineSymbols.For(model, dos, roms);
            return Disassemble(program, positional[^1], model, dos, machine);
        }
        catch (Exception exception) when (Expected(exception))
        {
            return Fail(exception.Message);
        }
    }

    private static bool Expected(Exception exception) => exception is InvalidDataException
        or IOException
        or ArgumentException
        or JsonException
        or FormatException
        or OverflowException
        or InvalidOperationException;

    private static int Disassemble(
        DisassemblyProgram program,
        string output,
        Apple2Model model,
        string dos,
        Dictionary<ushort, (string Name, string File)> machine)
    {
        // The first pass finds what the code refers to; only those of the machine's names go in the source.
        DisassemblyResult found = Disassembler.Analyze(program.Project(new Dictionary<ushort, string>()));
        Dictionary<ushort, string> names = [];
        Dictionary<string, string> files = new(StringComparer.Ordinal);
        HashSet<string> hinted = new(program.Hints.Names.Values, StringComparer.Ordinal);
        foreach (ushort target in found.References.Select(reference => reference.Target).Distinct())
        {
            if (program.Contains(target) || program.Hints.Names.ContainsKey(target)) { continue; }
            if (!machine.TryGetValue(target, out var symbol) || hinted.Contains(symbol.Name)) { continue; }
            names[target] = symbol.Name;
            files[symbol.Name] = symbol.File;
        }

        // A name the analysis refuses as a symbol, such as one that is also a mnemonic, is left out.
        DisassemblyResult result = Disassembler.Analyze(program.Project(names));
        ushort[] refused = Refused(result, names);
        while (refused.Length > 0)
        {
            foreach (ushort address in refused) { names.Remove(address); }
            result = Disassembler.Analyze(program.Project(names));
            refused = Refused(result, names);
        }

        if (!result.Success)
        {
            return Fail(string.Join('\n', result.Diagnostics.Where(diagnostic => diagnostic.IsError).Select(Describe)));
        }

        string heading = $"{program.What}: {program.Image.Length} bytes (${program.Image.Length:X4}) at ${program.Origin:X4}."
            + $"\nNames outside the program are the SDK sources' for the {model.DisplayName()}"
            + (dos == "none" ? "." : $" and DOS {dos}.");

        string source = Arrange(result.ExportSource(), heading, files, hinted);
        File.WriteAllText(output, source);
        string? difference = Difference(source, output, program);
        Report(result, output, names.Count, difference);
        return difference is null ? 0 : 1;
    }

    private static string Describe(DisassemblyDiagnostic diagnostic) =>
        $"${diagnostic.Address:X4}: {diagnostic.Code} {diagnostic.Message}";

    private static ushort[] Refused(DisassemblyResult result, Dictionary<ushort, string> names) =>
        [.. result.Diagnostics
            .Where(diagnostic => diagnostic.Code == "RCDIS002")
            .Select(diagnostic => diagnostic.Address)
            .Where(names.ContainsKey)];

    // The exported source under a heading, its equates grouped by the file that names them.
    private static string Arrange(string exported, string heading, Dictionary<string, string> files, HashSet<string> hinted)
    {
        string[] lines = exported.Split('\n');
        int code = Array.FindIndex(lines, line => line.StartsWith(".org ", StringComparison.Ordinal));
        List<(string Name, string Value, string? Group)> equates = [];
        foreach (string line in lines[1..code])
        {
            int equals = line.IndexOf(" = ", StringComparison.Ordinal);
            string name = line[..equals];
            string? group = files.TryGetValue(name, out string? file) ? file : hinted.Contains(name) ? "" : null;
            equates.Add((name, line[(equals + 3)..], group));
        }

        using ValueStringBuilder source = new(exported.Length + 1024, CultureInfo.InvariantCulture);
        foreach (string line in heading.Split('\n')) { source.Append($"; {line}\n"); }
        source.Append($"\n{lines[0]}\n");
        foreach (IGrouping<string?, (string Name, string Value, string? Group)> group in equates
            .GroupBy(equate => equate.Group)
            .OrderBy(group => group.Key switch { null => 2, "" => 1, _ => 0 })
            .ThenBy(group => group.Key, StringComparer.Ordinal))
        {
            source.Append(group.Key switch
            {
                null => "\n; Not named by the sources.\n",
                "" => "\n; Named by the hints.\n",
                string file => $"\n; From {file}.\n"
            });

            foreach ((string name, string value, _) in group.OrderBy(equate => equate.Value, StringComparer.Ordinal))
            {
                source.Append($"{name} = {value}\n");
            }
        }

        source.Append('\n');
        for (int index = code; index < lines.Length; index++)
        {
            source.Append(lines[index]);
            if (index + 1 < lines.Length) { source.Append('\n'); }
        }

        return source.ToString();
    }

    // Where the written source assembles differently from the program, or null when it assembles the same.
    private static string? Difference(string source, string path, DisassemblyProgram program)
    {
        AssemblyOptions options = new(program.Cpu, program.Origin, program.Image.Length)
        {
            SourceResolver = new FileAssemblySourceResolver()
        };

        AssemblyResult assembled = new Assembler.Assembler().Assemble(new AssemblySource(source, Path.GetFullPath(path)), options);
        if (!assembled.Success)
        {
            return string.Join('\n', assembled.Diagnostics.Select(diagnostic => diagnostic.Message));
        }

        ReadOnlySpan<byte> bytes = assembled.Sections[0].Bytes.Span;
        int same = bytes.CommonPrefixLength(program.Image);
        return same == program.Image.Length && bytes.Length == program.Image.Length
            ? null
            : $"the first difference is at ${program.Origin + same:X4}";
    }

    private static void Report(DisassemblyResult result, string output, int machineNames, string? difference)
    {
        int instructions = result.Instructions.Count;
        int codeBytes = result.Instructions.Sum(instruction => instruction.Size);
        Console.WriteLine($"Wrote {output}: {instructions} instructions ({codeBytes} bytes), "
            + $"{result.Image.Length - codeBytes} bytes as data, {machineNames} names from the SDK sources.");

        Console.WriteLine(difference is null
            ? "It assembles to the same bytes."
            : $"It does not assemble to the same bytes: {difference}.");

        // The ranges no code reached: data, or code that only an entry point or a jump table would show.
        AnalysisRegion[] left = [.. result.Regions.Where(region => region.Kind != AnalysisRegionKind.Code)];
        if (left.Length > 0) { Console.WriteLine("Bytes left as .byte:"); }
        foreach (AnalysisRegion region in left)
        {
            string kind = region.Kind == AnalysisRegionKind.Data ? "data by hint" : "not reached";
            Console.WriteLine($"  ${region.Address:X4}-${region.Address + region.Length - 1:X4} ({region.Length} bytes, {kind})");
        }

        foreach (DisassemblyDiagnostic diagnostic in result.Diagnostics.Where(diagnostic => !diagnostic.IsError))
        {
            Console.WriteLine($"  ${diagnostic.Address:X4}: {diagnostic.Message}");
        }
    }

    private static (byte[] Image, int Origin, string What) FromDisk(string disk, string name)
    {
        DosFile file = DosCommand.Find(disk, name);
        if (!file.TryGetBinary(out int address, out ReadOnlyMemory<byte> data))
        {
            throw new InvalidDataException($"\"{file.Name}\" is not a binary file; --dos extract writes its contents.");
        }

        return (data.ToArray(), address, $"\"{file.Name}\" on {Path.GetFileName(disk)}");
    }

    private static (byte[] Image, int Origin, string What) FromFile(string path, Dictionary<string, string> options)
    {
        if (!options.TryGetValue("--origin", out string? origin))
        {
            throw new ArgumentException("--origin is required for a file.");
        }

        return (File.ReadAllBytes(path), CommandAddress.Parse(origin), Path.GetFileName(path));
    }

    private static Apple2Model Model(string name) => name switch
    {
        "ii" => Apple2Model.II,
        "iiplus" => Apple2Model.IIPlus,
        "iie" or "original" => Apple2Model.IIe,
        "iie-enhanced" or "enhanced" => Apple2Model.IIeEnhanced,
        _ => throw new ArgumentException("--machine must be ii, iiplus, iie or iie-enhanced.")
    };

    private static int Fail(string message, int code = 1)
    {
        Console.Error.WriteLine(message);
        return code;
    }
}
