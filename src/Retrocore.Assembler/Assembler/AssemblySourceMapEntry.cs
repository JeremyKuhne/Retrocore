// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  A resolved statement's immutable output range.
/// </summary>
public sealed class AssemblySourceMapEntry
{
    // The text stays a range of the source until read, since most entries are never inspected.
    private readonly ReadOnlyMemory<char> _operation;
    private readonly AssemblyOperand _operand;
    private string? _operationText;

    /// <summary>
    ///  Creates an output mapping.
    /// </summary>
    /// <param name="statement">Independent resolved layout state.</param>
    /// <param name="original">Original syntax before operand compaction.</param>
    /// <param name="addressMode">The encoding's operand form name, or empty.</param>
    /// <param name="instructionSet">The CPU the statement was assembled for, or null when none was set.</param>
    internal AssemblySourceMapEntry(
        in LayoutStatement statement,
        AssemblyStatement original,
        string addressMode,
        Retrocore.Isa.InstructionSet? instructionSet)
    {
        InstructionSet = instructionSet;
        Address = statement.Address;
        Size = statement.NoOutput ? 0 : statement.Size;
        OccupiedSize = statement.Size;
        Offset = statement.Offset;
        Section = statement.Section;
        Location = statement.Location;
        _operation = original.OperationMemory;
        _operand = original.Operand;
        Label = original.Label;
        AddressMode = addressMode;
    }

    /// <summary>
    ///  Gets the CPU the statement was assembled for, or null when none was set.
    /// </summary>
    public Retrocore.Isa.InstructionSet? InstructionSet { get; }

    /// <summary>
    ///  Gets the resolved mnemonic or directive.
    /// </summary>
    public string Operation => _operationText ??= Uppercase(_operation);

    /// <summary>
    ///  Gets original operand syntax.
    /// </summary>
    public string Operand => _operand.Text;

    /// <summary>
    ///  Gets the defined label, if any.
    /// </summary>
    public string? Label { get; }

    /// <summary>
    ///  Gets the selected canonical CPU address-mode name.
    /// </summary>
    public string AddressMode { get; }

    /// <summary>
    ///  Gets the resolved address.
    /// </summary>
    public int Address { get; }

    /// <summary>
    ///  Gets the emitted size.
    /// </summary>
    public int Size { get; }

    /// <summary>
    ///  Gets the memory the statement occupies, including reserved space such as BSS that emits no bytes.
    /// </summary>
    internal int OccupiedSize { get; }

    /// <summary>
    ///  Gets the section-relative file offset, independent of the logical CPU address.
    /// </summary>
    public int Offset { get; }

    /// <summary>
    ///  Gets the index into AssemblyResult.Sections.
    /// </summary>
    public int Section { get; }

    /// <summary>
    ///  Gets the original source location.
    /// </summary>
    public AssemblyLocation? Location { get; }

    private static string Uppercase(ReadOnlyMemory<char> operation)
    {
        foreach (char character in operation.Span)
        {
            if (char.IsLower(character) || character > 127)
            {
                return AssemblySyntax.AsString(operation).ToUpperInvariant();
            }
        }

        return AssemblySyntax.AsString(operation);
    }
}
