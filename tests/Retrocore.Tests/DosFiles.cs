// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  Reads files from a DOS 3.3 disk image in DOS order, for tests that compare with what a disk holds.
/// </summary>
internal static class DosFiles
{
    /// <summary>
    ///  Gets the contents of each file of a type, in catalog order.
    /// </summary>
    /// <param name="disk">The image.</param>
    /// <param name="type">The file type, without the lock bit: 0 text, 1 Integer BASIC, 2 AppleSoft, 4 binary.</param>
    /// <returns>Each file's sectors, in track/sector list order.</returns>
    internal static IEnumerable<byte[]> Read(byte[] disk, int type) =>
        DosDisk.ReadFiles(disk).Where(file => (int)file.Type == type).Select(file => file.Contents.ToArray());

    /// <summary>
    ///  Gets a file's contents by name.
    /// </summary>
    /// <param name="disk">The image.</param>
    /// <param name="name">The file's name.</param>
    /// <returns>The file's sectors, in track/sector list order, or null when there is no such file.</returns>
    internal static byte[]? Find(byte[] disk, string name) =>
        DosDisk.ReadFiles(disk).FirstOrDefault(file => file.Name == name)?.Contents.ToArray();
}
