// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Machines.Trs80Model100;

namespace Retrocore.Debug;

/// <summary>
///  The SDK's native source for the Model 100's ROM, byte-identical to the US Model 100's and Tandy 102's.
/// </summary>
internal static class Trs80Model100SdkModules
{
    /// <summary>
    ///  Gets the source's root file name, which includes its modules.
    /// </summary>
    internal const string Source = "Model100.asm";

    /// <summary>
    ///  Gets the SDK's Model 100 ROM source directory beside the debug host.
    /// </summary>
    internal static string RomDirectory => Path.Join(SdkModules.RomDirectory, "Trs80Model100");

    /// <summary>
    ///  Gets the directory that holds the Model 100's source: the one given if it holds it, else its
    ///  <c>Trs80Model100</c> folder.
    /// </summary>
    /// <param name="directory">The SDK ROM directory, or null for the one beside the debug host.</param>
    /// <returns>The directory.</returns>
    internal static string SourceDirectory(string? directory)
    {
        if (directory is null) { return RomDirectory; }
        return File.Exists(Path.Join(directory, Source)) ? directory : Path.Join(directory, "Trs80Model100");
    }

    /// <summary>
    ///  Assembles the ROM for a model.
    /// </summary>
    /// <param name="path">The <c>Model100.asm</c> source.</param>
    /// <param name="model">The model, given to the source as <c>MODEL</c>: 100 or 102.</param>
    /// <returns>The 32 KB assembly, byte-identical to that model's ROM.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult Assemble(string path, Trs80Model100Variant model)
    {
        string full = Path.GetFullPath(path);
        AssemblyOptions options = new("I8085", 0, Trs80Model100Roms.RomSize)
        {
            SourceResolver = new FileAssemblySourceResolver(),
            PredefinedSymbols = new Dictionary<string, long>
            {
                ["MODEL"] = model == Trs80Model100Variant.Tandy102 ? 102 : 100
            }
        };

        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource(File.ReadAllText(full), full), options);
        return result.Success
            ? result
            : throw new InvalidDataException(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic => diagnostic.Message)));
    }
}
