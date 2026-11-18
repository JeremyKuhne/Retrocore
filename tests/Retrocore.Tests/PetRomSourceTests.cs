// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using Retrocore.Debug;
using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the SDK's sources for the Commodore PET's ROMs: BASIC 1 (original and revised) and BASIC 2, their
///  screen editors and kernals, and the 901447-08 and 901447-10 character ROMs.
/// </summary>
/// <remarks>
///  <para>
///   Digests pin each build, so no ROM is needed. With the dumps (see <see cref="PetMachineTests"/>), a build that
///   differs names its first different byte.
///  </para>
/// </remarks>
[TestClass]
public sealed class PetRomSourceTests
{
    private static readonly string s_sources = Path.Join(AppContext.BaseDirectory, "Inputs", "Pet");

    /// <summary>
    ///  BASIC builds byte-identically to each version's chips, <c>$C000-$DFFF</c>.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="original">For BASIC 1, the original chip rather than the revised one.</param>
    /// <param name="expectedHash">The SHA-256 of the 8K.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false, "629B630F695D004B788AA23BCFA4ACB84D405D4B22D136C7CF93571DD89EE4A1")]
    [DataRow(PetModel.Pet2001, true, "4CBF2F93B493076D7468A4C165FA3B93537E8A3BD9170C8B674073B50C3454A9")]
    [DataRow(PetModel.Pet2001Basic2, false, "5B426B5C50350E5D50C4308A81288BB34F310D7384BCC43C66A0E18716A4CDBE")]
    public void BasicMatchesTheChips(PetModel model, bool original, string expectedHash)
    {
        ReadOnlySpan<byte> image = PetSdkModules.BasicImage(PetSdkModules.AssembleBasic(s_sources, model, original), model).Span;
        Check(image, expectedHash, model, original, PetSdkModules.BasicOrigin(model));
    }

    /// <summary>
    ///  The screen editor's chip, <c>$E000-$E7FF</c>, builds byte-identically for each version from BASIC's end and
    ///  the editor's source.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="expectedHash">The SHA-256 of the 2K.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, "86DC50795651DE9F99C886EA61BD412F5372FA4940EEC7B550A9FA2D2DFFFC13")]
    [DataRow(PetModel.Pet2001Basic2, "5338B1DFFEBD695F6110C9995E16F7536BB63A909C2A0062B4789DE46904ADE9")]
    public void EditorMatchesTheChip(PetModel model, string expectedHash) =>
        Check(
            PetSdkModules.EditorImage(PetSdkModules.AssembleBasic(s_sources, model), PetSdkModules.AssembleEditor(s_sources, model), model),
            expectedHash,
            model,
            original: false,
            PetSdkModules.EditorOrigin);

    /// <summary>
    ///  The kernal builds byte-identically to each version's chips, <c>$F000-$FFFF</c>.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="expectedHash">The SHA-256 of the 4K.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, "397B8CA539372D6E731EBD426077976C00E714CD140DC00E66B6AF7E0FC0B3DE")]
    [DataRow(PetModel.Pet2001Basic2, "056D5E84A6E4F2B5B40A4109F49515C2496A4BF99139A9F59ABE486DED5CD03D")]
    public void KernalMatchesTheChips(PetModel model, string expectedHash) =>
        Check(PetSdkModules.AssembleKernal(s_sources, model).Sections[0].Bytes.Span, expectedHash, model, original: false, PetSdkModules.KernalOrigin);

    /// <summary>
    ///  The character ROM builds byte-identically to the 2001's 901447-08 and the 2001-N's 901447-10.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="expectedHash">The SHA-256 of the 2K.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, "697390D9CD7DA9E77D71935B0BF71D1181F624E0BE802CBFB472803861443340")]
    [DataRow(PetModel.Pet2001Basic2, "DA3374C21D6EA440CEF5F338CE3F524E0A1E40DCB1EF64446C695F92C636F1FA")]
    public void CharactersMatchTheChip(PetModel model, string expectedHash) =>
        Check(PetSdkModules.AssembleCharacters(s_sources, model).Sections[0].Bytes.Span, expectedHash, model, original: false, origin: null);

    /// <summary>
    ///  With no dumps at all, each model boots from the SDK's builds to <c>READY.</c>.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="banner">BASIC's banner.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, "*** COMMODORE BASIC ***")]
    [DataRow(PetModel.Pet2001Basic2, "### COMMODORE BASIC ###")]
    public void MachineBootsFromTheSdkBuilds(PetModel model, string banner)
    {
        PetMachine machine = new(PetSdkModules.BuildRoms(model, s_sources), model);
        string[] screen = PetMachineTests.RunToReady(machine);
        screen.Should().Contain(line => line.Trim() == banner, string.Join('\n', screen));
        screen.Should().Contain(line => line.StartsWith("READY.", StringComparison.Ordinal));
    }

    // Checks a build against its digest; when it differs and the dumps are present, names the first different byte.
    private static void Check(ReadOnlySpan<byte> actual, string expectedHash, PetModel model, bool original, int? origin)
    {
        string hash = Convert.ToHexString(SHA256.HashData(actual));
        if (hash == expectedHash) { return; }

        string directory = PetMachineTests.RomDirectory(model);
        string because = "the dumps are missing";
        if (File.Exists(Path.Join(directory, PetMachineTests.KernalChip(model))))
        {
            PetRoms roms = PetRoms.LoadFromDirectory(directory, model, original);
            ReadOnlySpan<byte> expected = origin is { } start
                ? roms.Image.Slice(start - PetRoms.Base, actual.Length)
                : roms.Characters;

            int first = actual.CommonPrefixLength(expected);
            because = origin is { } at ? $"the first difference is at ${at + first:X4}" : $"the first difference is at ${first:X3}";
        }

        hash.Should().Be(expectedHash, because);
    }
}
