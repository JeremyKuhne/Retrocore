// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Altair;

/// <summary>
///  The serial board the terminal is on.
/// </summary>
public enum AltairConsole
{
    /// <summary>
    ///  The 88-2SIO's first port, at ports $10 and $11.
    /// </summary>
    Serial2Sio,

    /// <summary>
    ///  The 88-SIO, at ports $00 and $01.
    /// </summary>
    Sio
}
