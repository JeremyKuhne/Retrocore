// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

/// <summary>
///  A revision of an image file: its length, when it was last written, and its SHA-256. Two revisions are the same
///  file when their lengths and hashes match; the time is shown, not compared.
/// </summary>
/// <param name="Length">The file's length in bytes.</param>
/// <param name="Written">When it was last written, in UTC.</param>
/// <param name="Sha256">Its SHA-256, in lower-case hexadecimal.</param>
internal sealed record FileRevision(long Length, DateTime Written, string Sha256)
{
    /// <summary>
    ///  Gets the revision of a file's bytes just read.
    /// </summary>
    /// <param name="path">The file.</param>
    /// <param name="bytes">Its bytes.</param>
    /// <returns>The revision.</returns>
    internal static FileRevision Of(string path, ReadOnlySpan<byte> bytes) =>
        new(bytes.Length, File.GetLastWriteTimeUtc(path), Convert.ToHexStringLower(SHA256.HashData(bytes)));

    /// <summary>
    ///  Reads a file's revision as it is now.
    /// </summary>
    /// <param name="path">The file.</param>
    /// <returns>The revision, or null when there is no such file.</returns>
    internal static FileRevision? Read(string path)
    {
        if (!File.Exists(path)) { return null; }
        using FileStream stream = new(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        return new(stream.Length, File.GetLastWriteTimeUtc(path), Convert.ToHexStringLower(SHA256.HashData(stream)));
    }

    /// <summary>
    ///  Gets whether another revision is the same file: the same length and hash.
    /// </summary>
    /// <param name="other">The other revision, or null for no file.</param>
    /// <returns>True when they are the same.</returns>
    internal bool SameAs(FileRevision? other) => other is not null && other.Length == Length && other.Sha256 == Sha256;

    /// <summary>
    ///  Writes the revision as the protocol gives it.
    /// </summary>
    /// <returns><c>{ length, written, sha256 }</c>.</returns>
    internal JsonObject ToJson() => new()
    {
        ["length"] = Length,
        ["written"] = Written.ToString("O", System.Globalization.CultureInfo.InvariantCulture),
        ["sha256"] = Sha256,
    };
}
