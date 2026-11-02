// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Resolves binary include data for .incbin, implemented alongside <see cref="IAssemblySourceResolver"/>.
/// </summary>
/// <remarks>
///  A resolver that only supplies text, such as the source generator's AdditionalFiles resolver, rejects .incbin.
/// </remarks>
public interface IAssemblyBinaryResolver
{
    /// <summary>
    ///  Resolves binary data relative to its caller, or an explicit include-path candidate.
    /// </summary>
    /// <param name="fromPath">The including source path, or empty for an explicit search-path candidate.</param>
    /// <param name="request">The requested file path.</param>
    /// <param name="data">The file's bytes.</param>
    /// <returns>Whether the file was found.</returns>
    bool TryResolveBinary(string fromPath, string request, [NotNullWhen(returnValue: true)] out byte[]? data);
}
