// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Documentation;

namespace Retrocore.Debug.Language;

/// <summary>
///  The text of the source files one or more analyses read from disk, each file read once and split into lines once.
/// </summary>
/// <remarks>
///  <para>
///   The assembly reads each included file, and the analysis reads it again for its lines; the SDK's roots share
///   files too, as AppleSoft and PET BASIC share Microsoft's BASIC. A cache lives for one analysis, or for one build of
///   the SDK index, so a file changed on disk is read again by the next one. It is for one thread at a time.
///  </para>
///  <para>
///   The assembly's documentation pass, the analysis and the editor's documentation parse all read a file's lines, so
///   one split is shared by every one of them and every root that includes the file. The arrays are only read.
///  </para>
///  <para>
///   Every assembly that includes a file gets the same <see cref="AssemblySource"/>, which reads its <c>Also:</c>
///   names once for all of them.
///  </para>
/// </remarks>
internal sealed class SourceFileCache
{
    // By the full path, as resolved; a null value is a file that was not found.
    private readonly Dictionary<string, string?> _texts = [with(StringComparer.Ordinal)];

    // By the full path, for the texts above that have been split.
    private readonly Dictionary<string, string[]> _lines = [with(StringComparer.Ordinal)];

    // By the full path, for the texts above that an assembly has included.
    private readonly Dictionary<string, AssemblySource> _sources = [with(StringComparer.Ordinal)];

    /// <summary>
    ///  Reads a file the assembly includes, as <see cref="Assembler.FileAssemblySourceResolver"/> reads it.
    /// </summary>
    /// <param name="path">The full path.</param>
    /// <returns>The text, or null when the file or its folder does not exist.</returns>
    internal string? TryRead(string path)
    {
        if (_texts.TryGetValue(path, out string? text)) { return text; }
        try
        {
            text = File.ReadAllText(path);
        }
        catch (Exception missing) when (missing is FileNotFoundException or DirectoryNotFoundException)
        {
            text = null;
        }

        _texts[path] = text;
        return text;
    }

    /// <summary>
    ///  Reads a file that must exist, such as the root.
    /// </summary>
    /// <param name="path">The full path.</param>
    /// <returns>The text.</returns>
    /// <exception cref="IOException">
    ///  The file can't be read, as <see cref="File.ReadAllText(string)"/> throws.
    /// </exception>
    internal string Read(string path)
    {
        if (_texts.TryGetValue(path, out string? text) && text is not null) { return text; }
        _texts[path] = text = File.ReadAllText(path);
        return text;
    }

    /// <summary>
    ///  Reads a file when it exists.
    /// </summary>
    /// <param name="path">The full path.</param>
    /// <returns>The text, or null when there is no file at the path.</returns>
    internal string? ReadIfExists(string path) =>
        _texts.TryGetValue(path, out string? text) ? text : File.Exists(path) ? TryRead(path) : null;

    /// <summary>
    ///  Reads a file the assembly includes as a source shared by every assembly that includes it, as
    ///  <see cref="TryRead"/> reads it.
    /// </summary>
    /// <param name="path">The full path, which the source is named by.</param>
    /// <returns>The source, or null when the file or its folder does not exist.</returns>
    internal AssemblySource? TryReadSource(string path)
    {
        if (_sources.TryGetValue(path, out AssemblySource? source)) { return source; }
        if (TryRead(path) is not { } text) { return null; }
        _sources[path] = source = new AssemblySource(text, LinesOf(path, text), path);
        return source;
    }

    /// <summary>
    ///  Reads a file's lines when it exists, as <see cref="ReadIfExists"/> reads it.
    /// </summary>
    /// <param name="path">The full path.</param>
    /// <returns>The lines, or null when there is no file at the path.</returns>
    internal string[]? ReadLinesIfExists(string path) => ReadIfExists(path) is { } text ? LinesOf(path, text) : null;

    // The lines of the text this cache holds for the path, split the first time.
    private string[] LinesOf(string path, string text)
    {
        if (!_lines.TryGetValue(path, out string[]? lines)) { _lines[path] = lines = DocumentationParser.Lines(text); }
        return lines;
    }
}
