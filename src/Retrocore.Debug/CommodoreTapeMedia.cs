// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Commodore;
using Retrocore.Media;
using Retrocore.Media.Commodore;

namespace Retrocore.Debug;

/// <summary>
///  Mounts Commodore cassette images for debugger launches and device actions.
/// </summary>
internal static class CommodoreTapeMedia
{
    /// <summary>
    ///  Reads a cassette image before replacing the tape in the Datasette, with PLAY down.
    /// </summary>
    /// <param name="deck">The Datasette.</param>
    /// <param name="path">The path to the cassette image.</param>
    internal static void Insert(CommodoreDatasette deck, string path)
    {
        string full = Path.GetFullPath(path);
        byte[] bytes = File.ReadAllBytes(full);
        string extension = Path.GetExtension(full);
        CommodoreTape tape;
        IImageCodec? codec = null;
        string format;
        if (extension.Equals(".prg", StringComparison.OrdinalIgnoreCase))
        {
            string name = Path.GetFileNameWithoutExtension(full);
            tape = CommodoreTapeBuilder.FromPrg(name.Length > 16 ? name[..16] : name, bytes);
            format = "PRG";
        }
        else if (extension.Equals(".t64", StringComparison.OrdinalIgnoreCase) || T64Format.IsT64(bytes))
        {
            tape = T64Format.Read(bytes);
            format = "T64";
        }
        else
        {
            CommodoreTapeCodec loaded;
            (tape, loaded) = CommodoreTapeCodec.Load(bytes);
            codec = loaded;
            format = loaded.Format;
        }

        // Parse before replacing the tape; PRG and T64 have no save-back codec.
        deck.Eject();
        deck.Insert(tape, full, format);
        MediaActions.Register(tape, full, codec, bytes);
        deck.Play();
    }
}
