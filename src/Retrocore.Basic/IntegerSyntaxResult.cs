// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  A typed line as Integer BASIC's tokenizer leaves it.
/// </summary>
/// <param name="Tokens">
///  The tokens, as the line is stored but for its first byte: the line number's constant marker, which storing
///  replaces with the line's length. Empty when the line is refused.
/// </param>
/// <param name="Sources">For each token, the index of the character it was made from.</param>
/// <param name="Error">The error, or null when the line is accepted.</param>
/// <param name="Column">For an error, the index of the character the tokenizer had reached.</param>
internal sealed record IntegerSyntaxResult(byte[] Tokens, int[] Sources, IntegerSyntaxError? Error, int Column);
