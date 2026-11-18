// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Commodore;

/// <summary>
///  A PET's ROMs: BASIC, the screen editor and the kernal, mapped from <c>$C000</c>, any option ROMs at
///  <c>$9000-$BFFF</c>, and the 2K character ROM.
/// </summary>
public sealed class PetRoms
{
    /// <summary>
    ///  The first address the ROM image covers.
    /// </summary>
    public const ushort Base = 0x9000;

    private readonly byte[] _image;
    private readonly byte[] _characters;

    /// <summary>
    ///  Constructs the ROMs from a 28K image of <c>$9000-$FFFF</c> and the character ROM.
    /// </summary>
    /// <param name="image">
    ///  <c>$9000-$FFFF</c>, with zeros where a socket is empty; the I/O at <c>$E800-$EFFF</c> hides that part.
    /// </param>
    /// <param name="characters">The 2K character ROM: two sets of 128 characters of 8 rows.</param>
    /// <exception cref="ArgumentException">An image is the wrong size.</exception>
    public PetRoms(ReadOnlySpan<byte> image, ReadOnlySpan<byte> characters)
    {
        if (image.Length != 0x10000 - Base)
        {
            throw new ArgumentException("The PET's ROM image covers $9000-$FFFF, 28,672 bytes.", nameof(image));
        }

        if (characters.Length != 0x800)
        {
            throw new ArgumentException("The PET's character ROM is 2,048 bytes.", nameof(characters));
        }

        _image = image.ToArray();
        _characters = characters.ToArray();
    }

    /// <summary>
    ///  Gets <c>$9000-$FFFF</c>.
    /// </summary>
    public ReadOnlySpan<byte> Image => _image;

    /// <summary>
    ///  Gets the character ROM.
    /// </summary>
    public ReadOnlySpan<byte> Characters => _characters;

    /// <summary>
    ///  Loads a model's ROMs from a directory holding MAME's chip files, as its <c>pet2001</c> set (BASIC 1),
    ///  <c>pet2001n</c> set (BASIC 2), <c>pet4016</c> set (BASIC 4) or <c>pet4032b</c> set (BASIC 4 with the business
    ///  keyboard) unzipped does.
    /// </summary>
    /// <param name="directory">The directory.</param>
    /// <param name="model">The model, which names the chips.</param>
    /// <param name="original">
    ///  The model's original BASIC chip rather than its revision: for BASIC 1, 901447-01 rather than 901447-09 at
    ///  <c>$C000</c>; for BASIC 4, 901465-19 rather than 901465-23 at <c>$B000</c>. BASIC 2 was never revised.
    /// </param>
    /// <returns>The ROMs.</returns>
    public static PetRoms LoadFromDirectory(string directory, PetModel model, bool original = false)
    {
        byte[] image = new byte[0x10000 - Base];
        if (model == PetModel.Pet2001)
        {
            // The static board's 2K sockets: H1 $C000, H5 $C800, H2 $D000, H6 $D800, H3 $E000, H4 $F000, H7 $F800.
            Load(original ? "901447-01.h1" : "901447-09.h1", 0xC000);
            Load("901447-02.h5", 0xC800);
            Load("901447-03.h2", 0xD000);
            Load("901447-04.h6", 0xD800);
            Load("901447-05.h3", 0xE000);
            Load("901447-06.h4", 0xF000);
            Load("901447-07.h7", 0xF800);
            return new(image, File.ReadAllBytes(Path.Join(directory, "901447-08.a2")));
        }

        if (model.BasicVersion() == 4)
        {
            // BASIC 4 fills $B000-$DFFF; the 2001-N's board takes the editor at UD8 and the kernal at UD9.
            Load(original ? "901465-19.ud5" : "901465-23.ud5", 0xB000);
            Load("901465-20.ud6", 0xC000);
            Load("901465-21.ud7", 0xD000);
            Load(model.HasBusinessKeyboard() ? "901474-02.ud8" : "901447-29.ud8", 0xE000);
            Load("901465-22.ud9", 0xF000);
            return new(image, File.ReadAllBytes(Path.Join(directory, "901447-10.uf10")));
        }

        Load("901465-01.ud6", 0xC000);
        Load("901465-02.ud7", 0xD000);
        Load("901447-24.ud8", 0xE000);
        Load("901465-03.ud9", 0xF000);
        return new(image, File.ReadAllBytes(Path.Join(directory, "901447-10.uf10")));

        void Load(string file, ushort address)
        {
            byte[] chip = File.ReadAllBytes(Path.Join(directory, file));
            chip.CopyTo(image, address - Base);
        }
    }
}
