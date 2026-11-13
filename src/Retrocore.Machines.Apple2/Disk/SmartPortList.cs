// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple2;

/// <summary>
///  A SmartPort call's parameter list: its count, the unit, the buffer, then the command's own parameters.
/// </summary>
/// <remarks>
///  <para>
///   An extended call's buffer takes four bytes and its block four, against two and three for a standard call. A IIe
///   reaches only bank 0, so the buffer's upper bytes are ignored, as Apple's firmware ignores them on a IIe.
///  </para>
/// </remarks>
/// <param name="bus">The bus whose memory holds the list.</param>
/// <param name="address">The list's address.</param>
/// <param name="extended">Whether the call is an extended one.</param>
internal readonly struct SmartPortList(Apple2Bus bus, ushort address, bool extended)
{
    /// <summary>
    ///  Gets whether the call is an extended one.
    /// </summary>
    public bool Extended => extended;

    /// <summary>
    ///  Gets the unit: 0 for the controller, else a drive.
    /// </summary>
    public int Unit => bus.Peek((ushort)(address + 1));

    /// <summary>
    ///  Gets the buffer's address.
    /// </summary>
    public ushort Buffer => (ushort)(bus.Peek((ushort)(address + 2)) | (bus.Peek((ushort)(address + 3)) << 8));

    /// <summary>
    ///  Gets the block: three bytes, or four in an extended list.
    /// </summary>
    public uint Block => (uint)(Parameter(0) | (Parameter(1) << 8) | (Parameter(2) << 16) | (extended ? Parameter(3) << 24 : 0));

    /// <summary>
    ///  Gets one of the command's own parameters, after the buffer.
    /// </summary>
    /// <param name="index">The parameter, from 0.</param>
    /// <returns>Its byte.</returns>
    public byte Parameter(int index) => bus.Peek((ushort)(address + (extended ? 6 : 4) + index));
}
