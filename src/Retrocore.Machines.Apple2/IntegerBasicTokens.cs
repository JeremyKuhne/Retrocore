// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple2;

/// <summary>
///  An Integer BASIC program as Integer BASIC tokenized it, and the lines it refused.
/// </summary>
/// <param name="Program">The program's bytes, from PP up to HIMEM.</param>
/// <param name="Errors">Each refused line and what Integer BASIC said about it.</param>
public sealed record IntegerBasicTokens(byte[] Program, IReadOnlyList<IntegerBasicError> Errors)
{
    /// <summary>
    ///  Gets whether Integer BASIC took every line.
    /// </summary>
    public bool Success => Errors.Count == 0;
}
