// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  A value a push saved: one register's, or the eight flags' when the flags register was pushed.
/// </summary>
/// <param name="Flags">Whether the unit is the flags.</param>
/// <param name="Slot">The register's bit.</param>
/// <param name="Values">The values: one, or the eight flags'.</param>
internal sealed record AnalysisRoutineUnit(bool Flags, int Slot, AnalysisValue[] Values);
