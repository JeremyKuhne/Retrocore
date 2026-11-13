// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

/// <summary>
///  A variable or parameter a compiler listing declares, at a word of its procedure's data, as <c>LDL</c> and
///  <c>LDO</c> number them from 1.
/// </summary>
/// <param name="Name">Its name, as declared.</param>
/// <param name="Word">Its first word.</param>
/// <param name="Words">How many words it takes, or 0 when the listing does not say.</param>
/// <param name="Type">Its type, as declared, such as <c>INTEGER</c> or <c>STRING[20]</c>.</param>
/// <param name="Reference">
///  Whether it is a <c>VAR</c> parameter, whose word holds the address of the variable the caller passed.
/// </param>
public sealed record PascalVariable(string Name, int Word, int Words, string Type, bool Reference = false);
