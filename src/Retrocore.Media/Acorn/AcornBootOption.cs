// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Acorn;

/// <summary>
///  What the DFS does with <c>$.!BOOT</c> on SHIFT-BREAK: the disk's boot option, which <c>*OPT 4</c> sets.
/// </summary>
public enum AcornBootOption
{
    /// <summary>
    ///  Nothing.
    /// </summary>
    None = 0,

    /// <summary>
    ///  <c>*LOAD $.!BOOT</c>.
    /// </summary>
    Load = 1,

    /// <summary>
    ///  <c>*RUN $.!BOOT</c>.
    /// </summary>
    Run = 2,

    /// <summary>
    ///  <c>*EXEC $.!BOOT</c>: its lines are typed as commands.
    /// </summary>
    Exec = 3
}
