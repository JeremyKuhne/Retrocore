// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    /// <summary>
    ///  The names the sources give addresses that a search for them takes.
    /// </summary>
    [Flags]
    private enum SourceNameKinds
    {
        /// <summary>
        ///  Neither.
        /// </summary>
        None = 0,

        /// <summary>
        ///  The labels that apply now.
        /// </summary>
        Labels = 1,

        /// <summary>
        ///  The constants the space's CPU addresses memory through.
        /// </summary>
        Constants = 2,

        /// <summary>
        ///  Both.
        /// </summary>
        All = Labels | Constants
    }
}
