// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Devices;

/// <summary>
///  What a connected controller is doing: its left stick and its buttons. Machines map it onto their own inputs,
///  such as the Apple II's game port.
/// </summary>
/// <param name="Name">The controller's name, such as "Xbox Series X Controller".</param>
/// <param name="LeftX">The left stick's X, from -32768 (left) to 32767 (right).</param>
/// <param name="LeftY">The left stick's Y, from -32768 (up) to 32767 (down).</param>
/// <param name="Buttons">The buttons held down.</param>
public readonly record struct ControllerState(string Name, short LeftX, short LeftY, ControllerButtons Buttons);
