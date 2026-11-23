// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

extern alias Generator;

using Retrocore.Assembler;
using GeneratorAssembly = Generator::Retrocore.Assembler;
using GeneratorPath = Generator::System.IO.PathExtensions;

namespace Retrocore.Tests;

/// <summary>
///  The include path rule the assembler, the ROM generator and the editor share: a fully qualified request is used
///  as it is, a relative one is joined to the including folder, and one that depends on current-directory state is
///  rejected.
/// </summary>
[TestClass]
public class AssemblySourcePathsTests
{
    /// <summary>
    ///  The generator's .NET Standard polyfills give the same results as .NET on the platform the tests run on.
    /// </summary>
    /// <param name="path1">The first path.</param>
    /// <param name="path2">The second path.</param>
    [TestMethod]
    [DataRow("", "")]
    [DataRow("", "Library.asm")]
    [DataRow("lib", "")]
    [DataRow("lib", "Library.asm")]
    [DataRow("lib/", "Library.asm")]
    [DataRow(@"lib\", "Library.asm")]
    [DataRow("lib", "/Library.asm")]
    [DataRow("lib", @"\Library.asm")]
    [DataRow("/work/lib", "/shared/Library.asm")]
    [DataRow(@"C:\work", @"D:\lib\Library.asm")]
    [DataRow(@"C:\work", "C:Library.asm")]
    [DataRow("C:", "Library.asm")]
    public void PolyfilledJoinMatchesDotNet(string path1, string path2) =>
        GeneratorPath.Join(path1, path2).Should().Be(Path.Join(path1, path2));

    /// <summary>
    ///  The generator's .NET Standard polyfill decides full qualification as .NET does on the platform the tests run
    ///  on.
    /// </summary>
    /// <param name="path">The path.</param>
    [TestMethod]
    [DataRow("")]
    [DataRow("Library.asm")]
    [DataRow("lib/Library.asm")]
    [DataRow("/")]
    [DataRow("/shared/Library.asm")]
    [DataRow(@"\")]
    [DataRow(@"\lib\Library.asm")]
    [DataRow(@"\\server\share\Library.asm")]
    [DataRow("//server/share/Library.asm")]
    [DataRow(@"\\?\C:\lib\Library.asm")]
    [DataRow(@"\?\C:\lib\Library.asm")]
    [DataRow(@"\??\C:\lib\Library.asm")]
    [DataRow("C:")]
    [DataRow("C:Library.asm")]
    [DataRow(@"C:\")]
    [DataRow(@"C:\lib\Library.asm")]
    [DataRow("C:/lib/Library.asm")]
    [DataRow(@"1:\lib\Library.asm")]
    public void PolyfilledFullQualificationMatchesDotNet(string path) =>
        GeneratorPath.IsPathFullyQualified(path).Should().Be(Path.IsPathFullyQualified(path));

    /// <summary>
    ///  The generator's polyfill applies .NET's Windows rules for full qualification on any platform, so the
    ///  Windows branch is checked where the tests run, against the results of .NET's <c>PathInternal.Windows</c>.
    /// </summary>
    /// <param name="path">The path.</param>
    /// <param name="expected">Whether .NET on Windows finds it fully qualified.</param>
    [TestMethod]
    [DataRow("", false)]
    [DataRow("Library.asm", false)]
    [DataRow(@"\", false)]
    [DataRow(@"\lib\Library.asm", false)]
    [DataRow("/lib/Library.asm", false)]
    [DataRow(@"\\server\share\Library.asm", true)]
    [DataRow("//server/share/Library.asm", true)]
    [DataRow(@"\/server", true)]
    [DataRow(@"\\?\C:\lib\Library.asm", true)]
    [DataRow(@"\?\C:\lib\Library.asm", true)]
    [DataRow(@"\??\C:\lib\Library.asm", true)]
    [DataRow("C:", false)]
    [DataRow("C:Library.asm", false)]
    [DataRow(@"C:\", true)]
    [DataRow(@"c:\lib\Library.asm", true)]
    [DataRow("C:/lib/Library.asm", true)]
    [DataRow(@"1:\lib\Library.asm", false)]
    public void PolyfilledFullQualificationFollowsWindowsRules(string path, bool expected) =>
        GeneratorPath.IsPathFullyQualified(path, windows: true).Should().Be(expected);

    /// <summary>
    ///  The generator's polyfill applies .NET's Unix rules for full qualification on any platform: only a leading
    ///  <c>/</c> qualifies.
    /// </summary>
    /// <param name="path">The path.</param>
    /// <param name="expected">Whether .NET on Unix finds it fully qualified.</param>
    [TestMethod]
    [DataRow("", false)]
    [DataRow("/", true)]
    [DataRow("/lib/Library.asm", true)]
    [DataRow(@"\lib\Library.asm", false)]
    [DataRow(@"\\server\share\Library.asm", false)]
    [DataRow(@"C:\lib\Library.asm", false)]
    public void PolyfilledFullQualificationFollowsUnixRules(string path, bool expected) =>
        GeneratorPath.IsPathFullyQualified(path, windows: false).Should().Be(expected);

    /// <summary>
    ///  The generator's polyfill joins with .NET's separators for each platform on any platform: Windows takes
    ///  either slash as a separator and adds <c>\</c>; Unix takes only <c>/</c>.
    /// </summary>
    /// <param name="path1">The first path.</param>
    /// <param name="path2">The second path.</param>
    /// <param name="windows">Whether to apply Windows rules.</param>
    /// <param name="expected">The joined path .NET gives on that platform.</param>
    [TestMethod]
    [DataRow(@"C:\work", "lib", true, @"C:\work\lib")]
    [DataRow(@"C:\work\", "lib", true, @"C:\work\lib")]
    [DataRow("C:/work/", "lib", true, "C:/work/lib")]
    [DataRow(@"C:\work", "/lib", true, @"C:\work/lib")]
    [DataRow(@"C:\work", @"\lib", true, @"C:\work\lib")]
    [DataRow("work", @"\lib", false, @"work/\lib")]
    [DataRow(@"work\", "lib", false, @"work\/lib")]
    [DataRow("/work/", "lib", false, "/work/lib")]
    public void PolyfilledJoinFollowsEachPlatformsRules(string path1, string path2, bool windows, string expected) =>
        GeneratorPath.Join(path1, path2, windows).Should().Be(expected);

    /// <summary>
    ///  Under Windows rules, a path rooted without being fully qualified depends on current-directory state and
    ///  every other path does not; under Unix rules none does. The assembler's and the generator's copies agree.
    /// </summary>
    /// <param name="path">The path.</param>
    /// <param name="expected">Whether it depends on current-directory state under Windows rules.</param>
    [TestMethod]
    [DataRow("", false)]
    [DataRow("Library.asm", false)]
    [DataRow(@"lib\Library.asm", false)]
    [DataRow(@"\", true)]
    [DataRow("/", true)]
    [DataRow(@"\lib\Library.asm", true)]
    [DataRow("/lib/Library.asm", true)]
    [DataRow(@"\\server\share\Library.asm", false)]
    [DataRow(@"\?\C:\lib\Library.asm", false)]
    [DataRow("C:", true)]
    [DataRow("C:Library.asm", true)]
    [DataRow(@"d:lib\Library.asm", true)]
    [DataRow(@"C:\lib\Library.asm", false)]
    [DataRow("C:/lib/Library.asm", false)]
    [DataRow("1:Library.asm", false)]
    public void CurrentDirectoryPathsFollowWindowsRules(string path, bool expected)
    {
        AssemblySourcePaths.DependsOnCurrentDirectory(path, windows: true).Should().Be(expected);
        GeneratorAssembly.AssemblySourcePaths.DependsOnCurrentDirectory(path, windows: true).Should().Be(expected);
        AssemblySourcePaths.DependsOnCurrentDirectory(path, windows: false).Should().BeFalse();
        GeneratorAssembly.AssemblySourcePaths.DependsOnCurrentDirectory(path, windows: false).Should().BeFalse();

        // Rooted and not fully qualified, by the polyfill's independent statement of .NET's Windows rule.
        bool rooted = path.Length > 0 && (path[0] is '\\' or '/' || (path.Length > 1 && path[1] == ':' && char.IsAsciiLetter(path[0])));
        expected.Should().Be(rooted && !GeneratorPath.IsPathFullyQualified(path, windows: true));
    }

    /// <summary>
    ///  The generator's copy of the rule resolves every request as the assembler's does, or rejects it as the
    ///  assembler's does.
    /// </summary>
    /// <param name="request">The include request.</param>
    [TestMethod]
    [DataRow("Library.asm")]
    [DataRow("../lib/Library.asm")]
    [DataRow("/shared/Library.asm")]
    [DataRow(@"\lib\Library.asm")]
    [DataRow("C:Library.asm")]
    [DataRow(@"C:\lib\Library.asm")]
    [DataRow(@"\\server\share\Library.asm")]
    public void GeneratorResolvesAsTheAssemblerDoes(string request)
    {
        string from = Path.GetFullPath(Path.Join(Path.GetTempPath(), "retrocore-paths", "program", "Main.asm"));
        bool rejected = AssemblySourcePaths.DependsOnCurrentDirectory(request);
        GeneratorAssembly.AssemblySourcePaths.DependsOnCurrentDirectory(request).Should().Be(rejected);
        if (rejected)
        {
            FluentActions.Invoking(() => GeneratorAssembly.AssemblySourcePaths.Resolve(from, request)).Should().Throw<ArgumentException>();
            return;
        }

        GeneratorAssembly.AssemblySourcePaths.Resolve(from, request).Should().Be(AssemblySourcePaths.Resolve(from, request));
    }

    /// <summary>
    ///  A relative request is joined to the including folder and a fully qualified one is used as it is.
    /// </summary>
    [TestMethod]
    public void RequestsAreJoinedUnlessFullyQualified()
    {
        string folder = Path.GetFullPath(Path.Join(Path.GetTempPath(), "retrocore-paths", "program"));
        string from = Path.Join(folder, "Main.asm");
        AssemblySourcePaths.Resolve(from, "Library.asm").Should().Be(Path.Join(folder, "Library.asm"));
        AssemblySourcePaths.Resolve(from, "../lib/Library.asm").Should().Be(Path.GetFullPath(Path.Join(folder, "..", "lib", "Library.asm")));

        string qualified = Path.GetFullPath(Path.Join(Path.GetTempPath(), "shared", "Library.asm"));
        AssemblySourcePaths.Resolve(from, qualified).Should().Be(qualified);
        AssemblySourcePaths.Combine("search", "Library.asm").Should().Be(Path.Join("search", "Library.asm"));
    }

    /// <summary>
    ///  Elsewhere than Windows, a backslash and a colon are ordinary file name characters, so neither makes a request
    ///  rooted.
    /// </summary>
    [TestMethod]
    [OSCondition(ConditionMode.Exclude, OperatingSystems.Windows)]
    public void WindowsRootsAreFileNamesElsewhere()
    {
        const string From = "/work/program/Main.asm";
        AssemblySourcePaths.Resolve(From, @"\lib\Library.asm").Should().Be(@"/work/program/\lib\Library.asm");
        AssemblySourcePaths.Resolve(From, "C:Library.asm").Should().Be("/work/program/C:Library.asm");
    }

    /// <summary>
    ///  On Windows, a request rooted without being fully qualified resolves against current-directory state, so it is
    ///  rejected; a fully qualified one is used as it is.
    /// </summary>
    /// <param name="request">The include request.</param>
    [TestMethod]
    [OSCondition(OperatingSystems.Windows)]
    [DataRow(@"\lib\Library.asm")]
    [DataRow("/lib/Library.asm")]
    [DataRow(@"\")]
    [DataRow("C:Library.asm")]
    [DataRow(@"d:lib\Library.asm")]
    [DataRow("C:")]
    public void CurrentDirectoryRequestsAreRejectedOnWindows(string request)
    {
        AssemblySourcePaths.DependsOnCurrentDirectory(request).Should().BeTrue();
        FluentActions.Invoking(() => AssemblySourcePaths.Resolve(@"C:\work\program\Main.asm", request))
            .Should().Throw<ArgumentException>().WithMessage("*relative or fully qualified*");
    }

    /// <summary>
    ///  On Windows, fully qualified requests, including UNC and device paths, are used as they are.
    /// </summary>
    [TestMethod]
    [OSCondition(OperatingSystems.Windows)]
    public void FullyQualifiedRequestsAreUsedOnWindows()
    {
        const string From = @"C:\work\program\Main.asm";
        AssemblySourcePaths.Resolve(From, @"D:\lib\Library.asm").Should().Be(@"D:\lib\Library.asm");
        AssemblySourcePaths.Resolve(From, "D:/lib/Library.asm").Should().Be(@"D:\lib\Library.asm");
        AssemblySourcePaths.Resolve(From, @"\\server\share\Library.asm").Should().Be(@"\\server\share\Library.asm");
        AssemblySourcePaths.Resolve(From, @"lib\Library.asm").Should().Be(@"C:\work\program\lib\Library.asm");
    }
}
