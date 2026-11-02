// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  The optional, cached cc65 assembler SDK is exercised without downloading or vendoring it.
/// </summary>
[TestClass]
public class Ca65SdkTests
{
    /// <summary>
    ///  Every SDK include parses in a fresh preprocessing environment.
    /// </summary>
    [TestMethod]
    public void AllSeventyFiveSdkIncludesParse()
    {
        string sdk = Sdk();
        string[] paths = Directory.GetFiles(sdk, "*.inc");
        paths.Length.Should().Be(75);
        List<string> failures = [];
        foreach (string path in paths)
        {
            AssemblyParseResult result = NativeAssembler.Parse(
                new AssemblySource(".include \"" + Path.GetFileName(path) + "\"", Path.Join(sdk, "probe.s")),
                Options(sdk));

            if (!result.Success)
            {
                IEnumerable<string> messages = result.Diagnostics.Take(3).Select(error => $"{error.Location?.Line}: {error.Message}");
                failures.Add(Path.GetFileName(path) + ": " + string.Join("; ", messages));
            }
        }

        failures.Should().BeEmpty();
    }

    /// <summary>
    ///  Every SDK's defined symbols match ld65's fully scoped debug values; unresolved interface declarations are not definitions.
    /// </summary>
    [TestMethod]
    public void AllSeventyFiveSdkSymbolTablesMatchCa65()
    {
        string sdk = Sdk();
        Ca65Toolchain tools = Ca65Toolchain.Require();
        string temporary = Directory.CreateTempSubdirectory("retrocore-ca65-sdk-").FullName;
        try
        {
            foreach (string path in Directory.GetFiles(sdk, "*.inc"))
            {
                string filename = Path.GetFileName(path);
                string prelude = filename switch
                {
                    "atari_antic.inc" => "ANTIC=$D400\n",
                    "atari_gtia.inc" => "GTIA=$D000\n",
                    "atari_pokey.inc" => "POKEY=$D200\n",
                    _ => ""
                };

                string text = prelude + ".include \"" + filename + "\"\n.code\n.export __SdkProbe\n__SdkProbe:nop\n.byte \"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789\"";
                string source = Path.Join(temporary, "probe.s");
                File.WriteAllText(source, text);
                AssemblySource? configuration = null;
                string? configPath = null;
                if (Path.GetFileName(path) == "sim65.inc")
                {
                    configPath = Path.Join(temporary, "sim65.cfg");
                    configuration = new(
                        "SYMBOLS{_peripherals:type=export,value=$FFC0;}MEMORY{MAIN:start=$1000,size=$6800,file=%O;}SEGMENTS{CODE:load=MAIN,type=rw;}",
                        configPath);

                    File.WriteAllText(configPath, configuration.Text);
                }

                Ca65Assembly reference = tools.Assemble(source, configPath, includePaths: [sdk]);
                // Interface declarations such as zeropage.inc's .globalzp names stay in the program: as in ca65, an
                // undefined .global is an unused import, not an error.
                AssemblyResult result = new NativeAssembler().Assemble(new AssemblySource(text, source), Options(sdk, configuration));
                result.Diagnostics.Should().BeEmpty(path);
                result.Files["output.bin"].ToArray().Should().Equal(reference.Bytes, path);
                reference.QualifiedSymbols.Count.Should().BeGreaterThan(0);
                foreach ((string name, long value) in reference.QualifiedSymbols)
                {
                    // ca65's built-in CPU constants are substituted as values, so they are not program symbols here.
                    if (name.StartsWith("CPU_", StringComparison.Ordinal)) { continue; }
                    result.Symbols.Should().ContainKey(name, path);
                    result.Symbols[name].Should().BeInRange(int.MinValue, uint.MaxValue, path + ": " + name);
                    // ld65 serializes negative constants as unsigned 32-bit values.
                    unchecked((uint)result.Symbols[name]).Should().Be(unchecked((uint)value), path + ": " + name);
                }
            }
        }
        finally
        {
            Directory.Delete(temporary, recursive: true);
        }
    }

    /// <summary>
    ///  Programs that load cc65 macro packages and SDK headers assemble to ca65's bytes.
    /// </summary>
    /// <param name="body">The program.</param>
    [TestMethod]
    [DataRow(".macpack generic\nadd #1\nsub #2\nbge Done\nDone:rts")]
    [DataRow(".include \"zeropage.inc\"\n.include \"apple2.inc\"\nlda #1\njsr $FDED")]
    [DataRow(".macpack cpu\n.byte <CPU_65C02, <CPU_ISET_65C02\n.if .cpu .bitand CPU_ISET_6502\n.byte 1\n.endif")]
    [DataRow(".macpack longbranch\njne Ahead\njcc Ahead\nAhead:rts")]
    public void MacroPackagesAndSdkHeadersMatchCa65(string body)
    {
        string sdk = Sdk();
        Ca65Toolchain tools = Ca65Toolchain.Require();
        string directory = Directory.CreateTempSubdirectory("retrocore-ca65-macpack-").FullName;
        try
        {
            string text = ".export Entry\nEntry:\n" + body;
            string path = Path.Join(directory, "main.s");
            File.WriteAllText(path, text);
            Ca65Assembly reference = tools.Assemble(path, includePaths: [sdk]);
            AssemblyResult result = new NativeAssembler().Assemble(new AssemblySource(text, path), Options(sdk));
            result.Diagnostics.Should().BeEmpty();
            reference.AssertMatches(result.Files["output.bin"].Span, result.Exports);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  longbranch.mac picks its short form from a location-counter condition, which is unknown before layout,
    ///  so its macros always take the valid long form here; ca65 uses beq for a nearby earlier target.
    /// </summary>
    [TestMethod]
    public void LongBranchMacrosUseTheLongFormBeforeLayout()
    {
        string sdk = Sdk();
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource(".macpack longbranch\nBack:nop\njeq Back", Path.Join(sdk, "probe.s")),
            Options(sdk));

        result.Diagnostics.Should().BeEmpty();
        result.Files["output.bin"].ToArray().Should().Equal(0xEA, 0xD0, 0x03, 0x4C, 0x00, 0x10);
    }

    private static string Sdk()
    {
        string sdk = Environment.GetEnvironmentVariable("RETROCORE_CA65_ASMINC")
            ?? Path.Join(
                ExternalTestData.Root,
                "m1-dependencies",
                "cc65-source",
                "asminc");

        if (!Directory.Exists(sdk))
        {
            Assert.Inconclusive("Set RETROCORE_CA65_ASMINC to the optional cc65 asminc directory.");
        }

        return sdk;
    }

    private static AssemblyOptions Options(
        string sdk,
        AssemblySource? configuration = null) => new(
            ProcessorVariant.Mos6502,
            0x1000,
            0x6800)
        {
        Dialect = AssemblyDialect.Ca65,
        LinkerConfiguration = configuration,
        SourceResolver = new FileAssemblySourceResolver(),
        IncludePaths = [sdk]
    };
}
