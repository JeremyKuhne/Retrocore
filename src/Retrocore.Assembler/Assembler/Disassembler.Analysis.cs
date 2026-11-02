// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu.M6502;

namespace Retrocore.Assembler;

/// <inheritdoc/>
public static partial class Disassembler
{
    /// <summary>
    ///  Analyzes an editable project into an independent snapshot without modifying its annotations.
    /// </summary>
    /// <param name="project">The image, entry points and caller overrides.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Instructions, regions, references and explicit analysis diagnostics.</returns>
    public static DisassemblyResult Analyze(AnalysisProject project, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(project);
        cancellationToken.ThrowIfCancellationRequested();
        return new AnalysisEngine(project, cancellationToken).Run();
    }

    /// <summary>
    ///  Disassembles a complete image linearly, preserving truncated tails as data.
    /// </summary>
    /// <param name="image">The input image.</param>
    /// <param name="origin">The non-wrapping load address.</param>
    /// <param name="variant">The CPU encoding set.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>The owned analysis snapshot.</returns>
    public static DisassemblyResult Disassemble(
        ReadOnlySpan<byte> image,
        int origin,
        ProcessorVariant variant,
        CancellationToken cancellationToken = default) =>
            Analyze(new(image, origin, variant) { Mode = DisassemblyMode.Linear }, cancellationToken);

    /// <summary>
    ///  Disassembles a complete image of any CPU linearly, preserving truncated tails as data.
    /// </summary>
    /// <param name="image">The input image.</param>
    /// <param name="origin">The non-wrapping load address.</param>
    /// <param name="set">The CPU's instruction set.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>The owned analysis snapshot.</returns>
    public static DisassemblyResult Disassemble(
        ReadOnlySpan<byte> image,
        int origin,
        Retrocore.Isa.InstructionSet set,
        CancellationToken cancellationToken = default) =>
            Analyze(new(image, origin, set) { Mode = DisassemblyMode.Linear }, cancellationToken);
}
