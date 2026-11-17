// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Altair;

/// <summary>
///  The Altair's clocks.
/// </summary>
public static class AltairTiming
{
    /// <summary>
    ///  The 8080's clock: 2 MHz, a 500 ns state.
    /// </summary>
    public const int ClockHertz = 2_000_000;

    /// <summary>
    ///  The CPU cycles in one 60 Hz terminal frame.
    /// </summary>
    public const int CyclesPerFrame = ClockHertz / 60;

    /// <summary>
    ///  Gets the CPU cycles one serial character takes at a baud rate: ten bits, a start bit, eight data bits and a
    ///  stop bit.
    /// </summary>
    /// <param name="baud">The baud rate.</param>
    /// <returns>The cycles.</returns>
    public static int CyclesPerCharacter(int baud) => ClockHertz * 10 / baud;
}
