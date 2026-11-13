// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

/// <summary>
///  A decompiled program.
/// </summary>
/// <param name="Source">The Pascal source.</param>
/// <param name="Warnings">
///  What could not be decompiled, or may not compile to the same code; empty when all could.
/// </param>
public sealed record PascalDecompilation(string Source, IReadOnlyList<string> Warnings);
