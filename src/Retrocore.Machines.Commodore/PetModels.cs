// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Commodore;

/// <summary>
///  What each <see cref="PetModel"/> has.
/// </summary>
public static class PetModels
{
    /// <summary>
    ///  Gets the model's BASIC: 1, 2 or 4.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <returns>The version.</returns>
    public static int BasicVersion(this PetModel model) => model switch
    {
        PetModel.Pet2001 => 1,
        PetModel.Pet2001Basic2 => 2,
        _ => 4
    };

    /// <summary>
    ///  Gets whether the model has the business keyboard.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <returns>Whether it does.</returns>
    public static bool HasBusinessKeyboard(this PetModel model) => model == PetModel.Pet4032Business;
}
