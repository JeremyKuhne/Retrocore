// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Machines.Commodore;

namespace Retrocore.Debug;

/// <summary>
///  Assembles the SDK's Commodore PET ROM sources: BASIC 1, 2 and 4, their screen editors and kernals, and the two
///  character ROMs.
/// </summary>
/// <remarks>
///  <para>
///   BASIC is a MACRO-10 overlay on Microsoft's <c>m6502.asm</c>, which lives in the shared
///   <c>Microsoft6502Basic</c> source folder.
///  </para>
/// </remarks>
internal static class PetSdkModules
{
    /// <summary>
    ///  Gets the address a model's BASIC starts at: <c>$C000</c>, or <c>$B000</c> for BASIC 4.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <returns>The address.</returns>
    internal static int BasicOrigin(PetModel model) => model.BasicVersion() == 4 ? 0xB000 : 0xC000;

    /// <summary>
    ///  Gets the size of a model's BASIC ROMs, to <c>$DFFF</c>: 8 KB, or 12 KB for BASIC 4.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <returns>The size.</returns>
    internal static int BasicSize(PetModel model) => 0xE000 - BasicOrigin(model);

    /// <summary>
    ///  Gets the address the screen editor starts at.
    /// </summary>
    internal const int EditorOrigin = 0xE000;

    /// <summary>
    ///  Gets the screen editor's size: 2 KB.
    /// </summary>
    internal const int EditorSize = 0x800;

    /// <summary>
    ///  Gets the address the kernal starts at.
    /// </summary>
    internal const int KernalOrigin = 0xF000;

    /// <summary>
    ///  Gets the kernal's size: 4 KB.
    /// </summary>
    internal const int KernalSize = 0x1000;

    /// <summary>
    ///  Gets a character ROM's size: 2 KB.
    /// </summary>
    internal const int CharacterRomSize = 0x800;

    /// <summary>
    ///  Gets the directory the debug host's copy of the sources is in.
    /// </summary>
    internal static string RomDirectory => Path.Join(SdkModules.RomDirectory, "Pet");

    /// <summary>
    ///  Gets the folder of a BASIC version's editor and kernal sources.
    /// </summary>
    /// <param name="model">The model, which names the version.</param>
    /// <returns><c>Basic1</c>, <c>Basic2</c> or <c>Basic4</c>.</returns>
    internal static string VersionFolder(PetModel model) => $"Basic{Version(model)}";

    /// <summary>
    ///  Gets a model's BASIC version, which names its sources: <c>Editor1.asm</c> and <c>Kernal1.asm</c> for BASIC 1,
    ///  and so on, so each is its own documentation module.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <returns>1, 2 or 4.</returns>
    internal static int Version(PetModel model) => model.BasicVersion();

    /// <summary>
    ///  Assembles a model's BASIC.
    /// </summary>
    /// <param name="directory">The PET sources' directory.</param>
    /// <param name="model">The model.</param>
    /// <param name="original">
    ///  The original chip rather than its revision: BASIC 1's 901447-01 rather than -09, or BASIC 4's 901465-19
    ///  rather than -23.
    /// </param>
    /// <returns>The assembly of the whole address space; <see cref="BasicImage"/> takes the ROM from it.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleBasic(string directory, PetModel model, bool original = false)
    {
        string path = Path.GetFullPath(Path.Join(directory, "Basic", BasicFile(model)));
        Dictionary<string, long> symbols = [];
        if (Version(model) != 2) { symbols["REVISD"] = original ? 0 : 1; }
        AssemblyOptions options = new(ProcessorVariant.Mos6502, 0, 0x10000)
        {
            SourceResolver = new OverlayBaseResolver(Path.Join(directory, "..", "Microsoft6502Basic")),
            PredefinedSymbols = symbols
        };

        return Checked(new Assembler.Assembler().Assemble(new AssemblySource(File.ReadAllText(path), path), options));
    }

    /// <summary>
    ///  Gets the file of a model's BASIC overlay.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <returns><c>Basic1.mac</c>, <c>Basic2.mac</c> or <c>Basic4.mac</c>.</returns>
    internal static string BasicFile(PetModel model) => $"Basic{Version(model)}.mac";

    /// <summary>
    ///  Takes BASIC's ROM, <c>$C000-$DFFF</c> or BASIC 4's <c>$B000-$DFFF</c>, from its assembly.
    /// </summary>
    /// <param name="result">The assembly.</param>
    /// <param name="model">The model.</param>
    /// <returns>The 8K or 12K image.</returns>
    internal static ReadOnlyMemory<byte> BasicImage(AssemblyResult result, PetModel model) =>
        result.Sections[0].Bytes.Slice(BasicOrigin(model), BasicSize(model));

    /// <summary>
    ///  Assembles a model's screen editor, <c>$E000-$E7FF</c>; BASIC 4's one source builds the graphics keyboard's
    ///  editor or, with <c>BUSINESS</c>, the business keyboard's.
    /// </summary>
    /// <param name="directory">The PET sources' directory.</param>
    /// <param name="model">The model.</param>
    /// <returns>The assembly.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleEditor(string directory, PetModel model) => Assemble(
        Path.Join(directory, VersionFolder(model), $"Editor{Version(model)}.asm"),
        EditorOrigin,
        EditorSize,
        Version(model) == 4 ? new() { ["BUSINESS"] = model.HasBusinessKeyboard() ? 1 : 0 } : []);

    /// <summary>
    ///  Builds a model's editor chip, <c>$E000-$E7FF</c>: BASIC 1 and 2 run past <c>$DFFF</c> into its first bytes,
    ///  the end of the math package, BASIC's start-up and its sign-on (to <c>$E1DD</c> in BASIC 2, <c>$E1E0</c> in
    ///  BASIC 1), and BASIC 1 keeps one more patch at <c>$E7F3-$E7F8</c>; the editor's source fills the rest. BASIC 4's
    ///  editor fills the whole chip.
    /// </summary>
    /// <param name="basic">BASIC's assembly.</param>
    /// <param name="editor">The editor's assembly.</param>
    /// <param name="model">The model.</param>
    /// <returns>The 2K image.</returns>
    internal static byte[] EditorImage(AssemblyResult basic, AssemblyResult editor, PetModel model)
    {
        byte[] image = editor.Sections[0].Bytes.ToArray();
        ReadOnlySpan<byte> all = basic.Sections[0].Bytes.Span;
        (int Start, int End)[] ranges = Version(model) switch
        {
            1 => [(0xE000, 0xE1E1), (0xE7F3, 0xE7F9)],
            2 => [(0xE000, 0xE1DE)],
            _ => []
        };

        foreach ((int start, int end) in ranges)
        {
            all[start..end].CopyTo(image.AsSpan(start - EditorOrigin));
        }

        return image;
    }

    /// <summary>
    ///  Assembles a model's kernal, <c>$F000-$FFFF</c>.
    /// </summary>
    /// <param name="directory">The PET sources' directory.</param>
    /// <param name="model">The model.</param>
    /// <returns>The assembly.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleKernal(string directory, PetModel model) =>
        Assemble(Path.Join(directory, VersionFolder(model), $"Kernal{Version(model)}.asm"), KernalOrigin, KernalSize, []);

    /// <summary>
    ///  Assembles a model's character ROM: the 2001's 901447-08 or the 2001-N's 901447-10.
    /// </summary>
    /// <param name="directory">The PET sources' directory.</param>
    /// <param name="model">The model.</param>
    /// <returns>The assembly.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleCharacters(string directory, PetModel model) => Assemble(
        Path.Join(directory, "CharacterGenerator.asm"),
        0,
        CharacterRomSize,
        new() { ["ORIGINAL"] = model == PetModel.Pet2001 ? 1 : 0 });

    /// <summary>
    ///  Builds a model's ROMs from the sources, byte-identical to its chips.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="directory">The PET sources' directory, or null for the copy beside the debug host.</param>
    /// <param name="original">
    ///  The original BASIC chip rather than its revision: BASIC 1's 901447-01 or BASIC 4's 901465-19.
    /// </param>
    /// <returns>The ROMs.</returns>
    /// <exception cref="InvalidDataException">A source has errors.</exception>
    internal static PetRoms BuildRoms(PetModel model, string? directory = null, bool original = false)
    {
        string roms = directory ?? RomDirectory;
        byte[] image = new byte[0x10000 - PetRoms.Base];
        AssemblyResult basic = AssembleBasic(roms, model, original);
        BasicImage(basic, model).Span.CopyTo(image.AsSpan(BasicOrigin(model) - PetRoms.Base));
        EditorImage(basic, AssembleEditor(roms, model), model).CopyTo(image.AsSpan(EditorOrigin - PetRoms.Base));
        AssembleKernal(roms, model).Sections[0].Bytes.Span.CopyTo(image.AsSpan(KernalOrigin - PetRoms.Base));
        return new(image, AssembleCharacters(roms, model).Sections[0].Bytes.Span);
    }

    private static AssemblyResult Assemble(string path, int origin, int size, Dictionary<string, long> symbols)
    {
        string full = Path.GetFullPath(path);
        AssemblyOptions options = new(ProcessorVariant.Mos6502, origin, size)
        {
            SourceResolver = new FileAssemblySourceResolver(),
            PredefinedSymbols = symbols
        };

        return Checked(new Assembler.Assembler().Assemble(new AssemblySource(File.ReadAllText(full), full), options));
    }

    private static AssemblyResult Checked(AssemblyResult result) => result.Success
        ? result
        : throw new InvalidDataException(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic => diagnostic.Message)));
}
