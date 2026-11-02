// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

namespace Retrocore.Assembler;

/// <summary>
///  Maps a single expanded object onto bounded MEMORY regions and assembles owned file images.
/// </summary>
internal sealed partial class AssemblyLinker
{
    // ld65's built-in none target, verbatim from cc65 2.19's cfg/none.cfg.
    private const string None = """
        FEATURES {
            STARTADDRESS: default = $1000;
        }
        SYMBOLS {
            __STACKSIZE__:  type = weak, value = $0800; # 2k stack
            __STACKSTART__: type = weak, value = $8000;
            __ZPSTART__:    type = weak, value = $0080;
        }
        MEMORY {
            ZP:   file = "", define = yes, start = __ZPSTART__, size = $001F;
            MAIN: file = %O,               start = %S,          size = __STACKSTART__ - __STACKSIZE__ - %S;
        }
        SEGMENTS {
            ZEROPAGE: load = ZP,   type = zp;
            STARTUP:  load = MAIN, type = ro,  optional = yes;
            LOWCODE:  load = MAIN, type = ro,  optional = yes;
            ONCE:     load = MAIN, type = ro,  optional = yes;
            CODE:     load = MAIN, type = rw;
            RODATA:   load = MAIN, type = rw;
            DATA:     load = MAIN, type = rw;
            BSS:      load = MAIN, type = bss, define   = yes;
        }
        FEATURES {
            CONDES: type    = constructor,
                    label   = __CONSTRUCTOR_TABLE__,
                    count   = __CONSTRUCTOR_COUNT__,
                    segment = ONCE;
            CONDES: type    = destructor,
                    label   = __DESTRUCTOR_TABLE__,
                    count   = __DESTRUCTOR_COUNT__,
                    segment = RODATA;
            CONDES: type    = interruptor,
                    label   = __INTERRUPTOR_TABLE__,
                    count   = __INTERRUPTOR_COUNT__,
                    segment = RODATA,
                    import  = __CALLIRQ__;
        }
        """;

    private readonly List<AssemblyMemoryRegion> _memory = [];
    private readonly List<AssemblySectionDefinition> _segments = [];
    private readonly List<AssemblyLinkerSymbol> _symbols = [];
    private readonly AssemblySource _configuration;
    private readonly string _output;
    private readonly string _text;
    private readonly string _defaultStart;
    private string? _startAddress;
    private int _position;

    private AssemblyLinker(AssemblySource configuration, string output, int defaultStart)
    {
        _configuration = configuration;
        _output = output;
        _text = configuration.Text;
        _defaultStart = defaultStart.ToString(CultureInfo.InvariantCulture);
    }

    /// <summary>
    ///  Creates a link plan without modifying caller-owned syntax.
    /// </summary>
    /// <param name="source">Expanded object syntax.</param>
    /// <param name="options">Explicit config and output settings.</param>
    /// <param name="project">Receives the compilation-only syntax view.</param>
    /// <returns>The file-image plan.</returns>
    internal static AssemblyLinker Create(AssemblyProject source, AssemblyOptions options, out AssemblyProject project)
    {
        AssemblySource configuration = options.LinkerConfiguration ?? new(None, "<none>");
        AssemblyLinker linker = new(configuration, options.OutputFile, options.Origin);
        linker.Parse();
        if (!linker._segments.Any(segment => segment.Name == "CODE"))
        {
            for (int index = 0; index < source.Statements.Count; index++)
            {
                AssemblyStatementKind kind = source.Statements[index].Kind;
                if (kind == AssemblyStatementKind.Section) { break; }
                if (kind is AssemblyStatementKind.Instruction
                    or AssemblyStatementKind.Data
                    or AssemblyStatementKind.Reserve
                    or AssemblyStatementKind.Label
                    or AssemblyStatementKind.Procedure
                    or AssemblyStatementKind.LogicalOrigin)
                {
                    throw new AssemblyError(index, "The implicit CODE segment has no linker definition.");
                }
            }
        }

        project = new(source.Statements.Count)
        {
            InitialSection = "CODE",
            SymbolAliases = source.SymbolAliases,
            MerlinOutput = source.MerlinOutput
        };

        foreach (AssemblySource document in source.Sources) { project.Sources.Add(document); }
        AssemblySectionDefinition? selected = linker.FindSegment("CODE");
        for (int index = 0; index < source.Statements.Count; index++)
        {
            AssemblyStatement node = source.Statements[index];
            if (node.Kind == AssemblyStatementKind.Section) { selected = linker.FindSegment(node.Operand.Text.Trim()); }
            if (node.Dialect == AssemblyDialect.Ca65
                && node.Kind is AssemblyStatementKind.Reserve or AssemblyStatementKind.Align
                && selected?.Memory is { FillByte: not 0 } memory)
            {
                AssemblyOperands operands = new(node.Operand.Text.AsMemory(), index);
                operands.MoveNext();
                if (!operands.MoveNext())
                {
                    node = new(
                        node.Kind,
                        node.Operation,
                        new($"{node.Operand.Text}, {memory.FillByte}"),
                        node.Label)
                    {
                        Location = node.Location,
                        WidthPolicy = node.WidthPolicy,
                        Dialect = node.Dialect
                    };
                }
            }

            project.Statements.Add(node);
        }

        if (source.DeclaredSections is { Count: > 0 })
        {
            throw linker.Failure("A linker configuration cannot be combined with native section definitions.");
        }

        foreach (AssemblySectionDefinition segment in linker._segments) { project.SectionDefinitions.Add(segment); }
        project.MemoryRegions = linker._memory;
        project.LinkerSymbols = linker._symbols;
        return linker;
    }

    /// <summary>
    ///  Produces files in MEMORY declaration order, concatenating regions assigned to the same file.
    /// </summary>
    /// <param name="image">Resolved output whose section indices stay unchanged for source maps.</param>
    internal void Emit(AssemblyImage image)
    {
        Dictionary<string, List<byte>> files = new(StringComparer.Ordinal);
        foreach (AssemblyMemoryRegion memory in _memory)
        {
            if (memory.File.Length == 0) { continue; }
            int length = memory.Fill ? memory.End - memory.Start : 0;
            foreach (AssemblySectionDefinition definition in _segments)
            {
                if (!ReferenceEquals(definition.Memory, memory)) { continue; }
                AssemblySection section = image.Sections.Single(item => item.Name == definition.Name);
                if (section.Bytes.Length != 0)
                {
                    length = Math.Max(length, section.Origin - memory.Start + section.Bytes.Length);
                }
            }

            byte[] data = new byte[length];
            if (memory.FillByte != 0) { data.AsSpan().Fill(memory.FillByte); }
            foreach (AssemblySectionDefinition definition in _segments)
            {
                if (!ReferenceEquals(definition.Memory, memory)) { continue; }
                AssemblySection section = image.Sections.Single(item => item.Name == definition.Name);
                if (section.Bytes.Length != 0)
                {
                    section.Bytes.Span.CopyTo(data.AsSpan(section.Origin - memory.Start));
                }
            }

            if (!files.TryGetValue(memory.File, out List<byte>? bytes))
            {
                bytes = [];
                files.Add(memory.File, bytes);
            }

            bytes.AddRange(data);
        }

        image.Files = files.ToDictionary(pair => pair.Key, pair => (ReadOnlyMemory<byte>)pair.Value.ToArray(), StringComparer.Ordinal);
    }

    private void Parse()
    {
        HashSet<string> blocks = new(StringComparer.Ordinal);
        List<(string Name, Dictionary<string, string> Attributes)> memory = [];
        List<(string Name, Dictionary<string, string> Attributes)> segments = [];
        while (Peek() != '\0')
        {
            string block = Token().ToUpperInvariant();
            if (block is not ("MEMORY" or "SEGMENTS" or "SYMBOLS" or "FEATURES"))
            {
                throw Failure($"Unsupported linker block '{block}'.");
            }

            // ld65 allows FEATURES more than once; the other blocks each describe the whole link.
            if (!blocks.Add(block) && block != "FEATURES") { throw Failure($"Duplicate linker block '{block}'."); }
            Expect('{');
            while (Peek() != '}')
            {
                string name = Token();
                if (!AssemblySyntax.IsPlainIdentifier(name)) { throw Failure("Expected a linker identifier."); }
                if (block == "SYMBOLS" && Peek() == '=')
                {
                    // The older SYMBOLS form is "name = value;".
                    _position++;
                    string value = Value();
                    Expect(';');
                    AddSymbol(name, value, weak: false);
                    continue;
                }

                Expect(':');
                Dictionary<string, string> attributes = new(StringComparer.Ordinal);
                do
                {
                    string attribute = Token().ToLowerInvariant();
                    Expect('=');
                    if (!attributes.TryAdd(attribute, Value()))
                    {
                        throw Failure($"Duplicate linker attribute '{attribute}'.");
                    }

                    // As in ld65, commas between attributes are optional.
                    if (Peek() == ',') { _position++; }
                }
                while (Peek() != ';');

                Expect(';');
                switch (block)
                {
                    case "MEMORY":
                        memory.Add((name, attributes));
                        break;
                    case "SEGMENTS":
                        segments.Add((name, attributes));
                        break;
                    case "SYMBOLS":
                        Symbol(name, attributes);
                        break;
                    default:
                        Feature(name, attributes);
                        break;
                }
            }

            Expect('}');
        }

        if (!blocks.Contains("MEMORY") || !blocks.Contains("SEGMENTS"))
        {
            throw Failure("Linker configuration requires MEMORY and SEGMENTS blocks.");
        }

        // As with ld65's -S option, %S is the FEATURES start address when given and otherwise the options' origin.
        _startAddress ??= _defaultStart;
        for (int index = 0; index < _symbols.Count; index++)
        {
            AssemblyLinkerSymbol symbol = _symbols[index];
            _symbols[index] = new(symbol.Name, Expression(symbol.Expression), symbol.Weak);
        }

        foreach (var region in memory) { Memory(region.Name, region.Attributes); }
        foreach (var segment in segments) { Segment(segment.Name, segment.Attributes); }
    }

    /// <summary>
    ///  Creates the generator's fixed, padded ROM placement without any filesystem access.
    /// </summary>
    /// <param name="origin">The ROM load address.</param>
    /// <param name="size">The exact ROM byte count.</param>
    /// <returns>A bounded single-output linker configuration.</returns>
    internal static AssemblySource ImageConfiguration(int origin, int size) => new(
        FormattableString.Invariant(
            $"MEMORY {{ ROM: start={origin}, size={size}, fill=yes, file=%O; }} SEGMENTS {{ CODE: load=ROM,type=ro; RODATA: load=ROM,type=ro; DATA: load=ROM,type=rw; BSS: load=ROM,type=bss; }}"),
        "<ROM>");

    private void Memory(string name, Dictionary<string, string> values)
    {
        if (_memory.Any(memory => memory.Name == name)) { throw Failure($"Duplicate MEMORY region '{name}'."); }
        string start = Expression(Take(values, "start", required: true));
        string size = Expression(Take(values, "size", required: true));
        string file = Take(values, "file") ?? "%O";
        file = file == "%O" ? _output : Quoted(file);
        bool fill = Flag(Take(values, "fill"));
        bool define = Flag(Take(values, "define"));
        int fillByte = Number(Take(values, "fillval") ?? "0");
        if (Take(values, "type") is { } type && type is not ("ro" or "rw"))
        {
            throw Failure($"Unsupported MEMORY type '{type}'.");
        }

        // A bank number only affects .bank expressions, which this front end does not support.
        _ = Take(values, "bank");

        Unknown(values);
        if (fillByte is < 0 or > 255) { throw Failure($"MEMORY region '{name}' needs a byte fill value."); }
        _memory.Add(new(name, start, size, file, fill, (byte)fillByte, define));
    }

    private void Symbol(string name, Dictionary<string, string> values)
    {
        string type = Take(values, "type") ?? "export";
        string? value = Take(values, "value");
        Unknown(values);
        switch (type)
        {
            case "import":
                // A single object supplies imported symbols itself, so the link defines nothing.
                if (value is not null) { throw Failure("An imported linker symbol takes no value."); }
                return;
            case "export":
            case "weak":
                AddSymbol(name, value ?? throw Failure($"Linker symbol '{name}' needs a value."), type == "weak");
                return;
            default:
                throw Failure($"Unsupported linker symbol type '{type}'.");
        }
    }

    private void AddSymbol(string name, string value, bool weak)
    {
        if (_symbols.Any(symbol => symbol.Name == name)) { throw Failure($"Duplicate linker symbol '{name}'."); }
        _symbols.Add(new(name, value, weak));
    }

    private void Feature(string name, Dictionary<string, string> values)
    {
        switch (name.ToUpperInvariant())
        {
            case "STARTADDRESS":
                string value = Take(values, "default", required: true) ?? "";
                Unknown(values);
                _startAddress = Number(value).ToString(CultureInfo.InvariantCulture);
                return;
            case "CONDES":
                // Constructor and destructor tables only collect .constructor entries, which this front end lacks.
                values.Clear();
                return;
            default:
                throw Failure($"Unsupported linker feature '{name}'.");
        }
    }

    private string Expression(string? text) =>
        (text ?? throw Failure("Expected a linker expression.")).Replace("%S", $"({_startAddress})");

    private AssemblySectionDefinition? FindSegment(string name)
    {
        foreach (AssemblySectionDefinition segment in _segments)
        {
            if (segment.Name == name) { return segment; }
        }

        return null;
    }

    private void Segment(string name, Dictionary<string, string> values)
    {
        if (_segments.Any(segment => segment.Name == name)) { throw Failure($"Duplicate segment '{name}'."); }
        string? load = Take(values, "load", required: true);
        AssemblyMemoryRegion memory = _memory.SingleOrDefault(region => region.Name == load)
            ?? throw Failure($"Unknown MEMORY region '{load}'.");

        string type = Take(values, "type", required: true) ?? throw Failure("A segment type is required.");
        if (type is not ("ro" or "rw" or "bss" or "zp")) { throw Failure($"Unsupported segment type '{type}'."); }
        int alignment = Number(Take(values, "align") ?? "1");
        _ = Flag(Take(values, "optional"));
        bool define = Flag(Take(values, "define"));

        // A fixed start, or an offset from a constant region start, places the segment instead of packing it.
        int? origin = Take(values, "start") is { } start ? Number(Expression(start)) : null;
        if (Take(values, "offset") is { } offset)
        {
            if (origin is not null) { throw Failure("A segment cannot have both start and offset."); }
            origin = Number(memory.StartExpression) + Number(Expression(offset));
        }

        Unknown(values);
        if (alignment <= 0 || alignment > 65536)
        {
            throw Failure("Segment alignment must be positive and within the address space.");
        }

        if (origin is < 0 or > ushort.MaxValue)
        {
            throw Failure($"Segment '{name}' must start within the address space.");
        }

        _segments.Add(new(name, origin)
        {
            Alignment = alignment,
            Memory = memory,
            DefineSymbols = define,
            NoOutput = type is "bss" or "zp",
            FillByte = memory.FillByte
        });
    }

    private AssemblyError Failure(string message)
    {
        int line = 0;
        for (int index = 0; index < _position; index++) { if (_text[index] == '\n') { line++; } }
        return new(-1, $"{_configuration.Path}({line + 1}): {message}");
    }

    private string? Take(Dictionary<string, string> values, string name, bool required = false)
    {
        if (values.TryGetValue(name, out string? value))
        {
            values.Remove(name);
            return value;
        }

        return required ? throw Failure($"Missing linker attribute '{name}'.") : null;
    }

    private void Unknown(Dictionary<string, string> values)
    {
        if (values.Count != 0) { throw Failure($"Unsupported linker attribute '{values.Keys.First()}'."); }
    }

    private bool Flag(string? text) => text switch
    {
        null or "no" => false,
        "yes" => true,
        _ => throw Failure("Expected yes or no.")
    };

    private string Quoted(string text) => AssemblySyntax.IsStringLiteral(text)
        ? text[1..^1] : throw Failure("Expected a quoted output filename or %O.");

    private int Number(string? text)
    {
        if (text is null) { throw Failure("Expected a constant expression."); }
        AssemblySymbols symbols = new();
        try
        {
            ExpressionEvaluator expression = new(text.AsMemory(), symbols, address: 0, line: -1);
            return !expression.TryEvaluate(out long value) || expression.ReadsAddress || value is < int.MinValue or > int.MaxValue
                ? throw Failure("Linker values must be constant 32-bit expressions.") : (int)value;
        }
        catch (OverflowException)
        {
            throw Failure("Linker constant expression overflow.");
        }
    }
}
