// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  The calls and interrupts in progress, as a CPU's call tracker follows them.
/// </summary>
internal interface IDebugCallStack
{
    /// <summary>
    ///  Forgets every call.
    /// </summary>
    void Reset();

    /// <summary>
    ///  Gets the frames: the current registers, then each caller's at its call, innermost first.
    /// </summary>
    /// <param name="current">The current registers.</param>
    /// <returns>The frames.</returns>
    DebugFrame[] Frames(in DebugFrame current);

    /// <summary>
    ///  Gets how many calls are in progress.
    /// </summary>
    /// <returns>The depth.</returns>
    int Depth();

    /// <summary>
    ///  Gets where the innermost call returns: the address and the stack pointer it returns with.
    /// </summary>
    /// <returns>The target, or null when no call is tracked.</returns>
    (ushort Address, int StackPointer)? ReturnTarget();
}
