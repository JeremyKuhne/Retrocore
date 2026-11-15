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
    ///  The baud rates the 88-2SIO's and 88-SIO's jumpers offer.
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
    ///  Gets or sets the terminal's baud rate, on the 88-2SIO's two ports and the 88-SIO.
    /// </summary>
    public int BaudRate { get; set; } = 9600;

    /// <summary>
    ///  Gets or sets the serial board the terminal is on.
    /// </summary>
    public AltairConsole Console { get; set; } = AltairConsole.Serial2Sio;

    /// <summary>
    ///  Gets or sets whether the 88-ACR cassette interface, with its recorder, is at ports $06 and $07.
    /// </summary>
    public bool CassetteInterface { get; set; } = true;

    /// <summary>
    ///  Gets or sets whether the terminal types lowercase letters as capitals, as Altair BASIC needs.
    /// </summary>
    public bool UpperCase { get; set; }

    /// <summary>
    ///  Checks the settings.
    /// </summary>
    /// <exception cref="ArgumentException">A setting is out of range.</exception>
    public void Validate()
    {
        if (!Enum.IsDefined(Console)) { throw new ArgumentException("The console must be the 88-2SIO or the 88-SIO."); }
        if (RamKilobytes is < 1 or > 64) { throw new ArgumentException("RAM must be 1 to 64 KB."); }
        if (!BaudRates.Contains(BaudRate))
        {
            throw new ArgumentException($"The 88-2SIO's baud rate must be one of {string.Join(", ", BaudRates)}.");
        }
    }
}
