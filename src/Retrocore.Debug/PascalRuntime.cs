// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;
using Retrocore.Pascal;

namespace Retrocore.Debug;

/// <summary>
///  Apple Pascal on a machine: finds the p-machine's interpreter in memory, notes its registers at each fetch, and
///  names the segments it runs from the code files on the disks in the drives.
/// </summary>
/// <remarks>
///  <para>
///   Nothing about Pascal is assumed until the interpreter's fetch is found, so a machine that never runs Pascal
///   pays only for an occasional look for it.
///  </para>
/// </remarks>
internal sealed class PascalRuntime
{
    private readonly Func<ushort, byte> _peek;
    private readonly (int Start, int End) _range;
    private readonly bool _extended;
    private readonly Func<ushort> _zeroPage;
    private readonly Func<IEnumerable<WozDisk>> _disks;
    private readonly PascalCodeLibrary _library = new();
    private readonly Dictionary<(ushort, byte, ulong), (string File, PascalSegment Segment)?> _names = [];

    // The disks the library was read from, each with its version, to read them again once one changes.
    private List<(WozDisk Disk, long Version)>? _libraryDisks;

    /// <summary>
    ///  Constructs one.
    /// </summary>
    /// <param name="name">The interpreter's name, such as <c>Apple III Pascal</c>.</param>
    /// <param name="memory">The memory the interpreter sees.</param>
    /// <param name="peek">Reads the memory the CPU sees.</param>
    /// <param name="range">Where to look for the interpreter.</param>
    /// <param name="extended">Whether its pointers have X-bytes.</param>
    /// <param name="zeroPage">Gets where zero page is now.</param>
    /// <param name="disks">Gets the disks in the drives.</param>
    internal PascalRuntime(
        string name,
        IPascalMemory memory,
        Func<ushort, byte> peek,
        (int Start, int End) range,
        bool extended,
        Func<ushort> zeroPage,
        Func<IEnumerable<WozDisk>> disks)
    {
        Name = name;
        Memory = memory;
        _peek = peek;
        _range = range;
        _extended = extended;
        _zeroPage = zeroPage;
        _disks = disks;
    }

    /// <summary>
    ///  Gets what the interpreter is, such as <c>Apple III Pascal</c>.
    /// </summary>
    internal string Name { get; }

    /// <summary>
    ///  Gets the memory the interpreter sees.
    /// </summary>
    internal IPascalMemory Memory { get; }

    /// <summary>
    ///  Gets the interpreter, once found.
    /// </summary>
    internal PascalInterpreter? Interpreter { get; private set; }

    /// <summary>
    ///  Gets the registers at the last fetch, which name the p-code running.
    /// </summary>
    internal PascalRegisters? Registers { get; private set; }

    /// <summary>
    ///  Looks for the interpreter's fetch, if it has not been found where it still is.
    /// </summary>
    /// <returns>Whether the interpreter is known.</returns>
    internal bool Scan()
    {
        if (Interpreter is { } known && PascalInterpreter.IsFetch(_peek, known.Fetch)) { return true; }
        if (PascalInterpreter.FindFetch(_peek, _range.Start, _range.End) is { } fetch)
        {
            Interpreter = new PascalInterpreter(Name, fetch, 0, _extended);
            Registers = null;
        }

        return Interpreter is not null;
    }

    /// <summary>
    ///  Says whether an instruction is the interpreter's fetch of the next p-code.
    /// </summary>
    /// <param name="pc">The instruction's address.</param>
    /// <returns>True at the fetch.</returns>
    internal bool AtFetch(ushort pc) =>
        Interpreter is { } interpreter && pc == interpreter.Fetch && _peek(pc) == 0xB1 && _peek((ushort)(pc + 1)) == 0x58;

    /// <summary>
    ///  Notes the registers at a fetch, with zero page where the interpreter keeps it.
    /// </summary>
    /// <returns>The procedure about to run a p-code, or null when the registers do not make sense.</returns>
    internal PascalFrame? ObserveFetch()
    {
        if (Interpreter is not { } interpreter) { return null; }
        ushort zeroPage = _zeroPage();
        if (interpreter.ZeroPage != zeroPage) { Interpreter = interpreter = interpreter with { ZeroPage = zeroPage }; }
        PascalRegisters registers = PascalRegisters.Read(Memory, interpreter);
        Registers = registers;
        return PascalMachine.Frame(Memory, registers.Segment, registers.JumpTable, registers.Code, registers.Mark);
    }

    /// <summary>
    ///  Reads the procedures running at the last fetch.
    /// </summary>
    /// <returns>The frames, the running procedure first.</returns>
    internal IReadOnlyList<PascalFrame> Frames() =>
        Interpreter is { } interpreter && Registers is { } registers ? PascalMachine.Frames(Memory, interpreter, registers) : [];

    /// <summary>
    ///  Finds the code file segment a frame's procedure belongs to, from the code files on the disks in the drives,
    ///  which it reads again when a disk has changed.
    /// </summary>
    /// <param name="frame">The frame.</param>
    /// <returns>The file and segment, or null when no disk has it.</returns>
    internal (string File, PascalSegment Segment)? Segment(PascalFrame frame)
    {
        // A segment is known by where it is and how it ends, as another can be loaded in the same place later.
        ulong tail = 0;
        for (int index = 0; index < 8; index++)
        {
            tail = (tail << 8) | Memory.Read((ushort)(frame.Segment.Address + 1 - index), frame.Segment.Bank);
        }

        (ushort, byte, ulong) key = (frame.Segment.Address, frame.Segment.Bank, tail);
        if (_names.TryGetValue(key, out (string, PascalSegment)? known) && (known is not null || !DisksChanged()))
        {
            return known;
        }

        if (DisksChanged()) { ReadLibrary(); }
        (string File, PascalSegment Segment)? found = _library.Find(Memory, frame.Segment);
        _names[key] = found;
        return found;
    }

    /// <summary>
    ///  Forgets the segments found, so the next look checks the disks again: the system may have loaded others.
    /// </summary>
    internal void Forget() => _names.Clear();

    /// <summary>
    ///  Names a frame's procedure, such as <c>HELLO.2</c>, or by number, <c>1.2</c>, when no code file has its segment.
    /// </summary>
    /// <param name="frame">The frame.</param>
    /// <returns>The name.</returns>
    internal string Describe(PascalFrame frame) =>
        $"{(Segment(frame) is { } found ? found.Segment.Name : frame.SegmentNumber.ToString(System.Globalization.CultureInfo.InvariantCulture))}.{frame.Procedure}";

    /// <summary>
    ///  Decodes the p-code at a frame's IPC.
    /// </summary>
    /// <param name="frame">The frame.</param>
    /// <returns>The instruction, or null when it does not decode.</returns>
    internal PcodeInstruction? Instruction(PascalFrame frame)
    {
        int length = frame.JumpTable.Address + 2 - frame.Entry.Address;
        if (length is <= 0 or > 0x4000) { return null; }

        byte[] code = new byte[length];
        for (int index = 0; index < length; index++)
        {
            code[index] = Memory.Read((ushort)(frame.Entry.Address + index), frame.Entry.Bank);
        }

        // Word alignment counts from the segment's start, which is on a word boundary.
        int skew = frame.Entry.Address & 1;
        try
        {
            byte[] aligned = skew == 0 ? code : [0, .. code];
            PcodeInstruction instruction = PcodeDisassembler.Decode(aligned, frame.Offset + skew, frame.JumpTable.Address - frame.Entry.Address + skew);
            return instruction with
            {
                Offset = instruction.Offset - skew, Targets = [.. instruction.Targets.Select(target => target < 0 ? target : target - skew)]
            };
        }
        catch (InvalidDataException)
        {
            return null;
        }
    }

    // Whether a disk has gone in, come out or been written since the library was read.
    private bool DisksChanged()
    {
        if (_libraryDisks is not { } read) { return true; }
        int count = 0;
        foreach (WozDisk disk in _disks())
        {
            if (count >= read.Count || read[count].Disk != disk || read[count].Version != disk.Version) { return true; }
            count++;
        }

        return count != read.Count;
    }

    private void ReadLibrary()
    {
        _library.Clear();
        _libraryDisks = [.. _disks().Select(disk => (disk, disk.Version))];
        foreach ((WozDisk disk, _) in _libraryDisks)
        {
            byte[] image;
            try
            {
                image = SectorDiskReader.Read(disk, proDosOrder: false);
            }
            catch (InvalidDataException)
            {
                continue;
            }

            foreach ((string name, byte[] data) in CodeFiles(image))
            {
                try
                {
                    _library.Add(name, PascalCodeFile.Read(data));
                }
                catch (InvalidDataException)
                {
                    // Not a code file after all.
                }
            }
        }
    }

    // The files on a Pascal or SOS volume that might be code files.
    private static IEnumerable<(string Name, byte[] Data)> CodeFiles(byte[] image)
    {
        if (PascalVolume.IsPascalVolume(image, proDosOrder: false))
        {
            PascalVolume volume = PascalVolume.Read(image, proDosOrder: false);
            foreach (PascalFileEntry file in volume.Files.Where(file => file.Kind is PascalFileKind.Code or PascalFileKind.Data))
            {
                byte[] data = volume.ReadFile(file);
                if (PascalCodeFile.IsCodeFile(data)) { yield return ($"{volume.Name}:{file.Name}", data); }
            }

            yield break;
        }

        SosVolume sos;
        try
        {
            sos = SosVolume.Read(image, proDosOrder: false);
        }
        catch (InvalidDataException)
        {
            yield break;
        }

        foreach (SosFileEntry file in sos.Files.Where(file => file.FileType is 0x02 or 0x05 && file.StorageType is >= 1 and <= 3))
        {
            byte[] data = sos.ReadFile(file.Name);
            if (PascalCodeFile.IsCodeFile(data)) { yield return ($"/{sos.Name}/{file.Name}", data); }
        }
    }
}
