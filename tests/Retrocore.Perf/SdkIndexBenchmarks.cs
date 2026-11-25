// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using BenchmarkDotNet.Attributes;
using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Debug.Language;

namespace Retrocore.Perf;

/// <summary>
///  Measures the language server's SDK index: every SDK root source assembled from disk and its documentation parsed,
///  as <see cref="SdkIndex"/> builds it, sharing one <see cref="SourceFileCache"/>, and the assembly alone.
/// </summary>
[MemoryDiagnoser]
public class SdkIndexBenchmarks
{
    private string[] _roots = [];
    private string _expected = "";
    private SourceAnalysis[] _last = [];

    /// <summary>
    ///  Gets or sets which roots are indexed: every root of the SDK, or AppleSoft's alone.
    /// </summary>
    [Params("All", "AppleSoft")]
    public string Roots { get; set; } = "All";

    /// <summary>
    ///  Finds the roots and records what indexing them must produce, outside timing.
    /// </summary>
    [GlobalSetup]
    public void Setup()
    {
        List<string> roots = SourceIncludes.Roots(SdkModules.RomDirectory);
        _roots = Roots == "All"
            ? [.. roots]
            : [.. roots.Where(root => Path.GetFileName(root).Equals("AppleSoft.asm", StringComparison.OrdinalIgnoreCase))];

        if (_roots.Length == 0)
        {
            throw new InvalidOperationException($"No SDK roots for {Roots} in {SdkModules.RomDirectory}.");
        }

        SourceFileCache files = new();
        _expected = Signature([.. _roots.Select(root => SdkIndex.Index(root, files))]);
        Console.WriteLine($"SDK index input: {_roots.Length} roots from {SdkModules.RomDirectory}, signature {_expected}");
    }

    /// <summary>
    ///  Indexes the roots as the language server does: each assembled, then its documentation parsed.
    /// </summary>
    /// <returns>The number of documentation topics, from the work done.</returns>
    [Benchmark(Baseline = true)]
    public int Index()
    {
        SourceAnalysis[] analyses = new SourceAnalysis[_roots.Length];
        SourceFileCache files = new();
        int topics = 0;
        for (int index = 0; index < _roots.Length; index++)
        {
            analyses[index] = SdkIndex.Index(_roots[index], files);
            topics += analyses[index].Documentation.Topics.Count;
        }

        _last = analyses;
        return topics;
    }

    /// <summary>
    ///  Assembles the roots and builds their analyses, without parsing their documentation.
    /// </summary>
    /// <returns>The number of bytes assembled, from the work done.</returns>
    [Benchmark]
    public int Assemble()
    {
        int bytes = 0;
        SourceFileCache files = new();
        foreach (string root in _roots)
        {
            SourceAnalysis analysis = SourceAnalysis.Assemble(root, _ => null, files);
            foreach (AssemblySection section in analysis.Result.Sections) { bytes += section.Bytes.Length; }
        }

        return bytes;
    }

    /// <summary>
    ///  Checks that the last indexing produced exactly what setup recorded.
    /// </summary>
    [GlobalCleanup]
    public void Validate()
    {
        if (_last.Length == 0) { return; }
        string actual = Signature(_last);
        if (actual != _expected)
        {
            throw new InvalidOperationException($"The SDK index changed: {actual}, expected {_expected}.");
        }
    }

    // Each root's success, bytes, symbols and documentation topics, hashed together.
    private static string Signature(SourceAnalysis[] analyses)
    {
        using IncrementalHash hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        foreach (SourceAnalysis analysis in analyses)
        {
            hash.AppendData(System.Text.Encoding.UTF8.GetBytes($"{analysis.Root}|{analysis.Result.Success}|{analysis.Result.Symbols.Count}|{analysis.Documentation.Topics.Count}|"));
            foreach (AssemblySection section in analysis.Result.Sections) { hash.AppendData(section.Bytes.Span); }
        }

        return Convert.ToHexString(hash.GetHashAndReset());
    }
}
