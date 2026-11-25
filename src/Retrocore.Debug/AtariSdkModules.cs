// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using System.Security.Cryptography;

namespace Retrocore.Debug;

/// <summary>
///  The SDK's sources of the Atari 400's and 800's ROMs: the OS (<c>Os.asm</c>), the floating point package
///  (<c>FloatingPoint.asm</c>), Atari BASIC (<c>AtariBasic.asm</c>) and the 810's firmware (<c>Atari810.asm</c>), with
///  each build's SHA-256, by which a dump is known to be the build the source makes.
/// </summary>
internal static class AtariSdkModules
{
    /// <summary>
    ///  Rev. A's OS, the 400's and 800's first.
    /// </summary>
    internal const int OsRevisionA = 1;

    /// <summary>
    ///  Rev. B's OS, the NTSC 400's and 800's last.
    /// </summary>
    internal const int OsRevisionB = 2;

    /// <summary>
    ///  The PAL machines' OS, rev. A with PAL's timing.
    /// </summary>
    internal const int OsPal = 3;

    /// <summary>
    ///  Atari BASIC rev. A.
    /// </summary>
    internal const int BasicRevisionA = 1;

    /// <summary>
    ///  Atari BASIC rev. B.
    /// </summary>
    internal const int BasicRevisionB = 2;

    /// <summary>
    ///  Atari BASIC rev. C.
    /// </summary>
    internal const int BasicRevisionC = 3;

    /// <summary>
    ///  Where the OS's two chips start.
    /// </summary>
    internal const int OsOrigin = 0xE000;

    /// <summary>
    ///  Where the floating point package's chip starts.
    /// </summary>
    internal const int FloatingPointOrigin = 0xD800;

    /// <summary>
    ///  Where the left cartridge, and Atari BASIC, start.
    /// </summary>
    internal const int BasicOrigin = 0xA000;

    private const int OsSize = 0x2000;
    private const int FloatingPointSize = 0x0800;
    private const int BasicSize = 0x2000;
    private const int DriveOrigin = 0x0800;
    private const int DriveSize = 0x0800;

    private static readonly Dictionary<string, int> s_os = new(StringComparer.Ordinal)
    {
        ["0838DA6141ECFE8555FE75E7A04F8C4111257E154D41DEFDC2D4D45D264090F5"] = OsRevisionA,
        ["C360F85832D56B377F51533C2B2E00179E8D61361BF2CB53BC0B546425D6F766"] = OsRevisionB,
        ["13DB31CCFE5432BFEAED7D89F09638D9E6C08888B0DADAB5527A9E3DEEA88C4D"] = OsPal
    };

    private static readonly Dictionary<string, int> s_basic = new(StringComparer.Ordinal)
    {
        ["0ACE07D4ED099D700D63B3220A7F6BCFC5E2627975B2B0BB3157796BB12852DA"] = BasicRevisionA,
        ["43DE6502B77D3E7058FCE6F4ED261CAFBEC37926B797BB1AE24470D39C998EA9"] = BasicRevisionB,
        ["4988CB41121921F997AB17A59DD1909FECE9273699EBA0C6FBAAFAE104AA27B0"] = BasicRevisionC
    };

    private const string FloatingPointHash = "B1F7774BAD07E02E03EF53ECE3C29A5B7546FE967A42A73D0A4F65CE6248BDE7";

    /// <summary>
    ///  Gets the directory that holds the Atari's sources.
    /// </summary>
    /// <param name="directory">The SDK's ROM sources, or null for those beside the host.</param>
    /// <returns>The directory.</returns>
    internal static string SdkDirectory(string? directory)
    {
        string root = directory ?? SdkModules.RomDirectory;
        return File.Exists(Path.Join(root, "Os.asm")) ? root : Path.Join(root, "Atari");
    }

    /// <summary>
    ///  Identifies the OS a ROM's two chips are.
    /// </summary>
    /// <param name="os">The 8K at <c>$E000</c>.</param>
    /// <returns>The <c>VERSION</c> of the build that makes it, or null when no build does.</returns>
    internal static int? OsVersionOf(ReadOnlySpan<byte> os) => s_os.TryGetValue(Hash(os), out int version) ? version : null;

    /// <summary>
    ///  Identifies Atari BASIC's revision.
    /// </summary>
    /// <param name="rom">The cartridge's 8K.</param>
    /// <returns>The <c>VERSION</c> of the build that makes it, or null when no build does.</returns>
    internal static int? BasicVersionOf(ReadOnlySpan<byte> rom) =>
        s_basic.TryGetValue(Hash(rom), out int version) ? version : null;

    /// <summary>
    ///  Tells whether a chip is the floating point package the SDK's source builds.
    /// </summary>
    /// <param name="rom">The 2K at <c>$D800</c>.</param>
    /// <returns>Whether it is.</returns>
    internal static bool IsFloatingPoint(ReadOnlySpan<byte> rom) => Hash(rom) == FloatingPointHash;

    /// <summary>
    ///  Assembles the OS.
    /// </summary>
    /// <param name="directory">The Atari's sources.</param>
    /// <param name="version">
    ///  The build: <see cref="OsRevisionA"/>, <see cref="OsRevisionB"/> or <see cref="OsPal"/>.
    /// </param>
    /// <returns>The assembly, its one section the two chips' 8K.</returns>
    internal static AssemblyResult AssembleOs(string directory, int version) =>
        Assemble(Path.Join(directory, "Os.asm"), OsOrigin, OsSize, version);

    /// <summary>
    ///  Assembles the floating point package.
    /// </summary>
    /// <param name="directory">The Atari's sources.</param>
    /// <returns>The assembly, its one section the chip's 2K.</returns>
    internal static AssemblyResult AssembleFloatingPoint(string directory) =>
        Assemble(Path.Join(directory, "FloatingPoint.asm"), FloatingPointOrigin, FloatingPointSize, version: null);

    /// <summary>
    ///  Assembles Atari BASIC.
    /// </summary>
    /// <param name="directory">The Atari's sources.</param>
    /// <param name="version">The revision: <see cref="BasicRevisionA"/> to <see cref="BasicRevisionC"/>.</param>
    /// <returns>The assembly, its one section the cartridge's 8K.</returns>
    internal static AssemblyResult AssembleBasic(string directory, int version) =>
        Assemble(Path.Join(directory, "AtariBasic.asm"), BasicOrigin, BasicSize, version);

    /// <summary>
    ///  Assembles the 810's firmware.
    /// </summary>
    /// <param name="directory">The Atari's sources.</param>
    /// <param name="revision">The revision, <c>'B'</c> or <c>'C'</c>.</param>
    /// <returns>The assembly, its one section the ROM's 2K.</returns>
    internal static AssemblyResult Assemble810(string directory, char revision) =>
        Assemble(Path.Join(directory, "Atari810.asm"), DriveOrigin, DriveSize, revision == 'B' ? 2 : 3);

    /// <summary>
    ///  Gets the OS and floating point package's ROM image from their sources, as <see cref="Machines.Atari.AtariRoms"/>
    ///  takes it: the package at <c>$D800</c>, then the OS.
    /// </summary>
    /// <param name="directory">The Atari's sources.</param>
    /// <param name="version">The OS's build.</param>
    /// <returns>The 10K image.</returns>
    internal static byte[] BuildImage(string directory, int version) =>
    [
        .. AssembleFloatingPoint(directory).Sections[0].Bytes.Span,
        .. AssembleOs(directory, version).Sections[0].Bytes.Span
    ];

    private static string Hash(ReadOnlySpan<byte> bytes) => Convert.ToHexString(SHA256.HashData(bytes));

    // Assembles a ROM source at its origin, with VERSION, when given.
    private static AssemblyResult Assemble(string path, int origin, int size, int? version)
    {
        string full = Path.GetFullPath(path);
        Dictionary<string, long> symbols = [];
        if (version is { } value) { symbols["VERSION"] = value; }
        AssemblyOptions options = new(ProcessorVariant.Mos6502, origin, size)
        {
            SourceResolver = new FileAssemblySourceResolver(),
            PredefinedSymbols = symbols
        };

        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource(File.ReadAllText(full), full), options);
        return result.Success
            ? result
            : throw new InvalidDataException(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic => diagnostic.Message)));
    }
}
