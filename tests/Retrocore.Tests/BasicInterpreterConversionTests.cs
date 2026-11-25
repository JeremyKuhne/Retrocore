// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Documentation;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  Checks the vendors' interpreter files as converted to the style guide (Basic.md, C and I): every old name they
///  give that Microsoft's MACRO-10 build defines reaches that build's value, every definition they make reaches the
///  overlay by its name or an old name, and each old name cites its vendor's documents, all in the bibliography.
/// </summary>
[TestClass]
public sealed class BasicInterpreterConversionTests
{
    // The files part C converted.
    private static readonly string[] s_appleFiles =
    [
        "AppleSoft.ErrorAndInput.asm", "AppleSoft.ControlFlow.asm", "AppleSoft.Print.asm", "AppleSoft.InputOutput.asm",
        "AppleSoft.Expressions.asm", "AppleSoft.Initialization.asm", "AppleSoft.DispatchTables.asm"
    ];

    private static readonly string[] s_commodoreFiles =
    [
        "Commodore.CommandInput.asm", "Commodore.StatementDispatch.asm", "Commodore.ChannelPrint.asm",
        "Commodore.ChannelInput.asm", "Commodore.VariableEvaluation.asm", "Commodore.Initialization.asm",
        "Commodore.DispatchTables.asm"
    ];

    // The documents a vendor's file may cite: its vendor's, Microsoft's source, and UNKN. BASIC 4's kernal listings
    // name BASIC's entries the kernal reaches (ERROR, READY, INIT and others), as the workspace's do.
    private static readonly string[] s_appleKeys = ["M6502", "UNKN", "ASTIL", "AS82", "ASRM78"];
    private static readonly string[] s_commodoreKeys =
        ["M6502", "UNKN", "CBM4S79", "K4S79", "HV1", "HV1R", "HV2", "HV4", "HV4R", "HVK4"];

    // The definitions that give no overlay name of their own, by vendor: the new constants, the labels that were
    // *+5 branches, and, each only where it needs it, AppleSoft's PrintTabOrSpace, whose old names are on its
    // per-build ReadArgument label (Basic.md I3), and BASIC 1's labels whose old names, from HV1 and HV1R, the
    // overlay lacks there (CRTSKP, XSPAC2, GLET and FREMES).
    private static readonly HashSet<string> s_appleSdkNames =
    [
        "CONTROL_C", "KEYBOARD_CONTROL_C", "COMMA_NEWLINE_COLUMN", "INPUT_LINE_LIMIT", "PROGRAM_ORIGIN",
        "PrintTabOrSpace"
    ];

    private static readonly string[] s_basic1SdkNames =
        ["PrintSpace::CursorRight", "PrintSpaces::Next", "DispatchStatement::ToLet", "SignOnMessage"];

    private static readonly HashSet<string> s_commodoreSdkNames =
    [
        "CARRIAGE_RETURN", "LINE_FEED", "CURSOR_RIGHT", "CURSOR_LEFT", "DELETE_CHARACTER", "CURSOR_HOME", "CURSOR_DOWN",
        "NextStatement::ReadLine", "LinkProgram::StoreLink"
    ];

    private const int MinimumOverlayNames = 100;
    private const int MinimumOldNames = 300;

    /// <summary>
    ///  In each AppleSoft build, the interpreter files' old names reach the overlay's values, and their definitions
    ///  reach the overlay by a name, apart from the SDK's own.
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
            native, legacy, AppleFiles, minimum: MinimumOverlayNames, s_appleSdkNames, scoped: true);
    }

    /// <summary>
    ///  In each PET build, the interpreter files' old names reach the overlay's values, and their definitions reach the
    ///  overlay by a name, apart from the SDK's own.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void PetOldNamesMatchTheOverlay(PetModel model, bool original)
    {
        AssemblyResult native = PetSdkModules.AssembleBasic(PetFolder, model, original);
        AssemblyResult legacy = PetLegacyBasic.Assemble(PetFolder, model, original);
        BasicWorkspaceConversionTests.CheckAgainstOverlay(
            native, legacy, CommodoreFiles, minimum: MinimumOverlayNames,
            model switch
            {
                PetModel.Pet2001 =>
                    [.. s_commodoreSdkNames, .. s_basic1SdkNames, .. BasicWorkspaceConversionTests.Basic4OverlayNames],
                PetModel.Pet2001Basic2 => [.. s_commodoreSdkNames, .. BasicWorkspaceConversionTests.Basic4OverlayNames],
                _ => s_commodoreSdkNames
            },
            scoped: true);
    }

    /// <summary>
    ///  Every old name in the interpreter files cites at least one key, each its vendor's document, Microsoft's source
    ///  or UNKN (no document gives it), and each in the bibliography.
    /// </summary>
    [TestMethod]
    public void OldNamesCiteTheirVendorsDocuments()
    {
        int count = 0;
        foreach ((string path, string[] keys) in AppleFiles.Select(path => (path, s_appleKeys))
            .Concat(CommodoreFiles.Select(path => (path, s_commodoreKeys))))
        {
            string name = Path.GetFileName(path);
            foreach (DocumentationAlso also in DocumentationParser.Parse(File.ReadAllText(path), path).Comments
                .SelectMany(comment => DocumentationAlso.Of(comment.Sections)))
            {
                count++;
                also.Sources.Should().NotBeEmpty($"{also.Name} in {name} must cite its documents");
                also.Sources.Should().BeSubsetOf(keys, $"{also.Name} in {name} is its vendor's name");
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
    private static string PetFolder => Path.Join(BasicNames.Inputs, "Pet");
    private static string CommodoreFolder => Path.Join(PetFolder, "Basic");
    private static string[] AppleFiles => [.. s_appleFiles.Select(file => Path.Join(AppleFolder, file))];
    private static string[] CommodoreFiles => [.. s_commodoreFiles.Select(file => Path.Join(CommodoreFolder, file))];
}
