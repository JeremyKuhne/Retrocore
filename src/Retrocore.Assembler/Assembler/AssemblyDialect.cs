// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Selects the syntax of one source document.
/// </summary>
public enum AssemblyDialect : byte
{
    /// <summary>
    ///  Native Retrocore assembly.
    /// </summary>
    Native,

    /// <summary>
    ///  ca65 assembly.
    /// </summary>
    Ca65,

    /// <summary>
    ///  Merlin 8/Pro assembly.
    /// </summary>
    Merlin,

    /// <summary>
    ///  The MACRO-10 subset used by Microsoft's 6502 BASIC sources.
    /// </summary>
    Macro10
}
