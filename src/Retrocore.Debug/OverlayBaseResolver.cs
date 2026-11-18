// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using System.Diagnostics.CodeAnalysis;

namespace Retrocore.Debug;

/// <summary>
///  Resolves sources as files, and a source that is not where it is named, such as an overlay's base kept with
///  another machine's sources, from a fallback folder by its file name.
/// </summary>
/// <param name="fallback">The folder to look in for a source not found where it is named.</param>
internal sealed class OverlayBaseResolver(string fallback) : IAssemblySourceResolver
{
    private readonly FileAssemblySourceResolver _files = new();

    /// <inheritdoc/>
    public bool TryResolve(string fromPath, string request, [NotNullWhen(returnValue: true)] out AssemblySource? source) =>
        _files.TryResolve(fromPath, request, out source)
            || _files.TryResolve("", Path.GetFullPath(Path.Join(fallback, Path.GetFileName(request))), out source);
}
