// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Runtime.CompilerServices;

namespace Retrocore.Debug;

/// <summary>
///  The fixed storage of a <see cref="DebugFrame"/>'s registers.
/// </summary>
[InlineArray(DebugFrame.Capacity)]
internal struct DebugFrameValues
{
    private ushort _element;
}
