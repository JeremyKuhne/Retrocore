// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  A segment of an Apple Pascal code file: its entry in the segment dictionary, and its code and procedures.
/// </summary>
public sealed class PascalSegment
{
    /// <summary>
    ///  Constructs a segment from its dictionary entry and code.
    /// </summary>
    /// <param name="slot">Its place in the dictionary.</param>
    /// <param name="name">Its name.</param>
    /// <param name="block">Its code's block.</param>
    /// <param name="length">Its length.</param>
    /// <param name="kind">Its kind.</param>
    /// <param name="textBlock">Its interface text's block.</param>
    /// <param name="information">Its information word: number, machine type and version.</param>
    /// <param name="code">Its code.</param>
    /// <param name="procedures">Its procedures.</param>
    internal PascalSegment(
        int slot,
        string name,
        int block,
        int length,
        PascalSegmentKind kind,
        int textBlock,
        int information,
        byte[] code,
        IReadOnlyList<PascalProcedure> procedures)
    {
        Slot = slot;
        Name = name;
        Block = block;
        Length = length;
        Kind = kind;
        TextBlock = textBlock;
        Number = information & 0xFF;
        MachineType = (PascalMachineType)((information >> 8) & 0xF);
        Version = (information >> 13) & 7;
        Code = code;
        Procedures = procedures;
    }

    /// <summary>
    ///  Gets its place in the segment dictionary, 0-15.
    /// </summary>
    public int Slot { get; }

    /// <summary>
    ///  Gets its name, up to eight characters, such as <c>PASCALSY</c>.
    /// </summary>
    public string Name { get; }

    /// <summary>
    ///  Gets the block its code starts at, relative to the file's first block.
    /// </summary>
    public int Block { get; }

    /// <summary>
    ///  Gets its length in bytes: the code's, or for a data segment the size of its variables.
    /// </summary>
    public int Length { get; }

    /// <summary>
    ///  Gets what it is.
    /// </summary>
    public PascalSegmentKind Kind { get; }

    /// <summary>
    ///  Gets the block where a unit's interface text starts, relative to the file, or 0 without one.
    /// </summary>
    public int TextBlock { get; }

    /// <summary>
    ///  Gets its segment number: the number the system loads it by and its calls name it by.
    /// </summary>
    public int Number { get; }

    /// <summary>
    ///  Gets the code it holds.
    /// </summary>
    public PascalMachineType MachineType { get; }

    /// <summary>
    ///  Gets the code file version: 2 for Apple Pascal 1.1 (UCSD II.1), 4 for Apple III Pascal 1.1 and 6 for its 1.2.
    /// </summary>
    public int Version { get; }

    /// <summary>
    ///  Gets its code, ending with its procedure dictionary; empty for a data segment.
    /// </summary>
    public byte[] Code { get; }

    /// <summary>
    ///  Gets its procedures, in procedure dictionary order; those the dictionary leaves out, or whose code is not in the
    ///  segment, are missing.
    /// </summary>
    public IReadOnlyList<PascalProcedure> Procedures { get; }

    /// <summary>
    ///  Gets the procedure the dictionary gives an index, from 1.
    /// </summary>
    /// <param name="index">The index.</param>
    /// <returns>The procedure, or null when the segment has none at that index.</returns>
    public PascalProcedure? Procedure(int index) => Procedures.FirstOrDefault(procedure => procedure.Index == index);

    /// <inheritdoc/>
    public override string ToString() => $"{Name} ({Number}, {Kind}, {MachineType})";
}
