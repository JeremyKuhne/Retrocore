// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  How the machine paces or completes media work.
/// </summary>
internal enum MediaSpeed
{
    /// <summary>
    ///  Retain the selected machine speed and all guest cycles.
    /// </summary>
    Normal,

    /// <summary>
    ///  Run all guest cycles without host pacing.
    /// </summary>
    Fast,

    /// <summary>
    ///  Skip eligible work; otherwise use Fast.
    /// </summary>
    Skip
}
