// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using System.Diagnostics.CodeAnalysis;

namespace Retrocore.Debug;

/// <summary>
///  Resolves sources and binaries as files, and Microsoft's BASIC, the base the BASIC overlays edit, from a fallback
///  folder when it is not where an overlay names it.
/// </summary>
/// <remarks>
///  <para>
///   The PET's overlays name <c>m6502.asm</c> beside AppleSoft's in the repository. In the SDK the host ships, the
///   sources sit under <c>Sdk/Roms</c>, AppleSoft's in <c>AppleSoft</c>, so the name no longer leads there. Only the
///   base falls back, by its file name: any other source not found stays not found.
///  </para>
/// </remarks>
/// <param name="fallback">The folder holding <see cref="BaseName"/>.</param>
internal sealed class OverlayBaseResolver(string fallback) : IAssemblySourceResolver, IAssemblyBinaryResolver
{
    /// <summary>
    ///  The base's file name.
    /// </summary>
    internal const string BaseName = "m6502.asm";

    private readonly FileAssemblySourceResolver _files = new();

    /// <summary>
    ///  Gets the folder of the SDK the host ships that holds the base.
    /// </summary>
    internal static string SdkFallback => Path.Join(SdkModules.SdkDirectory, "Roms", "AppleSoft");

    /// <summary>
    ///  Gets the fallback path of a request for the base, or null for any other request.
    /// </summary>
    /// <param name="request">The request.</param>
    /// <param name="folder">The folder holding the base.</param>
    /// <returns>The base's path in the folder, or null.</returns>
    internal static string? Fallback(string request, string folder) =>
        string.Equals(Path.GetFileName(request), BaseName, StringComparison.OrdinalIgnoreCase)
            ? Path.GetFullPath(Path.Join(folder, BaseName))
            : null;

    /// <inheritdoc/>
    public bool TryResolve(string fromPath, string request, [NotNullWhen(returnValue: true)] out AssemblySource? source)
    {
        if (_files.TryResolve(fromPath, request, out source)) { return true; }
        source = null;
        return Fallback(request, fallback) is { } path && _files.TryResolve("", path, out source);
    }

    /// <inheritdoc/>
    public bool TryResolveBinary(string fromPath, string request, [NotNullWhen(returnValue: true)] out byte[]? data) =>
        _files.TryResolveBinary(fromPath, request, out data);
}
