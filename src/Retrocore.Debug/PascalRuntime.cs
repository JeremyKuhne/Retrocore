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
    private readonly IReadOnlyList<Func<ushort, byte>> _views;
    private readonly (int Start, int End) _range;
    private readonly bool _extended;
    private readonly Func<ushort> _zeroPage;
    private readonly Func<byte>? _codeBank;
    private readonly Func<IEnumerable<WozDisk>> _disks;
    private readonly Func<ulong> _cycles;
    private readonly PascalCodeLibrary _library = new();
    private readonly List<(string File, PascalListing Listing)> _listings = [];

    // When the interpreter's fetch was last seen, and when its bytes were first found missing since.
    private ulong _lastFetch;
    private ulong? _missingSince;

    // The disks the library was read from, each with its version, to read them again once one changes.
    private List<(WozDisk Disk, long Version)>? _libraryDisks;

    /// <summary>
    ///  Constructs one.
    /// </summary>
    /// <param name="name">The interpreter's name, such as <c>Apple III Pascal</c>.</param>
    /// <param name="memory">The memory the interpreter sees.</param>
    /// <param name="peek">Reads the memory the CPU sees.</param>
    /// <param name="views">
    ///  Other ways to read where the interpreter may be, which the CPU sees only while they are switched in, such as
    ///  the language card's two banks at <c>$D000</c>.
    /// </param>
    /// <param name="range">Where to look for the interpreter.</param>
    /// <param name="extended">Whether its pointers have X-bytes.</param>
    /// <param name="zeroPage">Gets where zero page is now.</param>
    /// <param name="disks">Gets the disks in the drives.</param>
    /// <param name="cycles">Gets the machine's cycle count.</param>
    /// <param name="codeBank">
    ///  Gets where code is read from at a fetch, for a machine whose interpreter can keep code apart from data, as
    ///  Apple Pascal 1.3 does in the IIe's auxiliary 64K.
    /// </param>
    internal PascalRuntime(
        string name,
        IPascalMemory memory,
        Func<ushort, byte> peek,
        IReadOnlyList<Func<ushort, byte>> views,
        (int Start, int End) range,
        bool extended,
        Func<ushort> zeroPage,
        Func<IEnumerable<WozDisk>> disks,
        Func<ulong> cycles,
        Func<byte>? codeBank = null)
    {
        Name = name;
        Memory = memory;
        _peek = peek;
        _views = [peek, .. views];
        _range = range;
        _extended = extended;
        _zeroPage = zeroPage;
        _disks = disks;
        _cycles = cycles;
        _codeBank = codeBank;
    }

    /// <summary>
    ///  How long the interpreter's fetch may be missing, with no p-code run, before it counts as gone: a few seconds
    ///  of the machine's time, longer than SOS keeps the interpreter's bank switched out for a disk.
    /// </summary>
    internal const ulong LostCycles = 4_000_000;

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
    ///  Looks for the interpreter's fetch, if it has not been found where it still is, and lets it go once something
    ///  else has replaced it.
    /// </summary>
    /// <returns>Whether the interpreter is known.</returns>
    internal bool Scan()
    {
        if (Interpreter is { } known && _views.Any(view => PascalInterpreter.IsFetch(view, known.Fetch)))
        {
            _missingSince = null;
            return true;
        }

        if (_views.Select(view => PascalInterpreter.FindFetch(view, _range.Start, _range.End)).FirstOrDefault(found => found is not null) is { } fetch)
        {
            if (Interpreter?.Fetch != fetch) { Registers = null; }
            Interpreter = new PascalInterpreter(Name, fetch, Interpreter?.ZeroPage ?? 0, _extended, Interpreter?.CodeBank ?? 0);
            _missingSince = null;
            return true;
        }

        if (Interpreter is null) { return false; }

        // Its bank can be switched out for a while; it is gone only once missing for longer, with no p-code run.
        ulong now = _cycles();
        _missingSince ??= now;
        if (now - _missingSince.Value < LostCycles || now - _lastFetch < LostCycles) { return true; }

        Interpreter = null;
        Registers = null;
        _missingSince = null;
        return false;
    }

    /// <summary>
    ///  Forgets the registers, which a reset makes stale until the next fetch.
    /// </summary>
    internal void Reset() => Registers = null;

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
        byte codeBank = _codeBank?.Invoke() ?? 0;
        if (interpreter.ZeroPage != zeroPage || interpreter.CodeBank != codeBank)
        {
            Interpreter = interpreter = interpreter with { ZeroPage = zeroPage, CodeBank = codeBank };
        }

        PascalRegisters registers = PascalRegisters.Read(Memory, interpreter);
        Registers = registers;
        _lastFetch = _cycles();
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
    ///  which it reads again when a disk has changed. Each look compares the segment's end with every code file's, as
    ///  another segment can be loaded where one was.
    /// </summary>
    /// <param name="frame">The frame.</param>
    /// <returns>The file and segment, or null when no disk has it.</returns>
    internal (string File, PascalSegment Segment)? Segment(PascalFrame frame)
    {
        if (DisksChanged()) { ReadLibrary(); }
        return _library.Find(Memory, frame.Segment);
    }

    /// <summary>
    ///  Finds a segment of the code files on the disks in the drives by its name and number.
    /// </summary>
    /// <param name="name">The segment's name.</param>
    /// <param name="number">Its number.</param>
    /// <returns>The segment, or null.</returns>
    internal PascalSegment? CodeSegment(string name, int number)
    {
        Refresh();
        return _library.Segment(name, number);
    }

    /// <summary>
    ///  Gets a count of the times the disks have been read, which changes when their code files and listings may have.
    /// </summary>
    internal int Generation { get; private set; }

    /// <summary>
    ///  Reads the disks in the drives again if one has changed since they were read.
    /// </summary>
    /// <returns>Whether they were read again.</returns>
    internal bool Refresh()
    {
        if (!DisksChanged()) { return false; }
        ReadLibrary();
        return true;
    }

    /// <summary>
    ///  Gets the compiler listings on the disks in the drives, by file name, such as <c>/PASCAL2/HELLO.LST.TEXT</c>.
    /// </summary>
    internal IReadOnlyList<(string File, PascalListing Listing)> Listings
    {
        get
        {
            Refresh();
            return _listings;
        }
    }

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
                Offset = instruction.Offset - skew,
                Targets = [.. instruction.Targets.Select(target => target < 0 ? target : target - skew)]
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
        Generation++;
        _library.Clear();
        _listings.Clear();
        _libraryDisks = [.. _disks().Select(disk => (disk, disk.Version))];
        foreach ((WozDisk disk, _) in _libraryDisks)
        {
            // A disk that does not read as a volume has nothing to name code by, and a file that does not read is left
            // out.
            List<(string Name, bool Text, byte[] Data)> files;
            try
            {
                files = Files(SectorDiskReader.Read(disk, proDosOrder: false));
            }
            catch (InvalidDataException)
            {
                continue;
            }

            foreach ((string name, bool text, byte[] data) in files)
            {
                if (text)
                {
                    // A text file is a listing when most of its lines are a listing's.
                    string plain = PascalTextFile.Read(data);
                    PascalListing listing = PascalListing.Parse(plain);
                    int lines = plain.Split('\n').Count(line => line.Trim().Length != 0);
                    if (listing.Lines.Count != 0 && listing.Lines.Count * 2 >= lines)
                    {
                        _listings.Add((name, listing));
                    }

                    continue;
                }

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

    // The code and text files on a Pascal or SOS volume, leaving out any file whose blocks cannot be read.
    private static List<(string Name, bool Text, byte[] Data)> Files(byte[] image)
    {
        List<(string Name, bool Text, Func<byte[]> Read)> files = [];
        if (PascalVolume.IsPascalVolume(image, proDosOrder: false))
        {
            PascalVolume volume = PascalVolume.Read(image, proDosOrder: false);
            foreach (PascalFileEntry file in volume.Files.Where(file => file.Kind is PascalFileKind.Code or PascalFileKind.Data or PascalFileKind.Text))
            {
                files.Add(($"{volume.Name}:{file.Name}", file.Kind == PascalFileKind.Text, () => volume.ReadFile(file)));
            }
        }
        else
        {
            SosVolume sos = SosVolume.Read(image, proDosOrder: false);
            foreach (SosFileEntry file in sos.Files.Where(file => file.FileType is 0x02 or 0x03 or 0x05 && file.StorageType is >= 1 and <= 3))
            {
                files.Add(($"/{sos.Name}/{file.Name}", file.FileType == 0x03, () => sos.ReadFile(file.Name)));
            }
        }

        List<(string Name, bool Text, byte[] Data)> read = [];
        foreach ((string name, bool text, Func<byte[]> reader) in files)
        {
            try
            {
                byte[] data = reader();
                if (text || PascalCodeFile.IsCodeFile(data)) { read.Add((name, text, data)); }
            }
            catch (InvalidDataException)
            {
                // A damaged file; the volume's others may still read.
            }
        }

        return read;
    }
}