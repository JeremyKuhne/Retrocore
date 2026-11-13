// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Coco;

/// <summary>
///  How a composite monitor colors the CoCo 1 and 2's 256-dot two-color graphics (PMODE 4 in color set 1): each
///  pair of dots, one lit and one dark, shows red or blue, and which is which depends on the phase the VDG's clock
///  started in.
/// </summary>
public enum CocoArtifactColors : byte
{
    /// <summary>
    ///  Lit then dark is blue, dark then lit red.
    /// </summary>
    BlueRed,

    /// <summary>
    ///  Lit then dark is red, dark then lit blue.
    /// </summary>
    RedBlue,

    /// <summary>
    ///  None, as an RGB monitor or a sharp display shows the dots.
    /// </summary>
    None
}
