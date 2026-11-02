// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    /// <summary>
    ///  A BASIC file in the workspace: launched, or with breakpoints in it, and what it compiles to.
    /// </summary>
    /// <param name="Path">The file's full path.</param>
    /// <param name="Source">Its text, analyzed, with the line map from its numbers to its lines.</param>
    private sealed record BasicFile(string Path, BasicSource Source);
}
