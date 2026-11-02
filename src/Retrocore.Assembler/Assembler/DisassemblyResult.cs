// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu.M6502;
using System.Collections.ObjectModel;

namespace Retrocore.Assembler;

/// <summary>
///  An immutable analysis snapshot, including annotations and an allocation-free cross-reference index.
/// </summary>
public sealed class DisassemblyResult
{
    private readonly DisassembledInstruction[] _instructions;
    private readonly DisassemblyReference[] _references;

    /// <summary>
    ///  Creates a completed analysis snapshot.
    /// </summary>
    /// <param name="project">The input image and annotations.</param>
    /// <param name="instructions">Address-sorted decoded instructions.</param>
    /// <param name="regions">The complete image partition.</param>
    /// <param name="references">Target/source-sorted references.</param>
    /// <param name="symbols">User and generated symbols.</param>
    /// <param name="diagnostics">Conflicts and warnings.</param>
    internal DisassemblyResult(
        AnalysisProject project,
        DisassembledInstruction[] instructions,
        AnalysisRegion[] regions,
        DisassemblyReference[] references,
        Dictionary<ushort, string> symbols,
        DisassemblyDiagnostic[] diagnostics)
    {
        Image = project.Image;
        Origin = project.Origin;
        InstructionSet = project.InstructionSet;
        _instructions = instructions;
        _references = references;
        Instructions = Array.AsReadOnly(instructions);
        Regions = Array.AsReadOnly(regions);
        References = Array.AsReadOnly(references);
        SymbolMap = symbols;
        CommentMap = new Dictionary<ushort, string>(project.Comments);
        Symbols = new ReadOnlyDictionary<ushort, string>(SymbolMap);
        Comments = new ReadOnlyDictionary<ushort, string>(CommentMap);
        Diagnostics = Array.AsReadOnly(diagnostics);
        Success = !diagnostics.Any(diagnostic => diagnostic.IsError);
        Options = new(InstructionSet.Name, Origin, Image.Length);
    }

    /// <summary>
    ///  Gets whether the project inputs were valid; warnings preserve undecodable bytes as data.
    /// </summary>
    public bool Success { get; }

    /// <summary>
    ///  Gets the address-ordered instructions for internal sequential walks.
    /// </summary>
    internal ReadOnlySpan<DisassembledInstruction> InstructionSpan => _instructions;

    /// <summary>
    ///  Gets the symbol map behind <see cref="Symbols"/>, avoiding interface dispatch on hot internal lookups.
    /// </summary>
    internal Dictionary<ushort, string> SymbolMap { get; }

    /// <summary>
    ///  Gets the comment map behind <see cref="Comments"/>.
    /// </summary>
    internal Dictionary<ushort, string> CommentMap { get; }

    /// <summary>
    ///  Gets the owned image.
    /// </summary>
    public ReadOnlyMemory<byte> Image { get; }

    /// <summary>
    ///  Gets the load address.
    /// </summary>
    public ushort Origin { get; }

    /// <summary>
    ///  Gets the CPU encoding set.
    /// </summary>
    public ProcessorVariant Variant => M6502Isa.VariantOf(InstructionSet);

    /// <summary>
    ///  Gets the CPU's instruction set.
    /// </summary>
    public Retrocore.Isa.InstructionSet InstructionSet { get; }

    /// <summary>
    ///  Gets decoded instructions in address order.
    /// </summary>
    public IReadOnlyList<DisassembledInstruction> Instructions { get; }

    /// <summary>
    ///  Gets a gap-free classification of the image.
    /// </summary>
    public IReadOnlyList<AnalysisRegion> Regions { get; }

    /// <summary>
    ///  Gets references sorted by target, then source and kind.
    /// </summary>
    public IReadOnlyList<DisassemblyReference> References { get; }

    /// <summary>
    ///  Gets user and generated symbols, including external equates.
    /// </summary>
    public IReadOnlyDictionary<ushort, string> Symbols { get; }

    /// <summary>
    ///  Gets the immutable annotation snapshot.
    /// </summary>
    public IReadOnlyDictionary<ushort, string> Comments { get; }

    /// <summary>
    ///  Gets warnings and invalid-model errors.
    /// </summary>
    public IReadOnlyList<DisassemblyDiagnostic> Diagnostics { get; }

    /// <summary>
    ///  Gets assembler options that reproduce exactly this image's origin and byte count.
    /// </summary>
    public AssemblyOptions Options { get; }

    /// <summary>
    ///  Finds an instruction starting at an exact address.
    /// </summary>
    /// <param name="address">The instruction start.</param>
    /// <param name="instruction">The decoded value, or default.</param>
    /// <returns>Whether an instruction starts there.</returns>
    public bool TryGetInstruction(ushort address, out DisassembledInstruction instruction)
    {
        // Lower-bound search distinguishes an exact start from an address inside another instruction.
        int low = 0;
        int high = _instructions.Length;
        while (low < high)
        {
            int middle = low + ((high - low) / 2);
            if (_instructions[middle].Address < address) { low = middle + 1; }
            else { high = middle; }
        }

        instruction = low < _instructions.Length && _instructions[low].Address == address ? _instructions[low] : default;
        return instruction.Size != 0;
    }

    /// <summary>
    ///  Finds incoming references without allocating a filtered collection.
    /// </summary>
    /// <param name="address">The referenced address.</param>
    /// <returns>A slice of the immutable reference index.</returns>
    public ReadOnlySpan<DisassemblyReference> GetReferencesTo(ushort address)
    {
        // Target-first sorting puts every incoming edge in one contiguous slice.
        int low = 0;
        int high = _references.Length;
        while (low < high)
        {
            int middle = low + ((high - low) / 2);
            if (_references[middle].Target < address) { low = middle + 1; }
            else { high = middle; }
        }

        int end = low;
        while (end < _references.Length && _references[end].Target == address) { end++; }
        return _references.AsSpan(low, end - low);
    }

    /// <summary>
    ///  Exports annotated native source with byte fallbacks for noncanonical encodings.
    /// </summary>
    /// <returns>Source that round-trips with <see cref="Options"/>.</returns>
    public string ExportSource() => DisassemblyExporter.Export(this);

    /// <summary>
    ///  Exports through the ordinary assembler parser to a constructible/editable native model.
    /// </summary>
    /// <returns>The equivalent assembler project.</returns>
    public AssemblyProject ToAssemblyProject()
    {
        AssemblyParseResult parsed = Assembler.Parse(new(ExportSource(), "disassembly.asm"));
        return parsed.Success ? parsed.Project
            : throw new InvalidOperationException("The disassembler emitted invalid native source.");
    }
}
