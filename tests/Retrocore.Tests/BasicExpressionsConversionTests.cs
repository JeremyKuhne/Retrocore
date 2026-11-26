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
///  Checks the shared expression, variable and string modules as converted to the style guide (Basic.md, B2): every
///  old name they give that Microsoft's MACRO-10 build defines reaches that build's value, the vendors' own names for
///  their definitions resolve only in their vendor's builds and cite the documents that give them, and each cites
///  documents in the bibliography.
/// </summary>
[TestClass]
public sealed class BasicExpressionsConversionTests
{
    // The shared modules the expressions step converted.
    private static readonly string[] s_sharedFiles =
    [
        "MsBasic.ArrayMultiplication.asm", "MsBasic.Arrays.asm", "MsBasic.Assignment.asm", "MsBasic.Dim.asm",
        "MsBasic.ExpressionCore.asm", "MsBasic.OperandEvaluation.asm", "MsBasic.VariableInput.asm",
        "MsBasic.VariableLookup.asm", "MsBasic.StringStorage.asm", "MsBasic.StringStorage.Classic.asm",
        "MsBasic.StringStorage.Linked.asm", "MsBasic.StringConcatenation.asm", "MsBasic.StringConversion.asm",
        "MsBasic.StringFunctions.asm", "MsBasic.StringGarbageCollection.asm", "MsBasic.StringOutput.asm"
    ];

    /// <summary>
    ///  Commodore's names for these modules' definitions, with the documents that give each. Commodore's file guards
    ///  each by its target, so a build of part of the modules leaves them out.
    /// </summary>
    internal static readonly Dictionary<string, string[]> CommodoreOldNames = new(StringComparer.Ordinal)
    {
        ["COPYC"] = ["CBM4S79", "HV1", "HV1R", "HV2", "HV4", "HV4R"],
        ["STRD"] = ["CBM4S79", "HV1", "HV1R", "HV2", "HV4", "HV4R"],
        ["CHRD"] = ["CBM4S79", "HV1", "HV1R", "HV2", "HV4", "HV4R"],
        ["LEFTD"] = ["CBM4S79", "HV1", "HV1R", "HV2", "HV4", "HV4R"],
        ["RIGHTD"] = ["CBM4S79", "HV1", "HV1R", "HV2", "HV4", "HV4R"],
        ["MIDD"] = ["CBM4S79", "HV1", "HV1R", "HV2", "HV4", "HV4R"],
        ["NXTPTR"] = ["CBM4S79", "HV4", "HV4R"],
        ["QDSVAR"] = ["CBM4S79", "HV4", "HV4R"],
        ["ARYVA2"] = ["CBM4S79", "HV4", "HV4R"],
        ["ARYVA3"] = ["CBM4S79", "HV4", "HV4R"],
        ["ARYVGO"] = ["CBM4S79", "HV4", "HV4R"],
        ["ARYGET"] = ["CBM4S79", "HV4", "HV4R"],
        ["GOGO"] = ["CBM4S79", "HV4", "HV4R"],
        ["GOGO1"] = ["CBM4S79", "HV4", "HV4R"],
        ["DVARTS"] = ["CBM4S79", "HV4", "HV4R"],
        ["ARYDON"] = ["CBM4S79", "HV4", "HV4R"],
        ["RES00"] = ["CBM4S79", "HV4", "HV4R"],
        ["FRE01"] = ["CBM4S79", "HV4", "HV4R"],
        ["FRE02"] = ["CBM4S79", "HV4", "HV4R"],
        ["TRYAG3"] = ["CBM4S79", "HV4", "HV4R"],
        ["TRYAG4"] = ["CBM4S79", "HV4", "HV4R"],
        ["GETRTS"] = ["CBM4S79", "HV4", "HV4R"],
        ["ANDOP"] = ["M6502", "CBM4S79", "HV1", "HV1R", "HV2", "HV4", "HV4R"]
    };

    // The classic collector's steps, whose Microsoft names BASIC 1 and 2 give them and BASIC 4 gives its array
    // back-link steps instead (K12), with the documents that give them in BASIC 1 and 2.
    private static readonly Dictionary<string, string[]> s_classicCollectorNames = new(StringComparer.Ordinal)
    {
        ["ARYVA2"] = ["M6502", "HV1", "HV1R", "HV2"],
        ["ARYVA3"] = ["M6502", "HV1", "HV1R", "HV2"],
        ["ARYVGO"] = ["M6502", "HV1", "HV1R", "HV2"],
        ["ARYGET"] = ["M6502", "HV1", "HV1R", "HV2"],
        ["GOGO"] = ["M6502", "HV1", "HV1R", "HV2"],
        ["DVARTS"] = ["M6502", "HV1", "HV1R", "HV2"],
        ["TRYAG3"] = ["M6502", "HV1", "HV1R", "HV2"]
    };

    /// <summary>
    ///  The old names, in the MACRO-10 builds, of the definitions Commodore's guarded aliases name: a build of part of
    ///  the modules that predefines them would define the aliases.
    /// </summary>
    internal static readonly string[] CommodoreTargetOldNames =
    [
        "COPYZC", "FNDVAR", "STR", "CHR", "LEFT", "RIGHT", "MID", "NXTPTR", "QDSVAR", "ARYVA2",
        "ARYVA3", "ARYVGO", "ARYGET", "GOGO", "GOGO1", "DVARTS", "ARYDON", "TRYAG3", "TRYAG4", "GETRTS", "RES00", "FRE01", "FRE02",
        "ANDOP"
    ];

    private static string AppleFolder => Path.Join(BasicNames.Inputs, "AppleSoft");
    private static string PetFolder => Path.Join(BasicNames.Inputs, "Pet");
    private static string CommodoreFolder => Path.Join(PetFolder, "Basic");
    private static string SharedFolder => Path.Join(BasicNames.Inputs, "Microsoft6502Basic");
    private static string AppleNames => Path.Join(AppleFolder, "AppleSoft.HistoricalNames.asm");
    private static string CommodoreNames => Path.Join(CommodoreFolder, "Commodore.HistoricalNames.asm");
    private static string[] Shared => [.. s_sharedFiles.Select(file => Path.Join(SharedFolder, file))];

    // The documents a vendor's file may cite: its vendor's, Microsoft's source, and UNKN.
    private static readonly string[] s_appleKeys = ["M6502", "UNKN", "ASTIL", "AS82", "ASRM78"];
    private static readonly string[] s_commodoreKeys = ["M6502", "UNKN", "CBM4S79", "HV1", "HV1R", "HV2", "HV4", "HV4R", "BV20"];

    // The definitions in the converted files that give no overlay name of their own: the families' guard, the input
    // modes, the labels only the SDK names (branch targets that were *+5), and the labels whose names only a vendor
    // gives, which reach them through their vendor's aliases.
    private static readonly HashSet<string> s_sdkNames =
    [
        "FAMILIES_DECLARED", "INPUT_MODE_INPUT", "INPUT_MODE_GET", "INPUT_MODE_READ", "RELATION_TOKENS",
        "EvaluateExpression::Arithmetic", "EvaluateFunctionOperand::NotFn", "Functions::Val::NotEmpty",
        "FindVariable::SearchScalars", "Strings::ReserveSpace::CheckLinkedRoom", "Strings::ReserveSpace::Done",
        "Strings::ReserveSpace::CheckRoom", "Strings::ReserveSpace::BelowLink", "Operators::And", "Operators::And::LoadFalse",
        "Operators::And::LoadTrue",
        "Operators::Not::LoadFalse", "Variables::FindArray::Search", "Variables::ArrayFound::CheckDimensions",
        "Variables::ArrayMissing", "AssignVariableList::CheckEmptyLine", "AssignVariableList::RestoreCharacter",
        "AssignVariableList::EmptyNumber", "FindVariable::AfterVectors", "FindVariable::ToChooseArrayLookup",
        "FindVariable::NoParenthesis", "ZeroVariable", "Variables::ElementsStart::FromCount", "Variables::ChooseArrayLookup",
        "Functions::Len::ToFloat", "FindVariable::SecondMismatch", "Variables::CheckReservedName::CheckDiskStatus",
        "Variables::Create::NextArray", "Variables::Create::CheckArraysEnd", "Variables::Create::ReadArray",
        "Variables::Create::ScanElements", "Variables::Create::CheckElement", "Variables::Create::MoveLink",
        "Variables::Create::Advance", "Variables::Create::WriteEntry", "Strings::ReleaseDescriptor::CheckBottom",
        "Strings::ReleaseDescriptor::SkipLink", "Strings::ReleaseDescriptor::ReadDescriptor",
        "Strings::CollectGarbage::NextArray", "Strings::CollectGarbage::CheckArraysEnd", "Strings::CollectGarbage::ReadArray",
        "Strings::CollectGarbage::ElementsReady", "Strings::CollectGarbage::CheckElement", "Strings::CollectGarbage::Advance"
    ];

    // Each build compares about 250 old names with the overlay, and the files give about 300.
    private const int MinimumOverlayNames = 200;
    private const int MinimumOldNames = 250;

    private static readonly Apple2Model[] s_appleModels =
        [Apple2Model.IIPlus, Apple2Model.IIe, Apple2Model.IIeEnhanced];

    private static readonly (PetModel Model, bool Original)[] s_pets =
    [
        (PetModel.Pet2001, false), (PetModel.Pet2001, true), (PetModel.Pet2001Basic2, false),
        (PetModel.Pet4032, false), (PetModel.Pet4032, true)
    ];

    /// <summary>
    ///  In each AppleSoft build, every old name the converted files give that the MACRO-10 overlay defines reaches the
    ///  overlay's value, and every definition they make reaches the overlay by its name or an old name, apart from the
    ///  SDK's names and the vendor's aliases, whose values the alias tests check.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftOldNamesMatchTheOverlay(Apple2Model model)
    {
        AssemblyResult native = AssembleAppleSoft(model);
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(Path.Join(AppleFolder, "applesoft.mac"), model);
        BasicWorkspaceConversionTests.CheckAgainstOverlay(
            native, legacy, [.. Shared, AppleNames], minimum: MinimumOverlayNames, Exempt(native, AppleNames), scoped: true);
    }

    /// <summary>
    ///  In each PET build, every old name the converted files give that the MACRO-10 overlay defines reaches the
    ///  overlay's value, and every definition they make reaches the overlay by its name or an old name, apart from the
    ///  SDK's names and the vendor's aliases, whose values the alias tests check.
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
            native, legacy, [.. Shared, CommodoreNames], minimum: MinimumOverlayNames, Exempt(native, CommodoreNames), scoped: true);
    }

    /// <summary>
    ///  A vendor's name for a shared definition resolves in that vendor's builds only, and the shared files give only
    ///  names Microsoft's source gives.
    /// </summary>
    [TestMethod]
    public void VendorNamesResolveOnlyInTheirVendorsBuilds()
    {
        AssemblyResult[] apple = [.. s_appleModels.Select(AssembleAppleSoft)];
        AssemblyResult[] pet =
            [.. s_pets.Select(build => PetSdkModules.AssembleBasic(PetFolder, build.Model, build.Original))];

        HashSet<string> appleNames = BasicWorkspaceConversionTests.OldNames(apple, [AppleNames]);
        HashSet<string> petNames = BasicWorkspaceConversionTests.OldNames(pet, [CommodoreNames]);
        appleNames.Should().Contain(["INDLO1", "OROP1", "ANDOP", "STRNA3", "SIMZER", "QINTG1"]);
        petNames.Should().Contain(["COPYC", "STRD", "MIDD", "NXTPTR", "RES00", "ANDOP", "ARYVA2"]);

        // A name both vendors' files give, each for its own definition (Basic.md E4), reaches each vendor's own alias,
        // which the loop below checks; a name a vendor's unconverted code still gives a label of its own is that label
        // in those builds (BasicNames.VendorLabelNames).
        appleNames.Intersect(petNames).Should().BeEquivalentTo(BasicNames.BothVendorsNames);
        foreach (string name in appleNames.Except(petNames))
        {
            pet.Should().AllSatisfy(build => (build.HasSymbol(name) && !BasicNames.IsVendorLabel(build, name, CommodoreNames))
                .Should().BeFalse($"{name} is AppleSoft's name"));
        }

        foreach (string name in petNames.Except(appleNames))
        {
            apple.Should().AllSatisfy(build => (build.HasSymbol(name) && !BasicNames.IsVendorLabel(build, name, AppleNames))
                .Should().BeFalse($"{name} is the PET's name"));
        }

        // Each vendor's name reaches its vendor's alias, whose value is the shared definition's.
        foreach ((AssemblyResult[] builds, HashSet<string> names, string file) in
            ((AssemblyResult[], HashSet<string>, string)[])[(apple, appleNames, AppleNames), (pet, petNames, CommodoreNames)])
        {
            foreach (AssemblyResult build in builds)
            {
                foreach (string name in names.Where(old => build.HasSymbol(old)
                    && !BasicNames.IsVendorLabel(build, old, file)))
                {
                    BasicWorkspaceConversionTests.InFiles(build.HistoricalNames[name], [file]).Should().BeTrue(
                        $"{name} must reach the alias in {Path.GetFileName(file)}");
                }
            }
        }

        foreach (string path in Shared)
        {
            foreach (DocumentationAlso also in OldNamesIn(path))
            {
                also.Sources.Should().Contain("M6502", $"{also.Name} in {Path.GetFileName(path)} is on a shared definition");
            }
        }
    }

    /// <summary>
    ///  In each PET build, Commodore's name for each of these modules' definitions that the build has reaches its
    ///  target through Commodore's alias, inherits its documentation, cites the documents that give it (this build's
    ///  among them, unless it is Microsoft's name too and cites M6502), and has the debugger's source position of its
    ///  target.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void CommodoreAliasesCiteTheirDocuments(PetModel model, bool original)
    {
        AssemblyResult native = PetSdkModules.AssembleBasic(PetFolder, model, original);
        bool linked = native.HasSymbol("Variables::Create::NextArray");

        // BASIC 4's descriptor copy is its own, in Commodore's file, so COPYC's target is not a shared definition
        // there; BasicSharedInterpreterAliasesTests checks its address and citations in every build.
        Dictionary<string, string[]> expected = CommodoreOldNames
            .Where(pair => native.HistoricalNames.TryGetValue(pair.Key, out AssemblySymbol? definition)
                && BasicWorkspaceConversionTests.InFiles(definition, [CommodoreNames])
                && !(linked && pair.Key == "COPYC"))
            .ToDictionary(
                pair => pair.Key,
                pair => !linked && s_classicCollectorNames.TryGetValue(pair.Key, out string[]? classic) ? classic : pair.Value,
                StringComparer.Ordinal);

        expected.Should().ContainKeys("STRD", "CHRD", "LEFTD", "RIGHTD", "MIDD", "ANDOP", "ARYVA2");
        if (linked)
        {
            expected.Should().ContainKeys("NXTPTR", "QDSVAR", "GOGO1", "ARYDON", "RES00", "FRE01", "FRE02", "TRYAG4", "GETRTS");
        }

        BasicSharedFloatAliasesTests.CheckAliases(native, CommodoreNames, expected, (model, original), expected.Keys);
    }

    /// <summary>
    ///  Every old name in the converted files cites at least one document, every document is in the bibliography, and a
    ///  vendor's file cites only its vendor's documents and Microsoft's.
    /// </summary>
    [TestMethod]
    public void OldNamesCiteDocumentsInTheBibliography()
    {
        int count = 0;
        foreach ((string path, string[]? vendor) in Shared.Select(path => (path, (string[]?)null))
            .Append((AppleNames, s_appleKeys))
            .Append((CommodoreNames, s_commodoreKeys)))
        {
            string name = Path.GetFileName(path);
            foreach (DocumentationAlso also in OldNamesIn(path))
            {
                count++;
                also.Sources.Should().NotBeEmpty($"{also.Name} in {name} must cite its documents");
                if (vendor is not null)
                {
                    also.Sources.Should().BeSubsetOf(vendor, $"{also.Name} in {name} is its vendor's name");
                }

                foreach (string key in also.Sources)
                {
                    BasicAttribution.Bibliography.Find(key).Should().NotBeNull(
                        $"{also.Name} in {name} cites {key}, which must be in docs/Bibliography.md");
                }
            }
        }

        count.Should().BeGreaterThan(MinimumOldNames, "the converted modules keep every old name they renamed");
    }

    // The SDK's names and a vendor's aliases, whose values the alias tests check against the vendor's
    // listings.
    private static HashSet<string> Exempt(AssemblyResult native, string vendorNames)
    {
        HashSet<string> exempt = [.. s_sdkNames];
        foreach (AssemblySymbol alias in native.SymbolDefinitions
            .Where(symbol => BasicWorkspaceConversionTests.InFiles(symbol, [vendorNames])))
        {
            exempt.Add(alias.Name);
        }

        return exempt;
    }

    private static AssemblyResult AssembleAppleSoft(Apple2Model model) =>
        SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(BasicNames.Inputs), model);

    private static IEnumerable<DocumentationAlso> OldNamesIn(string path) =>
        DocumentationParser.Parse(File.ReadAllText(path), path).Comments
            .SelectMany(comment => DocumentationAlso.Of(comment.Sections));
}
