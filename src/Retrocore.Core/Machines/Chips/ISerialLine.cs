// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Chips;

/// <summary>
///  A serial port as the device at the other end of its line sees it: characters it sends, and characters delivered
///  to its receiver.
/// </summary>
public interface ISerialLine
{
    /// <summary>
    ///  Gets the CPU cycles one character takes on the line, start and stop bits included.
    /// </summary>
    int CyclesPerCharacter { get; }

    /// <summary>
    ///  Gets whether the receiver can take another character without losing one.
    /// </summary>
    bool CanReceive { get; }

    /// <summary>
    ///  Gets or sets what receives each character the port sends, as its last bit leaves.
    /// </summary>
    Action<byte>? Transmitted { get; set; }

    /// <summary>
    ///  Delivers a character from the line to the receiver.
    /// </summary>
    /// <param name="value">The character.</param>
    void Receive(byte value);
}
