// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Commodore;

/// <summary>
///  The IEEE-488 bus between a PET and its devices: eight data lines and eight control lines, each open collector,
///  low while any device pulls it low.
/// </summary>
/// <remarks>
///  <para>
///   The lines are active low, so a released line reads high. The PET is the controller: it pulls ATN to send
///   commands, and talkers and listeners hand each byte over with DAV, NRFD and NDAC, EOI marking the last.
///  </para>
/// </remarks>
public sealed class Ieee488Bus
{
    private readonly List<Ieee488Port> _ports = [];

    /// <summary>
    ///  Connects a device.
    /// </summary>
    /// <returns>The device's port, all lines released.</returns>
    public Ieee488Port Attach()
    {
        Ieee488Port port = new();
        _ports.Add(port);
        return port;
    }

    /// <summary>
    ///  Disconnects a device, releasing whatever it held low.
    /// </summary>
    /// <param name="port">Its port.</param>
    public void Detach(Ieee488Port port) => _ports.Remove(port);

    /// <summary>
    ///  Gets the data lines' levels, DIO1 in bit 0: a 0 where any device pulls the line low.
    /// </summary>
    public byte Data
    {
        get
        {
            byte data = 0xFF;
            foreach (Ieee488Port port in _ports) { data &= port.Data; }
            return data;
        }
    }

    /// <summary>
    ///  Gets whether a control line is high, released by every device.
    /// </summary>
    /// <param name="line">The line.</param>
    /// <returns>Its level.</returns>
    public bool High(Ieee488Lines line)
    {
        foreach (Ieee488Port port in _ports)
        {
            if ((port.Low & line) != 0) { return false; }
        }

        return true;
    }
}
