// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;

namespace Retrocore.Debug.Project;

/// <summary>
///  An entry of a project's or target's <c>sources</c>: a file or a pattern, and how to read what it names.
/// </summary>
/// <param name="Path">The file or pattern, relative to the project's folder.</param>
/// <param name="Dialect">The dialect, or null for native unless a file's first-line pragma names one.</param>
/// <param name="Kind">The language: <c>asm</c>, or <c>basic</c>, which does not build yet.</param>
internal sealed record ProjectSource(string Path, AssemblyDialect? Dialect, string Kind = "asm");
