// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Acorn;

/// <summary>
///  The BBC Micro's clocks, all divided from its 16 MHz crystal.
/// </summary>
public static class BbcTiming
{
    /// <summary>
    ///  The CPU's clock: 2 MHz, the machine's cycle.
    /// </summary>
    public const int CpuHertz = 2_000_000;

    /// <summary>
    ///  The 1 MHz bus clock: the VIAs, the ADC, the keyboard's scan and the slow peripherals.
    /// </summary>
    public const int SlowHertz = 1_000_000;

    /// <summary>
    ///  The CPU cycles in one 50 Hz frame of 312 lines of 64 µs, as the operating system programs the 6845.
    /// </summary>
    public const int CyclesPerFrame = 312 * 128;

    /// <summary>
    ///  The CPU cycles the sound chip's divided clock takes: its 4 MHz clock over 16, 250 kHz.
    /// </summary>
    public const int CyclesPerSoundStep = 8;
}
