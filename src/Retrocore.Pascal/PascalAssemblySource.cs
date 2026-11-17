// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

/// <summary>
///  Assembled procedures as source for Apple Pascal's Assembler.
/// </summary>
/// <param name="Text">The source.</param>
/// <param name="Notes">What it could not write as the code has it; empty when it wrote it all.</param>
public sealed record PascalAssemblySource(string Text, IReadOnlyList<string> Notes);
