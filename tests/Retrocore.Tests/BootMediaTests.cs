// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Debug.Project;
using System.Security.Cryptography;

namespace Retrocore.Tests;

/// <summary>
///  The SDK's catalog of boot media reads, and a set's files are found by their hashes whatever they are named and
///  wherever they are below a folder, and gathered under their usual names.
/// </summary>
[TestClass]
public sealed class BootMediaTests
{
    private string _folder = "";

    /// <summary>
    ///  Gets each test a folder of its own.
    /// </summary>
    [TestInitialize]
    public void Initialize()
    {
        _folder = Path.Join(Path.GetTempPath(), "retrocore-media-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_folder);
    }

    /// <summary>
    ///  Removes the test's folder.
    /// </summary>
    [TestCleanup]
    public void Cleanup()
    {
        if (Directory.Exists(_folder)) { Directory.Delete(_folder, recursive: true); }
    }

    /// <summary>
    ///  The catalog gives the 4040's set: the three DOS 2.0 chips, the controller's ROM and the GCR PROM, at the sizes
    ///  <c>Cbm4040Roms</c> takes, each with a SHA-1.
    /// </summary>
    [TestMethod]
    public void CatalogGivesThe4040sRoms()
    {
        BootMediaSet set = BootMedia.Named(SdkModules.SdkDirectory, BasicEnvironment.DriveRoms);
        set.Files.Select(file => (file.Name, file.Size)).Should().Equal(
            ("901468-14.uj1", 0x1000), ("901468-15.ul1", 0x1000), ("901468-16.uh1", 0x1000), ("901466-04.uk3", 0x400), ("901467.uk6", 0x800));

        set.Files.Should().OnlyContain(file => file.Sha1.Length == 40 && file.Sha1.All(char.IsAsciiHexDigitLower));
        (set.Folder, set.Variable).Should().Be(("c4040", "RETROCORE_PET_ROMS"));
    }

    /// <summary>
    ///  A set's files are found by hash under other names in nested folders, past files of the same size that are not
    ///  theirs, and gathered under their usual names; with one missing the set is not found, and the message names
    ///  every file and where it was looked for.
    /// </summary>
    [TestMethod]
    public void FilesAreFoundByHashWhateverTheirNames()
    {
        byte[] first = [.. Enumerable.Range(0, 16).Select(value => (byte)value)];
        byte[] second = [.. Enumerable.Range(0, 8).Select(value => (byte)(value * 3))];
        BootMediaSet set = new("test", "the test's chips", "a test", "nowhere", Variable: null, "chips",
            [new("one.bin", 16, Sha1(first)), new("two.bin", 8, Sha1(second))]);

        Write("a/decoy.rom", new byte[16]);
        Write("a/b/renamed.rom", first);
        Dictionary<string, string>? partial = BootMedia.Find(set, [_folder]);
        partial.Should().BeNull("one file is missing");
        BootMedia.Missing(set, [_folder]).Should().StartWith($"the test's chips, for a test, were not found by their hashes in {_folder}. They are nowhere: one.bin (SHA-1 {Sha1(first)}), two.bin (SHA-1 {Sha1(second)}).");

        Write("c/other.dat", second);
        Dictionary<string, string> found = BootMedia.Find(set, [_folder]) ?? throw new AssertFailedException("The set was not found.");
        found.Should().BeEquivalentTo(new Dictionary<string, string>
        {
            ["one.bin"] = Path.Join(_folder, "a", "b", "renamed.rom"),
            ["two.bin"] = Path.Join(_folder, "c", "other.dat")
        });

        string gathered = BootMedia.Gather(set, found, Path.Join(_folder, "out"));
        gathered.Should().Be(Path.Join(_folder, "out", "chips"));
        File.ReadAllBytes(Path.Join(gathered, "one.bin")).Should().Equal(first);
        File.ReadAllBytes(Path.Join(gathered, "two.bin")).Should().Equal(second);

        // A later search may find the copies themselves, which gather in place.
        Dictionary<string, string> copies = BootMedia.Find(set, [Path.Join(_folder, "out")]) ?? throw new AssertFailedException("The copies were not found.");
        BootMedia.Gather(set, copies, Path.Join(_folder, "out")).Should().Be(gathered);
        File.ReadAllBytes(Path.Join(gathered, "one.bin")).Should().Equal(first);
    }

    /// <summary>
    ///  The folders searched are the target's <c>bootImage</c>, then the launch's ROM folder and the set's folder beside
    ///  it, then the set's variable's and the cache, those that exist, each once.
    /// </summary>
    [TestMethod]
    public void RootsAreBootImageThenTheLaunchsRomFolder()
    {
        Directory.CreateDirectory(Path.Join(_folder, "boot"));
        Directory.CreateDirectory(Path.Join(_folder, "roms"));
        BootMediaSet set = new("test", "chips", "a test", "nowhere", Variable: null, "chips", []);
        Directory.CreateDirectory(Path.Join(_folder, "chips"));
        List<string> roots = BootMedia.Roots(set, Path.Join(_folder, "boot"), Path.Join(_folder, "roms"));
        roots.Take(3).Should().Equal(Path.Join(_folder, "boot"), Path.Join(_folder, "roms"), Path.Join(_folder, "chips"));
        roots.Should().OnlyHaveUniqueItems();
        if (Directory.Exists(BootMedia.CacheDirectory)) { roots.Last().Should().Be(BootMedia.CacheDirectory); }
        BootMedia.Roots(set, Path.Join(_folder, "missing"), romDirectory: null).Should().NotContain(Path.Join(_folder, "missing"));
    }

    /// <summary>
    ///  With MAME's c4040 set in <c>RETROCORE_PET_ROMS</c>, its files match the catalog's hashes, so the lookup finds
    ///  the drive's ROMs; inconclusive without them.
    /// </summary>
    [TestMethod]
    public void The4040sDumpsMatchTheCatalog()
    {
        string drive = Path.Join(PetMachineTests.RomRoot, "c4040");
        if (!File.Exists(Path.Join(drive, "901468-14.uj1")))
        {
            Assert.Inconclusive("Set RETROCORE_PET_ROMS to a folder with MAME's c4040 set unzipped.");
        }

        BootMediaSet set = BootMedia.Named(SdkModules.SdkDirectory, BasicEnvironment.DriveRoms);
        BootMedia.Find(set, [drive]).Should().NotBeNull(BootMedia.Missing(set, [drive]));
    }

    private static string Sha1(byte[] bytes) => Convert.ToHexStringLower(SHA1.HashData(bytes));

    private void Write(string path, byte[] bytes)
    {
        string file = Path.Join(_folder, path);
        Directory.CreateDirectory(Path.GetDirectoryName(file) ?? _folder);
        File.WriteAllBytes(file, bytes);
    }
}
