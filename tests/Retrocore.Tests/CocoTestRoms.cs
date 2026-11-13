// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Collections.Concurrent;
using Retrocore.Debug;
using Retrocore.Machines.Coco;

namespace Retrocore.Tests;

/// <summary>
///  The Color Computer's ROMs for tests: the dumps in <c>RETROCORE_COCO_ROMS</c> or
///  <c>%USERPROFILE%\Retrocore\coco-roms\extract</c> when they are there, and otherwise the ROMs built from the SDK's
///  sources, which are byte-identical to them, so the machine tests run with nothing external.
/// </summary>
internal static class CocoTestRoms
{
    private static readonly ConcurrentDictionary<(string Source, int Version), byte[]> s_built = new();
    private static readonly Lazy<byte[]> s_coco3 = new(() => CocoSdkModules.AssembleCoco3(SourceDirectory).Image);

    /// <summary>
    ///  Gets the directory of the dumps, or null when there is none.
    /// </summary>
    internal static string? Dumps
    {
        get
        {
            string directory = Environment.GetEnvironmentVariable("RETROCORE_COCO_ROMS")
                ?? Path.Join(ExternalTestData.Root, "coco-roms", "extract");

            return Directory.Exists(directory) ? directory : null;
        }
    }

    /// <summary>
    ///  Gets the machine's ROMs.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="color">Color BASIC's version, for a CoCo 1 or 2.</param>
    /// <param name="extended">Extended Color BASIC's version, or 0 for none, for a CoCo 1 or 2.</param>
    /// <returns>The ROMs.</returns>
    internal static CocoRoms Load(CocoModel model, int color = 12, int extended = 11)
    {
        if (Dumps is { } directory) { return CocoRoms.Load(model, directory, color, extended); }
        if (model == CocoModel.Coco3) { return CocoRoms.ForCoco3(s_coco3.Value); }
        byte[] colorBasic = Built("ColorBasic.asm", color);
        byte[] extendedBasic = extended == 0 ? [] : Built("ExtendedBasic.asm", extended);
        return CocoRoms.ForCoco12(colorBasic, extendedBasic);
    }

    /// <summary>
    ///  Gets Disk Extended Color BASIC's ROM, for the disk controller.
    /// </summary>
    /// <param name="version">The version, 10 or 11.</param>
    /// <returns>The 8 KB ROM.</returns>
    internal static byte[] DiskBasic(int version = 11) =>
        Dumps is { } directory ? CocoRoms.LoadDiskBasic(directory, version) : Built("DiskBasic.asm", version);

    private static string SourceDirectory => Path.Join(AppContext.BaseDirectory, "Inputs", "Coco");

    // One of the 8 KB BASICs, built from its source once for each version.
    private static byte[] Built(string source, int version) => s_built.GetOrAdd((source, version), key =>
    {
        string path = Path.Join(SourceDirectory, key.Source);
        return (key.Source switch
        {
            "ColorBasic.asm" => CocoSdkModules.AssembleColorBasic(path, key.Version),
            "ExtendedBasic.asm" => CocoSdkModules.AssembleExtendedBasic(path, key.Version),
            _ => CocoSdkModules.AssembleDiskBasic(path, key.Version)
        }).Sections[0].Bytes.ToArray();
    });
}
