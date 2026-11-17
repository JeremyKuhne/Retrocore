// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  An image file as the host found it: its revision, or none when it is gone, and whether it is a read-only file.
/// </summary>
/// <param name="Current">The file's revision, or null when there is no file.</param>
/// <param name="ReadOnly">Whether the file is marked read-only.</param>
internal sealed record ImageCheck(FileRevision? Current, bool ReadOnly)
{
    /// <summary>
    ///  Reads a file as it is now.
    /// </summary>
    /// <param name="path">The file.</param>
    /// <returns>What was found, or null when the file could not be read.</returns>
    internal static ImageCheck? Of(string path)
    {
        try
        {
            return new(FileRevision.Read(path), IsReadOnly(path));
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    /// <summary>
    ///  Gets whether a file is marked read-only: the file a link leads to, as a save writes there, not the link.
    /// </summary>
    /// <param name="path">The file.</param>
    /// <returns>True when it is there and marked read-only.</returns>
    internal static bool IsReadOnly(string path)
    {
        try
        {
            string target = ImageWriter.Resolve(path);
            return File.Exists(target) && File.GetAttributes(target).HasFlag(FileAttributes.ReadOnly);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or ArgumentException)
        {
            return false;
        }
    }
}
