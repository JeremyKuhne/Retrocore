// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using System.Diagnostics.CodeAnalysis;

namespace Retrocore.Debug;

/// <summary>
///  Resolves sources and binaries as files, with fallbacks for the shared Microsoft BASIC sources when repository
///  and SDK layouts differ.
/// </summary>
/// <remarks>
///  <para>
///   The overlays name the base by its repository path; the SDK ships it in
///   <c>Sdk/Roms/Microsoft6502Basic</c>. Native AppleSoft names shared modules relative to the SDK's sibling
///   folder, as do Commodore's platform definitions from their nested BASIC folder. These requests also need the
///   neutral project's folder when assembling from the repository. A repository-relative shared-module request can
///   likewise use the neighboring SDK folder when shipped.
///   Other missing sources do not fall back.
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
    internal static string SdkFallback => Path.Join(SdkModules.SdkDirectory, "Roms", "Microsoft6502Basic");

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

    /// <summary>
    ///  Gets the alternate paths for a shared BASIC source, in resolution order.
    /// </summary>
    /// <param name="fromPath">The source making the request.</param>
    /// <param name="request">The requested path.</param>
    /// <param name="fallback">The SDK folder holding the overlay base.</param>
    /// <returns>The alternate paths, after the path explicitly requested.</returns>
    internal static IEnumerable<string> Fallbacks(string fromPath, string request, string fallback)
    {
        if (RepositoryModule(fromPath, request) is { } module) { yield return module; }
        if (ModuleName(request, "../../../Retrocore.Basic/Roms/Microsoft6502Basic/") is { } name
            && NearbyShared(fromPath, name) is { } shipped)
        {
            yield return shipped;
        }

        if (Fallback(request, fallback) is not { } basePath) { yield break; }

        // Prefer the SDK copy beside the overlay, including an independently copied SDK, over the host's copy.
        if (NearbyBase(fromPath) is { } nearby && !string.Equals(nearby, basePath, StringComparison.OrdinalIgnoreCase))
        {
            yield return nearby;
        }

        yield return basePath;
    }

    private static string? RepositoryModule(string fromPath, string request)
    {
        if (fromPath.Length == 0) { return null; }
        string? name = ModuleName(request, "../Microsoft6502Basic/");
        if (name is null)
        {
            string? basic = Path.GetDirectoryName(Path.GetFullPath(fromPath));
            string? roms = basic is null ? null : Path.GetDirectoryName(basic);
            string? project = roms is null ? null : Path.GetDirectoryName(roms);
            if (string.Equals(Path.GetFileName(basic), "Basic", StringComparison.OrdinalIgnoreCase)
                && string.Equals(Path.GetFileName(roms), "Roms", StringComparison.OrdinalIgnoreCase)
                && string.Equals(Path.GetFileName(project), "Retrocore.Machines.Commodore", StringComparison.OrdinalIgnoreCase))
            {
                name = ModuleName(request, "../../Microsoft6502Basic/");
            }
        }

        if (name is null) { return null; }
        for (string? directory = Path.GetDirectoryName(Path.GetFullPath(fromPath));
            directory is not null;
            directory = Path.GetDirectoryName(directory))
        {
            string shared = Path.Join(directory, "Retrocore.Basic", "Roms", "Microsoft6502Basic");
            if (Directory.Exists(shared)) { return Path.GetFullPath(Path.Join(shared, name)); }
        }

        return null;
    }

    private static string? ModuleName(string request, string prefix)
    {
        string normalized = request.Replace('\\', '/');
        if (!normalized.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) { return null; }
        string name = normalized[prefix.Length..];
        if (name.Contains('/')
            || !name.StartsWith("MsBasic.", StringComparison.Ordinal)
            || !name.EndsWith(".asm", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        return name;
    }

    private static string? NearbyShared(string fromPath, string name)
    {
        if (fromPath.Length == 0) { return null; }
        for (string? directory = Path.GetDirectoryName(Path.GetFullPath(fromPath));
            directory is not null;
            directory = Path.GetDirectoryName(directory))
        {
            string shared = Path.Join(directory, "Microsoft6502Basic");
            if (Directory.Exists(shared)) { return Path.GetFullPath(Path.Join(shared, name)); }
        }

        return null;
    }

    private static string? NearbyBase(string fromPath)
    {
        if (fromPath.Length == 0) { return null; }
        for (string? directory = Path.GetDirectoryName(Path.GetFullPath(fromPath));
            directory is not null;
            directory = Path.GetDirectoryName(directory))
        {
            string path = Path.Join(directory, "Microsoft6502Basic", BaseName);
            if (File.Exists(path)) { return Path.GetFullPath(path); }
        }

        return null;
    }

    /// <inheritdoc/>
    public bool TryResolve(string fromPath, string request, [NotNullWhen(returnValue: true)] out AssemblySource? source)
    {
        if (_files.TryResolve(fromPath, request, out source)) { return true; }
        foreach (string path in Fallbacks(fromPath, request, fallback))
        {
            if (_files.TryResolve("", path, out source)) { return true; }
        }

        source = null;
        return false;
    }

    /// <inheritdoc/>
    public bool TryResolveBinary(string fromPath, string request, [NotNullWhen(returnValue: true)] out byte[]? data) =>
        _files.TryResolveBinary(fromPath, request, out data);
}
