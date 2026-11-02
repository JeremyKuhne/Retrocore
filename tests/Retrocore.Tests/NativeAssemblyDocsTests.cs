// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  Every <c>asm</c> example in the native assembly reference and the native assembly skill assembles, so the
///  documentation cannot drift from the dialect.
/// </summary>
[TestClass]
public class NativeAssemblyDocsTests
{
    /// <summary>
    ///  Assembles each example as its own source, on a 6502 unless it selects another CPU, with a 32K image.
    /// </summary>
    /// <param name="file">The document, under the test's <c>Inputs\Docs</c>.</param>
    [TestMethod]
    [DataRow("NativeAssembly.md")]
    [DataRow("Skill/examples.md")]
    public void ExamplesAssemble(string file)
    {
        string path = Path.Join(AppContext.BaseDirectory, "Inputs", "Docs", file);
        List<(int Line, string Source)> examples = Examples(File.ReadAllLines(path));
        examples.Should().NotBeEmpty();

        List<string> failures = [];
        foreach ((int line, string source) in examples)
        {
            AssemblyResult result = new NativeAssembler().Assemble(
                new AssemblySource(source, $"{file}:{line}"),
                new AssemblyOptions("Mos6502", 0, 0x8000));

            if (result.Diagnostics.Count != 0)
            {
                failures.Add($"{file} line {line}: {string.Join("; ", result.Diagnostics.Select(diagnostic => diagnostic.Message))}");
            }
        }

        failures.Should().BeEmpty();
    }

    // The fenced blocks tagged asm, with the line each starts on.
    private static List<(int Line, string Source)> Examples(string[] lines)
    {
        List<(int, string)> examples = [];
        for (int index = 0; index < lines.Length; index++)
        {
            if (lines[index].Trim() != "```asm") { continue; }
            int start = index + 1;
            while (index + 1 < lines.Length && lines[index + 1].Trim() != "```") { index++; }
            examples.Add((start + 1, string.Join('\n', lines[start..(index + 1)]) + "\n"));
            index++;
        }

        return examples;
    }
}
