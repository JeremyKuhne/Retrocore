// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using System.Diagnostics;
using System.Text;

namespace Retrocore.Tests;

/// <summary>
///  Runs an explicitly supplied or cached cc65 toolchain without downloading anything.
/// </summary>
/// <param name="directory">The directory containing ca65 and ld65.</param>
internal sealed class Ca65Toolchain(string directory)
{
    private static string ExecutableSuffix => OperatingSystem.IsWindows() ? ".exe" : "";

    /// <summary>
    ///  Gets the cc65 checkout's stock linker configurations, beside the executable directory.
    /// </summary>
    internal string ConfigDirectory => Path.GetFullPath(Path.Join(directory, "..", "cfg"));

    /// <summary>
    ///  Gets the optional toolchain, marking the calling test inconclusive when it is absent.
    /// </summary>
    /// <returns>The installed tools.</returns>
    internal static Ca65Toolchain Require()
    {
        string directory = Environment.GetEnvironmentVariable("RETROCORE_CC65")
            ?? Path.Join(
                ExternalTestData.Root,
                "m1-dependencies",
                "cc65-source",
                "src");

        Ca65Toolchain? tools = Find(directory);
        if (tools is null)
        {
            Assert.Inconclusive("Run tools\\Fetch-M1Dependencies.ps1 or set RETROCORE_CC65 to a directory containing ca65 and ld65.");
        }

        return tools;
    }

    /// <summary>
    ///  Finds both tools without treating an incomplete installation as usable.
    /// </summary>
    /// <param name="directory">The executable directory.</param>
    /// <returns>The tools, or null when either is missing.</returns>
    internal static Ca65Toolchain? Find(string directory) =>
        File.Exists(Path.Join(directory, "ca65" + ExecutableSuffix))
            && File.Exists(Path.Join(directory, "ld65" + ExecutableSuffix))
                ? new(Path.GetFullPath(directory)) : null;

    /// <summary>
    ///  Assembles one source and links with an explicit config or the built-in none target.
    /// </summary>
    /// <param name="sourcePath">The source file; relative includes resolve beside it.</param>
    /// <param name="configPath">An optional ld65 configuration.</param>
    /// <param name="includePaths">Explicit ca65 include directories for external corpus wrappers.</param>
    /// <returns>The owned bytes and debug metadata.</returns>
    internal Ca65Assembly Assemble(string sourcePath, string? configPath = null, IReadOnlyList<string>? includePaths = null)
    {
        string source = Path.GetFullPath(sourcePath);
        string workingDirectory = Path.GetDirectoryName(source)
            ?? throw new ArgumentException("The source must have a parent directory.", nameof(sourcePath));

        string temporary = Directory.CreateTempSubdirectory("retrocore-ca65-").FullName;
        try
        {
            string objectPath = Path.Join(temporary, "reference.o");
            string outputPath = Path.Join(temporary, "reference.bin");
            string debugPath = Path.Join(temporary, "reference.dbg");
            List<string> assemblyArguments = ["-g", source, "-o", objectPath];
            if (includePaths is not null)
            {
                foreach (string path in includePaths) { assemblyArguments.AddRange(["-I", path]); }
            }

            Run("ca65", workingDirectory, assemblyArguments);
            List<string> linkArguments = configPath is null
                ? ["-t", "none"] : ["-C", Path.GetFullPath(configPath)];

            string configs = Path.GetFullPath(Path.Join(directory, "..", "cfg"));
            if (configPath is null && Directory.Exists(configs))
            {
                linkArguments.AddRange(["--cfg-path", configs]);
            }

            linkArguments.AddRange([objectPath, "-o", outputPath, "--dbgfile", debugPath]);
            Run("ld65", temporary, linkArguments);
            SymbolTable symbols = new();
            symbols.Load(debugPath);
            return new(File.ReadAllBytes(outputPath), symbols, Ca65DebugSymbols.Read(debugPath));
        }
        finally
        {
            Directory.Delete(temporary, recursive: true);
        }
    }

    private void Run(string tool, string workingDirectory, IEnumerable<string> arguments)
    {
        ProcessStartInfo start = new(Path.Join(directory, tool + ExecutableSuffix))
        {
            WorkingDirectory = workingDirectory,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
            CreateNoWindow = true
        };

        foreach (string argument in arguments) { start.ArgumentList.Add(argument); }
        using Process process = Process.Start(start)
            ?? throw new InvalidOperationException($"Could not start {tool}.");

        Task<string> output = process.StandardOutput.ReadToEndAsync();
        Task<string> error = process.StandardError.ReadToEndAsync();
        if (!process.WaitForExit(milliseconds: 30_000))
        {
            process.Kill(entireProcessTree: true);
            process.WaitForExit();
            throw new TimeoutException($"{tool} exceeded the 30-second reference-build limit.");
        }

        string transcript = output.GetAwaiter().GetResult() + error.GetAwaiter().GetResult();
        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException($"{tool} exited with code {process.ExitCode}:\n{transcript}");
        }
    }
}
