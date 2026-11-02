// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Language;

/// <summary>
///  A document's URI as the client names it, such as <c>file:///n%3A/repos/main.asm</c> or the BASIC program's
///  <c>retrocore-basic:</c> document. Two are equal when their text is.
/// </summary>
/// <param name="Text">The URI.</param>
internal sealed record DocumentUri(string Text)
{
    /// <summary>
    ///  Gets the URI's path part, such as the file name of a <c>retrocore-basic:</c> document.
    /// </summary>
    public string Path => System.Uri.TryCreate(Text, UriKind.Absolute, out Uri? uri)
        ? System.Uri.UnescapeDataString(uri.AbsolutePath)
        : Text;

    /// <summary>
    ///  Makes the URI of a file.
    /// </summary>
    /// <param name="path">The file's full path.</param>
    /// <returns>The <c>file:</c> URI.</returns>
    public static DocumentUri FromFileSystemPath(string path) => new(new Uri(System.IO.Path.GetFullPath(path)).AbsoluteUri);

    /// <summary>
    ///  Gets the file a <c>file:</c> URI names, its escapes such as <c>%3A</c> undone.
    /// </summary>
    /// <returns>The path.</returns>
    /// <exception cref="ArgumentException">The URI is not a file's.</exception>
    public string GetFileSystemPath()
    {
        if (!System.Uri.TryCreate(Text, UriKind.Absolute, out Uri? uri) || !uri.IsFile)
        {
            throw new ArgumentException($"{Text} is not a file.");
        }

        // VS Code escapes the drive's colon, as file:///n%3A/repos, which LocalPath leaves escaped.
        string path = System.Uri.UnescapeDataString(uri.AbsolutePath);
        if (path.Length >= 3 && path[0] == '/' && char.IsAsciiLetter(path[1]) && path[2] == ':') { path = path[1..]; }
        if (uri.Host.Length != 0) { path = $"//{uri.Host}{path}"; }
        return path.Replace('/', System.IO.Path.DirectorySeparatorChar);
    }

    /// <inheritdoc/>
    public override string ToString() => Text;
}
