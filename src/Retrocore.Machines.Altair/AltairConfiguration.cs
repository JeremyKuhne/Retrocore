// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Altair;

/// <summary>
///  An Altair 8800's boards and switches.
/// </summary>
public sealed class AltairConfiguration
{
    /// <summary>
    ///  The baud rates the 88-2SIO's jumpers offer.
    /// </summary>
    public static IReadOnlyList<int> BaudRates { get; } = [110, 150, 300, 600, 1200, 2400, 4800, 9600];

    /// <summary>
    ///  Gets or sets the RAM from address 0, in kilobytes: 1 to 64.
    /// </summary>
    public int RamKilobytes { get; set; } = 64;

    /// <summary>
    ///  Gets or sets the front panel's 16 switches; the high 8 are the sense switches <c>IN $FF</c> reads.
    /// </summary>
    public ushort Switches { get; set; }

    /// <summary>
    ///  Gets or sets the 88-2SIO's baud rate, the same on both ports.
    /// </summary>
    public int BaudRate { get; set; } = 9600;

    /// <summary>
    ///  Checks the settings.
    /// </summary>
    /// <exception cref="ArgumentException">A setting is out of range.</exception>
    public void Validate()
    {
        if (RamKilobytes is < 1 or > 64) { throw new ArgumentException("RAM must be 1 to 64 KB."); }
        if (!BaudRates.Contains(BaudRate))
        {
            throw new ArgumentException($"The 88-2SIO's baud rate must be one of {string.Join(", ", BaudRates)}.");
        }
    }
}
