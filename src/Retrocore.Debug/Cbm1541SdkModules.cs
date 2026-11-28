// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Machines.Commodore.Serial;

namespace Retrocore.Debug;

/// <summary>
///  Assembles the SDK's source for the 1541's and 1540's DOS, <c>Serial/Dos1541.asm</c>, in any of its builds.
/// </summary>
/// <remarks>
///  <para>
///   One source gives every build: 325302-01 at <c>$C000</c>, the same in each, and at <c>$E000</c> the 1541's
///   901229 in revisions 01, 02, 03, 05 and 06, or the 1540's 325303-01, chosen by its <c>REVISION</c> symbol (1, 2,
///   3, 5, 6, or 40 for the 1540). 901229-04 has no dump, so no build.
///  </para>
/// </remarks>
internal static class Cbm1541SdkModules
{
    /// <summary>
    ///  The address the DOS starts at.
    /// </summary>
    internal const int Origin = 0xC000;

    /// <summary>
    ///  The size of each of the DOS's two 8K ROMs.
    /// </summary>
    internal const int ChipSize = 0x2000;

    /// <summary>
    ///  The <c>REVISION</c> that builds the 1540's 325303-01.
    /// </summary>
    internal const int Revision1540 = 40;

    /// <summary>
    ///  The 1541's revisions the source builds: 901229-01, -02, -03, -05 and -06.
    /// </summary>
    internal static readonly int[] Revisions1541 = [1, 2, 3, 5, 6];

    /// <summary>
    ///  Gets the drives' sources' directory beside the debug host.
    /// </summary>
    internal static string RomDirectory => Path.Join(SdkModules.RomDirectory, "Pet", "Serial");

    /// <summary>
    ///  Assembles the DOS, <c>$C000-$FFFF</c>.
    /// </summary>
    /// <param name="directory">The drives' sources' directory.</param>
    /// <param name="revision">901229's revision, 1, 2, 3, 5 or 6, or <see cref="Revision1540"/> for the 1540.</param>
    /// <returns>The assembly.</returns>
    /// <exception cref="ArgumentOutOfRangeException">The source has no such build.</exception>
    /// <exception cref="IOException">The source cannot be read.</exception>
    /// <exception cref="UnauthorizedAccessException">The source cannot be opened.</exception>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult Assemble(string directory, int revision)
    {
        if (revision != Revision1540 && !Revisions1541.Contains(revision))
        {
            throw new ArgumentOutOfRangeException(
                nameof(revision),
                "The DOS builds 901229-01, -02, -03, -05 and -06 (1, 2, 3, 5 and 6) and the 1540's 325303-01 (40).");
        }

        string full = Path.GetFullPath(Path.Join(directory, "Dos1541.asm"));
        AssemblyOptions options = new(ProcessorVariant.Mos6502, Origin, 2 * ChipSize)
        {
            SourceResolver = new FileAssemblySourceResolver(),
            PredefinedSymbols = new Dictionary<string, long> { ["REVISION"] = revision }
        };

        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource(File.ReadAllText(full), full), options);
        return result.Success
            ? result
            : throw new InvalidDataException(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic => diagnostic.Message)));
    }

    /// <summary>
    ///  Builds a drive's ROMs from the source, byte-identical to the chips.
    /// </summary>
    /// <param name="model">The drive, <c>1541</c> or <c>1540</c>.</param>
    /// <param name="revision">
    ///  For a 1541, 901229's revision: 1, 2, 3, 5 or 6, 6 being the last, as in MAME's default set.
    /// </param>
    /// <param name="directory">The drives' sources' directory, or null for the copy beside the debug host.</param>
    /// <returns>The ROMs.</returns>
    /// <exception cref="ArgumentException">The model is neither.</exception>
    /// <exception cref="ArgumentOutOfRangeException">The source has no such revision.</exception>
    /// <exception cref="IOException">The source cannot be read.</exception>
    /// <exception cref="UnauthorizedAccessException">The source cannot be opened.</exception>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static Cbm1541Roms BuildRoms(string model, int revision = 6, string? directory = null)
    {
        int build = model switch
        {
            "1541" => revision,
            "1540" => Revision1540,
            _ => throw new ArgumentException("The drive is a 1541 or a 1540.", nameof(model))
        };

        ReadOnlySpan<byte> image = Assemble(directory ?? RomDirectory, build).Sections[0].Bytes.Span;
        return new(image[..ChipSize], image[ChipSize..], model);
    }
}
