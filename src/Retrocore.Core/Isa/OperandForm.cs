// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Isa;

/// <summary>
///  An operand form: the native syntax an operand takes, and the fields its encoding carries.
/// </summary>
/// <remarks>
///  <para>
///   A pattern is literal text with <c>{}</c> where an expression goes, such as <c>#{}</c>, <c>({}),Y</c> or
///   <c>[IX{}],{}</c>; the empty pattern matches no operand. Each hole holds the next field, except that a
///   pattern with one hole and a form with several fields takes them as a comma-separated list. Forms that
///   share a pattern are alternatives, chosen by what the mnemonic has, or, for a narrow form
///   (<see cref="NarrowOf"/>), by whether the value fits.
///  </para>
/// </remarks>
public sealed class OperandForm
{
    private readonly OperandFieldKind[] _fields;
    private readonly int[] _offsets;

    /// <summary>
    ///  Creates a form.
    /// </summary>
    /// <param name="id">The dense ID, its position in the description.</param>
    /// <param name="name">The name, such as <c>ZeroPage</c>.</param>
    /// <param name="patterns">The operand patterns that select it.</param>
    /// <param name="fields">The encoded fields, in order.</param>
    public OperandForm(ushort id, string name, IReadOnlyList<string> patterns, IReadOnlyList<OperandFieldKind> fields)
    {
        Id = id;
        Name = name;
        Patterns = patterns;
        Fields = fields;
        _fields = [.. fields];
        _offsets = new int[_fields.Length];
        int size = 0;
        for (int index = 0; index < _fields.Length; index++)
        {
            _offsets[index] = size;
            size += FieldSize(_fields[index]);
            if (RelativeField < 0 && _fields[index] is OperandFieldKind.Relative8 or OperandFieldKind.Relative16)
            {
                RelativeField = index;
            }

            if (OpcodeField < 0 && IsOpcodeField(_fields[index])) { OpcodeField = index; }
        }

        Size = size;

        // Where the canonical (first) pattern's holes are, so formatting never searches for them.
        List<int> holes = [];
        string canonical = patterns.Count == 0 ? "" : patterns[0];
        int hole = canonical.IndexOf("{}", StringComparison.Ordinal);
        while (hole >= 0)
        {
            holes.Add(hole);
            hole = canonical.IndexOf("{}", hole + 2, StringComparison.Ordinal);
        }

        _holes = [.. holes];
    }

    private readonly int[] _holes;

    /// <summary>
    ///  Gets where each hole of the first pattern, the canonical syntax, starts.
    /// </summary>
    public ReadOnlySpan<int> CanonicalHoles => _holes;

    /// <summary>
    ///  Gets the dense ID.
    /// </summary>
    public ushort Id { get; }

    /// <summary>
    ///  Gets the name.
    /// </summary>
    public string Name { get; }

    /// <summary>
    ///  Gets the operand patterns that select the form.
    /// </summary>
    public IReadOnlyList<string> Patterns { get; }

    /// <summary>
    ///  Gets the encoded fields, in order.
    /// </summary>
    public IReadOnlyList<OperandFieldKind> Fields { get; }

    /// <summary>
    ///  Gets the number of fields.
    /// </summary>
    public int FieldCount => _fields.Length;

    /// <summary>
    ///  Gets the index of the first relative field, or -1 when there is none.
    /// </summary>
    public int RelativeField { get; } = -1;

    /// <summary>
    ///  Gets a field's kind without an interface call.
    /// </summary>
    /// <param name="index">The field index.</param>
    /// <returns>The kind.</returns>
    public OperandFieldKind Field(int index) => _fields[index];

    /// <summary>
    ///  Gets where a field starts among the operand bytes after the opcode.
    /// </summary>
    /// <param name="index">The field index.</param>
    /// <returns>The byte offset.</returns>
    public int FieldOffset(int index) => _offsets[index];

    /// <summary>
    ///  Gets the operand size in bytes, after the opcode.
    /// </summary>
    public int Size { get; }

    /// <summary>
    ///  Gets whether a mnemonic that has this form takes it for any operand, as relative branches do.
    /// </summary>
    public bool Exclusive { get; init; }

    /// <summary>
    ///  Gets the ID of the wider form this one is a narrow alternative of, such as zero page for absolute; -1
    ///  when it is not one.
    /// </summary>
    public int NarrowOf { get; init; } = -1;

    /// <summary>
    ///  Gets the ID of this form's narrow alternative; -1 when it has none.
    /// </summary>
    public int Narrow { get; internal set; } = -1;

    /// <summary>
    ///  Gets what the first field means: an address the instruction accesses, or a pointer's address.
    /// </summary>
    public OperandRole Role { get; init; }

    /// <summary>
    ///  Gets whether an index register is added to the first field's address.
    /// </summary>
    public bool IsIndexed { get; init; }

    /// <summary>
    ///  Gets the diagnostic for an operand with the wrong number of fields, for a form with several.
    /// </summary>
    public string? FieldMessage { get; init; }

    /// <summary>
    ///  Gets whether the form takes a narrow address, such as a zero-page one, alone or as the narrow
    ///  alternative of a wider form.
    /// </summary>
    public bool IsNarrow { get; init; }

    /// <summary>
    ///  Gets the number of bytes a field encodes as.
    /// </summary>
    /// <param name="field">The field.</param>
    /// <returns>Its size.</returns>
    public static int FieldSize(OperandFieldKind field) => field switch
    {
        OperandFieldKind.Word or OperandFieldKind.Relative16 => 2,
        OperandFieldKind.BitNumber or OperandFieldKind.Restart => 0,
        _ => 1
    };

    /// <summary>
    ///  Gets whether a field is held in the opcode's bits rather than in operand bytes.
    /// </summary>
    /// <param name="field">The field.</param>
    /// <returns>Whether it is.</returns>
    public static bool IsOpcodeField(OperandFieldKind field) => field is OperandFieldKind.BitNumber or OperandFieldKind.Restart;

    /// <summary>
    ///  Gets the index of the field held in the opcode's bits, or -1 when there is none.
    /// </summary>
    public int OpcodeField { get; private init; } = -1;

    /// <summary>
    ///  Counts the expression holes in a pattern.
    /// </summary>
    /// <param name="pattern">The pattern.</param>
    /// <returns>The number of <c>{}</c>.</returns>
    public static int HoleCount(string pattern)
    {
        int count = 0;
        int index = pattern.IndexOf("{}", StringComparison.Ordinal);
        while (index >= 0)
        {
            count++;
            index = pattern.IndexOf("{}", index + 2, StringComparison.Ordinal);
        }

        return count;
    }

    /// <summary>
    ///  Gets whether a pattern is literal text with no expression.
    /// </summary>
    /// <param name="pattern">The pattern.</param>
    /// <returns>Whether it has no <c>{}</c>.</returns>
    public static bool IsLiteral(string pattern) => pattern.IndexOf("{}", StringComparison.Ordinal) < 0;

    /// <inheritdoc/>
    public override string ToString() => Name;
}
