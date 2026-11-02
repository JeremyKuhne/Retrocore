// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  A FOR loop in progress, as its entry on BASIC's stack holds it.
/// </summary>
/// <param name="VariableAddress">The loop variable's value address.</param>
/// <param name="Step">The STEP.</param>
/// <param name="Limit">The TO limit.</param>
/// <param name="Line">The line of the FOR statement.</param>
public sealed record BasicLoop(int VariableAddress, double Step, double Limit, int Line);
