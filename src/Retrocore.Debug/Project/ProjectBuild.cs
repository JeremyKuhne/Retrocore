// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using System.Globalization;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Touki.Io;

namespace Retrocore.Debug.Project;

/// <summary>
///  Builds a project's target: assembles its sources as one stream for its CPU, with its defines, and writes its
///  binary, its debug information and its map.
/// </summary>
/// <remarks>
///  <para>
///   <c>retrocore build</c> and a <c>project</c> launch (<see cref="ProjectLaunch"/>) both build through here, so the
///   bytes the debugger loads are the bytes CI builds. Only the <c>bare</c> environment builds yet: a raw binary loaded
///   straight into RAM, so the sections that emit bytes must make one block, with no gap between them.
///  </para>
///  <para>
///   The build starts at the target's CPU (its <c>cpu</c>, or the project's), as a <c>source</c> launch starts at the
///   machine's. A <c>.cpu</c> in the sources may switch to another CPU the machine has, such as the enhanced IIe's
///   Rockwell 65C02 in a <c>6502</c> project, but naming one the machine lacks is an error that names the target.
///  </para>
///  <para>
///   Output goes to <c>&lt;output&gt;/&lt;target&gt;/</c>: <c>&lt;name&gt;.bin</c>, <c>&lt;name&gt;.dbg</c> and
///   <c>&lt;name&gt;.map</c>. <c>obj/&lt;target&gt;/build.json</c> records what was assembled, in order, with the
///   CPU and the defines.
///  </para>
/// </remarks>
internal static partial class ProjectBuild
{
    /// <summary>
    ///  Runs the project's steps that are not up to date (<see cref="ProjectSteps"/>), then assembles a target and
    ///  writes its output.
    /// </summary>
    /// <param name="target">The target.</param>
    /// <returns>The build.</returns>
    /// <exception cref="ProjectException">
    ///  A step fails, the target uses what is not supported yet, its sources are missing or have errors, it names a
    ///  CPU its machine lacks, or its bytes are not one block.
    /// </exception>
    /// <exception cref="IOException">The output cannot be written.</exception>
    /// <exception cref="UnauthorizedAccessException">The output cannot be written.</exception>
    internal static TargetBuild Build(ProjectTarget target)
    {
        target.RequireSupported();
        List<StepResult> steps = ProjectSteps.Run(target.Project);
        TargetBuild build = Assemble(target) with { Steps = steps };
        Write(build);
        return build;
    }

    /// <summary>
    ///  Assembles a target without writing anything.
    /// </summary>
    /// <param name="target">The target.</param>
    /// <returns>The build, whose output paths are where <see cref="Build"/> would write.</returns>
    /// <exception cref="ProjectException">As <see cref="Build"/>.</exception>
    internal static TargetBuild Assemble(ProjectTarget target)
    {
        target.RequireSupported();
        List<TargetSourceFile> files = target.SourceFiles();
        AssemblyOptions options = Options(
            target,
            new OverlayBaseResolver(OverlayBaseResolver.SdkFallback),
            target.LinkerConfiguration is { } linker ? new(Read(target, linker, "linker configuration"), linker) : null);

        List<AssemblySource> sources =
            [.. files.Select(file => new AssemblySource(Read(target, file.Path, "source"), file.Path, file.Dialect))];

        AssemblyParseResult parsed = Assembler.Assembler.Parse(sources, options);
        if (!parsed.Success) { throw Errors(target, parsed.Diagnostics); }
        CheckCpus(target, parsed.Project);

        AssemblyResult result = new Assembler.Assembler().Assemble(parsed.Project, options);
        if (!result.Success) { throw Errors(target, result.Diagnostics); }
        CheckReservedNames(target, result, sources);

        List<(int Address, ReadOnlyMemory<byte> Bytes)> segments = [.. SourceBuild.Emitted(result)];
        if (segments.Count == 0)
        {
            throw new ProjectException($"{target.Project.File}: target {target.Name}: the sources emit no bytes.");
        }

        RequireOneBlock(target, segments);

        int entry = FirstOwnAddress(target, result, files) ?? segments[0].Address;
        if (target.Project.Entry is { } label)
        {
            entry = result.Symbols.TryGetValue(label, out long value) && value is >= 0 and <= 0xFFFF
                ? (int)value
                : throw new ProjectException(
                    $"{target.Project.File}: target {target.Name}: the entry '{label}' is not an address the sources define.");
        }

        string output = Path.Join(target.Project.Output, target.Name);
        string name = target.Project.Name;
        return new(target, result, files, segments, entry)
        {
            Binary = Path.Join(output, name + ".bin"),
            DebugFile = Path.Join(output, name + ".dbg"),
            MapFile = Path.Join(output, name + ".map"),
            Record = Path.Join(target.Project.Intermediate, target.Name, "build.json")
        };
    }

    /// <summary>
    ///  Gets the options a target assembles with: its CPU and load address, the native dialect, its headers' folders
    ///  on the SDK paths, and its defines, the SDK's with the project's and its own. The build and the language server
    ///  both assemble with them, so a source chooses the same code in each.
    /// </summary>
    /// <param name="target">The target.</param>
    /// <param name="resolver">Reads the sources' includes.</param>
    /// <param name="linkerConfiguration">The target's linker configuration's text, or null for none.</param>
    /// <returns>The options.</returns>
    internal static AssemblyOptions Options(ProjectTarget target, IAssemblySourceResolver resolver, AssemblySource? linkerConfiguration)
    {
        int origin = target.Machine.LoadAddress;
        return new(target.Cpu.AssemblerName, origin, 0x10000 - origin)
        {
            Dialect = AssemblyDialect.Native,
            SourceResolver = resolver,
            SdkPaths = target.SdkPaths(SdkModules.SdkDirectory),
            PredefinedSymbols = target.Symbols(),
            PredefinedTexts = target.Texts(),
            LinkerConfiguration = linkerConfiguration
        };
    }

    /// <summary>
    ///  Gets a target's load image: its emitted segments, which make one block, from the lowest address up. These
    ///  are the bytes a launch loads, segment by segment.
    /// </summary>
    /// <param name="build">The build.</param>
    /// <returns>The load address and the bytes.</returns>
    internal static (int Address, byte[] Bytes) Image(TargetBuild build)
    {
        int start = build.Segments.Min(segment => segment.Address);
        int end = build.Segments.Max(segment => segment.Address + segment.Bytes.Length);
        byte[] image = new byte[end - start];
        foreach ((int address, ReadOnlyMemory<byte> bytes) in build.Segments)
        {
            bytes.Span.CopyTo(image.AsSpan(address - start));
        }

        return (start, image);
    }

    /// <summary>
    ///  Gets a target's map: where each section and symbol landed.
    /// </summary>
    /// <param name="build">The build.</param>
    /// <returns>The map's text.</returns>
    internal static string Map(TargetBuild build)
    {
        ProjectTarget target = build.Target;
        (int start, byte[] bytes) = Image(build);
        using StringWriter map = new(CultureInfo.InvariantCulture);
        map.WriteFormatted($"; {target.Project.Name}, target {target.Name}: ");
        map.WriteFormatted($"{target.Machine.Id}, {target.Environment}, {target.Cpu}\n");
        map.WriteFormatted($"load ${start:X4}-${start + bytes.Length - 1:X4} ({bytes.Length} {(bytes.Length == 1 ? "byte" : "bytes")})\n");
        map.WriteFormatted($"entry ${build.Entry:X4}\n\nsections\n");
        foreach ((string name, int origin, int length) in Sections(build.Result))
        {
            map.WriteFormatted($"  {name,-16} ${origin:X4}-${origin + length - 1:X4} {length,6}\n");
        }

        map.Write("\nsymbols\n");
        foreach (AssemblySymbol symbol in build.Result.SymbolDefinitions
            .OrderBy(symbol => symbol.Value)
            .ThenBy(symbol => symbol.Name, StringComparer.Ordinal))
        {
            string kind = symbol.IsConstant ? "constant" : "label";
            string value = symbol.Value is >= 0 and <= 0xFFFF ? $"${symbol.Value:X4}" : symbol.Value.ToString(CultureInfo.InvariantCulture);
            map.WriteFormatted($"  {symbol.Name,-24} {value} {kind}\n");
        }

        return map.ToString();
    }

    // Each section that emitted code or data, with what it emitted: up to its last byte, as SourceBuild.Emitted loads.
    private static IEnumerable<(string Name, int Origin, int Length)> Sections(AssemblyResult result)
    {
        int[] used = new int[result.Sections.Count];
        foreach (AssemblySourceMapEntry entry in result.SourceMap)
        {
            if (entry.Size != 0) { used[entry.Section] = Math.Max(used[entry.Section], entry.Offset + entry.Size); }
        }

        for (int index = 0; index < used.Length; index++)
        {
            if (used[index] != 0)
            {
                yield return (result.Sections[index].Name, result.Sections[index].Origin, used[index]);
            }
        }
    }

    private static void Write(TargetBuild build)
    {
        string output = Path.GetDirectoryName(build.Binary) ?? build.Target.Project.Output;
        Directory.CreateDirectory(output);
        Directory.CreateDirectory(Path.GetDirectoryName(build.Record) ?? build.Target.Project.Intermediate);
        File.WriteAllBytes(build.Binary, Image(build).Bytes);
        File.WriteAllText(build.DebugFile, SourceBuild.DebugInfo(build.Result));
        File.WriteAllText(build.MapFile, Map(build));

        JsonObject defines = [];
        foreach ((string name, long value) in build.Target.Symbols().OrderBy(pair => pair.Key, StringComparer.Ordinal))
        {
            defines[name] = value;
        }

        JsonObject record = new()
        {
            ["target"] = build.Target.Name,
            ["machine"] = build.Target.Machine.Id,
            ["environment"] = build.Target.Environment,
            ["cpu"] = build.Target.Cpu.Name,
            ["sources"] = new JsonArray([.. build.Sources.Select(file => (JsonNode?)file.Path)]),
            ["defines"] = defines
        };

        File.WriteAllText(build.Record, record.ToJsonString(new() { WriteIndented = true }));
    }

    // A bare binary is one block: each segment must start where the one below it ends.
    private static void RequireOneBlock(ProjectTarget target, List<(int Address, ReadOnlyMemory<byte> Bytes)> segments)
    {
        List<(int Address, ReadOnlyMemory<byte> Bytes)> ordered = [.. segments.OrderBy(segment => segment.Address)];
        for (int index = 1; index < ordered.Count; index++)
        {
            int end = ordered[index - 1].Address + ordered[index - 1].Bytes.Length;
            if (ordered[index].Address != end)
            {
                throw new ProjectException(
                    $"{target.Project.File}: target {target.Name}: a bare binary is one block, but its code and data end at ${end - 1:X4} and the next part starts at ${ordered[index].Address:X4}.");
            }
        }
    }

    // Every .cpu left after preprocessing that names one of the project CPUs must name one the machine has. The
    // assembler judges the rest, such as Pcode, whose macros write p-code under the 6502.
    private static void CheckCpus(ProjectTarget target, AssemblyProject project)
    {
        List<string> errors = [];
        foreach (AssemblyStatement statement in project.Statements)
        {
            if (statement.Kind != AssemblyStatementKind.Cpu) { continue; }
            string name = statement.Operand.Text.Trim();
            ProjectCpu machine = ProjectTarget.MachineCpu(target.Machine, target.Environment);
            if (ProjectCpu.Find(name) is not { } cpu || machine.Runs(cpu)) { continue; }
            string where = statement.Location is { } location ? $"{location.Path}({location.Line + 1}): " : "";
            errors.Add(
                $"{where}.cpu {name} names a CPU target {target.Name} lacks: its machine, {target.Machine.Id}, runs {machine} code.");
        }

        if (errors.Count != 0)
        {
            throw new ProjectException($"{target.Project.File}: target {target.Name}:{Environment.NewLine}{string.Join(Environment.NewLine, errors)}");
        }
    }

    // Names starting with RC_, in any case, are the SDK's: the project's sources may use them but not define them, as a
    // symbol at any scope, a textual definition or a macro. The predefined ones are defined at "<predefined>", not in a
    // file, and the SDK's own headers may define more.
    private static void CheckReservedNames(ProjectTarget target, AssemblyResult result, List<AssemblySource> sources)
    {
        string sdk = Path.GetFullPath(SdkModules.SdkDirectory) + Path.DirectorySeparatorChar;
        bool Own(string path) => File.Exists(path) && !Path.GetFullPath(path).StartsWith(sdk, StringComparison.OrdinalIgnoreCase);

        List<string> errors = [];
        foreach (AssemblySymbol symbol in result.SymbolDefinitions)
        {
            if (Reserved(symbol.Name) && symbol.Location is { } location && Own(location.Path))
            {
                errors.Add($"{location.Path}({location.Line + 1}): {symbol.Name}: names starting with {TargetDefines.Prefix} are the SDK's; give it another name.");
            }
        }

        // Textual definitions and macros are not symbols: their directives are found in the text of the sources and
        // of the files they include, as the assembly opened them, on the lines it assembled, as the symbols are.
        AssemblySkippedLines? skipped = result.SkippedLines;
        IEnumerable<string> opened = skipped?.Skipped.Keys ?? [];
        foreach (string path in sources.Select(source => source.Path).Concat(opened).Distinct(StringComparer.OrdinalIgnoreCase).Where(Own))
        {
            string[] lines = File.ReadAllLines(path);
            for (int line = 0; line < lines.Length; line++)
            {
                if (skipped?.IsAssembled(path, line) == false) { continue; }
                Match match = DefinitionLine().Match(lines[line]);
                if (match.Success && Reserved(match.Groups["name"].Value))
                {
                    errors.Add($"{path}({line + 1}): {match.Groups["name"].Value}: names starting with {TargetDefines.Prefix} are the SDK's; give it another name.");
                }
            }
        }

        if (errors.Count != 0)
        {
            throw new ProjectException($"{target.Project.File}: target {target.Name}:{Environment.NewLine}{string.Join(Environment.NewLine, errors)}");
        }
    }

    // Whether a name, or the last part of a scoped one, starts with RC_ in any case.
    private static bool Reserved(string name)
    {
        int scope = name.LastIndexOf("::", StringComparison.Ordinal);
        return name[(scope < 0 ? 0 : scope + 2)..].StartsWith(TargetDefines.Prefix, StringComparison.OrdinalIgnoreCase);
    }

    // A line that defines a textual definition or a macro, with an optional label before the directive.
    [GeneratedRegex(@"^\s*(?:[A-Za-z_][A-Za-z0-9_]*:\s*)?\.(?:define|macro|mac)\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex DefinitionLine();

    // Where a target starts when its project names no entry: the first byte its own sources emit, the project's and
    // the target's rather than the platform folders', which assemble before them; null when they emit none.
    private static int? FirstOwnAddress(ProjectTarget target, AssemblyResult result, List<TargetSourceFile> files)
    {
        HashSet<string> platform = [with(StringComparer.OrdinalIgnoreCase), .. target.PlatformFiles()];
        HashSet<string> own = [with(StringComparer.OrdinalIgnoreCase), .. files.Select(file => file.Path).Where(path => !platform.Contains(path))];
        foreach (AssemblySourceMapEntry entry in result.SourceMap)
        {
            if (entry.Size == 0 || entry.Location is not { } location) { continue; }
            while (location.ExpandedFrom is { } outer) { location = outer; }
            if (own.Contains(location.Path)) { return entry.Address; }
        }

        return null;
    }

    private static ProjectException Errors(ProjectTarget target, IEnumerable<AssemblyDiagnostic> diagnostics)
    {
        IEnumerable<string> errors = diagnostics.Select(diagnostic => diagnostic.Location is { } location
            ? $"{location.Path}({location.Line + 1}): {diagnostic.Message}"
            : diagnostic.Message);

        return new($"{target.Project.File}: target {target.Name}:{Environment.NewLine}{string.Join(Environment.NewLine, errors)}");
    }

    private static string Read(ProjectTarget target, string path, string what)
    {
        try
        {
            return File.ReadAllText(path);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            throw new ProjectException($"{target.Project.File}: target {target.Name}: the {what} {path} cannot be read: {exception.Message}");
        }
    }
}