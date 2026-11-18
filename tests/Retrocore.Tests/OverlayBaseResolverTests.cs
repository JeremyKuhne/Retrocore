// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;

namespace Retrocore.Tests;

/// <summary>
///  The PET's BASIC overlays find Microsoft's base where the shipped SDK keeps it, and <c>--define</c> takes 64-bit
///  values.
/// </summary>
[TestClass]
public sealed class OverlayBaseResolverTests
{
    /// <summary>
    ///  Laid out as the host ships the SDK, <c>Sdk/Roms/Pet</c> beside <c>Sdk/Roms/AppleSoft</c>, an overlay's base is
    ///  not where it names it; the resolver finds it, and plain files do not.
    /// </summary>
    [TestMethod]
    public void TheShippedOverlayFindsItsBase()
    {
        string sdk = Directory.CreateTempSubdirectory("retrocore-sdk").FullName;
        try
        {
            string roms = Path.Join(sdk, "Roms");
            Copy(Path.Join(AppContext.BaseDirectory, "Inputs", "Pet"), Path.Join(roms, "Pet"));
            Directory.CreateDirectory(Path.Join(roms, "AppleSoft"));
            File.Copy(
                Path.Join(AppContext.BaseDirectory, "Inputs", "AppleSoft", OverlayBaseResolver.BaseName),
                Path.Join(roms, "AppleSoft", OverlayBaseResolver.BaseName));

            string path = Path.Join(roms, "Pet", "Basic", "Basic2.mac");
            AssemblySource source = new(File.ReadAllText(path), path);
            Assembler.Assembler assembler = new();

            AssemblyResult plain = assembler.Assemble(source, Options(new FileAssemblySourceResolver()));
            plain.Success.Should().BeFalse();
            plain.Diagnostics.Should().Contain(diagnostic => diagnostic.Message.Contains("Cannot resolve overlay base", StringComparison.Ordinal));

            AssemblyResult shipped = assembler.Assemble(source, Options(new OverlayBaseResolver(Path.Join(roms, "AppleSoft"))));
            shipped.Success.Should().BeTrue(string.Join('\n', shipped.Diagnostics.Select(diagnostic => diagnostic.Message)));
        }
        finally
        {
            Directory.Delete(sdk, recursive: true);
        }

        static AssemblyOptions Options(IAssemblySourceResolver resolver) => new(ProcessorVariant.Mos6502, 0, 0x10000)
        {
            SourceResolver = resolver
        };

        static void Copy(string from, string to)
        {
            foreach (string file in Directory.EnumerateFiles(from, "*", SearchOption.AllDirectories))
            {
                string target = Path.Join(to, Path.GetRelativePath(from, file));
                Directory.CreateDirectory(Path.GetDirectoryName(target) ?? to);
                File.Copy(file, target);
            }
        }
    }

    /// <summary>
    ///  Only the base falls back, by its file name; any other source not found stays not found.
    /// </summary>
    [TestMethod]
    public void OnlyTheBaseFallsBack()
    {
        string folder = Path.Join(AppContext.BaseDirectory, "Inputs", "AppleSoft");
        OverlayBaseResolver resolver = new(folder);
        string from = Path.Join(AppContext.BaseDirectory, "nowhere", "Basic2.mac");
        resolver.TryResolve(from, "../../Apple2/m6502.asm", out AssemblySource? found).Should().BeTrue();
        found?.Path.Should().Be(Path.GetFullPath(Path.Join(folder, OverlayBaseResolver.BaseName)));
        resolver.TryResolve(from, "applesoft.mac", out _).Should().BeFalse("only the base falls back");
        OverlayBaseResolver.Fallback("Equates.asm", folder).Should().BeNull();
    }

    /// <summary>
    ///  A definition takes a 64-bit value in decimal, <c>$</c> or <c>0x</c>, or is 1 with no value; a malformed one is
    ///  refused rather than thrown.
    /// </summary>
    /// <param name="text">The definition.</param>
    /// <param name="name">The symbol, or null when refused.</param>
    /// <param name="value">Its value.</param>
    [TestMethod]
    [DataRow("REVISD", "REVISD", 1L)]
    [DataRow("REVISD=0", "REVISD", 0L)]
    [DataRow("LIMIT=2147483648", "LIMIT", 2_147_483_648L)]
    [DataRow("MASK=0x80000000", "MASK", 0x8000_0000L)]
    [DataRow("MASK=$FFFFFFFF", "MASK", 0xFFFF_FFFFL)]
    [DataRow("LOW=-1", "LOW", -1L)]
    [DataRow("REVISD=", null, 0L)]
    [DataRow("=1", null, 0L)]
    [DataRow("X=$", null, 0L)]
    [DataRow("X=twelve", null, 0L)]
    public void DefinitionsTake64BitValues(string text, string? name, long value)
    {
        bool parsed = DefineArgument.TryParse(text, out string parsedName, out long parsedValue);
        parsed.Should().Be(name is not null);
        if (name is null) { return; }
        parsedName.Should().Be(name);
        parsedValue.Should().Be(value);
    }
}
