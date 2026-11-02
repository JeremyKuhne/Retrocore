// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;

namespace Retrocore.Assembler;

/// <summary>
///  One assembly source statement and its stabilized layout.
/// </summary>
/// <remarks>
///  <para>
///   These records are private to a compilation and are updated in place during convergence. Keeping layout
///   out of the editable source model makes repeated assembly and old result snapshots independent.
///  </para>
///  <para>
///   The runtime auto-lays out this struct because it holds references: references and primitives are packed
///   first, then struct-typed fields follow in declaration order. Optional values are exposed as nullable
///   properties but stored as plain fields sharing one <see cref="LayoutValues"/> byte, so the small fields
///   and the encoding ID fill the space before <see cref="EncodingOperand"/> without per-value padding.
///  </para>
/// </remarks>
internal partial struct LayoutStatement
{
    private LayoutValues _values;
    private long _literalValue;

    // Declared before the auto-property backing fields so it follows the primitives rather than the 16-byte slice.
    private ushort _encoding;

    /// <summary>
    ///  Creates a source statement.
    /// </summary>
    /// <param name="line">The input-model statement index used to locate diagnostics.</param>
    /// <param name="label">An optional label or constant name.</param>
    /// <param name="kind">The layout behavior classified from the statement kind.</param>
    /// <param name="operand">The operand text.</param>
    internal LayoutStatement(int line, string? label, LayoutOperation kind, ReadOnlyMemory<char> operand)
    {
        Line = line;
        Label = label;
        Kind = kind;
        Mnemonic = InstructionSet.UnknownMnemonic;
        Form = OperandFormMatcher.NoForm;
        EncodingOperand = kind == LayoutOperation.Instruction
            ? AssemblySyntax.Compact(operand) : operand;
    }

    /// <summary>
    ///  Gets the input-model statement index, not a physical source line number.
    /// </summary>
    internal int Line { get; }

    /// <summary>
    ///  Gets the label or constant name.
    /// </summary>
    internal string? Label { get; }

    /// <summary>
    ///  Gets the layout behavior that passes dispatch on instead of comparing operation text.
    /// </summary>
    internal LayoutOperation Kind { get; }

    /// <summary>
    ///  Gets or sets the instruction's dense ID in the selected CPU's instruction set, resolved once the CPU is known.
    /// </summary>
    internal int Mnemonic { get; set; }

    /// <summary>
    ///  Gets or sets the operand form classified once from operand syntax: the wide form for an address that has
    ///  a narrow alternative, or <see cref="OperandFormMatcher.NoForm"/> when no form fits.
    /// </summary>
    internal ushort Form { get; set; }

    /// <summary>
    ///  Gets or sets whether <see cref="Form"/> has a narrow (zero-page) alternative,
    ///  <see cref="OperandForm.Narrow"/>, that the operand's value may select; false when operand syntax fixes
    ///  the form.
    /// </summary>
    internal bool HasNarrowForm
    {
        readonly get => (_values & LayoutValues.NarrowForm) != 0;
        set => _values = value ? _values | LayoutValues.NarrowForm : _values & ~LayoutValues.NarrowForm;
    }

    /// <summary>
    ///  Gets or sets whether <c>a:</c>, <c>!</c> or a <c>.w</c> suffix requires the absolute addressing form.
    /// </summary>
    internal bool ForcesAbsolute
    {
        readonly get => (_values & LayoutValues.ForcesAbsolute) != 0;
        set => _values = value ? _values | LayoutValues.ForcesAbsolute : _values & ~LayoutValues.ForcesAbsolute;
    }

    /// <summary>
    ///  Gets or sets the resolved encoding's ID in the statement's instruction set, or null for a
    ///  non-instruction statement.
    /// </summary>
    internal int? Encoding
    {
        readonly get => (_values & LayoutValues.Encoding) != 0 ? _encoding : null;
        set
        {
            _encoding = checked((ushort)value.GetValueOrDefault());
            _values = value.HasValue ? _values | LayoutValues.Encoding : _values & ~LayoutValues.Encoding;
        }
    }

    /// <summary>
    ///  Gets or sets where the recorded layout expression starts in <see cref="AssemblySymbols.Programs"/>.
    /// </summary>
    internal int ProgramStart { get; set; }

    /// <summary>
    ///  Gets or sets the recorded layout expression's step count, or zero before interpretation shows it reads
    ///  a symbol or the location counter.
    /// </summary>
    internal int ProgramLength { get; set; }

    /// <summary>
    ///  Gets or sets a layout value fixed by the statement's text: a literal layout expression's value, or a
    ///  data directive's byte count.
    /// </summary>
    internal long? LiteralValue
    {
        readonly get => (_values & LayoutValues.LiteralValue) != 0 ? _literalValue : null;
        set
        {
            _literalValue = value.GetValueOrDefault();
            _values = value.HasValue ? _values | LayoutValues.LiteralValue : _values & ~LayoutValues.LiteralValue;
        }
    }

    /// <summary>
    ///  Gets or sets once-compacted encoding syntax, without any width prefix, retaining the original operand
    ///  in the caller's project for source mappings.
    /// </summary>
    internal ReadOnlyMemory<char> EncodingOperand { get; set; }

    /// <summary>
    ///  Gets or sets the immutable original location.
    /// </summary>
    internal AssemblyLocation? Location { get; set; }

    /// <summary>
    ///  Gets or sets the laid-out address.
    /// </summary>
    internal int Address { get; set; }

    /// <summary>
    ///  Gets or sets the emitted size.
    /// </summary>
    internal int Size { get; set; }

    /// <summary>
    ///  Gets or sets the section-relative output offset, independent of the logical address.
    /// </summary>
    internal int Offset { get; set; }

    /// <summary>
    ///  Gets or sets the section index.
    /// </summary>
    internal int Section { get; set; }

    /// <summary>
    ///  Gets or sets the index in a compilation's optional table of CPU settings.
    /// </summary>
    internal byte CpuIndex { get; set; }

    /// <summary>
    ///  Gets or sets whether this statement belongs to a dummy region rather than BSS.
    /// </summary>
    internal bool IsDummy
    {
        readonly get => (_values & LayoutValues.IsDummy) != 0;
        set => _values = value ? _values | LayoutValues.IsDummy : _values & ~LayoutValues.IsDummy;
    }

    /// <summary>
    ///  Gets or sets whether z: requires a zero-page form.
    /// </summary>
    internal bool ForcesZeroPage
    {
        readonly get => (_values & LayoutValues.ForcesZeroPage) != 0;
        set => _values = value ? _values | LayoutValues.ForcesZeroPage : _values & ~LayoutValues.ForcesZeroPage;
    }

    /// <summary>
    ///  Gets or sets whether the first layout fixes address width.
    /// </summary>
    internal bool SourceOrder
    {
        readonly get => (_values & LayoutValues.SourceOrder) != 0;
        set => _values = value ? _values | LayoutValues.SourceOrder : _values & ~LayoutValues.SourceOrder;
    }

    /// <summary>
    ///  Gets or sets whether bytes are validated but not emitted.
    /// </summary>
    internal bool NoOutput
    {
        readonly get => (_values & LayoutValues.NoOutput) != 0;
        set => _values = value ? _values | LayoutValues.NoOutput : _values & ~LayoutValues.NoOutput;
    }

}
