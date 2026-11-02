// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    /// <summary>
    ///  One shown stack frame: a CPU frame, or one macro level of it.
    /// </summary>
    /// <param name="Cpu">The CPU frame index, whose registers the frame shows.</param>
    /// <param name="Pc">The frame's instruction address.</param>
    /// <param name="Line">The frame's source line, or null where no module describes the code.</param>
    private readonly record struct DisplayFrame(int Cpu, ushort Pc, SourceLine? Line);
}
