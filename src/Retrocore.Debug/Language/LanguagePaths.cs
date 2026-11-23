// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;

namespace Retrocore.Debug.Language;

/// <summary>
///  Path rules shared with the assembler's file resolver.
/// </summary>
internal static class LanguagePaths
{
    /// <summary>
    ///  Resolves an include request relative to the including file, with the assembler's own rule, so the editor
    ///  names a file by the path the assembler reads it from.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A rooted request replaces the including file's folder, as <see cref="Path.Combine(string, string)"/> lets
    ///   it: on Windows, <c>\lib\X.asm</c> is at the root of the current directory's drive and <c>C:X.asm</c> on
    ///   drive C, not under the including folder.
    ///  </para>
    /// </remarks>
    /// <param name="fromPath">The including file, or empty.</param>
    /// <param name="request">The requested path.</param>
    /// <returns>The full path.</returns>
    internal static string Resolve(string fromPath, string request) => AssemblySourcePaths.Resolve(fromPath, request);
}
