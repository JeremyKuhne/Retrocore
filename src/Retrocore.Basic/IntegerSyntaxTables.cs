// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  The syntax tables of a BASIC of the Integer BASIC family, as its tokenizer reads them.
/// </summary>
/// <param name="Table">The table's two pages, $EC00-$EDFF.</param>
/// <param name="Index">SYNTABLNDX: where each of the 32 rules starts.</param>
/// <param name="IndexStart">Where SYNTABLNDX is in memory, which the tokenizer can read as table bytes.</param>
/// <param name="ReservedWords">
///  Whether a keyword token of $85 or more ends a name instead (KEYMATCHED), as Integer BASIC's reserved words do.
/// </param>
internal sealed record IntegerSyntaxTables(byte[] Table, byte[] Index, int IndexStart, bool ReservedWords);
