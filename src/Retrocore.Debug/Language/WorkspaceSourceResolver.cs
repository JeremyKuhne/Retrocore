// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using System.Diagnostics.CodeAnalysis;

namespace Retrocore.Debug.Language;

/// <summary>
///  Resolves includes from the editor's open documents first, then from disk.
/// </summary>
internal sealed class WorkspaceSourceResolver : IAssemblySourceResolver, IAssemblyBinaryResolver
{
    private readonly Func<string, string?> _openText;
    private readonly FileAssemblySourceResolver _files = new();

    /// <summary>
    ///  Creates a resolver over the open documents.
    /// </summary>
    /// <param name="openText">The text of an open document by full path, or null when it is not open.</param>
    internal WorkspaceSourceResolver(Func<string, string?> openText) => _openText = openText;

    /// <summary>
    ///  Gets every path resolved so far, which the analysis treats as part of its root.
    /// </summary>
    internal HashSet<string> Resolved { get; } = [with(StringComparer.OrdinalIgnoreCase)];

    /// <inheritdoc/>
    public bool TryResolve(string fromPath, string request, [NotNullWhen(returnValue: true)] out AssemblySource? source)
    {
        string path = LanguagePaths.Resolve(fromPath, request);
        if (_openText(path) is { } text)
        {
            Resolved.Add(path);
            source = new(text, path);
            return true;
        }

        if (_files.TryResolve(fromPath, request, out source))
        {
            Resolved.Add(path);
            return true;
        }

        // A BASIC overlay's base, where the shipped SDK keeps it rather than where the overlay names it.
        if (OverlayBaseResolver.Fallback(request, OverlayBaseResolver.SdkFallback) is { } fallback)
        {
            if (_openText(fallback) is { } open)
            {
                Resolved.Add(fallback);
                source = new(open, fallback);
                return true;
            }

            if (_files.TryResolve("", fallback, out source))
            {
                Resolved.Add(fallback);
                return true;
            }
        }

        source = null;
        return false;
    }

    /// <inheritdoc/>
    public bool TryResolveBinary(string fromPath, string request, [NotNullWhen(returnValue: true)] out byte[]? data) =>
        _files.TryResolveBinary(fromPath, request, out data);
}
