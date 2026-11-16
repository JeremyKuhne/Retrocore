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
        byte[] bytes = File.ReadAllBytes(path);
        MemoryBlockDevice image = MemoryBlockDevice.Load(bytes);
        if (image.BlockCount > MaximumBlocks)
        {
            throw new InvalidDataException(
                $"{Path.GetFileName(path)} is not a ProDOS-order block image: it must be 1 to {MaximumBlocks} whole 512-byte blocks.");
        }

        BlockImageCodec? codec = BlockImageCodec.For(Path.GetExtension(path));
        drive.Eject();
        MediaActions.Register(image, path, codec, bytes);
        drive.Insert(image, path, codec?.Format ?? "PO");
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
