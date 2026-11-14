// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  Verifies cc65 debug information written for every dialect and read by the debugger.
/// </summary>
[TestClass]
public sealed class AssemblyDebugFileTests
{
    /// <summary>
    ///  Debug information for ca65 sources maps every address and source line as ld65's does, including include
    ///  files, nested macro body lines and BSS.
    /// </summary>
    /// <param name="kind">The IIe sample, or a source with nested macros and an include.</param>
    [TestMethod]
    [DataRow("sample")]
    [DataRow("macros")]
    public void Ca65DebugInfoMatchesLd65(string kind)
    {
        Ca65Toolchain toolchain = Ca65Toolchain.Require();
        string directory = Directory.CreateTempSubdirectory("retrocore-dbg-").FullName;
        try
        {
            string source;
            string config;
            if (kind == "sample")
            {
                source = Path.Join(directory, "main.s");
                config = Path.Join(directory, "link.cfg");
                File.Copy(Path.Join(AppContext.BaseDirectory, "Inputs", "IIe", "main.s"), source);
                File.Copy(Path.Join(AppContext.BaseDirectory, "Inputs", "IIe", "link.cfg"), config);
            }
            else
            {
                File.WriteAllText(
                    Path.Join(directory, "macs.inc"),
                    ".macro inner v\n    lda #v\n    sta $10\n.endmacro\n.macro outer v\n    inner v\n    inx\n.endmacro\n");

                File.WriteAllText(Path.Join(directory, "part.inc"), "sub:    ldy #1\n        rts\n");
                source = Path.Join(directory, "main.s");
                File.WriteAllText(
                    source,
                    ".include \"macs.inc\"\n.segment \"CODE\"\nstart:  outer 5\n        inner 7\n        nop\n.include \"part.inc\"\n        jmp start\n");

                config = Path.Join(directory, "link.cfg");
                File.WriteAllText(config, "MEMORY { MAIN: start=$6000, size=$1000, file=%O; }\nSEGMENTS { CODE: load=MAIN, type=ro; }\n");
            }

            SymbolTable reference = toolchain.Assemble(source, config).Symbols;
            AssemblyResult result = Assemble(source, AssemblyDialect.Ca65, config);
            SymbolTable actual = Load(result, directory);

            int mapped = 0;
            for (int address = 0; address <= ushort.MaxValue; address++)
            {
                (string Path, int Line)? expected = reference.Location((ushort)address);
                actual.Location((ushort)address).Should().Be(expected, $"address ${address:X4}");
                if (expected is not null) { mapped++; }
            }

            mapped.Should().BeGreaterThan(0);
            foreach (string file in Directory.GetFiles(directory).Where(file => file.EndsWith(".s") || file.EndsWith(".inc")))
            {
                int count = File.ReadAllLines(file).Length;
                for (int line = 1; line <= count; line++)
                {
                    actual.Addresses(file, line).Should().Equal(reference.Addresses(file, line), $"{Path.GetFileName(file)}:{line}");
                }
            }
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  Merlin debugging steps by macro call lines, breaks on macro body lines in every expansion, and maps PUT
    ///  files to their own lines.
    /// </summary>
    [TestMethod]
    public void MerlinSourcesDebugByLine()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-dbg-").FullName;
        try
        {
            string main = Path.Join(directory, "main.s");
            string part = Path.Join(directory, "part.s");
            File.WriteAllText(part, "        NOP\n");
            File.WriteAllText(
                main,
                "        ORG $6000\nTwice   MAC\n        INX\n        INX\n        EOM\nEntry   Twice\n        PUT part\n        Twice\n        RTS\n");

            SymbolTable symbols = Load(Assemble(main, AssemblyDialect.Merlin), directory);

            symbols.Location(0x6000).Should().Be((main, 6));
            symbols.Location(0x6001).Should().Be((main, 6));
            symbols.Location(0x6002).Should().Be((part, 1));
            symbols.Location(0x6003).Should().Be((main, 8));
            symbols.Location(0x6005).Should().Be((main, 9));
            symbols.Addresses(main, 3).Should().Equal(0x6000, 0x6003);
            symbols.Addresses(main, 4).Should().Equal(0x6001, 0x6004);
            symbols.Addresses(main, 6).Should().Equal(0x6000, 0x6001);
            symbols.Resolve("Entry").Should().Be(0x6000);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  Native debugging maps logical-origin code to its CPU addresses and resolves scoped names.
    /// </summary>
    [TestMethod]
    public void NativeSourcesDebugByLine()
    {
        string directory = Directory.CreateTempSubdirectory("retrocore-dbg-").FullName;
        try
        {
            string main = Path.Join(directory, "main.s");
            File.WriteAllText(
                main,
                """
                .macro pair
                  inx
                  iny
                .endmacro
                start: pair
                  .logicalorg $c000
                high: nop
                  .logicalorg
                  pair
                .proc outer
                inner: rts
                .endproc

                """);

            SymbolTable symbols = Load(Assemble(main, AssemblyDialect.Native), directory);

            symbols.Location(0x6000).Should().Be((main, 5));
            symbols.Location(0xC000).Should().Be((main, 7));
            symbols.Location(0x6002).Should().BeNull();
            symbols.Location(0x6003).Should().Be((main, 9));
            symbols.Addresses(main, 2).Should().Equal(0x6000, 0x6003);
            symbols.Resolve("high").Should().Be(0xC000);
            symbols.Resolve("outer::inner").Should().Be(0x6005);
            symbols.Resolve("inner").Should().Be(0x6005);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>
    ///  Failed assemblies have no debug information.
    /// </summary>
    [TestMethod]
    public void FailedAssembliesAreRejected()
    {
        AssemblyResult failed = new NativeAssembler().Assemble(
            new AssemblySource(" bogus"),
            new(ProcessorVariant.Mos6502, 0x6000, 0x100));

        Action write = () => AssemblyDebugFile.Write(failed, TextWriter.Null);
        write.Should().Throw<ArgumentException>();
    }

    private static AssemblyResult Assemble(string path, AssemblyDialect dialect, string? config = null)
    {
        AssemblyOptions options = new(ProcessorVariant.Mos6502, 0x6000, 0x6000)
        {
            Dialect = dialect,
            BuildTime = DateTimeOffset.UnixEpoch,
            SourceResolver = new FileAssemblySourceResolver(),
            LinkerConfiguration = config is null ? null : new(File.ReadAllText(config), config)
        };

        AssemblyResult result = new NativeAssembler().Assemble(new AssemblySource(File.ReadAllText(path), path), options);
        result.Diagnostics.Should().BeEmpty();
        return result;
    }

    /// <summary>
    ///  A VICE label file's labels apply wherever the module does, so Retrocore Memory shows them although they
    ///  have no source lines.
    /// </summary>
    [TestMethod]
    public void ViceLabelsApplyWithoutSourceLines()
    {
        string path = Path.Join(Path.GetTempPath(), $"{Guid.NewGuid():N}.lbl");
        File.WriteAllText(path, "al C:7000 .START");
        try
        {
            SymbolTable symbols = new();
            symbols.Load(path);
            IDebugModule module = new DebugFileModule(symbols);
            DebugTestMemory memory = new();
            module.Labels.Should().Contain(("START", 0x7000L));
            module.Position(memory, address: 0x7000).Should().BeNull("a VICE label has no source line");
            module.LabelApplies(memory, address: 0x7000).Should().BeTrue();
        }
        finally
        {
            File.Delete(path);
        }
    }

    /// <summary>
    ///  A debug file's constants resolve in expressions but are not memory labels, so COUNT = 3 does not name $0003.
    /// </summary>
    [TestMethod]
    public void DebugFileConstantsAreNotLabels()
    {
        SymbolTable symbols = new();
        symbols.LoadDebugInfo(
            [
                "sym\tid=0,name=\"COUNT\",addrsize=zeropage,scope=0,def=1,val=0x3,type=equ",
                "sym\tid=1,name=\"START\",addrsize=absolute,scope=0,def=2,val=0x7000,type=lab"
            ],
            Path.GetTempPath());

        DebugFileModule module = new(symbols);
        module.TryResolve("COUNT", out long count).Should().BeTrue();
        count.Should().Be(3);
        module.Labels.Should().ContainSingle().Which.Should().Be(("START", 0x7000L));
    }

    private static SymbolTable Load(AssemblyResult result, string directory)
    {
        using StringWriter writer = new();
        AssemblyDebugFile.Write(result, writer);
        SymbolTable symbols = new();
        symbols.LoadDebugInfo(writer.ToString().Split('\n'), directory);
        return symbols;
    }
}
