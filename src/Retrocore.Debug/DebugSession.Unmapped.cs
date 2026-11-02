// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    /// <summary>
    ///  The memory area of an address a bank has no byte for, which no module's area matches.
    /// </summary>
    private enum Unmapped
    {
        /// <summary>
        ///  No storage.
        /// </summary>
        Nothing
    }
}
