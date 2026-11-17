// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Desktop;

/// <summary>
///  Whether a row opens to its children, and how it starts.
/// </summary>
internal enum TreeState
{
    /// <summary>
    ///  No children.
    /// </summary>
    None,

    /// <summary>
    ///  Children, shown once opened.
    /// </summary>
    Collapsed,

    /// <summary>
    ///  Children, shown until closed.
    /// </summary>
    Expanded,
}