// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  A <c>.using</c> the assembly took: where it is and the scope names it gives.
/// </summary>
/// <param name="Location">The directive's location; within a macro's expansion, from its invocation.</param>
/// <param name="Names">The scope names as written.</param>
/// <param name="AtInvocation">For one a macro gives, whether it is at the expansion's top level.</param>
public sealed record AssemblyUsing(AssemblyLocation? Location, IReadOnlyList<string> Names, bool AtInvocation = true);
