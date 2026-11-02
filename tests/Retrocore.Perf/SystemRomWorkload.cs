// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Machines.Apple2;
using System.Buffers.Binary;
using System.Security.Cryptography;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Perf;

/// <summary>
///  A caller-supplied 16-KiB IIe image shared by round-trip tests and performance measurements.
/// </summary>
internal sealed class SystemRomWorkload
{
    /// <summary>
    ///  The CPU address of the first CD-chip byte.
    /// </summary>
    internal const int Origin = 0xC000;

    /// <summary>
    ///  The combined CD/EF system image size.
    /// </summary>
    internal const int ImageSize = 16384;

    /// <summary>
    ///  The size of each original chip dump.
    /// </summary>
    internal const int ChipSize = ImageSize / 2;

    /// <summary>
    ///  Gets the exact original CD-then-EF chip bytes.
    /// </summary>
    internal byte[] Image { get; }

    /// <summary>
    ///  Gets the image fingerprint used to identify measured input.
    /// </summary>
    internal string Sha256 { get; }

    /// <summary>
    ///  Gets the linear analysis input.
    /// </summary>
    internal AnalysisProject LinearProject { get; }

    /// <summary>
    ///  Gets flow input seeded from the image's interrupt/reset vectors.
    /// </summary>
    internal AnalysisProject FlowProject { get; }

    /// <summary>
    ///  Gets the verified linear analysis snapshot.
    /// </summary>
    internal DisassemblyResult LinearResult { get; }

    /// <summary>
    ///  Gets native source exported from the verified linear image.
    /// </summary>
    internal AssemblySource Source { get; }

    /// <summary>
    ///  Gets a pre-parsed model of the same exported source.
    /// </summary>
    internal AssemblyProject Project { get; }

    /// <summary>
    ///  Gets the exact CPU and fixed image bounds.
    /// </summary>
    internal AssemblyOptions Options { get; }

    /// <summary>
    ///  Loads existing external chip files without downloading or bundling firmware.
    /// </summary>
    /// <param name="model">The motherboard configuration.</param>
    /// <param name="directory">The existing ROM-chip directory.</param>
    internal SystemRomWorkload(Apple2Model model, string directory)
    {
        Image = Apple2Roms.LoadFromDirectory(model, directory).System.ToArray();
        if (Image.Length != ImageSize)
        {
            throw new InvalidDataException("A system-ROM workload must contain exactly 16 KiB.");
        }

        Sha256 = Convert.ToHexString(SHA256.HashData(Image));
        ProcessorVariant variant = model == Apple2Model.IIe ? ProcessorVariant.Mos6502 : ProcessorVariant.Rockwell65C02;
        Options = new(variant, Origin, ImageSize);
        LinearProject = new(Image, Origin, variant) { Mode = DisassemblyMode.Linear };
        FlowProject = new(Image, Origin, variant);
        FlowProject.EntryPoints.Clear();
        // NMI, reset and IRQ vectors are in the final six bytes, in little-endian order.
        for (int offset = Image.Length - (3 * sizeof(ushort)); offset < Image.Length; offset += sizeof(ushort))
        {
            ushort address = BinaryPrimitives.ReadUInt16LittleEndian(Image.AsSpan(offset));
            if (address >= Origin && !FlowProject.EntryPoints.Contains(address))
            {
                FlowProject.EntryPoints.Add(address);
            }
        }

        if (FlowProject.EntryPoints.Count == 0)
        {
            throw new InvalidDataException("The system image contains no in-ROM vectors.");
        }

        LinearResult = Disassembler.Analyze(LinearProject);
        RequireValid(LinearResult);
        Source = new(LinearResult.ExportSource(), model + ".system.asm");
        AssemblyParseResult parsed = NativeAssembler.Parse(Source);
        if (!parsed.Success)
        {
            throw new InvalidDataException(string.Join("; ", parsed.Diagnostics.Select(error => error.Message)));
        }

        Project = parsed.Project;
        NativeAssembler assembler = new();
        Verify(assembler.Assemble(Source, Options));
        Verify(assembler.Assemble(Project, Options));
    }

    /// <summary>
    ///  Checks exact section bounds and every original byte, rather than only a checksum.
    /// </summary>
    /// <param name="result">The rebuilt image.</param>
    internal void Verify(AssemblyResult result)
    {
        if (!result.Success)
        {
            throw new InvalidDataException(string.Join("; ", result.Diagnostics.Select(error => error.Message)));
        }

        if (result.Sections.Count != 1
            || result.Sections[0].Origin != Origin
            || result.Sections[0].Bytes.Length != Image.Length
            || !result.Sections[0].Bytes.Span.SequenceEqual(Image))
        {
            throw new InvalidDataException("System-ROM reassembly differs from its original CD/EF chip bytes.");
        }
    }

    /// <summary>
    ///  Rejects invalid/empty analysis while keeping visible warnings for ambiguous code/data.
    /// </summary>
    /// <param name="result">The complete analysis result.</param>
    internal static void RequireValid(DisassemblyResult result)
    {
        if (!result.Success
            || result.Instructions.Count == 0
            || result.Image.Length != ImageSize
            || result.Regions.Sum(region => region.Length) != ImageSize)
        {
            throw new InvalidDataException("System-ROM analysis was invalid, empty or incomplete: "
                + string.Join("; ", result.Diagnostics.Select(error => error.Message)));
        }
    }
}
