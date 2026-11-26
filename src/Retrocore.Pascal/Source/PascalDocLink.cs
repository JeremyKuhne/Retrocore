// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal.Source;

/// <summary>
///  A link in a documentation comment, <c>&lt;Name&gt;</c> or <c>&lt;text at Name&gt;</c>, and where it is.
/// </summary>
/// <param name="Target">The name it links to, which may be qualified (<c>Outer.Inner</c>).</param>
/// <param name="Line">Its line, from 0.</param>
/// <param name="Column">Its first column, from 0: the <c>&lt;</c>.</param>
/// <param name="EndColumn">The column after its <c>&gt;</c>.</param>
public sealed record PascalDocLink(string Target, int Line, int Column, int EndColumn);
