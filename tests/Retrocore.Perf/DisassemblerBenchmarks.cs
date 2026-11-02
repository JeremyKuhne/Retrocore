// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using BenchmarkDotNet.Attributes;
using Retrocore.Assembler;

namespace Retrocore.Perf;

/// <summary>
///  Measures complete 64-KiB flow analysis and caller-buffer decoding.
/// </summary>
[MemoryDiagnoser]
public class DisassemblerBenchmarks
{
    private readonly byte[] _image = CreateImage();
    private readonly DisassembledInstruction[] _decoded = new DisassembledInstruction[65536];
    private readonly AnalysisProject _project = CreateProject();

    /// <summary>
    ///  Validates the benchmark image before timing.
    /// </summary>
    [GlobalSetup]
    public void Setup()
    {
        DisassemblyResult result = Flow();
        if (!result.Success || result.Instructions.Count != 65536)
        {
            throw new InvalidOperationException("The complete flow image was not decoded.");
        }
    }

    /// <summary>
    ///  Traces every instruction in a full address space.
    /// </summary>
    /// <returns>The owned model snapshot.</returns>
    [Benchmark]
    public DisassemblyResult Flow() => Disassembler.Analyze(_project);

    /// <summary>
    ///  Decodes a full address space into reusable caller storage.
    /// </summary>
    /// <returns>The number of decoded instructions.</returns>
    [Benchmark]
    public int Decode()
    {
        Disassembler.Decode(_image, address: 0, ProcessorVariant.Mos6502, _decoded, out _, out int count);
        return count;
    }

    // Vectors would turn the final six bytes into data; this measures a full code decode.
    private static AnalysisProject CreateProject() =>
        new(CreateImage(), origin: 0, ProcessorVariant.Mos6502) { FollowVectors = false };

    private static byte[] CreateImage()
    {
        byte[] image = new byte[65536];
        Array.Fill(image, (byte)0xEA);
        image[^1] = 0x60;
        return image;
    }
}
