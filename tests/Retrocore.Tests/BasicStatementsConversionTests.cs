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
///  Checks the shared program and statement modules as converted to the style guide (Basic.md, B1): every old name
///  they give that Microsoft's MACRO-10 build defines reaches that build's value, the vendors' own names for their
///  definitions resolve only in their vendor's builds, and each cites documents in the bibliography.
/// </summary>
[TestClass]
public sealed class BasicStatementsConversionTests
{
    // The shared modules the statements step converted.
    private static readonly string[] s_sharedFiles =
    [
        "MsBasic.CharacterReader.asm", "MsBasic.CommandCore.asm", "MsBasic.For.asm", "MsBasic.LineNumber.asm",
        "MsBasic.LineSearch.asm", "MsBasic.Lister.asm", "MsBasic.MemoryAccess.asm", "MsBasic.MemoryManagement.asm",
        "MsBasic.Next.asm", "MsBasic.OperatorTable.asm", "MsBasic.Print.asm", "MsBasic.ProgramReset.asm",
        "MsBasic.ProgramTransfers.asm", "MsBasic.StatementFlow.asm", "MsBasic.UserFunctions.asm"
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
    private static readonly string[] s_commodoreKeys = ["M6502", "UNKN", "CBM4S79", "HV1", "HV1R", "HV2", "HV4", "HV4R"];

    // The definitions in the converted files that give no overlay name of their own: the families' guard, the
    // labels only the SDK names (CONT1 was the SDK's own; RUN's and FN's branch targets were *+5), and the labels
    // whose names only a vendor gives (AppleSoft's overlay, or BASIC 4's listings), which reach them through their
    // vendor's aliases (BasicSharedFloatAliasesTests).
    private static readonly HashSet<string> s_sdkNames =
    [
        "FAMILIES_DECLARED", "Statements::Cont::Resume", "Statements::PopFinish", "Statements::Run::WithLine",
        "Functions::Fn::RestoreText",
        "Statements::List::ReadSecondBound", "Statements::List::NextTableByte", "Statements::List::ReadTableByte",
        "Statements::List::ListWordCharacter", "Statements::List::ListLastCharacter",
        "Statements::List::ReadWordByte", "Statements::List::ListFirstWord"
    ];

    // Each build compares about 150 old names with the overlay, and the files give about 180.
    private const int MinimumOverlayNames = 140;
    private const int MinimumOldNames = 170;

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
    ///  SDK's names and the vendor's aliases, whose values BasicSharedFloatAliasesTests checks.
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
    ///  SDK's names and the vendor's aliases, whose values BasicSharedFloatAliasesTests checks.
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
        appleNames.Should().Contain(["NEW", "COMBYTE", "GOLST1", "GRODY1", "REMER1"]);
        petNames.Should().Contain(["CHDGOT", "CHDRTS", "RESCR2", "PRIT3B"]);

        foreach (string name in appleNames)
        {
            pet.Should().AllSatisfy(build => build.HasSymbol(name).Should().BeFalse($"{name} is AppleSoft's name"));
        }

        foreach (string name in petNames)
        {
            apple.Should().AllSatisfy(build => build.HasSymbol(name).Should().BeFalse($"{name} is the PET's name"));
        }

        // Each vendor's name reaches its vendor's alias, whose value is the shared definition's.
        foreach ((AssemblyResult[] builds, HashSet<string> names, string file) in
            ((AssemblyResult[], HashSet<string>, string)[])[(apple, appleNames, AppleNames), (pet, petNames, CommodoreNames)])
        {
            foreach (AssemblyResult build in builds)
            {
                foreach (string name in names.Where(build.HasSymbol))
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

    // The SDK's names and a vendor's aliases, whose values BasicSharedFloatAliasesTests checks against the vendor's
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
