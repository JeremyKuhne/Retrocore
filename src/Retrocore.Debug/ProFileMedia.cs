// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;
using Retrocore.Media;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

/// <summary>
///  The ProFile's images and the launch option that installs ProFile cards, which the Apple II and the Apple III
///  share.
/// </summary>
internal static class ProFileMedia
{
    /// <summary>
    ///  The most blocks an image can have: ProDOS and SOS count blocks in 16 bits.
    /// </summary>
    internal const int MaximumBlocks = 65535;

    /// <summary>
    ///  Puts an image in a ProFile, in place of any there: a ProDOS-order image (<c>.po</c> or <c>.hdv</c>), its
    ///  512-byte blocks in order with no header, or a 2MG of them, which the machine can write unless a 2MG locks it.
    ///  Changes stay in memory until the host saves them. The image is read and checked before the one in the drive
    ///  comes out, so one that cannot be read leaves that one.
    /// </summary>
    /// <param name="drive">The ProFile.</param>
    /// <param name="path">The image's path.</param>
    /// <exception cref="InvalidDataException">The file is not a whole number of blocks, or holds too many.</exception>
    internal static void Insert(ProFileDrive drive, string path)
    {
        path = Path.GetFullPath(path);
        byte[] bytes = ReadImage(path);
        MemoryBlockDevice image = MemoryBlockDevice.Load(bytes);
        BlockImageCodec? codec = BlockImageCodec.ForImage(bytes, Path.GetExtension(path));
        drive.Eject();
        MediaActions.Register(image, path, codec, bytes);
        drive.Insert(image, path, codec?.Format ?? "PO");
    }

    /// <summary>
    ///  Reads a ProDOS-order image of at most <see cref="MaximumBlocks"/> blocks, checking its size before reading it,
    ///  so a file too large is refused without being loaded: its length, or for a 2MG the data its header gives.
    /// </summary>
    /// <param name="path">The image's path.</param>
    /// <returns>The file's bytes.</returns>
    /// <exception cref="InvalidDataException">The image holds more than <see cref="MaximumBlocks"/> blocks.</exception>
    internal static byte[] ReadImage(string path)
    {
        const long MostData = MaximumBlocks * 512L;
        using (FileStream file = File.OpenRead(path))
        {
            Span<byte> header = stackalloc byte[TwoImgContainer.HeaderLength];
            int read = file.ReadAtLeast(header, header.Length, throwOnEndOfStream: false);
            bool twoImg = TwoImgContainer.IsTwoImg(header[..read]);

            // A 2MG's comment and creator data follow its blocks; a megabyte is far more than any writer puts there.
            if ((twoImg ? TwoImgContainer.DataLength(header) : file.Length) > MostData || file.Length > MostData + (1 << 20))
            {
                throw new InvalidDataException(
                    $"{Path.GetFileName(path)} is not a ProDOS-order block image: it must be 1 to {MaximumBlocks} whole 512-byte blocks.");
            }
        }

        return File.ReadAllBytes(path);
    }

    /// <summary>
    ///  Reads the launch's <c>proFiles</c>: each card's slot and, optionally, its ProFile's image.
    /// </summary>
    /// <param name="args">The launch's arguments.</param>
    /// <param name="slots">The slots a card can go in, for the error message.</param>
    /// <returns>The cards, in the order given.</returns>
    /// <exception cref="ArgumentException">The option is not an array of objects with a slot.</exception>
    internal static List<(int Slot, string? Image)> LaunchCards(JsonObject args, string slots)
    {
        List<(int, string?)> cards = [];
        if (args["proFiles"] is null) { return cards; }
        if (args["proFiles"] is not JsonArray array)
        {
            throw new ArgumentException("proFiles must be an array of { slot, image }.");
        }

        foreach (JsonNode? node in array)
        {
            if (node is not JsonObject card || card.Int("slot") is not { } slot)
            {
                throw new ArgumentException($"Each of proFiles needs a slot: {slots}.");
            }

            cards.Add((slot, card.String("image")));
        }

        return cards;
    }
}
