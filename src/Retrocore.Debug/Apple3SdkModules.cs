// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Media;
using System.Text;

namespace Retrocore.Debug;

/// <summary>
///  Builds the Apple III's ROM from the SDK's source, as the debugger's symbols for it and as its image.
/// </summary>
internal static class Apple3SdkModules
{
    /// <summary>
    ///  The boot ROM's address.
    /// </summary>
    internal const int BootRomOrigin = 0xF000;

    /// <summary>
    ///  The boot ROM's size.
    /// </summary>
    internal const int BootRomSize = 0x1000;

    /// <summary>
    ///  Where the SOS.KERNEL file's image starts in its source: the address Apple's build loaded it at.
    /// </summary>
    internal const int SosKernelOrigin = 0x2000;

    /// <summary>
    ///  The size of SOS 1.3's SOS.KERNEL file.
    /// </summary>
    internal const int SosKernelSize = 22016;

    /// <summary>
    ///  Gets the directory of the Apple III's ROM sources: a directory that holds them, or its <c>Apple3</c> folder.
    /// </summary>
    /// <param name="directory">The SDK ROM directory, or null for the copy beside the debug host.</param>
    /// <returns>The directory.</returns>
    internal static string Directory(string? directory)
    {
        string root = directory ?? SdkModules.RomDirectory;
        return File.Exists(Path.Join(root, "BootRom.asm")) ? root : Path.Join(root, "Apple3");
    }

    /// <summary>
    ///  Assembles the boot ROM.
    /// </summary>
    /// <param name="path">The <c>BootRom.asm</c> source.</param>
    /// <returns>The 4K assembly, byte-identical to the boot ROM.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleBootRom(string path) => Assemble(path, BootRomOrigin, BootRomSize);

    /// <summary>
    ///  Assembles SOS 1.3's kernel, as the SOS.KERNEL file.
    /// </summary>
    /// <param name="path">The <c>SosKernel.asm</c> source.</param>
    /// <returns>The file's image, its statements at the addresses each module runs from.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleSosKernel(string path) => Assemble(path, SosKernelOrigin, SosKernelSize);

    /// <summary>
    ///  Assembles SOS's bootstrap loader, block 0 of a SOS disk, at <c>$A000</c>.
    /// </summary>
    /// <param name="path">The <c>SosBoot.asm</c> source.</param>
    /// <param name="symbol">
    ///  The build's symbol, <c>SYSTEM_DEMO</c> or <c>ON_THREE</c>, or empty for Apple's loader.
    /// </param>
    /// <returns>The block.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleSosBoot(string path, string symbol)
    {
        if (symbol.Length == 0) { return Assemble(path, SosBootOrigin, SosBootSize); }

        // Another build sets its symbol and includes the source, from beside it.
        string wrapper = Path.Join(Path.GetDirectoryName(Path.GetFullPath(path)), $"_{symbol}.asm");
        return Assemble(wrapper, SosBootOrigin, SosBootSize, $"{symbol} = 1\n.include \"SosBoot.asm\"\n");
    }

    /// <summary>
    ///  Builds SOS 1.3's SOS.KERNEL file from the SDK's source, for a disk.
    /// </summary>
    /// <param name="directory">The SDK ROM directory, or null for the copy beside the debug host.</param>
    /// <returns>The file's 22,016 bytes, which start with its label, <c>SOS KRNL</c>.</returns>
    /// <exception cref="FileNotFoundException">
    ///  The Apple III sources (the directory, or its <c>Apple3</c> folder when it has no <c>BootRom.asm</c>) have no
    ///  <c>Sos/SosKernel.asm</c>.
    /// </exception>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static byte[] BuildSosKernel(string? directory) =>
        AssembleSosKernel(SourcePath(directory, "SosKernel.asm")).Sections[0].Bytes.ToArray();

    /// <summary>
    ///  Builds SOS's bootstrap loader from the SDK's source, Apple's SOS BOOT 1.1, for block 0 of a disk.
    /// </summary>
    /// <param name="directory">The SDK ROM directory, or null for the copy beside the debug host.</param>
    /// <returns>The block's 512 bytes.</returns>
    /// <exception cref="FileNotFoundException">
    ///  The Apple III sources (the directory, or its <c>Apple3</c> folder when it has no <c>BootRom.asm</c>) have no
    ///  <c>Sos/SosBoot.asm</c>.
    /// </exception>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static byte[] BuildSosBoot(string? directory) =>
        AssembleSosBoot(SourcePath(directory, "SosBoot.asm"), "").Sections[0].Bytes.ToArray();

    /// <summary>
    ///  Builds SOS.DRIVER's header from the SDK's source, <c>Sos/SosDriverHeader.asm</c>: the built-in drives,
    ///  Apple's STANDARD character set and its SHOLES keyboard layout.
    /// </summary>
    /// <param name="directory">The SDK ROM directory, or null for the copy beside the debug host.</param>
    /// <param name="drives">The number of built-in floppy drives SOS is to configure, 1-4.</param>
    /// <returns>The header's <see cref="SosDriverFile.HeaderSize"/> bytes, after its count.</returns>
    /// <exception cref="ArgumentOutOfRangeException">The drive count is not 1-4.</exception>
    /// <exception cref="FileNotFoundException">
    ///  The Apple III sources (the directory, or its <c>Apple3</c> folder when it has no <c>BootRom.asm</c>) have no
    ///  <c>Sos/SosDriverHeader.asm</c>.
    /// </exception>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static byte[] BuildSosDriverHeader(string? directory, int drives)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(drives, 1);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(drives, 4);
        string path = SourcePath(directory, "SosDriverHeader.asm");
        string wrapper = Path.Join(Path.GetDirectoryName(path), "_DRIVES.asm");
        return Assemble(wrapper, 0, SosDriverFile.HeaderSize, $"DRIVES = {drives}\n.include \"SosDriverHeader.asm\"\n")
            .Sections[0].Bytes.ToArray();
    }

    /// <summary>
    ///  Builds a SOS driver from the SDK's source in <c>Sos/Drivers</c>, as SOS.DRIVER holds it: its comment, its
    ///  code at origin 0, and the offsets of the words SOS relocates.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The source is assembled at two origins. Its code is the first build's, after the comment record
    ///   (<c>$FFFF</c>, a length and the comment's text) when it starts with one, up to the last byte it emits and
    ///   padded with a 0 to a whole number of words from the start of the record, as Apple's assembler padded it;
    ///   the words to relocate are those that differ by the distance between the origins. SOS relocates only words, so a
    ///   driver keeps no byte of its own address alone, such as an immediate high byte; such a byte would read as a
    ///   word with the byte before it.
    ///  </para>
    /// </remarks>
    /// <param name="directory">The SDK ROM directory, or null for the copy beside the debug host.</param>
    /// <param name="folder">The driver's folder, which holds its root of the same name, such as <c>Console</c>.</param>
    /// <param name="define">
    ///  A symbol to set to 1 for a build other than the default, such as <c>RELEASE_130</c> for the console's 1.30,
    ///  or empty.
    /// </param>
    /// <returns>The driver.</returns>
    /// <exception cref="FileNotFoundException">The SDK has no source for the driver.</exception>
    /// <exception cref="InvalidDataException">
    ///  The source has errors, emits no code, or its comment record runs past what it emits.
    /// </exception>
    internal static SosDriver BuildSosDriver(string? directory, string folder, string define = "")
    {
        ArgumentException.ThrowIfNullOrEmpty(folder);
        ArgumentNullException.ThrowIfNull(define);
        string root = SourcePath(directory, Path.Join("Drivers", folder, folder + ".asm"));
        (byte[] code, string comment) = DriverCode(AssembleDriver(root, define, 0));
        (byte[] moved, _) = DriverCode(AssembleDriver(root, define, DriverShift));
        if (moved.Length != code.Length)
        {
            throw new InvalidDataException($"The driver {folder} assembles to different lengths at different origins.");
        }

        List<int> relocations = [];
        for (int offset = 0; offset + 1 < code.Length; offset++)
        {
            int word = code[offset] | (code[offset + 1] << 8);
            int movedWord = moved[offset] | (moved[offset + 1] << 8);
            if (((movedWord - word) & 0xFFFF) == DriverShift) { relocations.Add(offset); }
        }

        return new SosDriver(comment, code, [.. relocations]);
    }

    /// <summary>
    ///  Builds a SOS.DRIVER file from the SDK's sources: the header, then each driver.
    /// </summary>
    /// <param name="directory">The SDK ROM directory, or null for the copy beside the debug host.</param>
    /// <param name="drives">The number of built-in floppy drives SOS is to configure, 1-4.</param>
    /// <param name="folders">
    ///  The drivers' folders in <c>Sos/Drivers</c>, in the order SOS is to load them, such as <c>Console</c>; SOS
    ///  needs the console's. The built-in disk's driver, <c>.D1</c> to <c>.D4</c>, is in the kernel.
    /// </param>
    /// <returns>The file.</returns>
    /// <exception cref="ArgumentException">There are no drivers.</exception>
    /// <exception cref="ArgumentOutOfRangeException">The drive count is not 1-4.</exception>
    /// <exception cref="FileNotFoundException">The SDK has no source for the header or a driver.</exception>
    /// <exception cref="InvalidDataException">A source has errors.</exception>
    internal static byte[] BuildSosDriverFile(string? directory, int drives, IReadOnlyList<string> folders)
    {
        ArgumentNullException.ThrowIfNull(folders);
        byte[] header = BuildSosDriverHeader(directory, drives);
        return SosDriverFile.Write(header, [.. folders.Select(folder => BuildSosDriver(directory, folder))]);
    }

    // The distance between the two origins a driver is assembled at: a whole number of pages, so that a source
    // that aligns to a page assembles the same.
    private const int DriverShift = 0x1000;

    // The space a driver's code may take.
    private const int DriverSpace = 0x8000;

    private static AssemblyResult AssembleDriver(string root, string define, int origin)
    {
        if (define.Length == 0) { return Assemble(root, origin, DriverSpace); }
        string wrapper = Path.Join(Path.GetDirectoryName(root), $"_{define}.asm");
        return Assemble(wrapper, origin, DriverSpace, $"{define} = 1\n.include \"{Path.GetFileName(root)}\"\n");
    }

    // A driver's code, after its comment record when it has one, up to the last byte its source emits and padded
    // to a word, and the comment.
    private static (byte[] Code, string Comment) DriverCode(AssemblyResult result)
    {
        ReadOnlySpan<byte> bytes = result.Sections[0].Bytes.Span;
        int end = result.SourceMap.Where(entry => entry.Section == 0).Select(entry => entry.Offset + entry.Size).DefaultIfEmpty(0).Max();
        int start = 0;
        string comment = "";
        if (end >= 4 && bytes[0] == 0xFF && bytes[1] == 0xFF)
        {
            int size = bytes[2] | (bytes[3] << 8);
            if (4 + size > end) { throw new InvalidDataException("The driver's comment record runs past its code."); }
            comment = Encoding.ASCII.GetString(bytes.Slice(4, size));
            start = 4 + size;
        }

        if (end <= start) { throw new InvalidDataException("The driver's source emits no code."); }

        // Apple's assembler padded the comment record and code to a whole number of words, and SOS.DRIVER keeps the
        // pad byte.
        byte[] code = new byte[(end + 1 & ~1) - start];
        bytes[start..end].CopyTo(code);
        return (code, comment);
    }

    // A source in the Apple III's Sos folder, which must be there.
    private static string SourcePath(string? directory, string file)
    {
        string path = Path.Join(Directory(directory), "Sos", file);
        return File.Exists(path) ? path : throw new FileNotFoundException($"The SDK has no SOS source {path}.", path);
    }

    /// <summary>
    ///  Where the boot ROM reads a SOS disk's block 0.
    /// </summary>
    internal const int SosBootOrigin = 0xA000;

    /// <summary>
    ///  The size of a block.
    /// </summary>
    internal const int SosBootSize = 512;

    /// <summary>
    ///  Assembles Business BASIC 1.23's interpreter, the SOS.INTERP file, from its header at <c>$51F2</c>.
    /// </summary>
    /// <param name="path">The <c>BusinessBasic.asm</c> source.</param>
    /// <returns>The file.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleBusinessBasic(string path) =>
        Assemble(path, BusinessBasicOrigin, BusinessBasicSize);

    /// <summary>
    ///  Where Business BASIC 1.23's SOS.INTERP starts: its 14-byte header, before the code it loads at <c>$5200</c>.
    /// </summary>
    internal const int BusinessBasicOrigin = 0x51F2;

    /// <summary>
    ///  The size of Business BASIC 1.23's SOS.INTERP file.
    /// </summary>
    internal const int BusinessBasicSize = 25963;

    /// <summary>
    ///  Assembles the SoftCard ///'s 256-byte address mapping PROM.
    /// </summary>
    /// <param name="path">The <c>SoftCard3Prom.asm</c> source.</param>
    /// <returns>The PROM's bytes.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static byte[] AssembleSoftCard3Prom(string path) =>
        Assemble(path, 0, SoftCard3PromSize, cpu: "Z80").Sections[0].Bytes.ToArray();

    /// <summary>
    ///  The size of the SoftCard ///'s mapping PROM.
    /// </summary>
    internal const int SoftCard3PromSize = 0x100;

    private static AssemblyResult Assemble(string path, int origin, int size, string? text = null, string cpu = "Mos6502")
    {
        string full = Path.GetFullPath(path);
        AssemblyOptions options = new(cpu, origin, size)
        {
            SourceResolver = new FileAssemblySourceResolver()
        };

        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource(text ?? File.ReadAllText(full), full), options);
        return result.Success
            ? result
            : throw new InvalidDataException(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic => diagnostic.Message)));
    }
}
