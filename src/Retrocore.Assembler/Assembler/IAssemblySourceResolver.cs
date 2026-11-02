// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Resolves caller-controlled include sources without requiring filesystem access.
/// </summary>
public interface IAssemblySourceResolver
{
    /// <summary>
    ///  Resolves an include relative to its caller, or an explicit include-path candidate.
    /// </summary>
    /// <param name="fromPath">The including source path, or empty for an explicit search-path candidate.</param>
    /// <param name="request">The requested source path.</param>
    /// <param name="source">The resolved text and optional dialect metadata.</param>
    /// <returns>Whether a source was found.</returns>
    bool TryResolve(string fromPath, string request, [NotNullWhen(returnValue: true)] out AssemblySource? source);
}
