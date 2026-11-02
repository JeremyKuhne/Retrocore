// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug.Language;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the language server's document URIs: the files they name, as VS Code writes them, and back.
/// </summary>
[TestClass]
public sealed class DocumentUriTests
{
    /// <summary>
    ///  VS Code's URIs escape the drive's colon and spaces; the path has neither escape, nor the leading slash.
    /// </summary>
    /// <param name="uri">The URI.</param>
    /// <param name="path">The file it names.</param>
    [TestMethod]
    [DataRow("file:///n%3A/repos/Retrocore/main.asm", @"n:\repos\Retrocore\main.asm")]
    [DataRow("file:///N:/repos/Retrocore/main.asm", @"N:\repos\Retrocore\main.asm")]
    [DataRow("file:///c%3A/Users/me/My%20Disks/boot.asm", @"c:\Users\me\My Disks\boot.asm")]
    [DataRow("file://server/share/rom.asm", @"\\server\share\rom.asm")]
    public void NamesTheFile(string uri, string path) => new DocumentUri(uri).GetFileSystemPath().Should().Be(path);

    /// <summary>
    ///  A file's URI names the same file again, with spaces escaped.
    /// </summary>
    [TestMethod]
    public void RoundTripsAFile()
    {
        DocumentUri uri = DocumentUri.FromFileSystemPath(@"C:\Retro Disks\Level2.asm");
        uri.Text.Should().Be("file:///C:/Retro%20Disks/Level2.asm");
        uri.GetFileSystemPath().Should().Be(@"C:\Retro Disks\Level2.asm");
    }

    /// <summary>
    ///  A document that is not a file, such as the BASIC program, has a path but no file.
    /// </summary>
    [TestMethod]
    public void AnotherSchemeIsNotAFile()
    {
        DocumentUri uri = new("retrocore-basic://0b9a/Program.level2.bas");
        uri.Path.Should().Be("/Program.level2.bas");
        Action file = () => uri.GetFileSystemPath();
        file.Should().Throw<ArgumentException>();
    }
}
