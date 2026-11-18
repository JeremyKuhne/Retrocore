// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Commodore;

/// <summary>
///  Which PET: the board and keyboard, and the ROMs in its sockets.
/// </summary>
public enum PetModel
{
    /// <summary>
    ///  The PET 2001 of 1977: the static board, the chiclet keyboard, a white screen and BASIC 1.
    /// </summary>
    Pet2001,

    /// <summary>
    ///  The PET 2001 with Commodore's upgrade ROMs, BASIC 2, the first BASIC whose IEEE-488 routines work with disk
    ///  drives. The ROMs are the 2001-N's.
    /// </summary>
    Pet2001Basic2,

    /// <summary>
    ///  The PET 4016 and 4032 of 1980: the 2001-N's board without a CRTC, the graphics keyboard, a green screen and
    ///  BASIC 4, with its disk commands. The 4016 has 16K and the 4032 32K.
    /// </summary>
    Pet4032,

    /// <summary>
    ///  The PET 4032 with the business keyboard and its editor, 901474-02.
    /// </summary>
    Pet4032Business
}
