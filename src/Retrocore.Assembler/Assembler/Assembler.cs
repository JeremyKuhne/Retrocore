// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;

namespace Retrocore.Assembler;

/// <summary>
///  Typed native-dialect assembly. Text and caller-built models use the same bounded compiler.
/// </summary>
public sealed partial class Assembler
{
    private readonly IReadOnlyDictionary<string, InstructionSet> _sets;

    /// <summary>
    ///  Accepts canonical opcode input from the runtime or Roslyn build adapter.
    /// </summary>
    /// <param name="sets">The shared CPU metadata.</param>
    internal Assembler(IReadOnlyDictionary<string, InstructionSet> sets) => _sets = sets;

    /// <summary>
    ///  Parses native assembly text into an editable typed model, preserving operation spelling.
    /// </summary>
    /// <param name="source">The immutable source document.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>The model and source diagnostics.</returns>
    public static AssemblyParseResult Parse(AssemblySource source, CancellationToken cancellationToken = default) =>
        Parse(source, options: null, cancellationToken);

    /// <summary>
    ///  Parses assembly text with preprocessing settings and an inherited dialect.
    /// </summary>
    /// <param name="source">The immutable source document.</param>
    /// <param name="options">Optional preprocessing settings and inherited dialect.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>The model and source diagnostics.</returns>
    public static AssemblyParseResult Parse(
        AssemblySource source,
        AssemblyOptions? options,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(source);
        cancellationToken.ThrowIfCancellationRequested();
        return ParseNative(source, cancellationToken, options);
    }

    /// <summary>
    ///  Parses several roots in order using one preprocessing and symbol environment.
    /// </summary>
    /// <param name="sources">The root documents.</param>
    /// <param name="options">Preprocessing and inherited dialect settings.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>The combined statement stream and diagnostics.</returns>
    public static AssemblyParseResult Parse(
        IEnumerable<AssemblySource> sources,
        AssemblyOptions options,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(sources);
        ArgumentNullException.ThrowIfNull(options);
        return AssemblyPreprocessor.Parse(sources, options, cancellationToken);
    }

    /// <summary>
    ///  Parses native statements, restarting through preprocessing at the first expansion directive.
    /// </summary>
    /// <param name="source">The document.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <param name="options">Optional preprocessing settings.</param>
    /// <returns>Native syntax and diagnostics.</returns>
    private static AssemblyParseResult ParseNative(
        AssemblySource source,
        CancellationToken cancellationToken,
        AssemblyOptions? options)
    {
        if (AssemblyPreprocessor.HasDialectSelection(source, options) || options?.PredefinedSymbols.Count > 0)
        {
            return AssemblyPreprocessor.Parse([source], options ?? DefaultPreprocessingOptions(), cancellationToken);
        }

        // Each statement takes at least one line. Sizing from the LF count avoids repeatedly regrowing a list
        // that, for ROM-sized sources, would be reallocated on the large-object heap.
        AssemblyProject project = new(source.Text.Count('\n') + 1);
        project.Sources.Add(source);
        List<AssemblyDiagnostic>? diagnostics = null;
        int nextLine = 0;
        foreach (ReadOnlyMemory<char> sourceLine in new AssemblyLines(source.Text.AsMemory()))
        {
            // Blank and comment-only lines still advance physical source locations.
            int line = nextLine++;
            cancellationToken.ThrowIfCancellationRequested();
            AssemblyStatement? node = ParseLine(sourceLine, line, out ReadOnlySpan<char> unsupported, out string? error);

            // Operands are evaluated after parsing, so a preprocessor function is found by its call syntax.
            if (sourceLine.Span.IndexOf('(') >= 0 && AssemblyPreprocessor.HasFunctionCall(sourceLine.Span))
            {
                return AssemblyPreprocessor.Parse([source], options ?? DefaultPreprocessingOptions(), cancellationToken);
            }

            if (error is not null)
            {
                // The preprocessor reparses the whole document, so nothing before this line is lost.
                if (!unsupported.IsEmpty && AssemblyPreprocessor.IsExpansion(unsupported))
                {
                    return AssemblyPreprocessor.Parse([source], options ?? DefaultPreprocessingOptions(), cancellationToken);
                }

                // Each line is independent, so keep checking and report every invalid line.
                (diagnostics ??= []).Add(new(error, new(source.Path, line)));
                continue;
            }

            if (node is null) { continue; }
            node.Location = new(source.Path, line);
            project.Statements.Add(node);
        }

        return new(project, diagnostics?.ToArray() ?? []);
    }

    /// <summary>
    ///  Parses one native line, shared by direct parsing and the preprocessor's expanded output.
    /// </summary>
    /// <param name="sourceLine">The physical or expanded line, including any comment.</param>
    /// <param name="line">The line index used by operand diagnostics.</param>
    /// <param name="unsupported">The unrecognized directive, or empty.</param>
    /// <param name="error">The diagnostic message, or null when the line is valid.</param>
    /// <returns>The statement, or null for a blank, comment-only or invalid line.</returns>
    internal static AssemblyStatement? ParseLine(
        ReadOnlyMemory<char> sourceLine,
        int line,
        out ReadOnlySpan<char> unsupported,
        out string? error)
    {
        unsupported = default;
        error = null;

        // The statement keeps ranges of the line, so parsing allocates no operation or operand strings.
        ReadOnlyMemory<char> text = sourceLine[..AssemblySyntax.WithoutComment(sourceLine.Span).Length].Trim();
        if (text.Length == 0) { return null; }
        string? label = null;
        ReadOnlyMemory<char> operation;
        ReadOnlyMemory<char> operand;
        int identifierLength = AssemblySyntax.IdentifierLength(text.Span);
        ReadOnlyMemory<char> suffix = text[identifierLength..].TrimStart();
        if (identifierLength != 0 && !suffix.IsEmpty && suffix.Span[0] == '=' && !suffix[1..].Span.Trim().IsEmpty)
        {
            // Constants lower to the same typed statement kind as caller-constructed .EQU nodes.
            label = text[..identifierLength].ToString();
            operation = ".EQU".AsMemory();
            operand = suffix[1..].Trim();
        }
        else if (identifierLength != 0
            && suffix.Length > 4
            && suffix.Span[..4].Equals(".SET", StringComparison.OrdinalIgnoreCase)
            && char.IsWhiteSpace(suffix.Span[4]))
        {
            label = text[..identifierLength].ToString();
            operation = ".SET".AsMemory();
            operand = suffix[4..].Trim();
        }
        else
        {
            ReadOnlySpan<char> span = text.Span;
            if (span[0] == ':' && (span.Length == 1 || span[1] != ':'))
            {
                label = ":";
                text = text[1..].TrimStart();
            }
            else if (identifierLength != 0 && identifierLength < span.Length && span[identifierLength] == ':')
            {
                label = text[..identifierLength].ToString();
                text = suffix[1..].Trim();
            }

            span = text.Span;
            int start = !span.IsEmpty && span[0] == '.' ? 1 : 0;
            int end = start;
            while (end < span.Length && AssemblySyntax.IsWord(span[end])) { end++; }
            if (start == 0 && end != 0 && AssemblySyntax.WideSuffixLength(span[end..]) is int wide and > 0)
            {
                // An instruction's .w suffix forces absolute addressing and stays part of the operation.
                end += wide;
            }

            if ((!span.IsEmpty && end == start) || (end < span.Length && !char.IsWhiteSpace(span[end])))
            {
                error = "Invalid assembly statement.";
                return null;
            }

            operation = text[..end];
            operand = text[end..].Trim();
        }

        if (label is not null && label != ":" && !AssemblySyntax.IsDefinitionIdentifier(label))
        {
            error = "Symbol definitions must be unqualified.";
            return null;
        }

        if (!TryGetStatementKind(operation.Span, out AssemblyStatementKind? kind))
        {
            unsupported = operation.Span;
            error = $"Unsupported directive '{operation}'.";
            return null;
        }

        if (kind == AssemblyStatementKind.Variable && label is null)
        {
            try
            {
                AssemblyOperands parts = new(operand, line);
                parts.MoveNext();
                if (!AssemblySyntax.IsDefinitionIdentifier(parts.Current.Span))
                {
                    throw new AssemblyError(line, ".set requires a name and expression.");
                }

                label = parts.Current.ToString();
                if (!parts.MoveNext()) { throw new AssemblyError(line, ".set requires a name and expression."); }
                operand = parts.Current;
                if (parts.MoveNext()) { throw new AssemblyError(line, ".set requires a name and expression."); }
            }
            catch (AssemblyError failure)
            {
                error = failure.Message;
                return null;
            }
        }

        return new(kind.Value, operation, new AssemblyOperand(operand), label);
    }

    /// <summary>
    ///  Supplies expansion limits when a caller parses without assembly options.
    /// </summary>
    /// <returns>Default options for the full address space.</returns>
    private static AssemblyOptions DefaultPreprocessingOptions() =>
        new(Cpu.M6502.ProcessorVariant.Mos6502, origin: 0, imageSize: InstructionEncoding.AddressSpaceSize);

    /// <summary>
    ///  Assembles source through parsing and the shared model compiler.
    /// </summary>
    /// <param name="source">The source document.</param>
    /// <param name="options">The CPU/image options.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>The immutable output or diagnostics.</returns>
    public AssemblyResult Assemble(AssemblySource source, AssemblyOptions options, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(options);
        AssemblyParseResult parsed = Parse(source, options, cancellationToken);
        return parsed.Success ? Assemble(parsed.Project, options, cancellationToken) : new([.. parsed.Diagnostics]);
    }

    /// <summary>
    ///  Assembles several root sources as one ordered stream.
    /// </summary>
    /// <param name="sources">The root documents.</param>
    /// <param name="options">CPU, image and preprocessing settings.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>The compiled image or source diagnostics.</returns>
    public AssemblyResult Assemble(
        IEnumerable<AssemblySource> sources,
        AssemblyOptions options,
        CancellationToken cancellationToken = default)
    {
        AssemblyParseResult parsed = Parse(sources, options, cancellationToken);
        return parsed.Success ? Assemble(parsed.Project, options, cancellationToken) : new([.. parsed.Diagnostics]);
    }

    /// <summary>
    ///  Assembles an editable model without retaining or modifying its pass state.
    /// </summary>
    /// <param name="project">The ordered statements.</param>
    /// <param name="options">The CPU/image options.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>The immutable output or model diagnostics.</returns>
    public AssemblyResult Assemble(AssemblyProject project, AssemblyOptions options, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(project);
        ArgumentNullException.ThrowIfNull(options);
        cancellationToken.ThrowIfCancellationRequested();
        List<AssemblyDiagnostic> diagnostics = [];
        bool link = options.Dialect == AssemblyDialect.Ca65 || options.LinkerConfiguration is not null;
        for (int index = 0; index < project.Statements.Count; index++)
        {
            AssemblyStatement node = project.Statements[index];
            if (node is null)
            {
                throw new ArgumentException("A project cannot contain null statements.", nameof(project));
            }

            if (node.Dialect == AssemblyDialect.Ca65) { link = true; }

            if (node.Operand is null)
            {
                throw new ArgumentException("Statement operation and operand are required.", nameof(project));
            }

            if (!TryGetStatementKind(node.OperationMemory.Span, out AssemblyStatementKind? kind) || kind != node.Kind)
            {
                diagnostics.Add(new("Statement kind does not match its operation.", node.Location, index));
            }

            if (node.Label is { } name && name != ":" && !AssemblySyntax.IsDefinitionIdentifier(name))
            {
                diagnostics.Add(new("Invalid symbol name.", node.Location, index));
            }

            if (node.WidthPolicy is { } policy && !Enum.IsDefined(policy))
            {
                diagnostics.Add(new("Invalid address-width policy.", node.Location, index));
            }

            if (node.Dialect is not (AssemblyDialect.Native or AssemblyDialect.Ca65 or AssemblyDialect.Merlin or AssemblyDialect.Macro10))
            {
                diagnostics.Add(new("Invalid source dialect.", node.Location, index));
            }
        }

        if (diagnostics.Count != 0) { return new([.. diagnostics]); }
        List<AssemblyError> errors = [];
        AssemblyImage? image = null;
        try
        {
            AssemblyLinker? linker = null;
            AssemblyProject input = project.MerlinOutput is not null ? MerlinFiles.Prepare(project) : project;
            if (link) { linker = AssemblyLinker.Create(input, options, out input); }
            image = AssemblyCompiler.Assemble(input, options, _sets, errors, cancellationToken);
            if (image is not null && linker is not null)
            {
                linker.Emit(image);
                image.Project = project;
            }
            else if (image is not null && project.MerlinOutput is { } output)
            {
                MerlinFiles.Emit(image, output);
                image.Project = project;
            }
        }
        catch (AssemblyError error)
        {
            errors.Add(error);
        }

        if (image is not null && errors.Count == 0) { return new(image); }

        // Phases report in their own order; a stable sort presents diagnostics in statement order.
        foreach (AssemblyError error in errors.OrderBy(error => error.Line))
        {
            // Model indices remain unambiguous when different sources reuse the same physical line number.
            int index = error.Line >= 0 && error.Line < project.Statements.Count ? error.Line : -1;
            AssemblyLocation? location = index >= 0 ? project.Statements[index].Location : null;
            diagnostics.Add(new(error.Message, location, index));
        }

        return new([.. diagnostics]);
    }

    /// <summary>
    ///  Classifies operation syntax without normalization or checking the selected CPU's instruction set.
    /// </summary>
    /// <param name="operation">The mnemonic or directive in any case, or empty text for a label-only node.</param>
    /// <param name="kind">The syntax category on success, or null for an unsupported directive.</param>
    /// <returns>Whether the operation has a supported syntax category.</returns>
    private static bool TryGetStatementKind(
        ReadOnlySpan<char> operation,
        [NotNullWhen(returnValue: true)] out AssemblyStatementKind? kind)
    {
        if (operation.IsEmpty)
        {
            kind = AssemblyStatementKind.Label;
        }
        else if (operation[0] != '.')
        {
            kind = AssemblyStatementKind.Instruction;
        }
        else
        {
            // Length dispatch limits directive comparisons; instruction classification never compares text.
            kind = operation.Length switch
            {
                4 when operation.Equals(".EQU", StringComparison.OrdinalIgnoreCase) => AssemblyStatementKind.Constant,
                4 when operation.Equals(".RES", StringComparison.OrdinalIgnoreCase) => AssemblyStatementKind.Reserve,
                4 when operation.Equals(".ORG", StringComparison.OrdinalIgnoreCase) => AssemblyStatementKind.Origin,
                4 when operation.Equals(".CPU", StringComparison.OrdinalIgnoreCase) => AssemblyStatementKind.Cpu,
                4 when operation.Equals(".SET", StringComparison.OrdinalIgnoreCase) => AssemblyStatementKind.Variable,
                4 when operation.Equals(".DUM", StringComparison.OrdinalIgnoreCase) => AssemblyStatementKind.DummyStart,
                5 when operation.Equals(".BYTE", StringComparison.OrdinalIgnoreCase)
                    || operation.Equals(".WORD", StringComparison.OrdinalIgnoreCase)
                    || operation.Equals(".DBYT", StringComparison.OrdinalIgnoreCase) => AssemblyStatementKind.Data,
                5 when operation.Equals(".DEND", StringComparison.OrdinalIgnoreCase) => AssemblyStatementKind.DummyEnd,
                5 when operation.Equals(".PROC", StringComparison.OrdinalIgnoreCase) => AssemblyStatementKind.Procedure,
                6 when operation.Equals(".DWORD", StringComparison.OrdinalIgnoreCase) => AssemblyStatementKind.Data,
                6 when operation.Equals(".ALIGN", StringComparison.OrdinalIgnoreCase) => AssemblyStatementKind.Align,
                6 when operation.Equals(".SCOPE", StringComparison.OrdinalIgnoreCase) => AssemblyStatementKind.Scope,
                7 when operation.Equals(".ASSERT", StringComparison.OrdinalIgnoreCase) => AssemblyStatementKind.Assertion,
                8 when operation.Equals(".FARADDR", StringComparison.OrdinalIgnoreCase) => AssemblyStatementKind.Data,
                7 when operation.Equals(".EXPORT", StringComparison.OrdinalIgnoreCase)
                    || operation.Equals(".GLOBAL", StringComparison.OrdinalIgnoreCase) => AssemblyStatementKind.Export,
                8 when operation.Equals(".HIASCII", StringComparison.OrdinalIgnoreCase) => AssemblyStatementKind.Data,
                8 when operation.Equals(".SECTION", StringComparison.OrdinalIgnoreCase) => AssemblyStatementKind.Section,
                8 when operation.Equals(".ENDPROC", StringComparison.OrdinalIgnoreCase) => AssemblyStatementKind.EndProcedure,
                9 when operation.Equals(".ENDSCOPE", StringComparison.OrdinalIgnoreCase) => AssemblyStatementKind.EndScope,
                9 when operation.Equals(".CHECKSUM", StringComparison.OrdinalIgnoreCase) => AssemblyStatementKind.Checksum,
                11 when operation.Equals(".LOGICALORG", StringComparison.OrdinalIgnoreCase) => AssemblyStatementKind.LogicalOrigin,
                _ => null
            };
        }

        return kind.HasValue;
    }
}
