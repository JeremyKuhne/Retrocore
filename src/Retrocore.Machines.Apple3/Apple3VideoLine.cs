// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple3;

/// <summary>
///  What the video hardware was set to as the beam started a line.
/// </summary>
/// <param name="Switches">The video switches, <see cref="Apple3Bus.VideoSwitches"/>.</param>
/// <param name="Scroll">The smooth-scroll offset, or 0 when smooth scrolling is off.</param>
/// <param name="VideoOn">Whether the environment register turns video on.</param>
/// <param name="ColorText">Whether VIA 1's PA6 allows color text.</param>
internal readonly record struct Apple3VideoLine(byte Switches, byte Scroll, bool VideoOn, bool ColorText);
