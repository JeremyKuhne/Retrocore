// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    /// <summary>
    ///  How a step on the Pascal thread ends.
    /// </summary>
    private enum PascalStep
    {
        /// <summary>
        ///  At the next p-code, in this procedure or one it calls.
        /// </summary>
        Into,

        /// <summary>
        ///  At the next p-code in this procedure or a caller.
        /// </summary>
        Over,

        /// <summary>
        ///  At the next p-code in a caller.
        /// </summary>
        Out,

        /// <summary>
        ///  At the next p-code, or soon after if none runs.
        /// </summary>
        Pause
    }
}
