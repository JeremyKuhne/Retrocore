// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Language;

/// <summary>
///  The text of the source files one or more analyses read from disk, each file read once.
/// </summary>
/// <remarks>
///  <para>
///   The assembly reads each included file, and the analysis reads it again for its lines; the SDK's roots share
///   files too, as AppleSoft and PET BASIC share Microsoft's BASIC. A cache lives for one analysis, or for one build of
///   the SDK index, so a file changed on disk is read again by the next one. It is for one thread at a time.
///  </para>
/// </remarks>
internal sealed class SourceFileCache
{
    // By the full path, as resolved; a null value is a file that was not found.
    private readonly Dictionary<string, string?> _texts = [with(StringComparer.Ordinal)];

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
}
