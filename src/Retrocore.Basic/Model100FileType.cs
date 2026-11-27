// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  The kind of a file in the Model 100's RAM.
/// </summary>
public enum Model100FileType
{
    /// <summary>
    ///  A <c>.BA</c> file, a tokenized BASIC program.
    /// </summary>
    Basic,

    /// <summary>
    ///  A <c>.DO</c> file, text in CR LF lines.
    /// </summary>
    Text,

    /// <summary>
    ///  A <c>.CO</c> file, machine code with its start, length and entry.
    /// </summary>
    Machine
}
