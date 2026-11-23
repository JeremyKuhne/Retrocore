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
    ///   A fully qualified request is used as it is and a relative one is joined to the including file's folder. A
    ///   Windows request rooted without being fully qualified, such as <c>\lib\X.asm</c> or <c>C:X.asm</c>, depends on
    ///   current-directory state and is rejected.
    ///  </para>
    /// </remarks>
    /// <param name="fromPath">The including file, or empty.</param>
    /// <param name="request">The requested path.</param>
    /// <returns>The full path.</returns>
    /// <exception cref="ArgumentException">The request depends on current-directory state.</exception>
    internal static string Resolve(string fromPath, string request) => AssemblySourcePaths.Resolve(fromPath, request);
}
