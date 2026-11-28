// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Commodore;
using System.Collections.Concurrent;

namespace Retrocore.Tests;

/// <summary>
///  Holds reusable builds for one immutable copy of the test inputs.
/// </summary>
/// <param name="directory">The test inputs directory.</param>
internal sealed class BasicInputBuilds(string directory)
{
    private readonly Lazy<AssemblyResult> _appleMath = new(() =>
        SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(directory), Apple2Model.IIeEnhanced));

    private readonly Lazy<AssemblyResult> _petMath = new(() =>
        PetSdkModules.AssembleBasic(Path.Join(directory, "Pet"), PetModel.Pet4032));

    private readonly ConcurrentDictionary<(PetModel Model, bool Original), Lazy<AssemblyResult>> _petLegacy = new();

    /// <summary>
    ///  Gets the inputs directory.
    /// </summary>
    internal string Directory { get; } = directory;

    /// <summary>
    ///  Gets the PET source directory in these inputs.
    /// </summary>
    internal string PetDirectory { get; } = Path.Join(directory, "Pet");

    /// <inheritdoc cref="BasicNames.AssembleMath"/>
    internal AssemblyResult Math(bool apple) => (apple ? _appleMath : _petMath).Value;

    /// <summary>
    ///  Gets a MACRO-10 oracle for the model and revision.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC uses its original chip.</param>
    /// <returns>The immutable assembly result.</returns>
    internal AssemblyResult PetLegacy(PetModel model, bool original) => _petLegacy.GetOrAdd(
        (model, original),
        static (build, path) => new(() => PetSdkModules.AssembleBasic(path, build.Model, build.Original, BasicSourceKind.Macro10)),
        PetDirectory).Value;
}
