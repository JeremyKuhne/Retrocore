// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  What a documented routine promises its caller: the registers, flags and memory it keeps, and, when it has a
///  <c>Uses:</c> section, every register it may change.
/// </summary>
/// <param name="Routine">The routine's name.</param>
/// <param name="Registers">Kept registers and flags, by instruction-set name, such as <c>A</c> or <c>P</c>.</param>
/// <param name="Memory">Kept memory: a name, its address and its length.</param>
/// <param name="Changes">Registers the documentation says may change, or null when it has no <c>Uses:</c>.</param>
internal sealed record DebugContract(
    string Routine,
    IReadOnlyList<string> Registers,
    IReadOnlyList<(string Name, ushort Address, int Length)> Memory,
    IReadOnlySet<string>? Changes);
