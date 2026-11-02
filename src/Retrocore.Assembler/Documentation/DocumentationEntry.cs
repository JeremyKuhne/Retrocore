// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  One entry of a section such as <c>In:</c>: a name and its meaning.
/// </summary>
/// <param name="Name">The register, flag, symbol or parameter.</param>
/// <param name="Meaning">What it means.</param>
/// <param name="Line">The zero-based source line.</param>
public sealed record DocumentationEntry(string Name, string Meaning, int Line);
