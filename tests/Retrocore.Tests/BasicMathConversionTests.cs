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
///  Checks the math package as converted to the style guide: the shared floating-point modules and Commodore's
///  composition keep every old name they renamed, each reaching the value Microsoft's MACRO-10 build gives it, the
///  vendors' own names for shared definitions resolve only in their vendor's builds, and each cites documents in the
///  bibliography.
/// </summary>
[TestClass]
public sealed class BasicMathConversionTests
{
    // The shared modules the math step converted.
    private static readonly string[] s_sharedFiles =
    [
        "MsBasic.AdditionCore.asm", "MsBasic.ArithmeticCore.asm", "MsBasic.MovementCore.asm",
        "MsBasic.ConversionCore.asm", "MsBasic.DecimalInputCore.asm", "MsBasic.OutputCore.asm",
        "MsBasic.FloatConstants.asm", "MsBasic.Logarithm.asm", "MsBasic.TranscendentalCore.asm",
        "MsBasic.RandomCore.asm", "MsBasic.IntegerConversion.asm", "MsBasic.Relational.asm",
        "MsBasic.SimpleFunctions.asm", "MsBasic.Families.asm"
    ];

    private static string AppleFolder => Path.Join(BasicNames.Inputs, "AppleSoft");
    private static string PetFolder => Path.Join(BasicNames.Inputs, "Pet");
    private static string CommodoreFolder => Path.Join(PetFolder, "Basic");
    private static string SharedFolder => Path.Join(BasicNames.Inputs, "Microsoft6502Basic");
    private static string AppleNames => Path.Join(AppleFolder, "AppleSoft.HistoricalNames.asm");
    private static string CommodoreNames => Path.Join(CommodoreFolder, "Commodore.HistoricalNames.asm");
    private static string CommodoreMath => Path.Join(CommodoreFolder, "Commodore.FloatingPoint.asm");
    private static string[] Shared => [.. s_sharedFiles.Select(file => Path.Join(SharedFolder, file))];

    // The documents a vendor's file may cite: its vendor's, Microsoft's source, and UNKN.
    private static readonly string[] s_appleKeys = ["M6502", "UNKN", "ASTIL", "AS82", "ASRM78"];
    private static readonly string[] s_commodoreKeys = ["M6502", "UNKN", "CBM4S79", "HV1", "HV1R", "HV2", "HV4", "HV4R"];

    // The definitions in the converted files that give no overlay name of their own: the families' guard, the guard
    // bytes that share OLDOV's byte under their own names, the constants and text of BASIC 2's hidden message and
    // BASIC 4's checksum byte, whose names only the SDK or HV4 gives, the entry the SDK names that Microsoft's
    // listing leaves unlabeled, and the two labels whose names Microsoft's source gives only in its Commodore builds,
    // which reach them through Commodore's aliases (BasicSharedFloatAliasesTests).
    private static readonly HashSet<string> s_sdkNames =
    [
        "FAMILIES_DECLARED", "Float::UnshiftedExtension", "Functions::Exp::RoundingByte",
        "HIDDEN_MESSAGE_LENGTH", "SCREEN_CODE_MASK", "Float::PrintFac", "HiddenMessageText", "RomChecksumAdjustment",
        "Functions::Log::MultiplyByLogOfTwo", "Functions::Tan::ToDividePacked"
    ];

    private static readonly Apple2Model[] s_appleModels =
        [Apple2Model.IIPlus, Apple2Model.IIe, Apple2Model.IIeEnhanced];

    private static readonly (PetModel Model, bool Original)[] s_pets =
    [
        (PetModel.Pet2001, false), (PetModel.Pet2001, true), (PetModel.Pet2001Basic2, false),
        (PetModel.Pet4032, false), (PetModel.Pet4032, true)
    ];

    /// <summary>
    ///  In each AppleSoft build, every old name the math files give reaches the value the MACRO-10 overlay gives that
    ///  name, and every definition they make reaches the overlay by its name or an old name.
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
            native, legacy, [.. Shared, AppleNames], minimum: 240, Exempt(native, AppleNames), scoped: true);
    }

    /// <summary>
    ///  In each PET build, every old name the math files give reaches the value the MACRO-10 overlay gives that name,
    ///  and every definition they make reaches the overlay by its name or an old name.
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
            native, legacy, [.. Shared, CommodoreNames, CommodoreMath], minimum: 240, Exempt(native, CommodoreNames), scoped: true);
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
        appleNames.Should().Contain(["PRNTFAC", "FIDVT", "BILLION", "MISMTCH", "OVERFLOW"]);
        petNames.Should().Contain(["SQR05", "TENC", "MULLN2", "GFDIV"]);

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
    ///  Every old name in the math files cites at least one document, every document is in the bibliography, and a
    ///  vendor's file cites only its vendor's documents and Microsoft's.
    /// </summary>
    [TestMethod]
    public void OldNamesCiteDocumentsInTheBibliography()
    {
        int count = 0;
        foreach ((string path, string[]? vendor) in Shared.Select(path => (path, (string[]?)null))
            .Append((AppleNames, s_appleKeys))
            .Append((CommodoreNames, s_commodoreKeys))
            .Append((CommodoreMath, s_commodoreKeys)))
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

        count.Should().BeGreaterThan(260, "the converted math package keeps every old name it renamed");
    }

    /// <summary>
    ///  The bytes the math package's guard names share with <c>OLDOV</c> are that byte in every build, and the
    ///  overlay's <c>OLDOV</c> is the same byte.
    /// </summary>
    [TestMethod]
    public void GuardBytesShareOldovsByte()
    {
        IEnumerable<(AssemblyResult Native, AssemblyResult Legacy)> builds = s_appleModels
            .Select(model => (AssembleAppleSoft(model),
                SdkModules.AssembleAppleSoft(Path.Join(AppleFolder, "applesoft.mac"), model)))
            .Concat(s_pets.Select(build => (PetSdkModules.AssembleBasic(PetFolder, build.Model, build.Original),
                PetLegacyBasic.Assemble(PetFolder, build.Model, build.Original))));

        foreach ((AssemblyResult native, AssemblyResult legacy) in builds)
        {
            long oldov = legacy.Symbol("OLDOV");
            native.Symbol("Float::UnshiftedExtension").Should().Be(oldov);
            native.Symbol("Functions::Exp::RoundingByte").Should().Be(oldov);
            native.Symbol("OLDOV").Should().Be(oldov, "OLDOV stays FunctionJumpHigh's old name");
        }
    }

    /// <summary>
    ///  Each module that adds to the families declares them through MsBasic.Families.asm, so a build can include any
    ///  of them, in any order, and only the first inclusion declares the families.
    /// </summary>
    /// <param name="twice">Whether the source includes the families' file itself as well, before the modules.</param>
    [TestMethod]
    [DataRow(data: true)]
    [DataRow(data: false)]
    public void FamiliesAreDeclaredOnce(bool twice)
    {
        string source = $"""
            .cpu Mos6502
            {(twice ? ".include \"MsBasic.Families.asm\"" : "")}
            .include "MsBasic.FloatConstants.asm"
            .include "MsBasic.Families.asm"
            .org $2000
                LogarithmConstants
            END_OF_CONSTANTS:
            """;

        AssemblyResult result = new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(SharedFolder, "FamiliesTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver()
            });

        result.Success.Should().BeTrue(string.Join(Environment.NewLine, result.Diagnostics.Select(d => d.Message)));
        result.Symbol("Float::One").Should().Be(0x2000);
        result.Symbol("FONE").Should().Be(0x2000);
        result.Symbol("END_OF_CONSTANTS").Should().Be(0x2000 + 5 * 5 + 21, "the families emit no bytes");
    }

    // The SDK's names, and a vendor's aliases and the definitions they alias: a vendor's name is on its alias, whose
    // value BasicSharedFloatAliasesTests checks against the vendor's listings, so the definition gives no name of its
    // own for the overlay.
    private static HashSet<string> Exempt(AssemblyResult native, string vendorNames)
    {
        HashSet<string> exempt = [.. s_sdkNames];
        foreach (AssemblySymbol alias in native.SymbolDefinitions
            .Where(symbol => BasicWorkspaceConversionTests.InFiles(symbol, [vendorNames])))
        {
            exempt.Add(alias.Name);
        }

        foreach (DocumentationComment comment in DocumentationParser.Parse(File.ReadAllText(vendorNames), vendorNames).Comments)
        {
            if (comment.Sections.FirstOrDefault(section => section.Name == "Inherit") is { } inherit)
            {
                exempt.Add(native.DefinitionName(inherit.Text.Trim().Trim('<', '>')));
            }
        }

        return exempt;
    }

    private static AssemblyResult AssembleAppleSoft(Apple2Model model) =>
        SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(BasicNames.Inputs), model);

    private static IEnumerable<DocumentationAlso> OldNamesIn(string path) =>
        DocumentationParser.Parse(File.ReadAllText(path), path).Comments
            .SelectMany(comment => DocumentationAlso.Of(comment.Sections));
}
