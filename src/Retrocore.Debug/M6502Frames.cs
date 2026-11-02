// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  Copies 6502 registers into debug frames.
/// </summary>
internal static class M6502Frames
{
    // A frame lists the description's registers in order: A, X, Y, S, P, PC.
    private const int RegisterA = 0;
    private const int RegisterX = 1;
    private const int RegisterY = 2;
    private const int RegisterS = 3;
    private const int RegisterP = 4;
    private const int RegisterPC = 5;

    /// <summary>
    ///  Copies a 6502's registers into a frame.
    /// </summary>
    /// <param name="registers">The registers.</param>
    /// <returns>The frame.</returns>
    internal static DebugFrame Of(ProcessorRegisters registers)
    {
        DebugFrame frame = new()
        {
            ProgramCounter = registers.ProgramCounter,
            StackPointer = registers.StackPointer
        };

        frame[RegisterA] = registers.Accumulator;
        frame[RegisterX] = registers.X;
        frame[RegisterY] = registers.Y;
        frame[RegisterS] = registers.StackPointer;
        frame[RegisterP] = (byte)registers.Status;
        frame[RegisterPC] = registers.ProgramCounter;
        return frame;
    }
}
