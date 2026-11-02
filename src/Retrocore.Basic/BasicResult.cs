// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  What a BASIC expression evaluates to.
/// </summary>
/// <param name="Value">The value.</param>
/// <param name="Double">Whether it is Level II double precision, which PRINT writes with 16 digits.</param>
public readonly record struct BasicResult(BasicValue Value, bool Double = false);
