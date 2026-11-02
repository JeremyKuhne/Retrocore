// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  A label in BASIC text: a line of its own, <c>name:</c> or <c>@name</c>, that names the line after it.
/// </summary>
/// <param name="Name">The name, uppercase, without its <c>@</c> or colon.</param>
/// <param name="Line">The zero-based line of the text it is on.</param>
/// <param name="Start">The column it starts at.</param>
/// <param name="End">The column past it.</param>
/// <param name="Number">The number of the line it names; -1 when there is none after it.</param>
public sealed record BasicLabel(string Name, int Line, int Start, int End, int Number);
