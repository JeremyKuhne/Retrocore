// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Documentation;

namespace Retrocore.Assembler;

/// <summary>
///  A documented routine's contract: what <c>Keeps:</c> lists, and what <c>Uses:</c> and <c>Out:</c> list when
///  there is a <c>Uses:</c>.
/// </summary>
/// <param name="Topic">The routine's documentation.</param>
/// <param name="Address">The routine's address.</param>
/// <param name="Kept">The registers <c>Keeps:</c> lists, as bits.</param>
/// <param name="KeptFlags">The flags <c>Keeps:</c> lists.</param>
/// <param name="Listed">The registers <c>Uses:</c> and <c>Out:</c> list, or null without <c>Uses:</c>.</param>
/// <param name="KeepItems">Each <c>Keeps:</c> item with its registers and flags.</param>
/// <param name="Own">The routine's other entries.</param>
internal sealed record AnalysisContract(
    DocumentationTopic Topic,
    ushort Address,
    uint Kept,
    byte KeptFlags,
    uint? Listed,
    List<(string Item, uint Registers, byte Flags)> KeepItems,
    IReadOnlySet<ushort> Own)
{
    /// <summary>
    ///  Gets the flags <c>Out:</c> names, which the routine changes.
    /// </summary>
    public byte OutFlags { get; init; }

    /// <summary>
    ///  Gets the <c>Entry:</c> label whose keeps clause this contract is, or null for the routine's own.
    /// </summary>
    public string? Entry { get; init; }
}
