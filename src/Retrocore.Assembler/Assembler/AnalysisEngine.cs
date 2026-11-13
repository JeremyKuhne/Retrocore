// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;
using System.Buffers;
using System.Collections;
using System.Globalization;

namespace Retrocore.Assembler;

/// <summary>
///  Bounded recursive-descent analysis using explicit work and byte-ownership arrays.
/// </summary>
/// <remarks>
///  <para>
///   Working positions are image-relative offsets; public instructions, references and diagnostics use CPU
///   addresses. Each owned byte records its instruction's starting offset, allowing a target in the middle
///   of an operand to be distinguished from an already analyzed instruction boundary.
///  </para>
///  <para>
///   Caller pins and decoded ownership are separate. Pins constrain discovery, while the result partition
///   reports what was actually decoded. Queued block starts are tracked independently to bound loops and
///   repeated references without using the CLR call stack.
///  </para>
///  <para>
///   This single-use engine rents the ownership map and returns it in <see cref="Run"/>'s finally block,
///   including cancellation and error paths. Only the image-length prefix of a rental is initialized or read;
///   accepted instructions are materialized into independent output storage before the rental is returned.
///  </para>
/// </remarks>
internal sealed class AnalysisEngine
{
    private const int UnownedOffset = -1;

    private const int InitialReferenceCapacity = 256;

    private const int TargetKeyShift = 24;

    private const int SourceKeyShift = 8;

    // A prefix letter, an underscore and four hexadecimal digits, such as L_C000.
    private const int GeneratedNameLength = 6;

    private readonly AnalysisProject _project;
    private readonly InstructionSet _set;
    private readonly CancellationToken _cancellationToken;
    private readonly int _length;
    private readonly int[] _owners;
    private readonly AnalysisRegionKind[] _pins;
    private readonly bool[] _queued;
    private readonly Stack<int> _work = new();
    private int _instructionCount;
    private readonly DisassembledInstruction[] _decoded;
    private DisassemblyReference[] _references;
    private int _referenceCount;
    private readonly List<DisassemblyDiagnostic> _diagnostics = [];

    /// <summary>
    ///  Creates independent analysis state.
    /// </summary>
    /// <param name="project">The immutable image and editable overrides.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    internal AnalysisEngine(AnalysisProject project, CancellationToken cancellationToken)
    {
        _project = project;
        _set = project.InstructionSet;
        _cancellationToken = cancellationToken;
        _length = project.Image.Length;
        _pins = new AnalysisRegionKind[_length];
        _queued = new bool[_length];
        _owners = ArrayPool<int>.Shared.Rent(_length);
        Array.Fill(_owners, UnownedOffset, 0, _length);

        // Pooled scratch keeps repeated analyses to output-only allocations; each decode is kept for output.
        _decoded = ArrayPool<DisassembledInstruction>.Shared.Rent(_length);
        _references = ArrayPool<DisassemblyReference>.Shared.Rent(InitialReferenceCapacity);
    }

    /// <summary>
    ///  Runs all passes once and returns the rented ownership map after creating independent output.
    /// </summary>
    /// <returns>An immutable analysis snapshot, including invalid-model diagnostics.</returns>
    internal DisassemblyResult Run()
    {
        try
        {
            if (Validate())
            {
                if (_project.Mode == DisassemblyMode.Linear)
                {
                    Trace(start: 0, _length, linear: true);
                }
                else
                {
                    foreach (AnalysisRegion region in _project.Regions)
                    {
                        // A caller's code range remains code even after an otherwise terminal instruction.
                        if (region.Kind == AnalysisRegionKind.Code)
                        {
                            int start = region.Address - _project.Origin;
                            Trace(start, start + region.Length, linear: true);
                        }
                    }

                    // Caller code regions win over vectors, so vectors are pinned only after those traces claim bytes.
                    // The CPU's vectors, such as the 6502's NMI, RESET and IRQ, and its fixed entry points, such
                    // as the Z80's restarts.
                    if (_project.FollowVectors)
                    {
                        bool littleEndian = _set.Endianness == Endianness.Little;
                        foreach (ushort vector in _set.Description.Vectors)
                        {
                            ushort low = littleEndian ? vector : (ushort)(vector + 1);
                            ushort high = littleEndian ? (ushort)(vector + 1) : vector;
                            FollowVector(vector, low, high);
                        }

                        foreach (ushort entry in _set.EntryPoints) { Enqueue(entry, entryPoint: false); }
                    }

                    foreach (ushort entry in _project.EntryPoints) { Enqueue(entry, entryPoint: true); }
                    while (_work.TryPop(out int start)) { Trace(start, _length, linear: false); }
                }
            }

            // References need target-first ordering; instruction order is recovered directly from byte ownership.
            SortReferences();
            DisassemblyReference[] references = _references[.._referenceCount];
            return new(_project, Instructions(), Regions(), references, Symbols(references), _diagnostics.ToArray());
        }
        finally
        {
            ArrayPool<int>.Shared.Return(_owners);
            ArrayPool<DisassembledInstruction>.Shared.Return(_decoded);
            ArrayPool<DisassemblyReference>.Shared.Return(_references);
        }
    }

    /// <summary>
    ///  Orders references by target, then source, then kind.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   Packing the three fields into one key orders them exactly as comparing each field in turn would,
    ///   while letting the sort compare primitives instead of calling a comparison delegate.
    ///  </para>
    /// </remarks>
    private void SortReferences()
    {
        ulong[] keys = ArrayPool<ulong>.Shared.Rent(_referenceCount);
        try
        {
            for (int index = 0; index < _referenceCount; index++)
            {
                DisassemblyReference reference = _references[index];
                keys[index] = ((ulong)reference.Target << TargetKeyShift)
                    | ((ulong)reference.Source << SourceKeyShift)
                    | (byte)reference.Kind;
            }

            Array.Sort(keys, _references, 0, _referenceCount);
        }
        finally
        {
            ArrayPool<ulong>.Shared.Return(keys);
        }
    }

    /// <summary>
    ///  Appends a reference, growing the pooled buffer when it is full.
    /// </summary>
    /// <param name="source">The referring address.</param>
    /// <param name="target">The referenced address.</param>
    /// <param name="kind">The reference's meaning.</param>
    private void AddReference(ushort source, ushort target, DisassemblyReferenceKind kind)
    {
        if (_referenceCount == _references.Length)
        {
            DisassemblyReference[] larger = ArrayPool<DisassemblyReference>.Shared.Rent(_references.Length * 2);
            Array.Copy(_references, larger, _referenceCount);
            ArrayPool<DisassemblyReference>.Shared.Return(_references);
            _references = larger;
        }

        _references[_referenceCount++] = new(source, target, kind);
    }

    /// <summary>
    ///  Materializes accepted instruction starts in address order without a second growable list or sort.
    /// </summary>
    /// <returns>Owned copies of the values decoded while tracing, ordered by the accepted ownership map.</returns>
    private DisassembledInstruction[] Instructions()
    {
        DisassembledInstruction[] instructions = new DisassembledInstruction[_instructionCount];
        int written = 0;
        int offset = 0;
        // A pool rental may be larger than the image; only initialized image offsets are meaningful.
        while (offset < _length)
        {
            if (_owners[offset] != offset)
            {
                offset++;
                continue;
            }

            DisassembledInstruction instruction = _decoded[offset];
            instructions[written++] = instruction;
            offset += instruction.Size;
        }

        return instructions;
    }

    /// <summary>
    ///  Validates editable overrides and compiles non-overlapping caller regions into the pin map.
    /// </summary>
    /// <returns>Whether tracing can proceed without invalid-model errors.</returns>
    /// <remarks>
    ///  <para>
    ///   Invalid names, ranges and entry points prevent export. Discovery conflicts are handled separately
    ///   as warnings, allowing the exporter to preserve ambiguous or incomplete bytes as data.
    ///  </para>
    /// </remarks>
    private bool Validate()
    {
        if (!Enum.IsDefined(_project.Mode))
        {
            Error("RCDIS001", _project.Origin, "The analysis mode is invalid.");
        }

        HashSet<string> names = new(StringComparer.Ordinal);
        foreach (KeyValuePair<ushort, string> pair in _project.Symbols)
        {
            if (pair.Value is null || !AssemblySyntax.IsPlainIdentifier(pair.Value) || !names.Add(pair.Value))
            {
                Error("RCDIS002", pair.Key, "Symbol names must be valid, unique native identifiers.");
            }
        }

        foreach (KeyValuePair<ushort, string> pair in _project.Comments)
        {
            if (!Contains(pair.Key) || pair.Value is null)
            {
                Error("RCDIS003", pair.Key, "Comments need an image address and non-null text.");
            }
        }

        // Explicit Unexplored pins still reserve a range even though their enum value matches an unpinned byte.
        BitArray? occupied = null;
        foreach (AnalysisRegion region in _project.Regions)
        {
            _cancellationToken.ThrowIfCancellationRequested();
            if (region is null)
            {
                Error("RCDIS004", _project.Origin, "A pinned region cannot be null.");
                continue;
            }

            int start = region.Address - _project.Origin;
            if (start < 0 || region.Length > _pins.Length - start)
            {
                Error("RCDIS004", region.Address, "A pinned region must fit inside the image.");
                continue;
            }

            occupied ??= new(_pins.Length);
            for (int offset = start; offset < start + region.Length; offset++)
            {
                if (occupied[offset])
                {
                    Error("RCDIS004", region.Address, "Pinned regions cannot overlap.");
                    break;
                }

                occupied[offset] = true;
                _pins[offset] = region.Kind;
            }
        }

        foreach (KeyValuePair<ushort, AnalysisCall> pair in _project.Calls)
        {
            if (pair.Value is null)
            {
                Error("RCDIS010", pair.Key, "A subroutine hint cannot be null.");
            }
        }

        if (_project.Mode == DisassemblyMode.Flow)
        {
            foreach (ushort entry in _project.EntryPoints)
            {
                if (!Contains(entry) || _pins[entry - _project.Origin] == AnalysisRegionKind.Data)
                {
                    Error("RCDIS005", entry, "An entry point must be inside the image and outside pinned data.");
                }
            }
        }

        return !_diagnostics.Any(diagnostic => diagnostic.IsError);
    }

    /// <summary>
    ///  Discovers instructions in a bounded range, optionally stopping when sequential control flow ends.
    /// </summary>
    /// <param name="start">The first image-relative offset.</param>
    /// <param name="end">The exclusive image-relative limit.</param>
    /// <param name="linear">Whether to continue past terminators for linear mode or an explicit code pin.</param>
    /// <remarks>
    ///  <para>
    ///   Branch and call targets are queued rather than recursively entered. Sequential tracing keeps the
    ///   caller's return path, while jumps, returns and reset-only halts end an inferred block.
    ///  </para>
    /// </remarks>
    private void Trace(int start, int end, bool linear)
    {
        int offset = start;
        while (offset < end)
        {
            _cancellationToken.ThrowIfCancellationRequested();
            if (_pins[offset] == AnalysisRegionKind.Data || _owners[offset] != UnownedOffset)
            {
                // Inferred flow cannot reinterpret owned bytes; a linear scan can skip them and resume later.
                if (!linear)
                {
                    if (_owners[offset] != UnownedOffset && _owners[offset] != offset)
                    {
                        Conflict(offset, "A control-flow target lands inside an existing instruction.");
                    }

                    return;
                }

                offset++;
                continue;
            }

            ushort address = (ushort)(_project.Origin + offset);
            if (!Disassembler.TryDecode(
                _project.Image.Span[
                    offset..end],
                address,
                _set,
                out DisassembledInstruction instruction))
            {
                // This trace preserves the tail instead of guessing that an operand byte starts another instruction.
                _diagnostics.Add(new("RCDIS006", address, "A truncated instruction was preserved as data."));
                return;
            }

            bool conflict = false;
            for (int index = offset; index < offset + instruction.Size; index++)
            {
                if (_pins[index] == AnalysisRegionKind.Data || _owners[index] != UnownedOffset)
                {
                    conflict = true;
                    break;
                }
            }

            if (conflict)
            {
                Conflict(offset, "An instruction overlaps pinned data or an existing instruction.");
                if (!linear) { return; }
                offset++;
                continue;
            }

            // Claim every encoding byte so later targets into operands are visible as conflicts.
            Array.Fill(_owners, offset, offset, instruction.Size);
            _decoded[offset] = instruction;
            _instructionCount++;
            AddReferences(in instruction);
            if (_project.Mode == DisassemblyMode.Flow && instruction.DirectTarget is { } target)
            {
                Enqueue(target, entryPoint: false);
            }

            if (_project.Mode == DisassemblyMode.Flow
                && _project.FollowVectors
                && instruction.Flow == DisassemblyFlow.IndirectJump
                && HasStaticPointerTarget(in instruction))
            {
                FollowIndirectJump(in instruction);
            }

            offset += instruction.Size;

            // A conditional call, such as the 8080's CNZ or the Z80's CALL NZ, continues when it is not taken, so a
            // hint that the subroutine never returns or reads inline bytes does not end or skip that path.
            if (instruction.Flow == DisassemblyFlow.Call
                && !instruction.Encoding.IsConditional
                && instruction.DirectTarget is { } callee
                && _project.Calls.TryGetValue(callee, out AnalysisCall? call))
            {
                if (call.Kind == AnalysisCallKind.NoReturn)
                {
                    // A linear scan decodes every byte anyway; only inferred flow ends at the call.
                    if (!linear) { return; }
                    continue;
                }

                int inline = InlineLength(call, offset);
                if (inline < 0 || !PinData(offset, inline))
                {
                    Conflict(offset, "Inline subroutine arguments run past the image or overlap an instruction.");
                    return;
                }

                offset += inline;
            }

            if (!linear && instruction.Flow == DisassemblyFlow.Break && !_project.StopOnBreak)
            {
                // Native BRK encodes one byte, but an interrupt return resumes after the signature byte too.
                offset++;
            }

            if (!linear && !FallsThrough(instruction.Flow)) { return; }
        }
    }

    /// <summary>
    ///  Measures the inline bytes a hinted subroutine reads after its JSR.
    /// </summary>
    /// <param name="call">The subroutine hint.</param>
    /// <param name="offset">The image offset immediately after the JSR.</param>
    /// <returns>The byte count, or -1 when a zero-terminated string has no terminator inside the image.</returns>
    private int InlineLength(AnalysisCall call, int offset)
    {
        if (call.Kind == AnalysisCallKind.InlineBytes) { return call.InlineLength; }
        int terminator = offset < _length ? _project.Image.Span[offset..].IndexOf((byte)0) : -1;
        return terminator < 0 ? -1 : terminator + 1;
    }

    /// <summary>
    ///  Pins unowned image bytes as data so tracing and export treat them as non-code.
    /// </summary>
    /// <param name="offset">The first image offset.</param>
    /// <param name="length">The byte count.</param>
    /// <returns>False, pinning nothing, when the range leaves the image or overlaps an instruction.</returns>
    private bool PinData(int offset, int length)
    {
        if (length > _length - offset) { return false; }
        for (int index = offset; index < offset + length; index++)
        {
            if (_owners[index] != UnownedOffset) { return false; }
        }

        Array.Fill(_pins, AnalysisRegionKind.Data, offset, length);
        return true;
    }

    private static bool HasStaticPointerTarget(in DisassembledInstruction instruction)
    {
        OperandForm form = instruction.Form;
        if (form is { Role: OperandRole.Pointer, IsIndexed: false })
        {
            return true;
        }

        // A postbyte can also name a fixed pointer, such as the MC6809's JMP [$FFFE] or JMP [Table,PCR].
        return instruction.PostbyteReference == PostbyteReference.Pointer;
    }

    /// <summary>
    ///  Follows the pointer of an indirect jump, such as <c>JMP (abs)</c> or <c>JMP [abs]</c>, whose bytes lie
    ///  inside the image.
    /// </summary>
    /// <param name="instruction">The indirect jump.</param>
    private void FollowIndirectJump(in DisassembledInstruction instruction)
    {
        ushort pointer = instruction.Operand;
        if (instruction.InstructionSet.Endianness == Endianness.Big)
        {
            FollowVector(pointer, (ushort)(pointer + 1), pointer);
            return;
        }

        ushort high = (ushort)(pointer + 1);
        if (instruction.InstructionSet.IndirectPageWrap && (pointer & byte.MaxValue) == byte.MaxValue)
        {
            // NMOS parts do not carry into the pointer's high byte, so JMP ($xxFF) reads it from $xx00.
            high = (ushort)(pointer & ~byte.MaxValue);
            _diagnostics.Add(new(
                "RCDIS008",
                instruction.Address,
                $"{instruction} reads its high byte from ${high:X4} on NMOS processors."));
        }

        FollowVector(pointer, pointer, high);
    }

    /// <summary>
    ///  Reads a code address stored in the image, pins its bytes as data and queues the target.
    /// </summary>
    /// <param name="source">The address recorded as the reference source.</param>
    /// <param name="low">The address of the target's low byte.</param>
    /// <param name="high">The address of the target's high byte.</param>
    /// <remarks>
    ///  <para>
    ///   A pointer byte that is already part of an instruction or a caller's code region makes the pointer
    ///   ambiguous, so it is not followed.
    ///  </para>
    /// </remarks>
    private void FollowVector(ushort source, ushort low, ushort high)
    {
        if (!Contains(low) || !Contains(high)) { return; }
        int lowOffset = low - _project.Origin;
        int highOffset = high - _project.Origin;
        if (_owners[lowOffset] != UnownedOffset
            || _owners[highOffset] != UnownedOffset
            || _pins[lowOffset] == AnalysisRegionKind.Code
            || _pins[highOffset] == AnalysisRegionKind.Code)
        {
            return;
        }

        _pins[lowOffset] = AnalysisRegionKind.Data;
        _pins[highOffset] = AnalysisRegionKind.Data;
        ReadOnlySpan<byte> image = _project.Image.Span;
        ushort target = (ushort)(image[lowOffset] | (image[highOffset] << InstructionEncoding.BitsPerByte));
        AddReference(source, target, DisassemblyReferenceKind.Vector);
        Enqueue(target, entryPoint: false);
    }

    /// <summary>
    ///  Records static control targets and encoded memory bases without resolving live effective addresses.
    /// </summary>
    /// <param name="instruction">The newly accepted instruction.</param>
    private void AddReferences(in DisassembledInstruction instruction)
    {
        if (instruction.DirectTarget is { } target)
        {
            DisassemblyReferenceKind kind = instruction.Flow switch
            {
                DisassemblyFlow.Call => DisassemblyReferenceKind.Call,
                DisassemblyFlow.Jump => DisassemblyReferenceKind.Jump,
                _ => DisassemblyReferenceKind.Branch
            };

            AddReference(instruction.Address, target, kind);
        }

        OperandForm form = instruction.Form;
        if (form.HasPostbyte)
        {
            // Only a postbyte that names a static address refers to one; registers and offsets do not.
            PostbyteReference reference = instruction.PostbyteReference;
            if (reference == PostbyteReference.None)
            {
                return;
            }

            if (instruction.Flow == DisassemblyFlow.IndirectJump)
            {
                AddReference(instruction.Address, instruction.Operand, DisassemblyReferenceKind.IndirectJump);
            }
            else if (reference == PostbyteReference.Pointer)
            {
                AddReference(instruction.Address, instruction.Operand, DisassemblyReferenceKind.Read);
            }
            else if (instruction.DirectTarget is null)
            {
                DisassemblyReferenceKind kind = instruction.InstructionSet.EncodingAccess(instruction.EncodingId) switch
                {
                    MemoryAccess.Write => DisassemblyReferenceKind.Write,
                    MemoryAccess.ReadWrite => DisassemblyReferenceKind.ReadWrite,
                    _ => DisassemblyReferenceKind.Read
                };

                AddReference(instruction.Address, instruction.Operand, kind);
            }

            return;
        }

        if (instruction.Flow == DisassemblyFlow.IndirectJump)
        {
            // A jump through a register, such as the Z80's JP [HL], encodes no address.
            if (form.FieldCount != 0)
            {
                AddReference(instruction.Address, instruction.Operand, DisassemblyReferenceKind.IndirectJump);
            }
        }
        else if (form.Role == OperandRole.Pointer)
        {
            // Indirect stores read their pointer; their eventual write address requires register/RAM state.
            AddReference(instruction.Address, instruction.Operand, DisassemblyReferenceKind.Read);
        }
        else if (form.Role == OperandRole.Memory && (instruction.RelativeTarget is not null || instruction.DirectTarget is null))
        {
            // A direct jump, call or absolute branch's address is its target, recorded above.
            DisassemblyReferenceKind kind = instruction.InstructionSet.EncodingAccess(instruction.EncodingId) switch
            {
                MemoryAccess.Write => DisassemblyReferenceKind.Write,
                MemoryAccess.ReadWrite => DisassemblyReferenceKind.ReadWrite,
                _ => DisassemblyReferenceKind.Read
            };

            AddReference(instruction.Address, instruction.Operand, kind);
        }
    }

    /// <summary>
    ///  Schedules an in-image block start at most once while keeping caller-pinned data protected.
    /// </summary>
    /// <param name="address">The absolute target address.</param>
    /// <param name="entryPoint">Whether validation already checked this caller-supplied root.</param>
    private void Enqueue(ushort address, bool entryPoint)
    {
        // External targets remain references, but this image has no bytes with which to trace them.
        if (!Contains(address)) { return; }
        int offset = address - _project.Origin;
        if (_queued[offset]) { return; }
        _queued[offset] = true;
        if (_pins[offset] == AnalysisRegionKind.Data)
        {
            if (!entryPoint) { Conflict(offset, "A control-flow target lands inside pinned data."); }
            return;
        }

        _work.Push(offset);
    }

    /// <summary>
    ///  Tests an absolute address against the non-wrapping image interval.
    /// </summary>
    /// <param name="address">The candidate CPU address.</param>
    /// <returns>Whether the image owns that address.</returns>
    private bool Contains(ushort address) => address >= _project.Origin && address - _project.Origin < _length;

    /// <summary>
    ///  Determines whether inferred tracing should continue at the next sequential instruction.
    /// </summary>
    /// <param name="flow">The instruction's static flow category.</param>
    /// <returns>Whether a fallthrough path is retained under the project's BRK policy.</returns>
    private bool FallsThrough(DisassemblyFlow flow) => flow is
        DisassemblyFlow.Next or DisassemblyFlow.Call or DisassemblyFlow.ConditionalBranch or DisassemblyFlow.Wait
            || (flow == DisassemblyFlow.Break && !_project.StopOnBreak);

    /// <summary>
    ///  Records an invalid project input that prevents successful analysis/export.
    /// </summary>
    /// <param name="code">The stable diagnostic family.</param>
    /// <param name="address">The affected absolute address.</param>
    /// <param name="message">The actionable explanation.</param>
    private void Error(string code, ushort address, string message) => _diagnostics.Add(new(code, address, message, isError: true));

    /// <summary>
    ///  Records a discovery conflict without discarding the underlying bytes.
    /// </summary>
    /// <param name="offset">The affected image-relative offset.</param>
    /// <param name="message">The reason the proposed decoding could not be accepted.</param>
    private void Conflict(int offset, string message) =>
        _diagnostics.Add(new("RCDIS007", (ushort)(_project.Origin + offset), message));

    /// <summary>
    ///  Coalesces equal adjacent classifications into a gap-free partition of the complete image.
    /// </summary>
    /// <returns>Address-ordered regions, including unexplored bytes that must survive export.</returns>
    private AnalysisRegion[] Regions()
    {
        List<AnalysisRegion> regions = [];
        int start = 0;
        while (start < _length)
        {
            AnalysisRegionKind kind = Kind(start);
            int end = start + 1;
            while (end < _length && Kind(end) == kind) { end++; }
            regions.Add(new(_project.Origin + start, end - start, kind));
            start = end;
        }

        return regions.ToArray();
    }

    /// <summary>
    ///  Classifies actual decoded ownership before considering an explicit data pin.
    /// </summary>
    /// <param name="offset">The image-relative byte offset.</param>
    /// <returns>Code, explicitly pinned data, or unexplored bytes.</returns>
    private AnalysisRegionKind Kind(int offset) => _owners[offset] != UnownedOffset ? AnalysisRegionKind.Code
        : _pins[offset] == AnalysisRegionKind.Data ? AnalysisRegionKind.Data : AnalysisRegionKind.Unexplored;

    /// <summary>
    ///  Copies caller labels and adds collision-free names for otherwise unnamed reference targets.
    /// </summary>
    /// <param name="references">The target-sorted references.</param>
    /// <returns>The independent symbol snapshot; generated names are never written back to the project.</returns>
    private Dictionary<ushort, string> Symbols(DisassemblyReference[] references)
    {
        Dictionary<ushort, string> symbols = new(_project.Symbols.Count + references.Length);
        foreach (KeyValuePair<ushort, string> pair in _project.Symbols) { symbols.Add(pair.Key, pair.Value); }
        if (!_project.GenerateLabels || _diagnostics.Any(diagnostic => diagnostic.IsError)) { return symbols; }

        // Each target gets one generated base name, and a numbered suffix never matches another base name,
        // so generated names can collide only with caller names.
        HashSet<string> names = new(_project.Symbols.Values, StringComparer.Ordinal);
        foreach (DisassemblyReference reference in references)
        {
            if (symbols.ContainsKey(reference.Target)) { continue; }
            char prefix = reference.Kind is DisassemblyReferenceKind.Jump
                or DisassemblyReferenceKind.Call
                or DisassemblyReferenceKind.Branch
                or DisassemblyReferenceKind.Vector ? 'L' : reference.Kind == DisassemblyReferenceKind.IndirectJump ? 'V' : 'D';

            string name = string.Create(GeneratedNameLength, (prefix, reference.Target), static (span, state) =>
            {
                span[0] = state.prefix;
                span[1] = '_';
                state.Target.TryFormat(span[2..], out _, "X4", CultureInfo.InvariantCulture);
            });

            string candidate = name;
            int suffix = 0;
            while (names.Contains(candidate)) { candidate = $"{name}_{++suffix}"; }
            symbols.Add(reference.Target, candidate);
        }

        return symbols;
    }
}
