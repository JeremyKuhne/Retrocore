// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;

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
    ///  Where the boot ROM reads a SOS disk's block 0.
    /// </summary>
    internal const int SosBootOrigin = 0xA000;

    /// <summary>
    ///  The size of a block.
    /// </summary>
    internal const int SosBootSize = 512;

    private static AssemblyResult Assemble(string path, int origin, int size, string? text = null)
    {
        string full = Path.GetFullPath(path);
        AssemblyOptions options = new("Mos6502", origin, size)
        {
            SourceResolver = new FileAssemblySourceResolver()
        };

        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource(text ?? File.ReadAllText(full), full), options);
        return result.Success
            ? result
            : throw new InvalidDataException(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic => diagnostic.Message)));
    }
}
