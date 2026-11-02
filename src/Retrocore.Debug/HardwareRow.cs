// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug;

/// <summary>
///  One row of a machine's installed hardware, as the Retro Devices view lists it: a slot, a card or a built-in part.
/// </summary>
/// <param name="Id">A stable identifier, such as <c>slot6</c>.</param>
/// <param name="Name">What the row is, such as <c>Slot 6</c>.</param>
/// <param name="Value">What is there, such as <c>Disk II controller</c>, or <c>empty</c>.</param>
/// <param name="Description">What it does, and which launch option installs or changes it.</param>
/// <param name="Devices">The ids of the devices on it, such as its drives, listed under it.</param>
/// <param name="Actions">
///  What <c>retro/hardware</c> can do to it: <c>addCard</c> for a free slot, <c>removeCard</c> for a card that can
///  come out.
/// </param>
internal sealed record HardwareRow(
    string Id,
    string Name,
    string Value,
    string Description,
    string[]? Devices = null,
    string[]? Actions = null)
{
    /// <summary>
    ///  Writes the rows for <c>retro/devices</c>.
    /// </summary>
    /// <param name="rows">The rows, in order.</param>
    /// <returns>The <c>hardware</c> array.</returns>
    internal static JsonArray Json(IEnumerable<HardwareRow> rows) =>
        rows.Select(row => new JsonObject
        {
            ["id"] = row.Id,
            ["name"] = row.Name,
            ["value"] = row.Value,
            ["description"] = row.Description,
            ["devices"] = (row.Devices ?? []).ToJsonArray(),
            ["actions"] = (row.Actions ?? []).ToJsonArray()
        }).ToJsonArray();

    /// <summary>
    ///  Gets the row for an empty slot.
    /// </summary>
    /// <param name="slot">The slot's number.</param>
    /// <param name="description">What it would take to fill it, or what uses its space.</param>
    /// <param name="free">Whether a card can be added to it.</param>
    /// <returns>The row.</returns>
    internal static HardwareRow Empty(int slot, string description, bool free = false) =>
        new($"slot{slot}", $"Slot {slot}", "empty", description, Actions: free ? ["addCard"] : null);
}
