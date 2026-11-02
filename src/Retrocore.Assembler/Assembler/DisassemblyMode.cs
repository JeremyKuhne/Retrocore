// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Determines how an image's instruction boundaries are discovered.
/// </summary>
public enum DisassemblyMode : byte
{
    /// <summary>
    ///  Decodes sequentially, except where the caller has pinned data.
    /// </summary>
    Linear,

    /// <summary>
    ///  Traces reachable code from entry points and explicitly pinned code regions.
    /// </summary>
    Flow
}
