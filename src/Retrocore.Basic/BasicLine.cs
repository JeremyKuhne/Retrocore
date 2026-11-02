// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  A program line as BASIC stores it.
/// </summary>
/// <param name="Number">The line number.</param>
/// <param name="Tokens">The statements, tokenized, without the zero that ends the line.</param>
public readonly record struct BasicLine(int Number, ReadOnlyMemory<byte> Tokens);
