// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Documentation;
using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  Checks AppleSoft's own files as converted to the style guide (Basic.md, E): every old name they give that the
///  MACRO-10 overlay defines reaches its value, every definition they make reaches the overlay by its name or an old
///  name, and each old name cites AppleSoft's documents, Microsoft's source or UNKN, all in the bibliography.
/// </summary>
[TestClass]
public sealed class BasicAppleConversionTests
{
    // The files part E converted, with the small modules and the root that compose the shared modules.
    private static readonly string[] s_files =
    [
        "AppleSoft.AppleCommands.asm", "AppleSoft.HighResolution.asm", "AppleSoft.PlatformHelpers.asm",
        "AppleSoft.Arrays.asm", "AppleSoft.Assignment.asm", "AppleSoft.Functions.asm", "AppleSoft.Lister.asm",
        "AppleSoft.MemoryManagement.asm", "AppleSoft.NumericConversion.asm", "AppleSoft.Strings.asm", "AppleSoft.asm"
    ];

    // The documents an AppleSoft file may cite: Apple's, Microsoft's source, and UNKN.
    private static readonly string[] s_appleKeys = ["M6502", "UNKN", "ASTIL", "AS82", "ASRM78"];

    // The definitions that give no overlay name of their own: the new constants, the build switches' defaults, and
    // HighRes::SetColor, the Technical Information Library's SETHCOL, which the overlay does not label (Basic.md E-Q3),
    // and the hi-res engine's names for the Monitor's bytes it borrows, whose old names are the Monitor's (E-Q5).
    private static readonly HashSet<string> s_sdkNames =
    [
        "LOW_RES_ROWS", "LOW_RES_COLUMNS", "TEXT_ROWS", "INVERSE_MASK_NORMAL", "INVERSE_MASK_INVERSE",
        "INVERSE_MASK_FLASH", "FLASH_MASK_FLASH", "HIGH_RES_PAGE1", "HIGH_RES_PAGE2", "PIXELS_PER_BYTE",
        "HIGH_RES_ROW_BYTES", "HIGH_RES_COLUMNS", "HIGH_RES_ROWS", "HIGH_RES_COLORS", "FIRST_PIXEL_MASK",
        "LAST_PIXEL_MASK", "SHAPE_PLOT_BIT", "COMMA_LIMIT_40", "COMMA_LIMIT_80", "ENHNCD", "APLPLS",
        "HighRes::SetColor", "HighRes::PixelMask", "HighRes::ByteAddress", "HighRes::ByteAddressHigh"
    ];

    private const int MinimumOverlayNames = 100;
    private const int MinimumOldNames = 150;

    /// <summary>
    ///  In each AppleSoft build, the files' old names reach the overlay's values, and their definitions reach the
    ///  overlay by a name, apart from the SDK's own.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftOldNamesMatchTheOverlay(Apple2Model model)
    {
        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(BasicNames.Inputs), model);
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(Path.Join(AppleFolder, "applesoft.mac"), model);
        BasicWorkspaceConversionTests.CheckAgainstOverlay(
            native, legacy, Files, minimum: MinimumOverlayNames, s_sdkNames, scoped: true);

        // The hi-res engine's names for the Monitor's bytes, which the comparison leaves out, are those bytes (E-Q5).
        native.Symbol("HighRes::PixelMask").Should().Be(native.Symbol("PlotColor"));
        native.Symbol("HighRes::ByteAddress").Should().Be(native.Symbol("LowResBase"));
        native.Symbol("HighRes::ByteAddressHigh").Should().Be(native.Symbol("LowResBaseHigh"));
        native.DefinitionName("HBAS").Should().Be("HighRes::ByteAddress", "ASTIL's HBAS is the hi-res byte address");
    }

    /// <summary>
    ///  Every old name in the files cites at least one key, each AppleSoft's document, Microsoft's source or UNKN (no
    ///  document gives it), and each in the bibliography.
    /// </summary>
    [TestMethod]
    public void OldNamesCiteAppleSoftsDocuments()
    {
        int count = 0;
        foreach (string path in Files)
        {
            string name = Path.GetFileName(path);
            foreach (DocumentationAlso also in DocumentationParser.Parse(File.ReadAllText(path), path).Comments
                .SelectMany(comment => DocumentationAlso.Of(comment.Sections)))
            {
                count++;
                also.Sources.Should().NotBeEmpty($"{also.Name} in {name} must cite its documents");
                also.Sources.Should().BeSubsetOf(s_appleKeys, $"{also.Name} in {name} is AppleSoft's name");
                foreach (string key in also.Sources)
                {
                    BasicAttribution.Bibliography.Find(key).Should().NotBeNull(
                        $"{also.Name} in {name} cites {key}, which must be in docs/Bibliography.md");
                }
            }
        }

        count.Should().BeGreaterThan(MinimumOldNames, "the converted files keep every old name they renamed");
    }

    private static string AppleFolder => Path.Join(BasicNames.Inputs, "AppleSoft");
    private static string[] Files => [.. s_files.Select(file => Path.Join(AppleFolder, file))];
}
