// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Machines.Apple2;
using Retrocore.Media;

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
    ///  Puts an image in a ProFile: a ProDOS-order image (<c>.po</c> or <c>.hdv</c>), its 512-byte blocks in order
    ///  with no header, which the machine can write. Changes stay in memory; the file is not written.
    /// </summary>
    /// <param name="drive">The ProFile.</param>
    /// <param name="path">The image's path.</param>
    /// <exception cref="InvalidDataException">The file is not a whole number of blocks, or holds too many.</exception>
    internal static void Insert(ProFileDrive drive, string path)
    {
        path = Path.GetFullPath(path);
        long length = new FileInfo(path).Length;
        if (length == 0 || length % 512 != 0 || length / 512 > MaximumBlocks)
        {
            throw new InvalidDataException(
                $"{Path.GetFileName(path)} is not a ProDOS-order block image: it must be 1 to {MaximumBlocks} whole 512-byte blocks.");
        }

        string format = Path.GetExtension(path).TrimStart('.').ToUpperInvariant();
        drive.Insert(new MemoryBlockDevice(File.ReadAllBytes(path), isReadOnly: false), path, format.Length == 0 ? "PO" : format);
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
