// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  The debugger's name for the Apple-1's $E000 bank while Apple-1 BASIC is in it, so BASIC's source maps there only
///  then.
/// </summary>
internal enum Apple1BasicArea
{
    /// <summary>
    ///  Apple-1 BASIC, in RAM at $E000-$EFFF.
    /// </summary>
    Basic
}
