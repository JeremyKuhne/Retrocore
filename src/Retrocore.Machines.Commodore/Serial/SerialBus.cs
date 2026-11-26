// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Commodore.Serial;

/// <summary>
///  The Commodore serial bus between a VIC-20, 64 or 128 and its drives and printers: ATN, CLK, DATA and SRQ, each
///  open collector, low while any device pulls it low.
/// </summary>
/// <remarks>
///  <para>
///   The lines are active low, so a released line reads high. The computer pulls ATN to send a command byte; every
///   device answers by pulling DATA. A talker sends each byte a bit at a time on DATA, clocked by CLK, and the
///   listener holds DATA low between bytes until it is ready for the next.
///  </para>
/// </remarks>
public sealed class SerialBus
{
    private readonly List<SerialPort> _ports = [];

    /// <summary>
    ///  Connects a device.
    /// </summary>
    /// <returns>The device's port, all lines released.</returns>
    public SerialPort Attach()
    {
        SerialPort port = new();
        _ports.Add(port);
        return port;
    }

    /// <summary>
    ///  Disconnects a device, releasing whatever it held low.
    /// </summary>
    /// <param name="port">Its port.</param>
    public void Detach(SerialPort port) => _ports.Remove(port);

    /// <summary>
    ///  Gets the lines some device pulls low.
    /// </summary>
    public SerialLines Low
    {
        get
        {
            SerialLines low = SerialLines.None;
            foreach (SerialPort port in _ports) { low |= port.Low; }
            return low;
        }
    }

    /// <summary>
    ///  Gets whether a line is high, released by every device.
    /// </summary>
    /// <param name="line">The line.</param>
    /// <returns>Its level.</returns>
    public bool High(SerialLines line) => (Low & line) == 0;
}
