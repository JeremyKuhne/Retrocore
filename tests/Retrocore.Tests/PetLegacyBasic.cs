// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  Builds the independent MACRO-10 oracle for tests of the native PET BASIC sources.
/// </summary>
internal static class PetLegacyBasic
{
    /// <summary>
    ///  Assembles a PET BASIC overlay against Microsoft's original source.
    /// </summary>
    /// <param name="directory">The PET source directory.</param>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    /// <returns>The assembled overlay.</returns>
    internal static AssemblyResult Assemble(string directory, PetModel model, bool original = false) =>
        BasicNames.AssemblePetLegacy(directory, model, original);
}
