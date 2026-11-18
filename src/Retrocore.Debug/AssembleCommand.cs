// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;

namespace Retrocore.Debug;

/// <summary>
///  Assembles a source into a binary and its cc65 debug information, so any dialect can be launched for debugging.
/// </summary>
/// <remarks>
///  <para>
///   <c>--assemble source output.bin [--dbg file.dbg] [--dialect native|ca65|merlin] [--cpu Mos6502|Rockwell65C02|Wdc65C02]
///   [--origin $6000] [--config link.cfg] [--define NAME=value]...</c>. The debug file defaults to the output name with a
///   <c>.dbg</c> extension. Each <c>--define</c> sets a symbol before the source, as a build's switch; without a value
///   it is 1.
///  </para>
/// </remarks>
internal static class AssembleCommand
{
    /// <summary>
    ///  Runs the command.
    /// </summary>
    /// <param name="args">The arguments after <c>--assemble</c>.</param>
    /// <returns>The process exit code.</returns>
    internal static int Run(string[] args)
    {
        if (args.Length < 2 || args.Length % 2 != 0)
        {
            Console.Error.WriteLine(
                "Usage: --assemble source output.bin [--dbg file.dbg] [--dialect native|ca65|merlin] [--cpu name] [--origin $6000] [--config link.cfg] [--define NAME=value]...");

            return 2;
        }

        Dictionary<string, string> options = [with(StringComparer.OrdinalIgnoreCase)];
        Dictionary<string, long> symbols = [];
        for (int index = 2; index < args.Length; index += 2)
        {
            if (string.Equals(args[index], "--define", StringComparison.OrdinalIgnoreCase))
            {
                string[] parts = args[index + 1].Split('=', 2);
                symbols[parts[0]] = parts.Length == 2 ? Address(parts[1]) : 1;
                continue;
            }

            options[args[index]] = args[index + 1];
        }

        string output = args[1];
        string debugFile = options.GetValueOrDefault("--dbg") ?? Path.ChangeExtension(output, ".dbg");
        try
        {
            AssemblyResult result = SourceBuild.Assemble(
                args[0],
                SourceBuild.Dialect(options.GetValueOrDefault("--dialect")),
                options.GetValueOrDefault("--cpu") ?? "Mos6502",
                options.TryGetValue("--origin", out string? origin) ? Address(origin) : 0x6000,
                options.GetValueOrDefault("--config"),
                symbols);

            File.WriteAllBytes(output, SourceBuild.OutputBytes(result).ToArray());
            File.WriteAllText(debugFile, SourceBuild.DebugInfo(result));
            return 0;
        }
        catch (Exception exception) when (exception is InvalidDataException or ArgumentException or IOException)
        {
            Console.Error.WriteLine(exception.Message);
            return 1;
        }
    }

    /// <summary>
    ///  Parses an address written as <c>$6000</c>, <c>0x6000</c> or decimal.
    /// </summary>
    /// <param name="text">The address.</param>
    /// <returns>The value.</returns>
    internal static int Address(string text) => CommandAddress.Parse(text);
}
