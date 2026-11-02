// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.Diagnostics;

namespace Retrocore.Generators;

/// <summary>
///  Resolves only declared AdditionalFiles, never arbitrary host files.
/// </summary>
internal sealed class AdditionalAssemblySourceResolver : IAssemblySourceResolver
{
    private readonly Dictionary<string, AdditionalText> _files = new(
        Path.DirectorySeparatorChar == '\\' ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal);
    private readonly AnalyzerConfigOptionsProvider _metadata;
    private CancellationToken _cancellation;

    /// <summary>
    ///  Indexes compiler-provided documents without reading include contents eagerly.
    /// </summary>
    /// <param name="files">Declared AdditionalFiles.</param>
    /// <param name="metadata">Per-file dialect metadata.</param>
    /// <param name="cancellation">Cancellation.</param>
    internal AdditionalAssemblySourceResolver(
        IEnumerable<AdditionalText> files,
        AnalyzerConfigOptionsProvider metadata,
        CancellationToken cancellation)
    {
        _metadata = metadata;
        _cancellation = cancellation;
        foreach (AdditionalText file in files) { _files[Path.GetFullPath(file.Path)] = file; }
    }

    /// <inheritdoc/>
    public bool TryResolve(string fromPath, string request, [NotNullWhen(returnValue: true)] out AssemblySource? source)
    {
        string path = AssemblySourcePaths.Resolve(fromPath, request);

        if (!_files.TryGetValue(Path.GetFullPath(path), out AdditionalText? file))
        {
            source = null;
            return false;
        }

        string text = file.GetText(_cancellation)?.ToString()
            ?? throw new IOException($"AdditionalFile source could not be read: {file.Path}");

        source = new(text, file.Path, Dialect(file));
        return true;
    }

    /// <summary>
    ///  Reads optional source dialect metadata shared by roots and includes.
    /// </summary>
    /// <param name="file">The AdditionalFile.</param>
    /// <returns>The resolver's dialect hint, or null.</returns>
    internal AssemblyDialect? Dialect(AdditionalText file)
    {
        bool configured = _metadata.GetOptions(file).TryGetValue("build_metadata.AdditionalFiles.RetrocoreDialect", out string? text)
            && !string.IsNullOrWhiteSpace(text);

        return configured ? ParseDialect(text ?? "") : null;
    }

    private static AssemblyDialect ParseDialect(string text) =>
        Enum.TryParse(text, ignoreCase: true, out AssemblyDialect dialect) && Enum.IsDefined(dialect)
            ? dialect : throw new AssemblyError(line: 0, $"Invalid RetrocoreDialect metadata '{text}'.");
}
