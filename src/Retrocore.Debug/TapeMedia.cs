// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;
using Retrocore.Media.Trs80;

namespace Retrocore.Debug;

/// <summary>
///  The tapes of the drives that record to a file named first, the TRS-80's, the Color Computer's, the Apple-1's,
///  the Altair's and the Model 100's: read from their images, and recordings started.
/// </summary>
/// <remarks>
///  <para>
///   A recording is a changed tape. Its file is written blank when the recording starts, so it is the tape's image:
///   saving the recording replaces it, as a disk's save replaces its image, and a file written there meanwhile is a
///   conflict. The file the blank replaces is kept as the image's one backup, as a save keeps it.
///  </para>
/// </remarks>
internal static class TapeMedia
{
    /// <summary>
    ///  Writes a blank tape's image at a path and registers the tape as coming from it.
    /// </summary>
    /// <param name="path">The recording's file, as the request names it.</param>
    /// <param name="tape">The blank tape.</param>
    /// <param name="codec">The codec that writes it.</param>
    /// <returns>The file's full path.</returns>
    /// <exception cref="ArgumentException">There is no path, its folder does not exist, or it is a folder.</exception>
    /// <exception cref="IOException">The file could not be written.</exception>
    internal static string Record(string? path, IMedium tape, IImageCodec codec)
    {
        string full = Path.GetFullPath(path ?? throw new ArgumentException("path is required, for saving the recording."));
        if (Directory.Exists(full) || Path.GetFileName(full).Length == 0)
        {
            throw new ArgumentException($"{full} is a folder; a recording needs a file name.");
        }

        if (!Directory.Exists(Path.GetDirectoryName(full)))
        {
            throw new ArgumentException($"The folder for {full} does not exist.");
        }

        byte[] blank = codec.Encode(tape.Snapshot()).Bytes;
        ImageWrite written = ImageWriter.Write(full, blank, FileRevision.Read(full));
        if (written.Outcome != "written")
        {
            throw new IOException($"{full} could not be written: {written.Reason ?? written.Outcome}.");
        }

        MediaActions.Register(tape, full, codec, blank);
        return full;
    }

    /// <summary>
    ///  Reads a TRS-80 or Color Computer CAS image and registers the tape as coming from it.
    /// </summary>
    /// <param name="path">The image.</param>
    /// <returns>The tape and the image's full path.</returns>
    /// <exception cref="IOException">The file could not be read.</exception>
    internal static (CassetteImage Tape, string Path) ReadCassette(string path)
    {
        string full = Path.GetFullPath(path);
        byte[] bytes = File.ReadAllBytes(full);
        CassetteImage tape = new(bytes);
        MediaActions.Register(tape, full, new CassetteCodec(), bytes);
        return (tape, full);
    }
}
