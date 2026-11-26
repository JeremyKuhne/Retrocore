// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using Retrocore.Debug;

namespace Retrocore.Tests;

/// <summary>
///  The <c>--model100</c> command on a RAM image, and host files read as Model 100 files.
/// </summary>
[TestClass]
public sealed class Model100CommandTests
{
    /// <summary>
    ///  A host file is read as its kind: the Model 100's own files as they are, BASIC text tokenized, plain text with CR
    ///  LF lines; its name comes from the file, a <c>.model100.bas</c> one's without the dialect.
    /// </summary>
    [TestMethod]
    public void HostFilesAreReadByKind()
    {
        string folder = Folder();
        try
        {
            string basic = Path.Join(folder, "game.model100.bas");
            File.WriteAllText(basic, "10 PRINT \"HI\"\n");
            (string name, byte[] bytes) = Model100Command.FromHost(basic);
            name.Should().Be("GAME.BA");
            BasicProgram.FromImage(BasicDialect.Model100, bytes).ToText().Should().Be("10 PRINT \"HI\"\n");

            string text = Path.Join(folder, "notes.txt");
            File.WriteAllText(text, "a\nb\n");
            (string textName, byte[] textBytes) = Model100Command.FromHost(text);
            textName.Should().Be("NOTES.DO");
            textBytes.Should().Equal("a\r\nb\r\n"u8.ToArray());
            Model100Command.FromHost(text, "other.do").Name.Should().Be("OTHER.DO");

            string raw = Path.Join(folder, "mc.co");
            File.WriteAllBytes(raw, [1, 2, 3]);
            Model100Command.FromHost(raw).Bytes.Should().Equal(1, 2, 3);

            string unknown = Path.Join(folder, "x.bin");
            File.WriteAllBytes(unknown, [0]);
            ((Action)(() => Model100Command.FromHost(unknown))).Should().Throw<ArgumentException>().WithMessage("*.ba, .do, .co, .bas or .txt*");
            string longName = Path.Join(folder, "toolong.txt");
            File.WriteAllText(longName, "x");
            ((Action)(() => Model100Command.FromHost(longName))).Should().Throw<ArgumentException>().WithMessage("*TOOLONG.DO is not*");
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  The command adds, lists, extracts and removes files in a RAM image, leaves the image as it was when a change
    ///  fails, and refuses an image of the wrong size.
    /// </summary>
    [TestMethod]
    public void CommandChangesTheImage()
    {
        string folder = Folder();
        try
        {
            string image = Path.Join(folder, "m100.ram");
            File.WriteAllBytes(image, Model100FilesTests.ColdStart()[0x8000..]);
            string basic = Path.Join(folder, "prog.bas");
            File.WriteAllText(basic, "10 ?\"HI\":A=1'C\n");
            string notes = Path.Join(folder, "note.txt");
            File.WriteAllText(notes, "ABC\n");

            Model100Command.Run(["add", image, basic]).Should().Be(0);
            Model100Command.Run(["add", image, notes]).Should().Be(0);
            Model100Files files = new(Model100Command.Memory(File.ReadAllBytes(image)));
            files.List().Select(file => file.Name).Should().Equal("PROG.BA", "NOTE.DO");
            files.Read("NOTE.DO").Should().Equal("ABC\r\n\x1A"u8.ToArray());

            string listing = Path.Join(folder, "listing.bas");
            Model100Command.Run(["extract", image, "prog.ba", listing, "--list"]).Should().Be(0);
            File.ReadAllText(listing).Should().Be("' retrocore model100\n10 PRINT\"HI\":A=1'C\n");
            string copy = Path.Join(folder, "prog.ba");
            Model100Command.Run(["extract", image, "PROG.BA", copy]).Should().Be(0);
            File.ReadAllBytes(copy).Should().Equal(files.Read("PROG.BA"));

            byte[] before = File.ReadAllBytes(image);
            Model100Command.Run(["delete", image, "GONE.DO"]).Should().Be(1);
            Model100Command.Run(["add", image, notes, "1BAD.DO"]).Should().Be(1);
            File.ReadAllBytes(image).Should().Equal(before, "a failed change leaves the image");
            Model100Command.Run(["delete", image, "NOTE.DO"]).Should().Be(0);
            new Model100Files(Model100Command.Memory(File.ReadAllBytes(image))).List().Select(file => file.Name).Should().Equal("PROG.BA");
            Directory.GetFiles(folder, "*.tmp").Should().BeEmpty();

            string small = Path.Join(folder, "small.ram");
            File.WriteAllBytes(small, new byte[100]);
            Model100Command.Run(["files", small]).Should().Be(1);
            Model100Command.Run(["unknown"]).Should().Be(2);
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    private static string Folder()
    {
        string folder = Path.Join(Path.GetTempPath(), $"retrocore-model100-{Guid.NewGuid():N}");
        Directory.CreateDirectory(folder);
        return folder;
    }
}
