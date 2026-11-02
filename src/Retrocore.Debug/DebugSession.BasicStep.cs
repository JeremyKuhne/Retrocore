// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    /// <summary>
    ///  What the BASIC thread is running to.
    /// </summary>
    private enum BasicStep
    {
        /// <summary>
        ///  The next statement, inside a GOSUB too, or a machine-code routine the statement calls.
        /// </summary>
        Into,

        /// <summary>
        ///  The next statement in this GOSUB or one it returns to.
        /// </summary>
        Over,

        /// <summary>
        ///  The statement after this GOSUB's RETURN.
        /// </summary>
        Out,

        /// <summary>
        ///  The next statement BASIC starts.
        /// </summary>
        Pause,

        /// <summary>
        ///  The first statement of a launched BASIC file.
        /// </summary>
        Entry
    }
}
