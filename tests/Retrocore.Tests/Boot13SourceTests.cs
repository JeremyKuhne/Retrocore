// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using Retrocore.Assembler;
using Retrocore.Documentation;
using Retrocore.Media;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  The System Masters' BOOT13 utilities, the 1980 masters' and the 1983 master's, against their sources.
/// </summary>
[TestClass]
public sealed class Boot13SourceTests
{
    private const string Digest1980 = "4C3740AFA7F45BCACEA171803A66FA13592C9A0FA20ADBD2961F9F85CE8C7C22";
    private const string Digest1983 = "B835FBEBE6E4E220077943767C39A98B71D45BDDB5830977BCB56ECB87CD5549";

    /// <summary>
    ///  Each source assembles byte-identically to its masters' BOOT13, without requiring the disk images, and its
    ///  documentation resolves.
    /// </summary>
    /// <param name="year">Which masters' BOOT13.</param>
    /// <param name="origin">Where it loads.</param>
    /// <param name="length">Its length.</param>
    /// <param name="digest">The SHA-256 of its bytes.</param>
    [TestMethod]
    [DataRow(1980, 0x1700, 0x08F0, Digest1980)]
    [DataRow(1983, 0x0C00, 0x0500, Digest1983)]
    public void SourceMatchesTheMaster(int year, int origin, int length, string digest)
    {
        string path = Path.Join(AppContext.BaseDirectory, "Inputs", "Software", $"Boot13.{year}.asm");
        string source = File.ReadAllText(path);
        AssemblyOptions options = new("Mos6502", origin, imageSize: length)
        {
            SourceResolver = new FileAssemblySourceResolver()
        };

        AssemblyResult result = new NativeAssembler().Assemble(new AssemblySource(source, path), options);
        result.Diagnostics.Should().BeEmpty();
        Convert.ToHexString(SHA256.HashData(result.Sections[0].Bytes.Span)).Should().Be(digest);

        DocumentationSet docs = DocumentationSet.Create([DocumentationParser.Parse(source, path)], result);
        new DocumentationResolver(docs).Check().Should().BeEmpty();
    }

    /// <summary>
    ///  With the System Masters, the file on each is the one its digest pins.
    /// </summary>
    /// <param name="master">The master's disk image.</param>
    /// <param name="origin">Where its BOOT13 loads.</param>
    /// <param name="digest">The SHA-256 of its bytes.</param>
    [TestMethod]
    [DataRow("DOS 3.3 System Master - 680-0051-00.dsk", 0x1700, Digest1980)]
    [DataRow("DOS 3.3 System Master - 680-0051-01 (1980).dsk", 0x1700, Digest1980)]
    [DataRow("DOS 3.3 System Master - 680-0210-A (1982).dsk", 0x0C00, Digest1983)]
    public void DigestIsTheMastersFile(string master, int origin, string digest)
    {
        string disk = Path.Join(ExternalTestData.Root, "iie-disks", master);
        if (!File.Exists(disk)) { Assert.Inconclusive($"The DOS 3.3 System Master ({disk}) is missing."); }

        DosFile file = DosDisk.ReadFiles(File.ReadAllBytes(disk)).Single(file => file.Name == "BOOT13");
        file.TryGetBinary(out int address, out ReadOnlyMemory<byte> data).Should().BeTrue();
        address.Should().Be(origin);
        Convert.ToHexString(SHA256.HashData(data.Span)).Should().Be(digest);
    }
}
