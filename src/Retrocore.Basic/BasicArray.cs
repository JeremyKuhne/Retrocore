// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  An array in BASIC's array table.
/// </summary>
/// <param name="Name">Its name as BASIC stores it, with its type's suffix.</param>
/// <param name="Kind">What its elements hold.</param>
/// <param name="Address">Where its entry starts.</param>
/// <param name="Dimensions">How many elements each subscript has, in subscript order: DIM A(10) has 11.</param>
/// <param name="ElementsAddress">Where its first element starts.</param>
/// <param name="ElementSize">The bytes in each element.</param>
public sealed record BasicArray(
    string Name,
    BasicVariableKind Kind,
    int Address,
    IReadOnlyList<int> Dimensions,
    int ElementsAddress,
    int ElementSize)
{
    /// <summary>
    ///  Gets the number of elements.
    /// </summary>
    public int Count => Dimensions.Aggregate(1, (count, size) => count * size);

    /// <summary>
    ///  Gets the address of an element; the first subscript varies fastest, as BASIC lays them out.
    /// </summary>
    /// <param name="subscripts">The subscripts, in order.</param>
    /// <returns>The element's address.</returns>
    /// <exception cref="ArgumentOutOfRangeException">The subscripts are not in the array.</exception>
    public int ElementAddress(IReadOnlyList<int> subscripts)
    {
        ArgumentNullException.ThrowIfNull(subscripts);
        if (subscripts.Count != Dimensions.Count)
        {
            throw new ArgumentOutOfRangeException(nameof(subscripts), "?BAD SUBSCRIPT: the wrong number of subscripts.");
        }

        int index = 0;
        for (int dimension = Dimensions.Count - 1; dimension >= 0; dimension--)
        {
            if (subscripts[dimension] < 0 || subscripts[dimension] >= Dimensions[dimension])
            {
                throw new ArgumentOutOfRangeException(nameof(subscripts), "?BAD SUBSCRIPT: a subscript is out of range.");
            }

            index = index * Dimensions[dimension] + subscripts[dimension];
        }

        return ElementsAddress + index * ElementSize;
    }

    /// <summary>
    ///  Gets the subscripts of the element at an index in memory order.
    /// </summary>
    /// <param name="index">The element's index.</param>
    /// <returns>Its subscripts.</returns>
    public int[] Subscripts(int index)
    {
        int[] subscripts = new int[Dimensions.Count];
        for (int dimension = 0; dimension < Dimensions.Count; dimension++)
        {
            subscripts[dimension] = index % Dimensions[dimension];
            index /= Dimensions[dimension];
        }

        return subscripts;
    }
}
