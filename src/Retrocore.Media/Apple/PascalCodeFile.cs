// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Media;

/// <summary>
///  An Apple Pascal code file, read-only: the segment dictionary in its first block, then each segment's code. The
///  Apple II's and the Apple III's Pascal share the format.
/// </summary>
/// <remarks>
///  <para>
///   The segment dictionary has 16 slots. For each, its code's block and length (bytes 0-63), its name (64-191, eight
///   characters), its kind (192-223), the block of a unit's interface text (224-255), and its information
///   (256-287): its segment number in the low byte, its machine type in bits 8-11 and the code file's version in
///   bits 13-15. Bytes 288-291 are the set of intrinsic units the program uses.
///  </para>
///  <para>
///   A segment ends with its procedure dictionary. Its last word is the segment number and, in its high byte, the
///   number of procedures; below it, from the end down, a self-relative pointer to each procedure's attributes (or 0
///   for a procedure that is not there). The attributes are the procedure number and lexical level. Below them, for
///   p-code, are self-relative pointers to the entry and the exit code, then the sizes of the parameters and of the
///   local data, then the jump table. An assembled procedure, numbered 0, has its entry pointer and below that its
///   four relocation lists, each a count followed downward by self-relative pointers.
///  </para>
///  <para>
///   A procedure whose pointers lead outside the segment's code is left out: a system segment's stub, such as the
///   <c>PASCALSY</c> segment at the head of Apple III Pascal's Editor, only declares procedures that are elsewhere.
///  </para>
/// </remarks>
public sealed class PascalCodeFile
{
    private const int BlockSize = 512;
    private const int Slots = 16;

    private PascalCodeFile(IReadOnlyList<PascalSegment> segments, uint intrinsics)
    {
        Segments = segments;
        IntrinsicUnits = intrinsics;
    }

    /// <summary>
    ///  Gets the segments the dictionary names, in slot order.
    /// </summary>
    public IReadOnlyList<PascalSegment> Segments { get; }

    /// <summary>
    ///  Gets the set of intrinsic units a program uses, one bit for each segment number from 0 to 31.
    /// </summary>
    public uint IntrinsicUnits { get; }

    /// <summary>
    ///  Reads a code file.
    /// </summary>
    /// <param name="data">The file's contents.</param>
    /// <returns>The code file.</returns>
    /// <exception cref="InvalidDataException">The file is not a code file.</exception>
    public static PascalCodeFile Read(ReadOnlySpan<byte> data)
    {
        if (data.Length < BlockSize)
        {
            throw new InvalidDataException("A code file starts with its 512-byte segment dictionary.");
        }

        List<PascalSegment> segments = [];
        for (int slot = 0; slot < Slots; slot++)
        {
            int block = Word(data, slot * 4);
            int length = Word(data, (slot * 4) + 2);
            string name = Encoding.ASCII.GetString(data.Slice(64 + (slot * 8), 8)).TrimEnd(' ', '\0');
            if (length == 0 && name.Length == 0) { continue; }

            PascalSegmentKind kind = (PascalSegmentKind)Word(data, 192 + (slot * 2));
            int text = Word(data, 224 + (slot * 2));
            int information = Word(data, 256 + (slot * 2));
            byte[] code = [];
            IReadOnlyList<PascalProcedure> procedures = [];
            if (kind != PascalSegmentKind.Data && length != 0 && block != 0)
            {
                long start = (long)block * BlockSize;
                if (start + length > data.Length)
                {
                    throw new InvalidDataException($"Segment {name} runs past the end of the file.");
                }

                code = data.Slice((int)start, length).ToArray();
                procedures = Procedures(code, name);
            }

            segments.Add(new PascalSegment(slot, name, block, length, kind, text, information, code, procedures));
        }

        uint intrinsics = (uint)(Word(data, 288) | (Word(data, 290) << 16));
        return new PascalCodeFile(segments, intrinsics);
    }

    /// <summary>
    ///  Says whether a file starts with a plausible segment dictionary.
    /// </summary>
    /// <param name="data">The file's contents.</param>
    /// <returns>True when every slot's code is inside the file and some slot has code.</returns>
    public static bool IsCodeFile(ReadOnlySpan<byte> data)
    {
        if (data.Length < BlockSize || data.Length % BlockSize != 0) { return false; }

        bool any = false;
        for (int slot = 0; slot < Slots; slot++)
        {
            int block = Word(data, slot * 4);
            int length = Word(data, (slot * 4) + 2);
            if (length == 0 || block == 0) { continue; }
            if (((long)block * BlockSize) + length > data.Length || length < 2) { return false; }
            any = true;
        }

        return any;
    }

    /// <summary>
    ///  Gets the segment with a name, in any case.
    /// </summary>
    /// <param name="name">The name.</param>
    /// <returns>The segment, or null.</returns>
    public PascalSegment? Segment(string name) =>
        Segments.FirstOrDefault(segment => string.Equals(segment.Name, name, StringComparison.OrdinalIgnoreCase));

    private static List<PascalProcedure> Procedures(byte[] code, string name)
    {
        int length = code.Length;
        if (length < 2 || (length & 1) != 0)
        {
            throw new InvalidDataException($"Segment {name} does not end with a procedure dictionary.");
        }

        int count = Math.Min((int)code[length - 1], (length - 2) / 2);
        List<PascalProcedure> procedures = new(count);
        for (int index = 1; index <= count; index++)
        {
            int pointer = length - 2 - (index * 2);
            int offset = Word(code, pointer);
            if (offset != 0 && Procedure(code, index, pointer - offset) is { } procedure) { procedures.Add(procedure); }
        }

        return procedures;
    }

    // A procedure, or null when its pointers lead outside the segment's code, as they do for the procedures a
    // system segment's stub only declares.
    private static PascalProcedure? Procedure(byte[] code, int index, int attributes)
    {
        int dictionary = code.Length - 2 - (code[^1] * 2);
        if (attributes < 2 || attributes >= dictionary) { return null; }

        int number = code[attributes];
        int level = (sbyte)code[attributes + 1];
        int entry = Relative(code, attributes - 2);
        if (number != 0)
        {
            int exit = attributes >= 8 ? Relative(code, attributes - 4) : -1;
            return entry < 0 || exit < entry
                ? null
                : new PascalProcedure(index, number, level, attributes, entry, exit, Word(code, attributes - 6), Word(code, attributes - 8), []);
        }

        IReadOnlyList<int>[] lists = new IReadOnlyList<int>[4];
        int pointer = attributes - 2;
        for (int list = 0; list < lists.Length; list++)
        {
            pointer -= 2;
            if (pointer < 0) { return null; }

            int items = Word(code, pointer);
            List<int> offsets = new(Math.Min(items, pointer / 2));
            for (int item = 0; item < items; item++)
            {
                pointer -= 2;
                int target = Relative(code, pointer);
                if (target < 0) { return null; }
                offsets.Add(target);
            }

            lists[list] = offsets;
        }

        return entry < 0 ? null : new PascalProcedure(index, number, level, attributes, entry, entry, 0, 0, lists);
    }

    // A self-relative pointer: the address it is at less its contents, or -1 when that is outside the code.
    private static int Relative(byte[] code, int pointer)
    {
        if (pointer < 0) { return -1; }

        int target = pointer - Word(code, pointer);
        return target < 0 || target >= code.Length ? -1 : target;
    }

    private static int Word(ReadOnlySpan<byte> data, int offset) => data[offset] | (data[offset + 1] << 8);
}
