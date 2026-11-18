// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Machines.Acorn;
using System.Security.Cryptography;

namespace Retrocore.Debug;

/// <summary>
///  Assembles the SDK's BBC Micro ROM sources: MOS 1.20 (<c>Mos.asm</c>), BASIC II (<c>BbcBasic.asm</c>), DNFS 1.20
///  (<c>Dnfs.asm</c>) and the SAA5050's characters (<c>Saa5050.asm</c>).
/// </summary>
internal static class BbcSdkModules
{
    /// <summary>
    ///  Gets the address the MOS starts at.
    /// </summary>
    internal const int MosOrigin = 0xC000;

    /// <summary>
    ///  Gets the address a paged ROM starts at.
    /// </summary>
    internal const int PagedOrigin = 0x8000;

    // The SHA-256 digests of the dumps the sources build: MAME's os12.rom, basic2.rom and dnfs120.rom.
    private static readonly byte[] s_mos = Convert.FromHexString("2D9FEA69017864F6962704481829F95FEE08446C8C3A13826D5D4E44000AC9DE");
    private static readonly byte[] s_basic = Convert.FromHexString("45BD55DC0F6F0F8F1FE9E2481DE7DEF206565EEC8F600BA3068B849CA4132079");
    private static readonly byte[] s_dnfs = Convert.FromHexString("E745E34895225A6650B712C1DD0656CB0B0B15F072A8AE6D9EA8D1AC257EB3D6");

    /// <summary>
    ///  Gets the directory the debug host's copy of the sources is in.
    /// </summary>
    internal static string RomDirectory => Path.Join(SdkModules.RomDirectory, "Acorn");

    /// <summary>
    ///  Gets the directory of the BBC Micro's ROM sources: a directory that holds them, or its <c>Acorn</c> folder.
    /// </summary>
    /// <param name="directory">The SDK ROM directory, or null for the copy beside the debug host.</param>
    /// <returns>The directory.</returns>
    internal static string SdkDirectory(string? directory)
    {
        string root = directory ?? SdkModules.RomDirectory;
        return File.Exists(Path.Join(root, "Mos.asm")) ? root : Path.Join(root, "Acorn");
    }

    /// <summary>
    ///  Tests whether a ROM is MOS 1.20, the one <c>Mos.asm</c> builds.
    /// </summary>
    /// <param name="rom">The 16K image.</param>
    /// <returns>Whether it is.</returns>
    internal static bool IsMos(ReadOnlySpan<byte> rom) => Matches(rom, s_mos);

    /// <summary>
    ///  Tests whether a ROM is BASIC II, the one <c>BbcBasic.asm</c> builds.
    /// </summary>
    /// <param name="rom">The 16K image.</param>
    /// <returns>Whether it is.</returns>
    internal static bool IsBasic(ReadOnlySpan<byte> rom) => Matches(rom, s_basic);

    /// <summary>
    ///  Tests whether a ROM is DNFS 1.20, the one <c>Dnfs.asm</c> builds.
    /// </summary>
    /// <param name="rom">The 16K image.</param>
    /// <returns>Whether it is.</returns>
    internal static bool IsDnfs(ReadOnlySpan<byte> rom) => Matches(rom, s_dnfs);

    /// <summary>
    ///  Assembles MOS 1.20.
    /// </summary>
    /// <param name="directory">The directory that holds <c>Mos.asm</c>.</param>
    /// <returns>The assembly, byte-identical to the ROM.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleMos(string directory) =>
        Assemble(Path.Join(directory, "Mos.asm"), MosOrigin, BbcRoms.RomSize);

    /// <summary>
    ///  Assembles BASIC II.
    /// </summary>
    /// <param name="directory">The directory that holds <c>BbcBasic.asm</c>.</param>
    /// <returns>The assembly, byte-identical to the ROM.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleBasic(string directory) =>
        Assemble(Path.Join(directory, "BbcBasic.asm"), PagedOrigin, BbcRoms.RomSize);

    /// <summary>
    ///  Assembles DNFS 1.20.
    /// </summary>
    /// <param name="directory">The directory that holds <c>Dnfs.asm</c>.</param>
    /// <returns>The assembly, byte-identical to the ROM.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleDnfs(string directory) =>
        Assemble(Path.Join(directory, "Dnfs.asm"), PagedOrigin, BbcRoms.RomSize);

    /// <summary>
    ///  Assembles the SAA5050's 96 characters.
    /// </summary>
    /// <param name="directory">The directory that holds <c>Saa5050.asm</c>.</param>
    /// <returns>The assembly, byte-identical to the character ROM.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleCharacters(string directory) =>
        Assemble(Path.Join(directory, "Saa5050.asm"), 0, BbcRoms.CharacterRomSize);

    /// <summary>
    ///  Builds a Model A's or B's ROMs from the sources: the MOS, the characters, BASIC in socket 3 and, when asked,
    ///  DNFS in socket 0.
    /// </summary>
    /// <param name="directory">The directory that holds the sources.</param>
    /// <param name="filingSystem">Whether to fit DNFS.</param>
    /// <returns>The ROMs.</returns>
    /// <exception cref="InvalidDataException">A source has errors.</exception>
    internal static BbcRoms Build(string directory, bool filingSystem)
    {
        BbcRoms roms = new(AssembleMos(directory).Sections[0].Bytes.Span, AssembleCharacters(directory).Sections[0].Bytes.Span);
        roms.Fit(3, AssembleBasic(directory).Sections[0].Bytes.Span);
        if (filingSystem) { roms.Fit(0, AssembleDnfs(directory).Sections[0].Bytes.Span); }
        return roms;
    }

    private static bool Matches(ReadOnlySpan<byte> rom, byte[] digest) =>
        rom.Length == BbcRoms.RomSize && SHA256.HashData(rom).AsSpan().SequenceEqual(digest);

    // Assembles a ROM source at its origin.
    private static AssemblyResult Assemble(string path, int origin, int size)
    {
        string full = Path.GetFullPath(path);
        AssemblyOptions options = new(ProcessorVariant.Mos6502, origin, size)
        {
            SourceResolver = new FileAssemblySourceResolver()
        };

        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource(File.ReadAllText(full), full), options);
        return result.Success
            ? result
            : throw new InvalidDataException(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic => diagnostic.Message)));
    }
}
