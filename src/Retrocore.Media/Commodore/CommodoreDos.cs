// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Commodore;

/// <summary>
///  The DOS whose layout a 35-track disk's sectors follow.
/// </summary>
public enum CommodoreDos
{
    /// <summary>
    ///  DOS 2, of the 4040 (and the 1541 after it): 21, 19, 18 and 17 sectors by zone, 683 in all, as a D64 image
    ///  holds them.
    /// </summary>
    Dos2,

    /// <summary>
    ///  DOS 1, of the 2040 and 3040: 21, 20, 18 and 17 sectors by zone, 690 in all, as a D67 image holds them.
    /// </summary>
    Dos1
}
