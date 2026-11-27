// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  What Atari BASIC's tokenizer made of a line.
/// </summary>
/// <param name="Tokens">
///  The line's bytes after its number and length: each statement's offset, token and tokens. Empty when the line is
///  refused.
/// </param>
/// <param name="Sources">Each token's character in the statements' text, or -1 for a statement's offset.</param>
/// <param name="Error">What the ROM reports when it refuses the line, or null.</param>
/// <param name="Column">
///  Where in the statements' text the error is: for a syntax error, the furthest place the checker reached; for
///  error 4 or 14, where the checker was.
/// </param>
internal sealed record AtariSyntaxResult(byte[] Tokens, int[] Sources, string? Error, int Column);
