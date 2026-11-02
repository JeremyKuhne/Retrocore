// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Diagnostics;
using System.Globalization;

namespace Retrocore.Tests;

/// <summary>
///  Optional approved Merlin32 executable; a zero exit code alone is not evidence of a successful assembly.
/// </summary>
internal static class MerlinToolchain
{
    /// <summary>
    ///  Builds a self-contained fixture in an isolated output directory.
    /// </summary>
    /// <param name="body">The Merlin source body.</param>
    /// <returns>Owned output and original symbols.</returns>
    internal static MerlinAssembly Assemble(string body)
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-merlin-").FullName;
        try
        {
            string path = Path.Join(directory, "main.s");
            File.WriteAllText(path, "        ORG $1000\n        DSK output.bin\n        TYP $06\n" + body);
            return AssembleFile(path, "output.bin");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  Builds an already staged corpus without accessing source-directed files outside that directory.
    /// </summary>
    /// <param name="path">The staged master source.</param>
    /// <param name="outputName">The expected output name.</param>
    /// <returns>The owned reference.</returns>
    internal static MerlinAssembly AssembleFile(string path, string outputName)
    {
        string dependencies = Path.Join(ExternalTestData.Root, "m1-dependencies");

        string exe = Environment.GetEnvironmentVariable("RETROCORE_MERLIN32")
            ?? Path.Join(dependencies, "Merlin32_v1.2_b2", "Windows", "Merlin32.exe");

        if (!File.Exists(exe)) { Assert.Inconclusive("Set RETROCORE_MERLIN32 to the optional Merlin32 executable."); }
        string library = Path.Join(dependencies, "Merlin32_v1.2_b2", "Library");
        string directory = Path.GetDirectoryName(Path.GetFullPath(path)) ?? throw new InvalidOperationException();
        string output = Path.Join(directory, outputName);
        if (File.Exists(output)) { File.Delete(output); }
        ProcessStartInfo start = new(exe)
        {
            WorkingDirectory = directory,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };

        start.ArgumentList.Add("-V");
        start.ArgumentList.Add(library);
        start.ArgumentList.Add(Path.GetFullPath(path));
        using Process process = Process.Start(start) ?? throw new InvalidOperationException("Merlin32 did not start.");
        Task<string> stdout = process.StandardOutput.ReadToEndAsync();
        Task<string> stderr = process.StandardError.ReadToEndAsync();
        if (!process.WaitForExit(60_000))
        {
            process.Kill(entireProcessTree: true);
            throw new InvalidOperationException("Merlin32 exceeded the reference build timeout.");
        }

        string log = stdout.GetAwaiter().GetResult() + stderr.GetAwaiter().GetResult();
        if (process.ExitCode != 0 || log.Contains(
            "[Error]",
            StringComparison.OrdinalIgnoreCase) || log.Contains(
                "Error,",
                StringComparison.OrdinalIgnoreCase) || !File.Exists(
                    output))
        {
            throw new InvalidOperationException(
                "Merlin32 failed with exit code " + process.ExitCode.ToString(
                    CultureInfo.InvariantCulture) + ":\n" + log);
        }

        byte[] bytes = File.ReadAllBytes(output);
        Assert.IsNotEmpty(bytes, "The reference must emit nonempty work.");
        Dictionary<string, long> symbols = new(StringComparer.Ordinal);
        foreach (string line in File.ReadLines(output + "_Symbols.txt").Skip(1))
        {
            string[] columns = line.Split(';');
            if (columns.Length < 6) { continue; }
            string value = columns[4].Split('/').Last();
            if (long.TryParse(value, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out long address))
            {
                symbols[columns[5]] = address;
            }
        }

        return new(bytes, symbols);
    }
}
