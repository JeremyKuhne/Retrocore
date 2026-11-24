// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;

namespace Retrocore.Tests;

/// <summary>
///  The shipped native roots reject unsupported legacy I/O settings without constraining custom compositions.
/// </summary>
[TestClass]
public sealed class BasicNativeRootSwitchTests
{
    private static string Inputs => BasicNames.Inputs;
    private static string SharedInputs => Path.Join(Inputs, "Microsoft6502Basic");

    /// <summary>
    ///  Each shipped root reports which alternate legacy setting it cannot support.
    /// </summary>
    /// <param name="root">The native root's file name without its extension.</param>
    /// <param name="symbol">The legacy setting being overridden.</param>
    /// <param name="unsupported">The alternate value.</param>
    [TestMethod]
    [DataRow("AppleSoft", "TIME", 1)]
    [DataRow("AppleSoft", "EXTIO", 1)]
    [DataRow("AppleSoft", "DISKO", 1)]
    [DataRow("Basic1", "TIME", 0)]
    [DataRow("Basic1", "EXTIO", 0)]
    [DataRow("Basic1", "DISKO", 0)]
    [DataRow("Basic2", "TIME", 0)]
    [DataRow("Basic2", "EXTIO", 0)]
    [DataRow("Basic2", "DISKO", 0)]
    [DataRow("Basic4", "TIME", 0)]
    [DataRow("Basic4", "EXTIO", 0)]
    [DataRow("Basic4", "DISKO", 0)]
    public void ShippedRootsRejectUnsupportedOverrides(string root, string symbol, int unsupported)
    {
        AssemblyResult image = AssembleRoot(root, new() { [symbol] = unsupported });
        image.Success.Should().BeFalse();
        string title = root == "AppleSoft" ? root : $"BASIC {root[^1]}";
        string expected = $"{title} requires {symbol} = {1 - unsupported}.";
        image.Diagnostics.Select(diagnostic => diagnostic.Message)
            .Should().Contain(message => message.Contains(expected));
    }

    /// <summary>
    ///  Each shipped root rejects a value predefined by the name the BASIC conversion renamed it from (decision X15),
    ///  which it would otherwise ignore: a PET switch's <c>.ifndef</c> default is not reached through <c>Also:</c>, and
    ///  AppleSoft fixes Microsoft's values, so a predefined old name there only shadows the definition's.
    /// </summary>
    /// <param name="root">The native root's file name without its extension.</param>
    /// <param name="oldName">Microsoft's or the SDK's earlier name for the switch.</param>
    /// <param name="name">The switch's name now.</param>
    [TestMethod]
    [DataRow("AppleSoft", "BUFPAG", "INPUT_BUFFER_PAGE")]
    [DataRow("AppleSoft", "BUFLEN", "INPUT_BUFFER_LENGTH")]
    [DataRow("AppleSoft", "NULCMD", "NULL_COMMAND")]
    [DataRow("AppleSoft", "NUMLEV", "STACK_LEVELS")]
    [DataRow("AppleSoft", "STKEND", "STACK_END")]
    [DataRow("Basic1", "BUFPAG", "INPUT_BUFFER_PAGE")]
    [DataRow("Basic1", "BUFLEN", "INPUT_BUFFER_LENGTH")]
    [DataRow("Basic1", "NULCMD", "NULL_COMMAND")]
    [DataRow("Basic1", "NUMLEV", "STACK_LEVELS")]
    [DataRow("Basic1", "STKEND", "STACK_END")]
    [DataRow("Basic1", "LOCAL_TRMPOS", "LOCAL_TERMINAL_POSITION")]
    [DataRow("Basic1", "VARTXT_IN_LINNUM", "VARIABLE_LIST_IN_LINE_NUMBER")]
    [DataRow("Basic2", "BUFPAG", "INPUT_BUFFER_PAGE")]
    [DataRow("Basic2", "BUFLEN", "INPUT_BUFFER_LENGTH")]
    [DataRow("Basic2", "NULCMD", "NULL_COMMAND")]
    [DataRow("Basic2", "NUMLEV", "STACK_LEVELS")]
    [DataRow("Basic2", "STKEND", "STACK_END")]
    [DataRow("Basic2", "LOCAL_TRMPOS", "LOCAL_TERMINAL_POSITION")]
    [DataRow("Basic2", "VARTXT_IN_LINNUM", "VARIABLE_LIST_IN_LINE_NUMBER")]
    [DataRow("Basic4", "BUFPAG", "INPUT_BUFFER_PAGE")]
    [DataRow("Basic4", "BUFLEN", "INPUT_BUFFER_LENGTH")]
    [DataRow("Basic4", "NULCMD", "NULL_COMMAND")]
    [DataRow("Basic4", "NUMLEV", "STACK_LEVELS")]
    [DataRow("Basic4", "STKEND", "STACK_END")]
    [DataRow("Basic4", "LOCAL_TRMPOS", "LOCAL_TERMINAL_POSITION")]
    [DataRow("Basic4", "VARTXT_IN_LINNUM", "VARIABLE_LIST_IN_LINE_NUMBER")]
    public void ShippedRootsRejectRenamedSwitchNames(string root, string oldName, string name)
    {
        AssemblyResult image = AssembleRoot(root, new() { [oldName] = 0 }, asGiven: true);
        image.Success.Should().BeFalse($"{root} must not silently ignore a predefined {oldName}");
        string expected = root == "AppleSoft"
            ? $"AppleSoft fixes {name}; {oldName} cannot be predefined."
            : $"Predefine {name}, not {oldName}.";

        image.Diagnostics.Select(diagnostic => diagnostic.Message)
            .Should().Contain(message => message.Contains(expected));
    }

    /// <summary>
    ///  Explicit supported values retain the same image as the default configuration, for both PET chip revisions.
    /// </summary>
    /// <param name="root">The native root's file name without its extension.</param>
    /// <param name="revision">The PET chip revision, or -1 for a root without a revision choice.</param>
    [TestMethod]
    [DataRow("AppleSoft", -1)]
    [DataRow("Basic1", 0)]
    [DataRow("Basic1", 1)]
    [DataRow("Basic2", -1)]
    [DataRow("Basic4", 0)]
    [DataRow("Basic4", 1)]
    public void ExplicitSupportedValuesPreserveTheDefaultImage(string root, int revision)
    {
        Dictionary<string, long> symbols = [];
        if (revision >= 0) { symbols["REVISD"] = revision; }
        AssemblyResult baseline = RequireSuccess(AssembleRoot(root, symbols));

        int supported = root == "AppleSoft" ? 0 : 1;
        symbols["TIME"] = supported;
        symbols["EXTIO"] = supported;
        symbols["DISKO"] = supported;
        AssemblyResult explicitImage = RequireSuccess(AssembleRoot(root, symbols));

        explicitImage.Sections[0].Bytes.ToArray().Should().Equal(baseline.Sections[0].Bytes.ToArray());
    }

    /// <summary>
    ///  A custom composition can override the legacy settings and independently select the time-output table.
    /// </summary>
    /// <param name="realio">The Microsoft I/O target used for defaults.</param>
    /// <param name="legacyValue">The explicit legacy setting, opposite to the shipped root's value.</param>
    /// <param name="includeTime">Whether the macro emits the time-output table.</param>
    [TestMethod]
    [DataRow(3, 0, 1)]
    [DataRow(4, 1, 0)]
    public void CustomCompositionSelectsTimeTableIndependently(int realio, int legacyValue, int includeTime)
    {
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.Switches.asm"
            .include "MsBasic.FloatConstants.asm"
            .org $3000
                OUTPUT_TABLES 0, {includeTime}
            END_OF_TABLE:
            """;

        AssemblyResult result = RequireSuccess(new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(SharedInputs, "CustomSwitchTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                PredefinedSymbols = BasicNames.WithCurrentNames(new Dictionary<string, long>
                {
                    ["REALIO"] = realio,
                    ["TIME"] = legacyValue,
                    ["EXTIO"] = legacyValue,
                    ["DISKO"] = legacyValue
                })
            }));

        (result.Symbol("END_OF_TABLE") - result.Symbol("FDCEND")).Should().Be(includeTime * 24);
    }

    // Assembles a root with predefined symbols, each also under the name a rename gave it unless asGiven is set.
    private static AssemblyResult AssembleRoot(string root, Dictionary<string, long> symbols, bool asGiven = false)
    {
        string path = root == "AppleSoft"
            ? Path.Join(Inputs, "AppleSoft", "AppleSoft.asm")
            : Path.Join(Inputs, "Pet", "Basic", $"{root}.asm");

        return new Assembler.Assembler().Assemble(
            new AssemblySource(File.ReadAllText(path), path),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new OverlayBaseResolver(SharedInputs),
                PredefinedSymbols = BasicNames.AsGiven(asGiven ? symbols : BasicNames.WithCurrentNames(symbols))
            });
    }

    private static AssemblyResult RequireSuccess(AssemblyResult result)
    {
        result.Success.Should().BeTrue(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic => diagnostic.Message)));
        return result;
    }
}
