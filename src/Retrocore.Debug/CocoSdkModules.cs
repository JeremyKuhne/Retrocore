// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Cpu.M6809;

namespace Retrocore.Debug;

/// <summary>
///  Assembles the SDK's Color Computer ROM sources: Color BASIC 1.0 to 1.3, Extended Color BASIC 1.0 and 1.1, and
///  Disk Extended Color BASIC 1.0 and 1.1.
/// </summary>
internal static class CocoSdkModules
{
    /// <summary>
    ///  Gets the address Color BASIC's ROM starts at.
    /// </summary>
    internal const int ColorBasicOrigin = 0xA000;

    /// <summary>
    ///  Gets the address Extended Color BASIC's ROM starts at.
    /// </summary>
    internal const int ExtendedBasicOrigin = 0x8000;

    /// <summary>
    ///  Gets the address Disk Extended Color BASIC's ROM starts at.
    /// </summary>
    internal const int DiskBasicOrigin = 0xC000;

    /// <summary>
    ///  Gets the size of each BASIC ROM: 8 KB.
    /// </summary>
    internal const int RomSize = 0x2000;

    // The sign-on messages, "COLOR BASIC 1." and "EXTENDED COLOR BASIC 1." and then the version's digit, in every
    // version; Disk BASIC's, "DISK EXTENDED COLOR BASIC 1.", moves in 1.1.
    private const int ColorSignOn = 0x147;
    private const int ExtendedSignOn = 0xE8;
    private const int DiskSignOn10 = 0x126;
    private const int DiskSignOn11 = 0x139;

    /// <summary>
    ///  Gets the directory the debug host's copy of the sources is in.
    /// </summary>
    internal static string RomDirectory => Path.Join(SdkModules.RomDirectory, "Coco");

    /// <summary>
    ///  Gets the directory of the Color Computer ROM sources: a directory that holds them, or its <c>Coco</c>
    ///  folder.
    /// </summary>
    /// <param name="directory">The SDK ROM directory, or null for the copy beside the debug host.</param>
    /// <returns>The directory.</returns>
    internal static string SdkDirectory(string? directory)
    {
        string root = directory ?? SdkModules.RomDirectory;
        return File.Exists(Path.Join(root, "ColorBasic.asm")) ? root : Path.Join(root, "Coco");
    }

    /// <summary>
    ///  Identifies the Color BASIC version of a ROM image from its sign-on message.
    /// </summary>
    /// <param name="rom">The 8K Color BASIC image.</param>
    /// <returns>10, 11, 12 or 13, or null when the image has no Color BASIC sign-on.</returns>
    internal static int? VersionOf(ReadOnlySpan<byte> rom) => Version(rom, ColorSignOn, "COLOR BASIC 1."u8, 3);

    /// <summary>
    ///  Identifies the Extended Color BASIC version of a ROM image from its sign-on message.
    /// </summary>
    /// <param name="rom">The 8K Extended Color BASIC image.</param>
    /// <returns>10 or 11, or null when the image has no Extended Color BASIC sign-on.</returns>
    internal static int? ExtendedVersionOf(ReadOnlySpan<byte> rom) =>
        Version(rom, ExtendedSignOn, "EXTENDED COLOR BASIC 1."u8, 1);

    /// <summary>
    ///  Identifies the Disk Extended Color BASIC version of a ROM image from its sign-on message.
    /// </summary>
    /// <param name="rom">The 8K Disk Extended Color BASIC image.</param>
    /// <returns>10 or 11, or null when the image has neither version's sign-on.</returns>
    internal static int? DiskVersionOf(ReadOnlySpan<byte> rom)
    {
        if (Version(rom, DiskSignOn11, "DISK EXTENDED COLOR BASIC 1."u8, 1) is 11) { return 11; }
        return Version(rom, DiskSignOn10, "DISK EXTENDED COLOR BASIC 1."u8, 1) is 10 ? 10 : null;
    }

    /// <summary>
    ///  Assembles Color BASIC for a version.
    /// </summary>
    /// <param name="path">The <c>ColorBasic.asm</c> source.</param>
    /// <param name="version">10, 11, 12 or 13, given to the source as <c>VERSION</c>.</param>
    /// <returns>The assembly, byte-identical to that version's ROM.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleColorBasic(string path, int version) =>
        Assemble(path, ColorBasicOrigin, version);

    /// <summary>
    ///  Assembles Extended Color BASIC for a version.
    /// </summary>
    /// <param name="path">The <c>ExtendedBasic.asm</c> source.</param>
    /// <param name="version">10 or 11, given to the source as <c>VERSION</c>.</param>
    /// <returns>The assembly, byte-identical to that version's ROM.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleExtendedBasic(string path, int version) =>
        Assemble(path, ExtendedBasicOrigin, version);

    /// <summary>
    ///  Assembles Disk Extended Color BASIC for a version.
    /// </summary>
    /// <param name="path">The <c>DiskBasic.asm</c> source.</param>
    /// <param name="version">10 or 11, given to the source as <c>VERSION</c>.</param>
    /// <returns>The assembly, byte-identical to that version's ROM.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleDiskBasic(string path, int version) =>
        Assemble(path, DiskBasicOrigin, version);

    // The version digit after a sign-on's text, as 10 plus it.
    private static int? Version(ReadOnlySpan<byte> rom, int offset, ReadOnlySpan<byte> text, int highest)
    {
        if (rom.Length < RomSize || !rom.Slice(offset, text.Length).SequenceEqual(text))
        {
            return null;
        }

        int digit = rom[offset + text.Length] - '0';
        return digit >= 0 && digit <= highest ? 10 + digit : null;
    }

    // Assembles an 8 KB ROM source at its origin, with VERSION set.
    private static AssemblyResult Assemble(string path, int origin, int version)
    {
        string full = Path.GetFullPath(path);
        AssemblyOptions options = new(M6809Isa.Name, origin, RomSize)
        {
            SourceResolver = new FileAssemblySourceResolver(),
            PredefinedSymbols = new Dictionary<string, long> { ["VERSION"] = version }
        };

        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource(File.ReadAllText(full), full), options);
        return result.Success
            ? result
            : throw new InvalidDataException(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic => diagnostic.Message)));
    }
}
