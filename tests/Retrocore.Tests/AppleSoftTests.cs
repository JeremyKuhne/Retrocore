// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Machines.Apple2;
using System.Security.Cryptography;
using System.Text;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the SDK's native AppleSoft II listing and its selectable legacy source.
/// </summary>
[TestClass]
public sealed class AppleSoftTests
{
    private const int AppleSoftOffset = SdkModules.AppleSoftOrigin - 0xC000;

    private static string NativePath => Path.Join(BasicNames.Inputs, "AppleSoft", "AppleSoft.asm");
    private static string OverlayPath => Path.Join(BasicNames.Inputs, "AppleSoft", "applesoft.mac");

    /// <summary>
    ///  Both listings are byte-identical for each model, pinned by digest so no ROM is needed.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    /// <param name="expectedHash">The SHA-256 of the model's ROM at $D000-$F7FF.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus, "ED8D83176BB9445B3EAA815E07956777BDFAA9E4892A8D7F5019DEAD62434C4C")]
    [DataRow(Apple2Model.IIe, "9676882149E86EDCAA960639140BB2070439F667997A5405987B9DB8742746EB")]
    [DataRow(Apple2Model.IIeEnhanced, "498D7571F6C6A920075084B84D497619DEF48F9D5A7160A964B3B512EE5214FC")]
    public void AppleSoftSourcesMatchTheModelsRom(Apple2Model model, string expectedHash)
    {
        foreach (string source in new[] { NativePath, OverlayPath })
        {
            AssemblyResult result = SdkModules.AssembleAppleSoft(source, model);

            result.Diagnostics.Should().BeEmpty();
            ReadOnlySpan<byte> bytes = SdkModules.AppleSoftImage(result).Span;
            Convert.ToHexString(SHA256.HashData(bytes)).Should().Be(expectedHash);
        }
    }

    /// <summary>
    ///  The relocated Microsoft source keeps its pinned, LF-normalized SHA-256.
    /// </summary>
    [TestMethod]
    public void MicrosoftSourceKeepsItsPinnedSha()
    {
        string path = Path.GetFullPath(Path.Join(OverlayPath, "..", "..", "Microsoft6502Basic", "m6502.asm"));
        string source = File.ReadAllText(path).Replace("\r\n", "\n", StringComparison.Ordinal);
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(source)))
            .Should().Be("F3EC99C91DEDB8EB3441DED866F45797BB3E03ED26567A253E24CECF23CD63AC");
    }

    /// <summary>
    ///  The native listing keeps the legacy ROM's entry-point names and addresses for existing callers.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void NativeListingKeepsLegacyRomLabels(Apple2Model model)
    {
        AssemblyResult native = SdkModules.AssembleAppleSoft(NativePath, model);
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(OverlayPath, model);
        var labels = legacy.SymbolDefinitions.Where(symbol =>
            !symbol.IsConstant && symbol.Value is >= SdkModules.AppleSoftOrigin and < 0xF800);

        foreach (var label in labels)
        {
            native.SymbolsWithHistoricalNames.Should().ContainKey(label.Name);
            native.Symbol(label.Name).Should().Be(label.Value, $"the legacy entry point {label.Name} must stay at its ROM address");
        }

        foreach (string name in (string[])["REALIO", "INTPRC", "ADDPRC", "LNGERR", "TIME", "EXTIO", "DISKO"])
        {
            native.Symbol(name).Should().Be(legacy.Symbol(name), $"{name} must match the Microsoft build");
        }
    }

    /// <summary>
    ///  A standalone native build selects the enhanced IIe just as the legacy overlay does.
    /// </summary>
    [TestMethod]
    public void StandaloneNativeBuildDefaultsToEnhancedIIe()
    {
        string path = Path.GetFullPath(NativePath);
        AssemblyOptions options = new(ProcessorVariant.Mos6502, 0, 0x10000)
        {
            SourceResolver = new FileAssemblySourceResolver()
        };

        AssemblyResult standalone = new Retrocore.Assembler.Assembler().Assemble(
            new AssemblySource(File.ReadAllText(path), path),
            options);

        standalone.Success.Should().BeTrue();
        SdkModules.AppleSoftImage(standalone).ToArray().Should().Equal(
            SdkModules.AppleSoftImage(SdkModules.AssembleAppleSoft(OverlayPath, Apple2Model.IIeEnhanced)).ToArray());
    }

    /// <summary>
    ///  The native default and explicit legacy choice build the same machine ROM.
    /// </summary>
    [TestMethod]
    public void AppleSoftSourceSelectionPreservesBuiltRoms()
    {
        string inputs = BasicNames.Inputs;
        foreach (Apple2Model model in (Apple2Model[])[Apple2Model.IIPlus, Apple2Model.IIeEnhanced])
        {
            Apple2Roms native = SdkModules.BuildRoms(model, inputs);
            Apple2Roms legacy = SdkModules.BuildRoms(model, inputs, basicSource: BasicSourceKind.Macro10);

            native.System.ToArray().Should().Equal(legacy.System.ToArray());
            native.Characters.ToArray().Should().Equal(legacy.Characters.ToArray());
        }
    }

    /// <summary>
    ///  With the user's ROM dumps, each build also compares byte for byte, which names the first difference.
    /// </summary>
    /// <param name="model">The IIe model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftMatchesTheDumps(Apple2Model model)
    {
        string? directory = Environment.GetEnvironmentVariable("RETROCORE_IIE_ROMS");
        if (directory is null)
        {
            Assert.Inconclusive("Set RETROCORE_IIE_ROMS to externally supplied CD/EF/video ROM chips.");
        }

        Apple2Roms roms = Apple2Roms.LoadFromDirectory(model, directory);
        ReadOnlySpan<byte> expected = roms.System.Slice(AppleSoftOffset, SdkModules.AppleSoftSize);
        ReadOnlySpan<byte> actual = SdkModules.AppleSoftImage(SdkModules.AssembleAppleSoft(NativePath, model)).Span;
        int first = actual.CommonPrefixLength(expected);
        first.Should().Be(SdkModules.AppleSoftSize, $"the first difference is at ${SdkModules.AppleSoftOrigin + first:X4}");
    }

    /// <summary>
    ///  Native AppleSoft debugs in its subsystem sources and applies only while internal ROM is mapped.
    /// </summary>
    [TestMethod]
    public void AppleSoftDebugsInNativeSource()
    {
        string inputs = BasicNames.Inputs;
        Apple2Bus bus = new(SdkModules.BuildRoms(Apple2Model.IIeEnhanced, inputs));
        DebugInfo debug = new();
        SdkModules.AddTo(debug, Apple2Model.IIeEnhanced, inputs);

        ushort gone = (ushort)debug.Resolve("GONE");
        gone.Should().BeInRange((ushort)SdkModules.AppleSoftOrigin, (ushort)0xF7FF);
        DebugPosition? position = debug.Position(new Apple2TestMemory(bus), gone);
        position.Should().NotBeNull();
        position?.Chain.Should().ContainSingle();
        position?.Chain[0].Path.Should().EndWith("AppleSoft.ControlFlow.asm");

        foreach ((string name, string definition, string invocation) in ((string, string, string)[])
            [
                ("PRINT", "MsBasic.Print.asm", "AppleSoft.Print.asm"),
                ("FADDH", "MsBasic.AdditionCore.asm", "MsBasic.FloatingPoint.asm"),
                ("FADD", "MsBasic.AdditionCore.asm", "MsBasic.FloatingPoint.asm"),
                ("LOG", "MsBasic.Logarithm.asm", "MsBasic.FloatArithmetic.asm"),
                ("FMULT", "MsBasic.ArithmeticCore.asm", "MsBasic.FloatArithmetic.asm"),
                ("MOVFM", "MsBasic.MovementCore.asm", "MsBasic.FloatMovement.asm"),
                ("SIGN", "MsBasic.ConversionCore.asm", "MsBasic.FloatConversion.asm"),
                ("FIN", "MsBasic.DecimalInputCore.asm", "MsBasic.FloatConversion.asm"),
                ("FOUT", "MsBasic.OutputCore.asm", "MsBasic.FloatOutput.asm"),
                ("EXP", "MsBasic.TranscendentalCore.asm", "MsBasic.Transcendental.asm"),
                ("RND", "MsBasic.RandomCore.asm", "MsBasic.Transcendental.asm")
            ])
        {
            ushort address = (ushort)debug.Resolve(name);
            DebugPosition mapped = debug.Position(new Apple2TestMemory(bus), address)
                ?? throw new AssertFailedException($"No source for {name}.");

            mapped.Chain.Should().HaveCount(2);
            mapped.Chain[0].Path.Should().EndWith(definition);
            mapped.Chain[1].Path.Should().EndWith(invocation);
            debug.Modules.SelectMany(module => module.Entries(mapped.Chain[0].Path, mapped.Chain[0].Line))
                .Should().Contain(address, $"{name}'s source line must accept a breakpoint");
        }

        // Language-card RAM at $D000 is someone else's code, such as ProDOS.
        bus.Read(0xC080);
        debug.Position(new Apple2TestMemory(bus), gone).Should().BeNull();
    }

    /// <summary>
    ///  The legacy selection still maps through its original macro source.
    /// </summary>
    [TestMethod]
    public void AppleSoftMacro10SourceRemainsDebuggable()
    {
        string inputs = BasicNames.Inputs;
        Apple2Roms roms = SdkModules.BuildRoms(
            Apple2Model.IIeEnhanced,
            inputs,
            basicSource: BasicSourceKind.Macro10);

        Apple2Bus bus = new(roms);
        DebugInfo debug = new();
        SdkModules.AddTo(debug, Apple2Model.IIeEnhanced, inputs, basicSource: BasicSourceKind.Macro10);

        ushort gone = (ushort)debug.Resolve("GONE");
        DebugPosition? position = debug.Position(new Apple2TestMemory(bus), gone);
        string microsoftSource = Path.GetFullPath(Path.Join(OverlayPath, "..", "..", "Microsoft6502Basic", "m6502.asm"));
        position.Should().NotBeNull();
        position?.Chain.Should().ContainSingle();
        position?.Chain[0].Path.Should().Be(microsoftSource);
        position?.Chain[0].Line.Should().Be(2165);
    }
}