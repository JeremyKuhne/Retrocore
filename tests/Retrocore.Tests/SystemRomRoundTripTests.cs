// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Machines.Apple2;
using Retrocore.Perf;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  Byte-exact external original/enhanced IIe system-ROM disassembly and reassembly.
/// </summary>
[TestClass]
public class SystemRomRoundTripTests
{
    /// <summary>
    ///  Verifies both discovery modes through saved native source and typed-model assembly.
    /// </summary>
    /// <param name="model">The external motherboard ROM configuration.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void SystemImagesRoundTripExactly(Apple2Model model)
    {
        string? directory = Environment.GetEnvironmentVariable("RETROCORE_IIE_ROMS");
        if (directory is null)
        {
            Assert.Inconclusive("Set RETROCORE_IIE_ROMS to externally supplied CD/EF/video ROM chips.");
        }

        SystemRomWorkload workload = new(model, directory);
        ReadOnlySpan<byte> image = workload.Image;
        NativeAssembler assembler = new();
        string? output = Environment.GetEnvironmentVariable("RETROCORE_SYSTEM_ROM_OUTPUT");
        List<object> results = [];
        foreach (DisassemblyMode mode in Enum.GetValues<DisassemblyMode>())
        {
            DisassemblyResult analysis = mode == DisassemblyMode.Linear
                ? workload.LinearResult : Disassembler.Analyze(workload.FlowProject);

            SystemRomWorkload.RequireValid(analysis);
            string source = analysis.ExportSource();
            if (output is not null)
            {
                Directory.CreateDirectory(output);
                string path = Path.Join(output, $"{model}.{mode}.asm");
                File.WriteAllText(path, source, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
                source = File.ReadAllText(path);
            }

            AssemblyResult text = assembler.Assemble(new AssemblySource(source), analysis.Options);
            AssemblyResult typed = assembler.Assemble(analysis.ToAssemblyProject(), analysis.Options);
            workload.Verify(text);
            workload.Verify(typed);
            text.Sections[0].Bytes.Span[..SystemRomWorkload.ChipSize].SequenceEqual(image[..SystemRomWorkload.ChipSize])
                .Should().BeTrue();

            text.Sections[0].Bytes.Span[SystemRomWorkload.ChipSize..].SequenceEqual(image[SystemRomWorkload.ChipSize..])
                .Should().BeTrue();

            if (output is not null)
            {
                File.WriteAllBytes(Path.Join(output, $"{model}.{mode}.reassembled.bin"), text.Sections[0].Bytes.ToArray());
                File.WriteAllBytes(Path.Join(output, $"{model}.{mode}.model.bin"), typed.Sections[0].Bytes.ToArray());
            }

            results.Add(new
            {
                Mode = mode.ToString(),
                InstructionCount = analysis.Instructions.Count,
                CodeBytes = analysis.Regions.Where(region => region.Kind == AnalysisRegionKind.Code).Sum(region => region.Length),
                DataBytes = analysis.Regions.Where(region => region.Kind == AnalysisRegionKind.Data).Sum(region => region.Length),
                UnexploredBytes = analysis.Regions.Where(
                    region => region.Kind == AnalysisRegionKind.Unexplored).Sum(
                        region => region.Length),
                SourceCharacters = source.Length,
                SourceStatements = NativeAssembler.Parse(new(source)).Project.Statements.Count,
                OriginalSha256 = workload.Sha256,
                TextSha256 = Hash(text.Sections[0].Bytes.Span),
                ModelSha256 = Hash(typed.Sections[0].Bytes.Span),
                TextByteDifferences = 0,
                ModelByteDifferences = 0,
                Diagnostics = analysis.Diagnostics.Select(diagnostic => new
                {
                    diagnostic.Code, diagnostic.Address, diagnostic.Message
                }).ToArray()
            });
        }

        if (output is not null)
        {
            object report = new
            {
                Model = model.ToString(),
                Cpu = workload.Options.Variant.ToString(),
                Origin = SystemRomWorkload.Origin,
                Size = workload.Image.Length,
                InputDirectory = directory,
                MergeOrder = "CD chip followed by EF chip",
                CdChipSha256 = Hash(image[..SystemRomWorkload.ChipSize]),
                EfChipSha256 = Hash(image[SystemRomWorkload.ChipSize..]),
                LibrarySha256 = Hash(File.ReadAllBytes(typeof(Disassembler).Assembly.Location)),
                Runtime = System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription,
                GeneratedUtc = DateTimeOffset.UtcNow,
                Results = results
            };

            File.WriteAllText(
                Path.Join(output, $"{model}.roundtrip.json"),
                JsonSerializer.Serialize(report, new JsonSerializerOptions
                {
                    WriteIndented = true
                }),
                new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        }
    }

    /// <summary>
    ///  Fingerprints observed bytes only after full byte comparisons have succeeded.
    /// </summary>
    /// <param name="bytes">The exact input or output image.</param>
    /// <returns>The SHA-256 fingerprint.</returns>
    private static string Hash(ReadOnlySpan<byte> bytes) => Convert.ToHexString(SHA256.HashData(bytes));
}
