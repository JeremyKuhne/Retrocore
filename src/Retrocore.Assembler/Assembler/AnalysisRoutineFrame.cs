// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  What one push saved on a stack.
/// </summary>
/// <param name="Bytes">The bytes pushed.</param>
/// <param name="Units">The values, in register order.</param>
internal sealed record AnalysisRoutineFrame(int Bytes, List<AnalysisRoutineUnit> Units);
