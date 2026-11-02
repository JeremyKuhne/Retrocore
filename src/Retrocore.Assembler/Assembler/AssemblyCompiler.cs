// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using Retrocore.Isa;

namespace Retrocore.Assembler;

/// <summary>
///  A managed build-time 6502 assembler with stabilized label layout and range-checked emission.
///  Instruction encodings are supplied by the CPU's canonical opcode definitions.
/// </summary>
/// <remarks>
///  <para>
///   Compilation first separates metadata from emitting statements, then repeats layout until addresses,
///   symbols and addressing modes stop changing, and only then writes bytes. Layout state belongs to this
///   compilation, never to the caller's editable syntax nodes.
///  </para>
///  <para>
///   Diagnostic positions in this engine are input-model statement indices. The facade translates them to
///   optional source locations; they are not necessarily physical source line numbers.
///  </para>
/// </remarks>
internal static partial class AssemblyCompiler
{
    private const int MaximumLayoutPasses = 32;

    // Matches the name AssemblySection used before sections could be declared.
    private const string DefaultSectionName = ".text";

    private const char AsciiMaximum = (char)sbyte.MaxValue;

    private const byte HighAsciiBit = 0x80;

    // After these passes an absolute encoding never shrinks, so widths only grow and layout must converge.
    private const int ShrinkingLayoutPasses = 8;

    /// <summary>
    ///  Assembles a padded ROM without executing external tools or introducing runtime dependencies.
    /// </summary>
    /// <param name="project">The typed assembly model.</param>
    /// <param name="options">The CPU and fixed-image options.</param>
    /// <param name="sets">Encoders keyed by CPU variant.</param>
    /// <param name="errors">Receives every independent statement error.</param>
    /// <param name="cancellationToken">The cancellation token.</param>
    /// <returns>The compiled image, or null when <paramref name="errors"/> received any error.</returns>
    /// <exception cref="AssemblyError">An error that prevents checking any further statements.</exception>
    /// <remarks>
    ///  <para>
    ///   Declarations and the first layout pass check every statement, skipping one that fails. Later passes
    ///   depend on complete addresses, so they run only when those checks succeed. Emission then checks every
    ///   statement again against final symbol values.
    ///  </para>
    /// </remarks>
    internal static AssemblyImage? Assemble(
        AssemblyProject project,
        AssemblyOptions options,
        IReadOnlyDictionary<string, InstructionSet> sets,
        List<AssemblyError> errors,
        CancellationToken cancellationToken)
    {
        // Sizing by labels rather than statements keeps the table off the large-object heap for ROM sources.
        int labels = 0;
        bool scoped = false;

        // Only a change of dialect between statements resets local labels, so a single-dialect source starts there.
        AssemblyDialect dialect = project.Statements.Count == 0 ? AssemblyDialect.Native : project.Statements[0].Dialect;
        foreach (AssemblyStatement node in project.Statements)
        {
            if (node.Label is not null) { labels++; }
            if (!scoped) { scoped = node.Dialect != dialect || AssemblyNameResolver.RequiresResolution(node); }
            dialect = node.Dialect;
        }

        AssemblyNameResolver? names = null;
        if (scoped)
        {
            names = AssemblyNameResolver.Resolve(project, options, sets, errors, cancellationToken);
            if (errors.Count != 0) { return null; }
            project = names.Project;
        }

        // Every name is declared before layout, so an expression recorded before its target is laid out
        // still refers to the symbol a later definition sets.
        AssemblySymbols symbols = new(labels);
        try
        {
            AssemblyImage? image = Assemble(project, options, sets, symbols, labels, names?.Exports, errors, cancellationToken);
            if (image is not null) { names?.Publish(image); }
            return image;
        }
        finally
        {
            symbols.Programs.Release();
        }
    }

    /// <summary>
    ///  Assembles with a symbol table whose recorded programs the caller releases.
    /// </summary>
    /// <param name="project">The typed assembly model.</param>
    /// <param name="options">The CPU and fixed-image options.</param>
    /// <param name="sets">Encoders keyed by CPU variant.</param>
    /// <param name="symbols">The empty symbol table for this compilation.</param>
    /// <param name="symbolCapacity">The source declaration count.</param>
    /// <param name="exportNames">Optional plain-to-qualified export bindings.</param>
    /// <param name="errors">Receives every independent statement error.</param>
    /// <param name="cancellationToken">The cancellation token.</param>
    /// <returns>The compiled image, or null when <paramref name="errors"/> received any error.</returns>
    private static AssemblyImage? Assemble(
        AssemblyProject project,
        AssemblyOptions options,
        IReadOnlyDictionary<string, InstructionSet> sets,
        AssemblySymbols symbols,
        int symbolCapacity,
        Dictionary<string, string>? exportNames,
        List<AssemblyError> errors,
        CancellationToken cancellationToken)
    {
        // Metadata directives consume model indices but do not occupy entries in the layout array.
        LayoutStatement[] statements = new LayoutStatement[project.Statements.Count];
        int statementCount = 0;
        Dictionary<string, AssemblyStatement> declared = new(symbolCapacity, StringComparer.Ordinal);
        HashSet<string> exports = new(StringComparer.Ordinal);

        // .global names are exported only when defined; an undefined one is an unused import in a single object.
        HashSet<string>? optionalExports = null;
        if (!sets.TryGetValue(options.Cpu, out InstructionSet? codes))
        {
            throw new AssemblyError(line: 0, $"Unknown CPU '{options.Cpu}'.");
        }

        bool declaredCpu = false;
        List<InstructionSet>? cpuSettings = null;
        byte cpuIndex = 0;
        int sectionCount = 0;
        bool noOutputRegions = false;
        for (int index = 0; index < project.Statements.Count; index++)
        {
            AssemblyStatement node = project.Statements[index];
            cancellationToken.ThrowIfCancellationRequested();
            int line = index;
            string? label = node.Label;

            // A duplicate still lays out, so references to the name do not add unresolved-symbol errors.
            if (label is not null)
            {
                bool variable = node.Kind == AssemblyStatementKind.Variable;
                if (declared.TryGetValue(label, out AssemblyStatement? previous))
                {
                    if (variable && previous.Kind == AssemblyStatementKind.Variable)
                    {
                        // The public definition is the last assignment, matching the published final value.
                        declared[label] = node;
                    }
                    else
                    {
                        errors.Add(new(line, variable || previous.Kind == AssemblyStatementKind.Variable
                            ? $"Duplicate symbol '{label}': a variable cannot also be a label or equate."
                            : $"Duplicate symbol '{label}'."));
                    }
                }
                else
                {
                    declared.Add(label, node);
                }

                // Each assignment defines its own immutable version, so layout passes still converge.
                if (variable && previous is null or { Kind: AssemblyStatementKind.Variable })
                {
                    label = symbols.DeclareVersion(label);
                }

                symbols.Declare(label);
            }

            ReadOnlySpan<char> mnemonic = node.OperationMemory.Span;
            ReadOnlyMemory<char> operand = node.Operand.Memory;

            // The facade has already matched each kind to its operation text, so dispatch needs no directive list.
            if (node.Kind == AssemblyStatementKind.Cpu)
            {
                if (label is not null || !TryCpu(node.Operand.Text, sets, out InstructionSet? declaredCodes))
                {
                    errors.Add(new(line, "Expected '.cpu' naming a known CPU, such as Mos6502, 65SC02 or Z80."));
                    continue;
                }

                if (!declaredCpu)
                {
                    codes = declaredCodes;
                    declaredCpu = true;
                }

                if (!ReferenceEquals(codes, declaredCodes))
                {
                    cpuSettings ??= [codes];
                    int selected = cpuSettings.IndexOf(declaredCodes);
                    if (selected < 0)
                    {
                        selected = cpuSettings.Count;
                        cpuSettings.Add(declaredCodes);
                    }

                    cpuIndex = checked((byte)selected);
                }
                else
                {
                    cpuIndex = 0;
                }

                continue;
            }

            if (node.Kind == AssemblyStatementKind.Export)
            {
                try
                {
                    if (label is not null) { throw new AssemblyError(line, "An export cannot have an address label."); }
                    bool global = mnemonic.Equals(".global", StringComparison.OrdinalIgnoreCase);
                    foreach (ReadOnlyMemory<char> item in new AssemblyOperands(operand, line))
                    {
                        string name = item.ToString();
                        if (!AssemblySyntax.IsPlainIdentifier(item.Span))
                        {
                            throw new AssemblyError(line, $"Invalid or duplicate exported symbol '{name}'.");
                        }

                        // Repeating .global is harmless, and an .export of a .global name makes it required.
                        if (exports.Add(name))
                        {
                            if (global) { (optionalExports ??= new(StringComparer.Ordinal)).Add(name); }
                        }
                        else if (!global && optionalExports?.Remove(name) != true)
                        {
                            throw new AssemblyError(line, $"Invalid or duplicate exported symbol '{name}'.");
                        }
                    }
                }
                catch (AssemblyError error)
                {
                    errors.Add(error);
                }

                continue;
            }

            LayoutOperation operation = node.Kind switch
            {
                AssemblyStatementKind.Label => LayoutOperation.Label,
                AssemblyStatementKind.Instruction => LayoutOperation.Instruction,
                AssemblyStatementKind.Constant or AssemblyStatementKind.Variable => LayoutOperation.Constant,
                AssemblyStatementKind.Data => DataOperation(mnemonic),
                AssemblyStatementKind.Reserve => LayoutOperation.Reserve,
                AssemblyStatementKind.Origin => LayoutOperation.Origin,
                AssemblyStatementKind.Assertion => LayoutOperation.Assertion,
                AssemblyStatementKind.Section => LayoutOperation.Section,
                AssemblyStatementKind.Align => LayoutOperation.Align,
                AssemblyStatementKind.LogicalOrigin => LayoutOperation.LogicalOrigin,
                AssemblyStatementKind.DummyStart => LayoutOperation.DummyStart,
                AssemblyStatementKind.DummyEnd => LayoutOperation.DummyEnd,
                AssemblyStatementKind.Checksum => LayoutOperation.Checksum,
                _ => throw new AssemblyError(line, $"Unsupported directive '{mnemonic}'.")
            };

            statements[statementCount++] = new(line, label, operation, operand)
            {
                Location = node.Location,
                CpuIndex = cpuIndex,
                SourceOrder = (node.WidthPolicy ?? options.WidthPolicy) == AssemblyWidthPolicy.SourceOrder
            };

            if (operation == LayoutOperation.Section) { sectionCount++; }
            noOutputRegions |= operation == LayoutOperation.DummyStart;
        }

        if (codes is null)
        {
            throw new AssemblyError(line: 0, "A known CPU is required.");
        }

        // A .cpu declaration may follow instructions, so mnemonics and operand syntax resolve once the CPU is final.
        // Sets of one description share its operand forms; a .cpu of another family, such as the Z80 in a 6502
        // source, brings its own.
        OperandFormMatcher matcher = OperandFormMatcher.Get(codes.Description);
        OperandFormMatcher[]? matchers = cpuSettings?.Select(set => OperandFormMatcher.Get(set.Description)).ToArray();
        int shrinkBudget = 0;
        for (int index = 0; index < statementCount; index++)
        {
            ref LayoutStatement statement = ref statements[index];
            if (statement.Kind == LayoutOperation.Instruction)
            {
                ReadOnlySpan<char> mnemonic = project.Statements[statement.Line].OperationMemory.Span;
                if (mnemonic.EndsWith(".W", StringComparison.OrdinalIgnoreCase))
                {
                    statement.ForcesAbsolute = true;
                    mnemonic = mnemonic[..^2];
                }

                InstructionSet selected = cpuSettings is null ? codes : cpuSettings[statement.CpuIndex];
                statement.Mnemonic = selected.GetMnemonic(mnemonic);
                ClassifyOperand(selected, matchers?[statement.CpuIndex] ?? matcher, ref statement);
                if (CanShrinkSyntax(in statement)) { shrinkBudget++; }
            }
        }

        // Keep previous-pass forward values until their declarations are visited again in the current pass.
        List<LayoutSection> sections = CollectSections(
            project,
            statements,
            statementCount,
            sectionCount,
            shrinkBudget,
            options,
            symbols,
            declared,
            errors);

        DeclareLinkerSymbols(project, symbols, declared, errors);
        Dictionary<int, int>? labelSizes = null;
        if (project.LabelSizes is { } sized)
        {
            labelSizes = new(sized.Count);
            foreach (KeyValuePair<string, int> pair in sized)
            {
                labelSizes[pair.Value] = DeclareSectionSymbol(pair.Key, pair.Value, symbols, declared, errors);
            }
        }

        foreach (LayoutSection section in sections) { noOutputRegions |= section.NoOutput; }
        bool stable = false;
        bool needsBoundsCheck = false;
        for (int pass = 0; pass < MaximumLayoutPasses; pass++)
        {
            bool changed = EvaluateLinkerValues(project, symbols, firstPass: pass == 0);
            changed |= PlaceSections(sections);
            bool allowShrink = pass < ShrinkingLayoutPasses;
            symbols.ResetBindings();

            int current = project.InitialSection is { } initial ? FindSection(sections, initial) : 0;
            if (current < 0) { current = 0; }
            LayoutContext context = new()
            {
                Address = sections[current].RunOrigin,
                Capacity = sections[current].Capacity,
                ShrinkBudget = sections[current].ShrinkBudget,
                NoOutput = sections[current].NoOutput,
                RunOrigin = sections[current].RunOrigin,
                SectionProvisional = sections[current].Provisional,
                Provisional = sections[current].Provisional,
                SegmentRelative = sections[current].Definition?.Memory is not null,
                LabelSizes = labelSizes,
                DummyLine = -1
            };

            for (int index = 0; index < statementCount; index++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                try
                {
                    ref LayoutStatement statement = ref statements[index];
                    if (statement.Kind == LayoutOperation.Section)
                    {
                        if (context.DummyLine >= 0)
                        {
                            throw new AssemblyError(statement.Line, ".section is not allowed inside .dum.");
                        }

                        int previousAddress = statement.Address;
                        int previousOffset = statement.Offset;
                        SelectSection(ref statement, symbols, sections, ref current, ref context);
                        changed |= previousAddress != context.Address || previousOffset != context.Offset;
                        statement.Address = context.Address;
                        statement.Offset = context.Offset;
                        if (statement.Label is { } sectionLabel)
                        {
                            changed |= symbols.SetValue(sectionLabel, context.Address);
                        }
                    }
                    else
                    {
                        if (noOutputRegions)
                        {
                            bool dummy = context.DummyLine >= 0;
                            statement.NoOutput = dummy || context.NoOutput;
                            statement.IsDummy = dummy;
                        }

                        InstructionSet selected = cpuSettings is null ? codes : cpuSettings[statement.CpuIndex];
                        changed |= Layout(
                            ref statement,
                            selected,
                            matchers?[statement.CpuIndex] ?? matcher,
                            symbols,
                            project,
                            ref context,
                            allowShrink,
                            pass == 0);
                    }
                }
                catch (AssemblyError error) when (pass == 0)
                {
                    // The failed statement occupies nothing, so later statements still report their own errors.
                    errors.Add(error);
                }
            }

            SaveSection(sections, current, context.Address, context.Offset);
            needsBoundsCheck = context.RelaxedBounds;
            changed |= UpdateSectionSymbols(sections, symbols);
            changed |= UpdateMemorySymbols(project, sections, symbols);
            if (context.DummyLine >= 0) { errors.Add(new(context.DummyLine, "Unterminated .dum region.")); }
            if (errors.Count != 0) { return null; }

            // Both symbol values and instruction widths must stabilize; either can move later labels.
            if (!changed)
            {
                stable = true;
                break;
            }
        }

        if (!stable)
        {
            throw new AssemblyError(line: 0, $"Assembly layout did not stabilize within {MaximumLayoutPasses} passes.");
        }

        CheckSections(sections, errors);
        if (needsBoundsCheck) { CheckStatementBounds(statements, statementCount, sections, errors); }
        if (errors.Count != 0) { return null; }

        // Zero-initialized fixed images supply .org gaps and any unused tail padding.
        byte[][] images = new byte[sections.Count][];
        for (int index = 0; index < images.Length; index++)
        {
            LayoutSection section = sections[index];
            images[index] = section.NoOutput ? [] : new byte[section.Size];
            if (section.FillByte != 0) { images[index].AsSpan().Fill(section.FillByte); }
        }

        int scratchSize = 0;
        if (noOutputRegions)
        {
            foreach (LayoutStatement statement in statements.AsSpan(0, statementCount))
            {
                if (statement.NoOutput) { scratchSize = Math.Max(scratchSize, statement.Size); }
            }
        }

        byte[] scratch = scratchSize == 0 ? [] : new byte[scratchSize];
        symbols.ResetBindings();
        for (int index = 0; index < statementCount; index++)
        {
            cancellationToken.ThrowIfCancellationRequested();

            try
            {
                ref LayoutStatement statement = ref statements[index];
                InstructionSet selected = cpuSettings is null ? codes : cpuSettings[statement.CpuIndex];
                OperandFormMatcher selectedMatcher = matchers?[statement.CpuIndex] ?? matcher;
                Emit(in statement, selected, selectedMatcher, symbols, statement.NoOutput ? scratch : images[statement.Section]);
            }
            catch (AssemblyError error)
            {
                errors.Add(error);
            }
        }

        Dictionary<string, long> exported = new(exports.Count, StringComparer.Ordinal);
        foreach (string name in exports)
        {
            string target = exportNames is not null && exportNames.TryGetValue(name, out string? resolved) ? resolved : name;
            bool resolvedValue = symbols.TryGetValue(target.AsMemory(), out long value);
            if (!resolvedValue && optionalExports?.Contains(name) == true) { continue; }
            if (!resolvedValue || value is < int.MinValue or > int.MaxValue)
            {
                errors.Add(new(line: 0, $"Export '{name}' is unresolved or out of range."));
                continue;
            }

            exported.Add(name, value);
        }

        if (errors.Count != 0) { return null; }
        AssemblySection[] output = new AssemblySection[sections.Count];
        for (int index = 0; index < output.Length; index++)
        {
            output[index] = new(
                sections[index].Name,
                sections[index].Origin,
                sections[index].RunOrigin,
                sections[index].Size,
                images[index]);
        }

        return new(output, exported, symbols.Snapshot(), declared, statements, statementCount, project)
        {
            InstructionSets = cpuSettings is null ? [codes] : [.. cpuSettings]
        };
    }

    /// <summary>
    ///  Distinguishes the data directives that share <see cref="AssemblyStatementKind.Data"/>.
    /// </summary>
    /// <param name="mnemonic">The directive in any case.</param>
    /// <returns>The directive's layout behavior.</returns>
    private static LayoutOperation DataOperation(ReadOnlySpan<char> mnemonic) => mnemonic.Length switch
    {
        5 when mnemonic.Equals(".WORD", StringComparison.OrdinalIgnoreCase) => LayoutOperation.Word,
        5 when mnemonic.Equals(".DBYT", StringComparison.OrdinalIgnoreCase) => LayoutOperation.BigEndianWord,
        5 => LayoutOperation.Byte,
        6 => LayoutOperation.Dword,
        8 when mnemonic.Equals(".FARADDR", StringComparison.OrdinalIgnoreCase) => LayoutOperation.FarAddress,
        _ => LayoutOperation.HighAscii
    };

    /// <summary>
    ///  Reports sections whose names repeat or whose address ranges overlap.
    /// </summary>
    /// <param name="sections">The stabilized sections in declaration order.</param>
    /// <param name="errors">Receives an error at each later conflicting section.</param>
    private static void CheckSections(List<LayoutSection> sections, List<AssemblyError> errors)
    {
        for (int later = 1; later < sections.Count; later++)
        {
            LayoutSection current = sections[later];
            for (int earlier = 0; earlier < later; earlier++)
            {
                LayoutSection previous = sections[earlier];
                if (current.Size == 0 || previous.Size == 0) { continue; }
                if (string.Equals(previous.Name, current.Name, StringComparison.Ordinal))
                {
                    errors.Add(new(current.Line, $"Duplicate section '{current.Name}'."));
                    break;
                }

                if (previous.Definition?.Memory is { } previousMemory
                    && current.Definition?.Memory is { } currentMemory
                    && !ReferenceEquals(previousMemory, currentMemory))
                {
                    continue;
                }

                if (current.Origin < previous.Origin + previous.Size && previous.Origin < current.Origin + current.Size)
                {
                    errors.Add(new(current.Line, $"Section '{current.Name}' overlaps section '{previous.Name}'."));
                    break;
                }
            }
        }
    }

    /// <summary>
    ///  Lays out one statement at the current location counter for this pass.
    /// </summary>
    /// <param name="statement">The statement, updated with its address, size and encoding.</param>
    /// <param name="codes">The CPU's instruction set.</param>
    /// <param name="matcher">The instruction set's operand forms.</param>
    /// <param name="symbols">Values known so far in this layout pass.</param>
    /// <param name="project">Original syntax, read only when reporting instruction errors.</param>
    /// <param name="context">The current counters, bounds and dummy-region state.</param>
    /// <param name="allowShrink">Whether an absolute encoding from the previous pass may become zero-page.</param>
    /// <param name="firstPass">Whether this is the first layout pass, which reports every independent error.</param>
    /// <returns>Whether a symbol value or the statement's layout changed.</returns>
    private static bool Layout(
        ref LayoutStatement statement,
        InstructionSet codes,
        OperandFormMatcher matcher,
        AssemblySymbols symbols,
        AssemblyProject project,
        ref LayoutContext context,
        bool allowShrink,
        bool firstPass)
    {
        int address = context.Address;
        int offset = context.Offset;
        bool changed = false;
        if (statement.Kind is LayoutOperation.LogicalOrigin or LayoutOperation.DummyStart or LayoutOperation.DummyEnd)
        {
            if (statement.Kind == LayoutOperation.DummyEnd)
            {
                if (context.DummyLine < 0 || statement.EncodingOperand.Length != 0)
                {
                    throw new AssemblyError(statement.Line, ".dend requires an open .dum and no operand.");
                }

                address = context.DummyAddress;
                context.DummyLine = -1;
                statement.IsDummy = false;
            }
            else
            {
                if (statement.Kind == LayoutOperation.DummyStart && context.DummyLine >= 0)
                {
                    throw new AssemblyError(statement.Line, "Nested .dum regions are not supported.");
                }

                // An empty .logicalorg ends a logical region: the counter returns to the section's own address.
                int target = statement.Kind == LayoutOperation.LogicalOrigin && statement.EncodingOperand.IsEmpty
                    ? context.RunOrigin + offset
                    : Word(LayoutValue(ref statement, statement.EncodingOperand, symbols, address), statement.Line);

                if (statement.Kind == LayoutOperation.LogicalOrigin)
                {
                    // An absolute .logicalorg address is meaningful even where the section's own address is not.
                    context.Logical = !statement.EncodingOperand.IsEmpty;
                    context.Provisional = context.SectionProvisional && !context.Logical;
                }

                if (statement.Kind == LayoutOperation.DummyStart)
                {
                    context.DummyAddress = address;
                    context.DummyLine = statement.Line;
                    statement.IsDummy = true;
                }

                address = target;
            }

            context.Address = address;
            changed = statement.Address != address || statement.Offset != offset;
            statement.Address = address;
            statement.Offset = offset;
            statement.Size = 0;
            if (statement.Label is { } logicalLabel) { changed |= symbols.SetValue(logicalLabel, address); }
            return changed;
        }

        if (statement.Kind == LayoutOperation.Constant)
        {
            statement.Address = address;
            statement.Offset = offset;
            int constantId = symbols.Declare(
                statement.Label ?? throw new AssemblyError(statement.Line, "Constant name is missing."));

            if (TryLayoutValue(ref statement, statement.EncodingOperand, symbols, address, out long constant))
            {
                changed = symbols.SetValue(constantId, constant);
            }

            // A .set version becomes visible only after its own operand reads the previous version.
            symbols.Bind(constantId);
            return changed;
        }

        // A label in a provisionally placed section stays unknown, like a forward reference, so instruction
        // widths chosen this pass do not depend on an address the linker has not determined.
        if (statement.Label is { } name && !context.Provisional) { changed = symbols.SetValue(name, address); }

        // Data and assertions evaluate only at emission, which other errors skip. Checking them in the first
        // pass reports a .set variable read before its assignment alongside those errors.
        if (firstPass && symbols.HasVariables && DefersEvaluation(statement.Kind))
        {
            CheckVariableReads(in statement, symbols, address);
        }

        int length;
        int? encoding = null;
        switch (statement.Kind)
        {
            case LayoutOperation.Label: length = 0;
                break;
            case LayoutOperation.Origin:
                long target = LayoutValue(ref statement, statement.EncodingOperand, symbols, address);
                if (target < address)
                {
                    throw new AssemblyError(statement.Line, ".org cannot overlap or move backwards.");
                }

                if (target > InstructionEncoding.AddressSpaceSize)
                {
                    throw new AssemblyError(statement.Line, ".org exceeds the current section.");
                }

                length = (int)target - address;
                break;
            // Data length depends only on operand text, so later passes reuse the first pass's count.
            case LayoutOperation.Byte or LayoutOperation.HighAscii:
                length = (int)(statement.LiteralValue ??= DataLength(statement.EncodingOperand, statement.Line, allowStrings: true));
                break;
            case LayoutOperation.Word:
            case LayoutOperation.BigEndianWord:
                length = (int)(statement.LiteralValue ??= checked(
                    DataLength(statement.EncodingOperand, statement.Line, allowStrings: false) * 2));

                break;
            case LayoutOperation.Dword:
                length = (int)(statement.LiteralValue ??= checked(
                    DataLength(statement.EncodingOperand, statement.Line, allowStrings: false) * sizeof(uint)));

                break;
            case LayoutOperation.FarAddress:
                length = (int)(statement.LiteralValue ??= checked(
                    DataLength(statement.EncodingOperand, statement.Line, allowStrings: false) * 3));

                break;
            case LayoutOperation.Reserve:
                ReadOnlyMemory<char> reserveCount = ReserveOperands(statement.EncodingOperand, statement.Line, out _);
                long count = LayoutValue(ref statement, reserveCount, symbols, address);
                long remaining = context.DummyLine >= 0
                    ? InstructionEncoding.AddressSpaceSize - (long)address : context.Capacity - (long)offset;

                if (count < 0 || count > remaining + context.ShrinkBudget)
                {
                    throw new AssemblyError(statement.Line, ".res exceeds the current section.");
                }

                length = (int)count;
                break;
            case LayoutOperation.Align:
                ReadOnlyMemory<char> alignmentOperand = ReserveOperands(statement.EncodingOperand, statement.Line, out _);
                long alignment = LayoutValue(ref statement, alignmentOperand, symbols, address);
                if (alignment <= 0 || alignment > InstructionEncoding.AddressSpaceSize || (alignment & (alignment - 1)) != 0)
                {
                    throw new AssemblyError(statement.Line, ".align requires a power-of-two alignment within 64 KiB.");
                }

                // As in ld65, a linker segment aligns relative to its own start; an absolute counter aligns itself.
                length = context.SegmentRelative && !context.Logical
                    ? AlignAddress(offset, (int)alignment) - offset
                    : AlignAddress(address, (int)alignment) - address;

                break;
            case LayoutOperation.Checksum:
                if (statement.EncodingOperand.Length != 0 || statement.NoOutput)
                {
                    throw new AssemblyError(statement.Line, ".checksum requires file output and no operand.");
                }

                length = 1;
                break;
            case LayoutOperation.Assertion: length = 0;
                break;
            default:
                int selected = SelectEncoding(codes, matcher, ref statement, symbols, project, address, allowShrink);
                encoding = selected;
                length = codes.Size(selected);
                break;
        }

        int available = InstructionEncoding.AddressSpaceSize - address;
        if (context.DummyLine < 0) { available = Math.Min(available, context.Capacity - offset); }
        if (length < 0)
        {
            throw new AssemblyError(statement.Line, "Statement exceeds the current section.");
        }

        if (length > available)
        {
            if (length > available + (long)context.ShrinkBudget)
            {
                throw new AssemblyError(statement.Line, "Statement exceeds the current section.");
            }

            context.RelaxedBounds = true;
        }

        changed |= statement.Address != address
            || statement.Offset != offset
            || statement.Size != length
            || statement.Encoding != encoding;

        statement.Address = address;
        statement.Offset = offset;
        statement.Size = length;
        if (context.LabelSizes is { } sizes && sizes.TryGetValue(statement.Line, out int sizeSymbol))
        {
            changed |= symbols.SetValue(sizeSymbol, length);
        }

        statement.Encoding = encoding;
        context.Address = address + length;
        if (context.DummyLine < 0) { context.Offset = offset + length; }
        return changed;
    }

    /// <summary>
    ///  Writes a stabilized statement, resolving every remaining expression against the final symbols.
    /// </summary>
    /// <param name="statement">The final address, size and addressing mode.</param>
    /// <param name="symbols">The final symbol values.</param>
    /// <param name="image">The fixed output buffer.</param>
    private static void Emit(
        in LayoutStatement statement,
        InstructionSet codes,
        OperandFormMatcher matcher,
        AssemblySymbols symbols,
        byte[] image)
    {
        int start = statement.NoOutput ? 0 : statement.Offset;
        int offset = start;
        switch (statement.Kind)
        {
            case LayoutOperation.Label: case LayoutOperation.Origin: case LayoutOperation.Section:
            case LayoutOperation.LogicalOrigin: case LayoutOperation.DummyStart: case LayoutOperation.DummyEnd: return;
            // An unused constant must still fail if its expression never resolved during layout.
            case LayoutOperation.Constant: EmittedLayoutValue(in statement, statement.EncodingOperand, symbols);
                if (symbols.HasVariables && statement.Label is { } constantName)
                {
                    symbols.Bind(symbols.Declare(constantName));
                }

                return;
            case LayoutOperation.Assertion:
                ReadOnlyMemory<char> assertion = AssertionOperand(statement.EncodingOperand, statement.Line, out string? message);
                if (Value(assertion, symbols, statement.Address, statement.Line) == 0)
                {
                    throw new AssemblyError(statement.Line, $"Assembly assertion failed: {message ?? assertion.ToString()}");
                }

                return;
            case LayoutOperation.Reserve:
            case LayoutOperation.Align:
                ReserveOperands(statement.EncodingOperand, statement.Line, out ReadOnlyMemory<char> fillOperand);
                byte fill = !fillOperand.IsEmpty
                    ? Byte(Value(fillOperand, symbols, statement.Address, statement.Line), statement.Line) : (byte)0;

                image.AsSpan(offset, statement.Size).Fill(fill);
                return;
            case LayoutOperation.Checksum:
                byte checksum = 0;
                foreach (byte value in image.AsSpan(0, offset)) { checksum ^= value; }
                image[offset] = checksum;
                return;
            case LayoutOperation.Byte:
            case LayoutOperation.HighAscii:
            case LayoutOperation.Word:
            case LayoutOperation.Dword:
            case LayoutOperation.BigEndianWord:
            case LayoutOperation.FarAddress:
                // Apple II text sets bit 7 on every character, including numeric control codes.
                byte high = statement.Kind == LayoutOperation.HighAscii ? HighAsciiBit : (byte)0;
                foreach (ReadOnlyMemory<char> expression in new AssemblyOperands(statement.EncodingOperand, statement.Line))
                {
                    if (AssemblySyntax.IsStringLiteral(expression.Span))
                    {
                        foreach (char character in expression.Span[1..^1])
                        {
                            image[offset++] = character <= AsciiMaximum
                                ? (byte)(character | high)
                                : throw new AssemblyError(statement.Line, "String literals must contain only ASCII characters.");
                        }

                        continue;
                    }

                    // The location counter advances for each data element, not only once per directive.
                    long value = Value(expression, symbols, statement.Address + offset - start, statement.Line);
                    if (statement.Kind is LayoutOperation.Byte or LayoutOperation.HighAscii)
                    {
                        image[offset++] = (byte)(Byte(value, statement.Line) | high);
                    }
                    else if (statement.Kind is LayoutOperation.Word or LayoutOperation.BigEndianWord)
                    {
                        int word = Word(value, statement.Line);

                        bool bigEndian = statement.Kind == LayoutOperation.BigEndianWord;
                        image[offset++] = (byte)(bigEndian ? word >> 8 : word);
                        image[offset++] = (byte)(bigEndian ? word : word >> 8);
                    }
                    else if (statement.Kind == LayoutOperation.FarAddress)
                    {
                        if (value is < 0 or > 0xFFFFFF)
                        {
                            throw new AssemblyError(statement.Line, "Operand is outside the 24-bit range.");
                        }

                        image[offset++] = (byte)value;
                        image[offset++] = (byte)(value >> 8);
                        image[offset++] = (byte)(value >> 16);
                    }
                    else
                    {
                        // As in ca65, a negative value emits its two's-complement form.
                        if (value is < int.MinValue or > uint.MaxValue)
                        {
                            throw new AssemblyError(statement.Line, "Operand is outside the 32-bit range.");
                        }

                        for (int part = 0; part < sizeof(uint); part++)
                        {
                            image[offset++] = (byte)(value >> (part * InstructionEncoding.BitsPerByte));
                        }
                    }
                }

                return;
        }

        IsaEncoding encoding = codes.Encodings[statement.Encoding
            ?? throw new InvalidOperationException("An instruction must have a stabilized encoding before emission.")];

        // A split opcode, such as the Z80's DD CB d op, puts its last bytes after the operand bytes.
        OperandForm form = codes.Forms[encoding.Form];
        int first = offset;
        if (encoding.SplitAt == 0)
        {
            for (int index = 0; index < encoding.OpcodeLength; index++)
            {
                image[first + index] = encoding.OpcodeByte(index);
            }
        }
        else
        {
            for (int index = 0; index < encoding.OpcodeLength; index++)
            {
                image[first + encoding.OpcodeBytePosition(index, form.Size)] = encoding.OpcodeByte(index);
            }
        }

        if (form.FieldCount == 0) { return; }
        offset = first + encoding.OpcodeBytesBeforeOperands;
        FieldContext fields = new(
            first + encoding.OpcodeBytePosition(encoding.OpcodeLength - 1, form.Size),
            statement.Address + statement.Size,
            codes.Endianness,
            statement.Line);

        if (matcher.HasHoles(form.Id))
        {
            // Each hole holds one field, such as the displacement and value of LD [IX+d],n.
            Span<ReadOnlyMemory<char>> expressions = new ReadOnlyMemory<char>[OperandFormMatcher.MaximumHoles];
            int holes = matcher.Expressions(statement.EncodingOperand, form.Id, expressions);
            if (holes != form.FieldCount)
            {
                throw new AssemblyError(statement.Line, form.FieldMessage ?? $"Expected {form.FieldCount} operands.");
            }

            for (int field = 0; field < form.FieldCount; field++)
            {
                long value = Value(expressions[field], symbols, statement.Address, statement.Line);
                offset = EmitField(image, offset, form.Field(field), value, in fields);
            }

            return;
        }

        ReadOnlyMemory<char> operand = matcher.Expression(statement.EncodingOperand, form.Id);
        if (form.FieldCount == 1)
        {
            // An address operand's layout expression is the emitted expression; other forms evaluate it here once.
            long value = statement.HasNarrowForm
                ? EmittedLayoutValue(in statement, operand, symbols)
                : Value(operand, symbols, statement.Address, statement.Line);

            EmitField(image, offset, form.Field(0), value, in fields);
            return;
        }

        // Check the count before evaluating, so a missing field reports the form's own message.
        AssemblyOperands counter = new(operand, statement.Line);
        int count = 0;
        while (counter.MoveNext()) { count++; }
        if (count != form.FieldCount)
        {
            throw new AssemblyError(statement.Line, form.FieldMessage ?? $"Expected {form.FieldCount} operands.");
        }

        AssemblyOperands parts = new(operand, statement.Line);
        for (int field = 0; field < form.FieldCount; field++)
        {
            parts.MoveNext();
            long value = Value(parts.Current, symbols, statement.Address, statement.Line);
            offset = EmitField(image, offset, form.Field(field), value, in fields);
        }
    }


    /// <summary>
    ///  Writes one operand field.
    /// </summary>
    /// <param name="image">The output.</param>
    /// <param name="offset">Where the field starts.</param>
    /// <param name="field">The field's kind.</param>
    /// <param name="value">The field's value: a target address for a relative field.</param>
    /// <param name="fields">The instruction's opcode position, next address, byte order and line.</param>
    /// <returns>The offset after the field; an opcode field takes no operand byte.</returns>
    private static int EmitField(byte[] image, int offset, OperandFieldKind field, long value, in FieldContext fields)
    {
        int line = fields.Line;
        switch (field)
        {
            case OperandFieldKind.Byte:
                image[offset] = Byte(value, line);
                return offset + 1;
            case OperandFieldKind.Relative8:
                image[offset] = Relative(value, fields.Next, line);
                return offset + 1;
            case OperandFieldKind.Displacement8:
                image[offset] = value is >= sbyte.MinValue and <= sbyte.MaxValue
                    ? unchecked((byte)value)
                    : throw new AssemblyError(line, "Displacement is outside the signed 8-bit range.");

                return offset + 1;
            case OperandFieldKind.BitNumber:
                image[fields.OpcodeByte] |= value is >= 0 and < InstructionEncoding.BitsPerByte
                    ? (byte)(value << OpcodeFieldShift)
                    : throw new AssemblyError(line, "Bit number must be 0-7.");

                return offset;
            case OperandFieldKind.Restart:
                image[fields.OpcodeByte] |= value is >= 0 and <= RestartMask && (value & ~RestartMask) == 0
                    ? (byte)value
                    : throw new AssemblyError(line, "Restart address must be $00, $08, $10, $18, $20, $28, $30 or $38.");

                return offset;
            default:
                int word = field == OperandFieldKind.Word ? Word(value, line) : Relative16(value, fields.Next, line);
                byte low = (byte)word;
                byte high = (byte)(word >> InstructionEncoding.BitsPerByte);
                image[offset] = fields.Endianness == Endianness.Little ? low : high;
                image[offset + 1] = fields.Endianness == Endianness.Little ? high : low;
                return offset + 2;
        }
    }

    // A bit number or restart address sits in bits 3-5 of the last opcode byte.
    private const int OpcodeFieldShift = 3;
    private const int RestartMask = 0x38;

    /// <summary>
    ///  Classifies operand syntax once, since only the zero-page or absolute width can change between passes.
    /// </summary>
    /// <param name="codes">The CPU's instruction set.</param>
    /// <param name="matcher">The instruction set's operand forms.</param>
    /// <param name="statement">The instruction with its resolved mnemonic ID and once-compacted operand.</param>
    /// <remarks>
    ///  <para>
    ///   Classification never throws: an unsupported form is reported by the pass that reaches the statement,
    ///   keeping diagnostics in statement order.
    ///  </para>
    /// </remarks>
    private static void ClassifyOperand(InstructionSet codes, OperandFormMatcher matcher, ref LayoutStatement statement)
    {
        int prefix = AssemblySyntax.AbsolutePrefixLength(statement.EncodingOperand.Span);
        if (prefix != 0)
        {
            statement.ForcesAbsolute = true;
            statement.EncodingOperand = statement.EncodingOperand[prefix..];
        }

        int zeroPrefix = AssemblySyntax.ZeroPagePrefixLength(statement.EncodingOperand.Span);
        if (zeroPrefix != 0)
        {
            statement.ForcesZeroPage = true;
            statement.EncodingOperand = statement.EncodingOperand[zeroPrefix..];
        }

        statement.Form = matcher.Classify(codes, statement.Mnemonic, statement.EncodingOperand.Span, out ushort narrow);
        statement.HasNarrowForm = narrow != OperandFormMatcher.NoForm;
    }

    /// <summary>
    ///  Selects the classified form, choosing an address width from the current layout's symbol values.
    /// </summary>
    /// <param name="codes">The CPU's instruction set.</param>
    /// <param name="matcher">The instruction set's operand forms.</param>
    /// <param name="statement">The instruction with its classified operand syntax.</param>
    /// <param name="symbols">Values known so far in this layout pass.</param>
    /// <param name="project">Original instruction syntax for diagnostics.</param>
    /// <param name="address">The instruction address used for the location counter.</param>
    /// <param name="allowShrink">Whether an absolute encoding from the previous pass may become zero-page.</param>
    /// <returns>The encoding's ID, retained through final emission.</returns>
    /// <remarks>
    ///  <para>
    ///   Shrinking an instruction moves later labels, which can push an operand back out of zero page. Once
    ///   shrinking stops, the previous wide choice is kept, so such an operand settles as a valid absolute form.
    ///  </para>
    /// </remarks>
    private static int SelectEncoding(
        InstructionSet codes,
        OperandFormMatcher matcher,
        ref LayoutStatement statement,
        AssemblySymbols symbols,
        AssemblyProject project,
        int address,
        bool allowShrink)
    {
        int mnemonic = statement.Mnemonic;
        int line = statement.Line;
        int form = statement.Form;
        bool narrowForm = statement.HasNarrowForm || (form != OperandFormMatcher.NoForm && codes.Forms[form].IsNarrow);
        if (statement.ForcesZeroPage && (statement.ForcesAbsolute || !narrowForm))
        {
            throw new AssemblyError(line, "Forced zero-page addressing requires a zero-page address form.");
        }

        if (statement.ForcesAbsolute && !statement.HasNarrowForm)
        {
            throw new AssemblyError(line, "Forced absolute addressing requires an address operand.");
        }

        if (statement.HasNarrowForm)
        {
            int narrow = codes.Forms[form].Narrow;

            // Evaluate even when only one width exists, so expression errors surface in the same pass and statement.
            ReadOnlyMemory<char> expression = matcher.Expression(statement.EncodingOperand, form);
            // Unknown forward values use a wide encoding unless the CPU offers only the narrow form.
            bool known = TryLayoutValue(ref statement, expression, symbols, address, out long value);
            if (statement.SourceOrder && statement.Encoding is { } fixedEncoding)
            {
                return fixedEncoding;
            }

            bool keepWide = !allowShrink && statement.Encoding is { } previous && codes.Encodings[previous].Form == form;
            long limit = (1L << (codes.Forms[narrow].Size * InstructionEncoding.BitsPerByte)) - 1;
            bool small = known && value >= 0 && value <= limit && !keepWide;

            // A forced width never falls back to the narrow form, even when the CPU lacks the wide one.
            bool shrink = !statement.ForcesAbsolute && (small || !codes.Has(mnemonic, form));
            form = statement.ForcesZeroPage || (shrink && codes.Has(mnemonic, narrow)) ? narrow : form;
        }

        if (!codes.TryGet(mnemonic, form, out int encoding))
        {
            string operation = project.Statements[line].Operation.ToUpperInvariant();
            throw new AssemblyError(
                line,
                $"Unknown instruction or unsupported addressing mode: {operation} {statement.EncodingOperand}.");
        }

        return codes.Exclusion(mnemonic) is { } reason
            ? throw new AssemblyError(
                line,
                string.Format(CultureInfo.InvariantCulture, reason, project.Statements[line].Operation))
            : encoding;
    }

    /// <summary>
    ///  Encodes a branch displacement with 16-bit program-counter wrapping and signed 8-bit range checks.
    /// </summary>
    /// <param name="target">The resolved absolute target address.</param>
    /// <param name="next">The address immediately after the complete branch instruction.</param>
    /// <param name="line">The input-model statement index for diagnostics.</param>
    /// <returns>The two's-complement displacement byte.</returns>
    private static byte Relative(long target, int next, int line)
    {
        Word(target, line);
        // Normalize modulo 64 KiB before checking range, including branches across $FFFF/$0000.
        int displacement = (int)((target - (next & ushort.MaxValue) + InstructionEncoding.AddressSpaceSize) & ushort.MaxValue);
        if (displacement > short.MaxValue) { displacement -= InstructionEncoding.AddressSpaceSize; }
        return displacement is < sbyte.MinValue or > sbyte.MaxValue
            ? throw new AssemblyError(line, "Branch target is outside the signed 8-bit range.")
            : (byte)displacement;
    }

    /// <summary>
    ///  Encodes a long branch displacement, which reaches the whole 16-bit address space by wrapping.
    /// </summary>
    /// <param name="target">The resolved absolute target address.</param>
    /// <param name="next">The address immediately after the complete branch instruction.</param>
    /// <param name="line">The input-model statement index for diagnostics.</param>
    /// <returns>The displacement as an unsigned word.</returns>
    private static int Relative16(long target, int next, int line)
    {
        Word(target, line);
        return (int)((target - (next & ushort.MaxValue)) & ushort.MaxValue);
    }

    /// <summary>
    ///  Requires a byte-sized value instead of silently truncating an expression.
    /// </summary>
    /// <param name="value">The resolved value.</param>
    /// <param name="line">The input-model statement index for diagnostics.</param>
    /// <returns>The validated byte.</returns>
    private static byte Byte(long value, int line) => value is >= 0 and <= byte.MaxValue
        ? (byte)value : throw new AssemblyError(line, "Operand is outside the byte range; use < or > for extraction.");

    /// <summary>
    ///  Requires a value in the CPU's unsigned 16-bit address space.
    /// </summary>
    /// <param name="value">The resolved value.</param>
    /// <param name="line">The input-model statement index for diagnostics.</param>
    /// <returns>The validated word value.</returns>
    private static int Word(long value, int line) => value is >= 0 and <= ushort.MaxValue
        ? (int)value : throw new AssemblyError(line, "Operand is outside the 16-bit address range.");

    /// <summary>
    ///  Evaluates operands that layout otherwise defers to emission, surfacing early variable reads.
    /// </summary>
    /// <param name="statement">A data or assertion statement.</param>
    /// <param name="symbols">Values and variable bindings known so far in this pass.</param>
    /// <param name="address">The location counter.</param>
    private static void CheckVariableReads(in LayoutStatement statement, AssemblySymbols symbols, int address)
    {
        if (statement.Kind == LayoutOperation.Assertion)
        {
            TryValue(AssertionOperand(statement.EncodingOperand, statement.Line, out _), symbols, address, statement.Line, out _);
            return;
        }

        foreach (ReadOnlyMemory<char> expression in new AssemblyOperands(statement.EncodingOperand, statement.Line))
        {
            if (!AssemblySyntax.IsStringLiteral(expression.Span))
            {
                TryValue(expression, symbols, address, statement.Line, out _);
            }
        }
    }

    private static ReadOnlyMemory<char> AssertionOperand(ReadOnlyMemory<char> text, int line, out string? message)
    {
        message = null;
        if (text.Span.IndexOf(',') < 0) { return text; }
        AssemblyOperands operands = new(text, line);
        operands.MoveNext();
        ReadOnlyMemory<char> expression = operands.Current;
        if (!operands.MoveNext() || !AssemblySyntax.IsStringLiteral(operands.Current.Span))
        {
            throw new AssemblyError(line, "An assertion message must be a quoted string.");
        }

        message = operands.Current.Span[1..^1].ToString();
        return operands.MoveNext() ? throw new AssemblyError(line, "An assertion takes an expression and optional message.") : expression;
    }

    private static bool DefersEvaluation(LayoutOperation kind) => kind switch
    {
        LayoutOperation.Byte => true,
        LayoutOperation.HighAscii => true,
        LayoutOperation.Word => true,
        LayoutOperation.Dword => true,
        LayoutOperation.BigEndianWord => true,
        LayoutOperation.FarAddress => true,
        LayoutOperation.Assertion => true,
        _ => false
    };

    /// <summary>
    ///  Evaluates an expression that must resolve at this phase, reporting unresolved symbols as errors.
    /// </summary>
    /// <param name="text">The expression slice.</param>
    /// <param name="symbols">The currently available symbol values.</param>
    /// <param name="address">The value of the location counter.</param>
    /// <param name="line">The input-model statement index for diagnostics.</param>
    /// <returns>The resolved integer value.</returns>
    private static long Value(ReadOnlyMemory<char> text, AssemblySymbols symbols, int address, int line) =>
        TryValue(text, symbols, address, line, out long value) ? value : throw new AssemblyError(line, $"Unresolved expression '{text}'.");

    /// <summary>
    ///  Evaluates without rejecting forward references and translates checked overflow to an addressed error.
    /// </summary>
    /// <param name="text">The expression slice.</param>
    /// <param name="symbols">The currently available symbol values.</param>
    /// <param name="address">The value of the location counter.</param>
    /// <param name="line">The input-model statement index for diagnostics.</param>
    /// <param name="value">The result, meaningful only when all referenced symbols resolved.</param>
    /// <returns>Whether the value is known in this pass.</returns>
    private static bool TryValue(ReadOnlyMemory<char> text, AssemblySymbols symbols, int address, int line, out long value) =>
        TryValue(text, symbols, address, line, out value, out _);

    /// <summary>
    ///  Evaluates without rejecting forward references, also reporting whether the value depends on layout.
    /// </summary>
    /// <param name="text">The expression slice.</param>
    /// <param name="symbols">The currently available symbol values.</param>
    /// <param name="address">The value of the location counter.</param>
    /// <param name="line">The input-model statement index for diagnostics.</param>
    /// <param name="value">The result, meaningful only when all referenced symbols resolved.</param>
    /// <param name="contextual">Whether the expression read a symbol or the location counter.</param>
    /// <param name="recording">Receives the postfix steps of the evaluation, when supplied.</param>
    /// <returns>Whether the value is known in this pass.</returns>
    private static bool TryValue(
        ReadOnlyMemory<char> text,
        AssemblySymbols symbols,
        int address,
        int line,
        out long value,
        out bool contextual,
        ExpressionPrograms? recording = null)
    {
        try
        {
            ExpressionEvaluator evaluator = new(text, symbols, address, line, recording);
            bool known = evaluator.TryEvaluate(out value);
            contextual = evaluator.IsContextual;
            return known;
        }
        catch (OverflowException)
        {
            throw new AssemblyError(line, "Expression overflow.");
        }
    }

    /// <summary>
    ///  Evaluates a statement's layout expression, reusing a value that its text alone determined in an earlier pass.
    /// </summary>
    /// <param name="statement">The statement owning the expression and its cached value.</param>
    /// <param name="text">The statement's single layout-time expression.</param>
    /// <param name="symbols">The currently available symbol values.</param>
    /// <param name="address">The value of the location counter.</param>
    /// <param name="value">The result, meaningful only when all referenced symbols resolved.</param>
    /// <returns>Whether the value is known in this pass.</returns>
    /// <remarks>
    ///  <para>
    ///   The first evaluation always interprets the text, so every diagnostic still surfaces in the first pass at
    ///   the same statement. A literal's value cannot change, so later passes reuse it. Any other expression is
    ///   recorded while it is interpreted, and later passes and emission replay that program instead.
    ///  </para>
    /// </remarks>
    private static bool TryLayoutValue(
        ref LayoutStatement statement,
        ReadOnlyMemory<char> text,
        AssemblySymbols symbols,
        int address,
        out long value)
    {
        if (statement.LiteralValue is { } literal)
        {
            value = literal;
            return true;
        }

        if (statement.ProgramLength != 0)
        {
            return TryRecordedValue(in statement, symbols, address, out value);
        }

        ExpressionPrograms programs = symbols.Programs;
        int start = programs.Count;
        bool known = TryValue(text, symbols, address, statement.Line, out value, out bool contextual, programs);
        if (contextual)
        {
            statement.ProgramStart = start;
            statement.ProgramLength = programs.Count - start;
        }
        else
        {
            programs.Truncate(start);
            statement.LiteralValue = value;
        }

        return known;
    }

    /// <summary>
    ///  Replays a recorded expression, translating checked overflow to an addressed error as interpretation does.
    /// </summary>
    /// <param name="statement">The statement whose layout expression was recorded.</param>
    /// <param name="symbols">The currently available symbol values and recorded programs.</param>
    /// <param name="address">The value of the location counter.</param>
    /// <param name="value">The result, meaningful only when all referenced symbols resolved.</param>
    /// <returns>Whether the value is known in this pass.</returns>
    private static bool TryRecordedValue(in LayoutStatement statement, AssemblySymbols symbols, int address, out long value)
    {
        try
        {
            return symbols.Programs.TryEvaluate(
                statement.ProgramStart,
                statement.ProgramLength,
                symbols,
                address,
                statement.Line,
                out value);
        }
        catch (OverflowException)
        {
            throw new AssemblyError(statement.Line, "Expression overflow.");
        }
    }

    /// <summary>
    ///  Evaluates a stabilized statement's layout expression during emission, reusing its literal or recording.
    /// </summary>
    /// <param name="statement">The statement whose layout expression is being emitted.</param>
    /// <param name="text">The same expression text that layout evaluated.</param>
    /// <param name="symbols">The final symbol values.</param>
    /// <returns>The resolved integer value.</returns>
    private static long EmittedLayoutValue(in LayoutStatement statement, ReadOnlyMemory<char> text, AssemblySymbols symbols)
    {
        // A layout expression is either a cached literal or a recording, never both.
        return statement.ProgramLength != 0
            ? TryRecordedValue(in statement, symbols, statement.Address, out long value)
                ? value
                : throw new AssemblyError(statement.Line, $"Unresolved expression '{text}'.")
            : statement.LiteralValue ?? Value(text, symbols, statement.Address, statement.Line);
    }

    /// <summary>
    ///  Evaluates a statement's layout expression that must resolve in this pass.
    /// </summary>
    /// <param name="statement">The statement owning the expression and its cached value.</param>
    /// <param name="text">The statement's single layout-time expression.</param>
    /// <param name="symbols">The currently available symbol values.</param>
    /// <param name="address">The value of the location counter.</param>
    /// <returns>The resolved integer value.</returns>
    private static long LayoutValue(
        ref LayoutStatement statement,
        ReadOnlyMemory<char> text,
        AssemblySymbols symbols,
        int address)
    {
        return TryLayoutValue(ref statement, text, symbols, address, out long value)
            ? value
            : throw new AssemblyError(statement.Line, $"Unresolved expression '{text}'.");
    }

    /// <summary>
    ///  Determines directive size while validating the complete operand list without materializing its slices.
    /// </summary>
    /// <param name="text">The directive operands.</param>
    /// <param name="line">The input-model statement index for diagnostics.</param>
    /// <param name="allowStrings">Whether a string literal may supply one element per character.</param>
    /// <returns>The number of data elements.</returns>
    private static int DataLength(ReadOnlyMemory<char> text, int line, bool allowStrings)
    {
        int count = 0;
        foreach (ReadOnlyMemory<char> operand in new AssemblyOperands(text, line))
        {
            if (!AssemblySyntax.IsStringLiteral(operand.Span))
            {
                count++;
            }
            else if (allowStrings)
            {
                count += operand.Length - 2;
            }
            else
            {
                throw new AssemblyError(line, "String literals are only valid in .byte and .hiascii.");
            }
        }

        return count;
    }

    /// <summary>
    ///  Evaluates a .section statement's name, origin and size.
    /// </summary>
    /// <param name="statement">The .section statement.</param>
    /// <param name="symbols">Values known so far in this layout pass.</param>
    /// <param name="address">The location counter before the section starts.</param>
    /// <returns>The validated section.</returns>
    private static LayoutSection SectionOperands(in LayoutStatement statement, AssemblySymbols symbols, int address)
    {
        int line = statement.Line;
        AssemblyOperands operands = new(statement.EncodingOperand, line);
        ReadOnlyMemory<char> name = operands.MoveNext() ? operands.Current : default;
        ReadOnlyMemory<char> origin = operands.MoveNext() ? operands.Current : default;
        ReadOnlyMemory<char> size = operands.MoveNext() ? operands.Current : default;
        ReadOnlyMemory<char> fill = operands.MoveNext() ? operands.Current : default;
        ReadOnlyMemory<char> trim = operands.MoveNext() ? operands.Current : default;
        if (size.IsEmpty || operands.MoveNext() || !AssemblySyntax.IsPlainIdentifier(name.Span))
        {
            throw new AssemblyError(line, ".section requires a name, origin and size.");
        }

        long start = Value(origin, symbols, address, line);
        long length = Value(size, symbols, address, line);
        return start is < 0 or > ushort.MaxValue || length <= 0 || length > InstructionEncoding.AddressSpaceSize - start
            ? throw new AssemblyError(line, ".section must fit within the 64 KiB address space.")
            : new(name.ToString(), (int)start, (int)length, line)
            {
                FillByte = fill.IsEmpty ? (byte)0 : Byte(Value(fill, symbols, address, line), line),
                Trim = !trim.IsEmpty && Value(trim, symbols, address, line) != 0
            };
    }

    /// <summary>
    ///  Maps a .cpu operand to its instruction set, such as <c>Mos6502</c> or the subset <c>65SC02</c>.
    /// </summary>
    /// <param name="name">The .cpu operand.</param>
    /// <param name="sets">Instruction sets keyed by name.</param>
    /// <param name="codes">The selected instruction set.</param>
    /// <returns>Whether the name selects a known CPU.</returns>
    internal static bool TryCpu(
        string name,
        IReadOnlyDictionary<string, InstructionSet> sets,
        [NotNullWhen(returnValue: true)] out InstructionSet? codes) => sets.TryGetValue(name, out codes);

    /// <summary>
    ///  Validates .res arity and separates its size expression from its optional emission-time fill expression.
    /// </summary>
    /// <param name="text">The count and optional fill operands.</param>
    /// <param name="line">The input-model statement index for diagnostics.</param>
    /// <param name="fill">The fill expression, or empty memory when the default zero fill applies.</param>
    /// <returns>The required count expression.</returns>
    private static ReadOnlyMemory<char> ReserveOperands(ReadOnlyMemory<char> text, int line, out ReadOnlyMemory<char> fill)
    {
        AssemblyOperands operands = new(text, line);
        operands.MoveNext();
        ReadOnlyMemory<char> count = operands.Current;
        fill = operands.MoveNext() ? operands.Current : default;
        return operands.MoveNext() ? throw new AssemblyError(line, ".res accepts count and optional fill byte.") : count;
    }
}
