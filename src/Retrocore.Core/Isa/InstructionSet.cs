// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Isa;

/// <summary>
///  A CPU's instruction set as data: registers, flags, operand forms and encodings, read from its description
///  file by <see cref="IsaParser"/>.
/// </summary>
/// <remarks>
///  <para>
///   Mnemonics get dense IDs, and encodings are found by indexing a mnemonic-by-form table, so assembly passes
///   never hash text once a statement's mnemonic is resolved.
///  </para>
/// </remarks>
public sealed partial class InstructionSet
{
    /// <summary>
    ///  The ID of text that names no mnemonic; every lookup through it fails.
    /// </summary>
    public const int UnknownMnemonic = -1;

    /// <summary>
    ///  The <see cref="FirstByteMap"/> value of a byte that is not a whole opcode.
    /// </summary>
    public const uint NoSingleByteOpcode = uint.MaxValue;

    private readonly List<string> _mnemonics = [];
    private readonly List<string> _baseNames = [];
    private readonly Dictionary<string, int> _ids = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<uint, int> _packed = [];
    private readonly List<IsaEncoding> _encodings = [];
    private readonly List<InstructionFlow> _flows = [];
    private readonly List<byte> _sizes = [];

    // Arrays of the lists above once the set is built, so decoding and analysis index them directly.
    private IsaEncoding[] _encodingArray = [];
    private byte[] _sizeArray = [];
    private InstructionFlow[] _flowArray = [];
    private uint[] _firstByteMap = [];
    private OperandForm[] _formArray = [];
    private readonly List<MemoryAccess> _access = [];
    private readonly List<MemoryAccess> _encodingAccess = [];
    private MemoryAccess[] _encodingAccessArray = [];
    private List<(uint Prefix, int PrefixLength, int OperandSize, int OpcodeLength)>? _splits;
    private readonly Dictionary<int, string> _exclusions = [];
    // Single-byte opcodes by first byte, -1 for none; PostbyteEntry marks an encoding with a postbyte field.
    private readonly int[] _decode = CreateDecodeTable();
    private const int PostbyteEntry = 1 << 30;
    private bool _hasPostbytes;
    private Dictionary<ulong, int>? _prefixed;
    private int _maximumOpcodeLength = 1;
    private int[] _table = [];

    // Sets that values refer to by handle, so those values can stay unmanaged; slot 0 means none.
    private static readonly object s_handleLock = new();
    private static InstructionSet?[] s_handles = [null];
    private ushort _handle;

    private InstructionSet(string name, IsaDescription description)
    {
        Name = name;
        Description = description;
    }

    /// <summary>
    ///  Gets the instruction set's name, as <c>.cpu</c> selects it.
    /// </summary>
    public string Name { get; }

    /// <summary>
    ///  Gets whether it has no instructions of its own, so a source writes it with macros (see <see cref="MacroOnly"/>).
    /// </summary>
    public bool IsMacroOnly => _mnemonics.Count == 0;

    /// <summary>
    ///  Gets the description shared by the instruction sets of one file: byte order, registers, flags and forms.
    /// </summary>
    public IsaDescription Description { get; }

    /// <summary>
    ///  Gets the operand forms, indexed by ID.
    /// </summary>
    public IReadOnlyList<OperandForm> Forms => Description.Forms;

    /// <summary>
    ///  Gets the byte order.
    /// </summary>
    public Endianness Endianness => Description.Endianness;

    /// <summary>
    ///  Gets the encodings, indexed by encoding ID.
    /// </summary>
    public IReadOnlyList<IsaEncoding> Encodings => _encodingArray;

    /// <summary>
    ///  Gets whether an indirect pointer at the end of a page reads its high byte from the start of that page, as
    ///  the NMOS 6502's <c>JMP ($xxFF)</c> does.
    /// </summary>
    public bool IndirectPageWrap { get; private init; }

    /// <summary>
    ///  Gets the codec for the set's postbyte fields, or <see langword="null"/> when the set has none or its
    ///  description was parsed without one.
    /// </summary>
    public PostbyteCodec? Postbytes { get; private init; }

    /// <summary>
    ///  Gets a small number that identifies this set for the life of the process, so unmanaged values such as
    ///  decoded instructions can refer to it; <see cref="FromHandle"/> returns the set.
    /// </summary>
    public ushort Handle
    {
        get
        {
            if (_handle != 0) { return _handle; }
            lock (s_handleLock)
            {
                if (_handle == 0)
                {
                    // Copy on write, so readers index the array without taking the lock.
                    InstructionSet?[] handles = new InstructionSet?[s_handles.Length + 1];
                    Array.Copy(s_handles, handles, s_handles.Length);
                    handles[^1] = this;
                    _handle = checked((ushort)(handles.Length - 1));
                    Volatile.Write(ref s_handles, handles);
                }

                return _handle;
            }
        }
    }

    /// <summary>
    ///  Gets the set a <see cref="Handle"/> identifies.
    /// </summary>
    /// <param name="handle">The handle.</param>
    /// <returns>The set.</returns>
    /// <exception cref="ArgumentOutOfRangeException">No set has the handle.</exception>
    public static InstructionSet FromHandle(ushort handle)
    {
        InstructionSet?[] handles = Volatile.Read(ref s_handles);
        return handle < handles.Length && handles[handle] is { } set
            ? set
            : throw new ArgumentOutOfRangeException(nameof(handle));
    }

    /// <summary>
    ///  Gets the number of distinct mnemonics.
    /// </summary>
    public int MnemonicCount => _mnemonics.Count;

    /// <summary>
    ///  Resolves mnemonic text to its dense ID.
    /// </summary>
    /// <param name="mnemonic">The mnemonic in any case.</param>
    /// <returns>The ID, or <see cref="UnknownMnemonic"/>.</returns>
    public int GetMnemonic(ReadOnlySpan<char> mnemonic)
    {
        return TryPack(mnemonic, out uint key)
            ? _packed.TryGetValue(key, out int packed) ? packed : UnknownMnemonic
            : _ids.TryGetValue(mnemonic.ToString(), out int id) ? id : UnknownMnemonic;
    }

    /// <inheritdoc cref="GetMnemonic(ReadOnlySpan{char})"/>
    public int GetMnemonic(string mnemonic) => GetMnemonic(mnemonic.AsSpan());

    /// <summary>
    ///  Gets a mnemonic's name.
    /// </summary>
    /// <param name="mnemonic">The dense ID.</param>
    /// <returns>The name, such as <c>BBR3</c>.</returns>
    public string MnemonicName(int mnemonic) => _mnemonics[mnemonic];

    /// <summary>
    ///  Gets a mnemonic's instruction name before any bit suffix, such as <c>BBR</c> for <c>BBR3</c>.
    /// </summary>
    /// <param name="mnemonic">The dense ID.</param>
    /// <returns>The instruction name.</returns>
    public string InstructionName(int mnemonic) => _baseNames[mnemonic];

    /// <summary>
    ///  Looks up the encoding of a mnemonic in a form.
    /// </summary>
    /// <param name="mnemonic">The dense mnemonic ID; <see cref="UnknownMnemonic"/> never matches.</param>
    /// <param name="form">The form ID.</param>
    /// <param name="encoding">The encoding ID.</param>
    /// <returns>Whether the mnemonic has the form.</returns>
    public bool TryGet(int mnemonic, int form, out int encoding)
    {
        int count = Forms.Count;
        if ((uint)mnemonic < (uint)_mnemonics.Count && (uint)form < (uint)count)
        {
            encoding = _table[mnemonic * count + form];
            return encoding >= 0;
        }

        encoding = -1;
        return false;
    }

    /// <summary>
    ///  Gets whether a mnemonic has a form.
    /// </summary>
    /// <param name="mnemonic">The dense mnemonic ID.</param>
    /// <param name="form">The form ID.</param>
    /// <returns>Whether it has it.</returns>
    public bool Has(int mnemonic, int form) => TryGet(mnemonic, form, out _);

    /// <summary>
    ///  Gets why a mnemonic is excluded from this set, as a subset excludes some of its base's instructions.
    /// </summary>
    /// <param name="mnemonic">The dense mnemonic ID.</param>
    /// <returns>The reason, or null when it is available.</returns>
    public string? Exclusion(int mnemonic) =>
        _exclusions.Count != 0 && _exclusions.TryGetValue(mnemonic, out string? reason) ? reason : null;

    /// <summary>
    ///  Gets the total size of an encoding: its opcode and operand bytes.
    /// </summary>
    /// <param name="encoding">The encoding ID.</param>
    /// <returns>The size in bytes.</returns>
    public int Size(int encoding) => _sizeArray[encoding];

    /// <summary>
    ///  Gets an encoding without an interface call, for decoding loops.
    /// </summary>
    /// <param name="encoding">The encoding ID.</param>
    /// <returns>The encoding.</returns>
    public IsaEncoding GetEncoding(int encoding) => _encodingArray[encoding];

    /// <summary>
    ///  Gets an operand form without an interface call, for decoding loops.
    /// </summary>
    /// <param name="form">The form ID.</param>
    /// <returns>The form.</returns>
    public OperandForm GetForm(int form) => _formArray[form];

    /// <summary>
    ///  Gets an encoding's control-flow class.
    /// </summary>
    /// <param name="encoding">The encoding ID.</param>
    /// <returns>The class.</returns>
    public InstructionFlow Flow(int encoding) => _flowArray[encoding];

    /// <summary>
    ///  Gets, for each possible first byte, the single-byte opcode it is: the encoding ID in bits 0-15 and the
    ///  encoding's total size in bits 16-23, or <see cref="NoSingleByteOpcode"/> for a prefix or unused byte.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   Decoding loops hold this span in a local, so a single-byte instruction decodes with one table read.
    ///   <see cref="TryDecode(ReadOnlySpan{byte}, out int)"/> handles prefixed opcodes.
    ///  </para>
    /// </remarks>
    public ReadOnlySpan<uint> FirstByteMap => _firstByteMap;

    /// <summary>
    ///  Gets how an instruction accesses a memory operand.
    /// </summary>
    /// <param name="mnemonic">The dense mnemonic ID.</param>
    /// <returns>The access.</returns>
    public MemoryAccess Access(int mnemonic) => _access[mnemonic];

    /// <summary>
    ///  Gets how an encoding accesses its memory operand, which can differ between a mnemonic's forms, as the
    ///  Z80's <c>LD A,[nn]</c> reads and <c>LD [nn],A</c> writes.
    /// </summary>
    /// <param name="encoding">The encoding ID.</param>
    /// <returns>The access.</returns>
    public MemoryAccess EncodingAccess(int encoding) => _encodingAccessArray[encoding];

    /// <summary>
    ///  Finds the encoding whose opcode starts some bytes.
    /// </summary>
    /// <param name="bytes">Bytes starting at an instruction.</param>
    /// <param name="encoding">The encoding ID.</param>
    /// <returns>Whether an opcode matched; its operand bytes may still be missing.</returns>
    [System.Runtime.CompilerServices.MethodImpl(System.Runtime.CompilerServices.MethodImplOptions.AggressiveInlining)]
    public bool TryDecode(ReadOnlySpan<byte> bytes, out int encoding)
    {
        // A single-byte opcode without a postbyte is one table read; the rest take the slower path.
        if (!bytes.IsEmpty)
        {
            int entry = _decode[bytes[0]];
            if ((uint)entry < PostbyteEntry)
            {
                encoding = entry;
                return true;
            }
        }

        return TryDecodeSlow(bytes, out encoding, out _);
    }

    /// <summary>
    ///  Finds the encoding whose opcode starts some bytes and computes its total length, including the bytes a
    ///  postbyte field selects.
    /// </summary>
    /// <param name="bytes">Bytes starting at an instruction.</param>
    /// <param name="encoding">The encoding ID.</param>
    /// <param name="size">The complete byte length of the instruction.</param>
    /// <returns>Whether a valid opcode, and postbyte when the form has one, matched.</returns>
    [System.Runtime.CompilerServices.MethodImpl(System.Runtime.CompilerServices.MethodImplOptions.AggressiveInlining)]
    public bool TryDecode(ReadOnlySpan<byte> bytes, out int encoding, out int size)
    {
        if (!bytes.IsEmpty)
        {
            int entry = _decode[bytes[0]];
            if ((uint)entry < PostbyteEntry)
            {
                encoding = entry;
                size = _sizeArray[entry];
                return true;
            }
        }

        return TryDecodeSlow(bytes, out encoding, out size);
    }

    // Prefixed opcodes, postbyte fields and bytes that start no opcode.
    [System.Runtime.CompilerServices.MethodImpl(System.Runtime.CompilerServices.MethodImplOptions.NoInlining)]
    private bool TryDecodeSlow(ReadOnlySpan<byte> bytes, out int encoding, out int size)
    {
        size = 0;
        if (bytes.IsEmpty)
        {
            encoding = -1;
            return false;
        }

        int entry = _decode[bytes[0]];
        if (entry >= 0)
        {
            encoding = entry & ~PostbyteEntry;
        }
        else if (_prefixed is null || !TryDecodePrefixed(bytes, out encoding))
        {
            encoding = -1;
            return false;
        }

        IsaEncoding value = _encodingArray[encoding];
        if (!_hasPostbytes || !_formArray[value.Form].HasPostbyte)
        {
            size = _sizeArray[encoding];
            return true;
        }

        int opcodeLength = value.OpcodeLength;
        if (Postbytes is not { } codec
            || bytes.Length <= opcodeLength
            || !codec.TryGetSize(_formArray[value.Form].Field(0), bytes[opcodeLength..], out int fieldSize))
        {
            return false;
        }

        size = opcodeLength + fieldSize;
        return true;
    }

    private bool TryDecodePrefixed(ReadOnlySpan<byte> bytes, out int encoding)
    {
        // The longest opcode that matches wins, as a prefix byte selects a longer table.
        encoding = -1;
        if (_prefixed is not { } prefixed) { return false; }
        if (_splits is { } splits && TryDecodeSplit(bytes, splits, prefixed, out encoding)) { return true; }
        uint opcode = bytes[0];
        int limit = Math.Min(_maximumOpcodeLength, bytes.Length);
        for (int length = 2; length <= limit; length++)
        {
            opcode |= (uint)bytes[length - 1] << ((length - 1) * 8);
            if (prefixed.TryGetValue(((ulong)length << 32) | opcode, out int found)) { encoding = found; }
        }

        return encoding >= 0;
    }

    // An opcode whose operand bytes come before its last bytes, such as DD CB d op, is keyed without them.
    private static bool TryDecodeSplit(
        ReadOnlySpan<byte> bytes,
        List<(uint Prefix, int PrefixLength, int OperandSize, int OpcodeLength)> splits,
        Dictionary<ulong, int> prefixed,
        out int encoding)
    {
        foreach ((uint prefix, int prefixLength, int operandSize, int opcodeLength) in splits)
        {
            if (bytes.Length < opcodeLength + operandSize) { continue; }
            uint opcode = 0;
            for (int index = 0; index < prefixLength; index++) { opcode |= (uint)bytes[index] << (index * 8); }
            if (opcode != prefix) { continue; }
            for (int index = prefixLength; index < opcodeLength; index++)
            {
                opcode |= (uint)bytes[index + operandSize] << (index * 8);
            }

            if (prefixed.TryGetValue(((ulong)opcodeLength << 32) | opcode, out encoding)) { return true; }
        }

        encoding = -1;
        return false;
    }

    /// <inheritdoc/>
    public override string ToString() => Name;

    private static int[] CreateDecodeTable()
    {
        // A loop rather than Array.Fill, which the generator's .NET Standard 2.0 lacks.
        int[] table = new int[256];
        for (int index = 0; index < table.Length; index++) { table[index] = -1; }
        return table;
    }

    private void Freeze()
    {
        _encodingArray = [.. _encodings];
        _sizeArray = [.. _sizes];
        _flowArray = [.. _flows];
        _encodingAccessArray = [.. _encodingAccess];
        _formArray = [.. Description.Forms];
        foreach (IsaEncoding encoding in _encodingArray)
        {
            _hasPostbytes |= _formArray[encoding.Form].HasPostbyte;
        }

        // A postbyte's opcode is marked in the decode table, so other opcodes decode without reading its form.
        _firstByteMap = new uint[256];
        for (int value = 0; value < _firstByteMap.Length; value++)
        {
            int encoding = _decode[value];
            if (encoding >= 0) { encoding &= ~PostbyteEntry; }
            bool postbyte = encoding >= 0 && _formArray[_encodingArray[encoding].Form].HasPostbyte;
            if (postbyte) { _decode[value] = encoding | PostbyteEntry; }
            _firstByteMap[value] = encoding < 0 || postbyte
                ? NoSingleByteOpcode
                : (uint)encoding | ((uint)_sizeArray[encoding] << 16);
        }
    }

    /// <summary>
    ///  Registers an alternate mnemonic spelling that resolves to an existing canonical mnemonic ID.
    /// </summary>
    /// <param name="alias">The alternate mnemonic spelling.</param>
    /// <param name="canonical">The canonical mnemonic already added to this set.</param>
    internal void AddAlias(string alias, string canonical)
    {
        if (!_ids.TryGetValue(canonical, out int id))
        {
            throw new FormatException($"Instruction set '{Name}': alias '{alias}' names unknown mnemonic '{canonical}'.");
        }

        if (_ids.ContainsKey(alias))
        {
            throw new FormatException($"Instruction set '{Name}': duplicate mnemonic or alias '{alias}'.");
        }

        _ids.Add(alias, id);
        if (TryPack(alias.AsSpan(), out uint key)) { _packed.Add(key, id); }
    }

    private void Add(
        string mnemonic,
        IsaEntry entry,
        OperandForm form,
        InstructionFlow flow,
        MemoryAccess access,
        MemoryAccess encodingAccess,
        bool prefer)
    {
        if (!_ids.TryGetValue(mnemonic, out int id))
        {
            id = _mnemonics.Count;
            _mnemonics.Add(mnemonic);
            _baseNames.Add(entry.Instruction);
            _access.Add(access);
            _ids.Add(mnemonic, id);
            if (TryPack(mnemonic.AsSpan(), out uint key)) { _packed.Add(key, id); }
            int count = Forms.Count;
            int[] table = new int[_mnemonics.Count * count];
            Array.Copy(_table, table, _table.Length);
            for (int index = _table.Length; index < table.Length; index++) { table[index] = -1; }
            _table = table;
        }

        // The first encoding of a mnemonic and form is canonical unless a later one is preferred, or is
        // documented where the first is not, as DD CB d 46 is the BIT b,[IX+d] that DD CB d 40 aliases.
        int slot = id * Forms.Count + form.Id;
        if (_table[slot] < 0 || prefer || (!entry.Undocumented && _encodings[_table[slot]].Undocumented))
        {
            _table[slot] = _encodings.Count;
        }

        int encoding = _encodings.Count;
        _encodings.Add(new((ushort)id, form.Id, entry.Opcode, entry.Length, entry.Undocumented, entry.SplitAt)
        {
            Cycles = entry.Cycles,
            CyclesTaken = entry.CyclesTaken
        });

        _flows.Add(flow);
        _encodingAccess.Add(encodingAccess);
        _sizes.Add(checked((byte)(entry.Length + form.Size)));
        if (entry.SplitAt != 0) { AddSplit(entry, form); }

        // A field held in bits 3-5 of the last opcode byte makes eight opcodes decode to this one encoding.
        int shift = (entry.Length - 1) * 8;
        int variants = form.OpcodeField >= 0 ? 8 : 1;
        if (variants > 1 && ((entry.Opcode >> shift) & 0x38) != 0)
        {
            throw new FormatException(
                $"Instruction set '{Name}': {entry.Instruction} {form.Name} needs bits 3-5 of its last opcode byte clear.");
        }

        for (int variant = 0; variant < variants; variant++)
        {
            uint opcode = entry.Opcode | ((uint)(variant << 3) << shift);
            if (entry.Length == 1)
            {
                if (_decode[opcode] >= 0) { throw Duplicate(opcode, entry.Length); }
                _decode[opcode] = encoding;
            }
            else
            {
                ulong key = ((ulong)entry.Length << 32) | opcode;
                Dictionary<ulong, int> prefixed = _prefixed ??= [];
                if (prefixed.ContainsKey(key)) { throw Duplicate(opcode, entry.Length); }
                prefixed.Add(key, encoding);
                _maximumOpcodeLength = Math.Max(_maximumOpcodeLength, entry.Length);
            }
        }
    }

    // Split opcodes after one prefix share an operand size, so decoding knows which bytes to skip.
    private void AddSplit(IsaEntry entry, OperandForm form)
    {
        uint prefix = entry.Opcode & (uint)((1UL << (entry.SplitAt * 8)) - 1);
        List<(uint Prefix, int PrefixLength, int OperandSize, int OpcodeLength)> splits = _splits ??= [];
        foreach ((uint other, int otherLength, int otherSize, int otherOpcodeLength) in splits)
        {
            if (other != prefix || otherLength != entry.SplitAt) { continue; }
            if (otherSize != form.Size || otherOpcodeLength != entry.Length)
            {
                throw new FormatException(
                    $"Instruction set '{Name}': split opcodes after one prefix need one operand size and opcode length.");
            }

            return;
        }

        splits.Add((prefix, entry.SplitAt, form.Size, entry.Length));
    }

    private FormatException Duplicate(uint opcode, int length)
    {
        string bytes = "";
        for (int index = 0; index < length; index++)
        {
            bytes += ((opcode >> (index * 8)) & 0xFF).ToString("X2", System.Globalization.CultureInfo.InvariantCulture) + " ";
        }

        return new($"Instruction set '{Name}': opcode {bytes.TrimEnd()} is defined twice.");
    }

    /// <summary>
    ///  Packs up to four ASCII characters, uppercased, into one lookup key.
    /// </summary>
    private static bool TryPack(ReadOnlySpan<char> text, out uint key)
    {
        key = 0;
        if (text.Length is 0 or > 4) { return false; }
        foreach (char character in text)
        {
            if (character > 127) { return false; }
            uint upper = character is >= 'a' and <= 'z' ? (uint)(character - ('a' - 'A')) : character;
            key = (key << 8) | upper;
        }

        return true;
    }
}
