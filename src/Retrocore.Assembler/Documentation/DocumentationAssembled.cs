// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  What the assembler took from one source file, so its documentation follows the same <c>.using</c> lines.
/// </summary>
/// <param name="UsingAssembled">Whether the <c>.using</c> on a zero-based line was assembled.</param>
/// <param name="InvokedUsings">The names of each <c>.using</c> a macro invoked on a line produced.</param>
public sealed record DocumentationAssembled(Func<int, bool> UsingAssembled, Func<int, IReadOnlyList<string[]>> InvokedUsings);
