// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using System.Text;

namespace Retrocore.Debug;

/// <summary>
///  Retrocore's local data on this PC, shared by every host: the backups saves keep and the locks that keep two
///  hosts from writing one image at once. <c>RETROCORE_LOCAL_DATA</c> moves it, as the tests do.
/// </summary>
internal static class LocalData
{
    /// <summary>
    ///  Gets the folder: <c>RETROCORE_LOCAL_DATA</c>, or <c>Retrocore</c> in the user's local application data.
    /// </summary>
    internal static string Root => Environment.GetEnvironmentVariable("RETROCORE_LOCAL_DATA") is { Length: > 0 } root
        ? root
        : Path.Join(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Retrocore");

    /// <summary>
    ///  Gets where the one backup of an image is kept: a folder named for the image's full path, holding a file of the
    ///  image's name.
    /// </summary>
    /// <param name="image">The image's full path.</param>
    /// <returns>The backup's path.</returns>
    internal static string BackupFor(string image) => Path.Join(Root, "Backups", Key(image), Path.GetFileName(image));

    /// <summary>
    ///  Gets the lock file every Retrocore host on this PC takes before it checks and replaces an image.
    /// </summary>
    /// <param name="image">The image's full path.</param>
    /// <returns>The lock file's path.</returns>
    internal static string LockFor(string image) => Path.Join(Root, "Locks", Key(image) + ".lock");

    // A short name for a path: the start of its SHA-256, without case where the file system ignores it.
    private static string Key(string image)
    {
        string normalized = OperatingSystem.IsWindows() || OperatingSystem.IsMacOS() ? image.ToUpperInvariant() : image;
        return Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(normalized)))[..32];
    }
}
