// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Cpu.I8080;
using Retrocore.Machines.Altair;

namespace Retrocore.Debug;

/// <summary>
///  The Altair's boot PROMs as SDK sources: MITS's disk boot loader (DBL) and multi-boot loader (MBL).
/// </summary>
internal static class AltairSdkModules
{
    /// <summary>
    ///  The DBL PROM's source.
    /// </summary>
    internal const string DblSource = "Dbl.asm";

    /// <summary>
    ///  The MBL PROM's source.
    /// </summary>
    internal const string MblSource = "Mbl.asm";

    /// <summary>
    ///  Gets the folder of the sources in the SDK.
    /// </summary>
    internal static string RomDirectory => Path.Join(SdkModules.RomDirectory, "Altair");

    /// <summary>
    ///  Assembles the DBL PROM.
    /// </summary>
    /// <param name="path">The source.</param>
    /// <returns>The assembly, 256 bytes at $FF00.</returns>
    internal static AssemblyResult AssembleDbl(string path) => Assemble(path, AltairBus.DblAddress);

    /// <summary>
    ///  Assembles the MBL PROM.
    /// </summary>
    /// <param name="path">The source.</param>
    /// <returns>The assembly, 256 bytes at $FE00.</returns>
    internal static AssemblyResult AssembleMbl(string path) => Assemble(path, AltairBus.MblAddress);

    /// <summary>
    ///  Builds both PROMs from a folder of their sources.
    /// </summary>
    /// <param name="directory">The folder, or null for the SDK's.</param>
    /// <returns>The PROMs.</returns>
    internal static AltairRoms Build(string? directory = null)
    {
        string folder = directory ?? RomDirectory;
        return new AltairRoms
        {
            Dbl = AssembleDbl(Path.Join(folder, DblSource)).Sections[0].Bytes.ToArray(),
            Mbl = AssembleMbl(Path.Join(folder, MblSource)).Sections[0].Bytes.ToArray()
        };
    }

    private static AssemblyResult Assemble(string path, int origin)
    {
        string full = Path.GetFullPath(path);
        AssemblyOptions options = new(I8080Isa.Name, origin, AltairRoms.PromSize)
        {
            SourceResolver = new FileAssemblySourceResolver()
        };

        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource(File.ReadAllText(full), full), options);
        return result.Success
            ? result
            : throw new InvalidDataException(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic => diagnostic.Message)));
    }
}
