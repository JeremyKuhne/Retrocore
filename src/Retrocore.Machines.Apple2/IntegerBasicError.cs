// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple2;

/// <summary>
///  A line Integer BASIC refused, and why.
/// </summary>
/// <param name="Line">The zero-based index of the line in the text.</param>
/// <param name="Message">What was wrong, such as <c>*** SYNTAX ERR</c>.</param>
public sealed record IntegerBasicError(int Line, string Message);
