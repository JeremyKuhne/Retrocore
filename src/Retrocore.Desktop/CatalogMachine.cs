// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Desktop;

/// <summary>
///  A machine Retrocore can start.
/// </summary>
/// <param name="Id">A stable key, such as <c>apple2-iiplus</c>.</param>
/// <param name="Label">The machine's name.</param>
/// <param name="Detail">What it is.</param>
/// <param name="Configuration">The launch options that make it this machine.</param>
/// <param name="Choices">Its settings.</param>
internal sealed record CatalogMachine(
    string Id,
    string Label,
    string Detail,
    IReadOnlyDictionary<string, string> Configuration,
    IReadOnlyList<MachineChoice> Choices);