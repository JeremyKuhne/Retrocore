// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  Evidence for a single key offered to a guest input path.
/// </summary>
internal enum InputReceipt
{
    /// <summary>
    ///  The key was delivered to the device; neither acknowledgement nor admission has been observed.
    /// </summary>
    Pending,

    /// <summary>
    ///  The firmware acknowledged the hardware, but admission is not known yet.
    /// </summary>
    Acknowledged,

    /// <summary>
    ///  The verified firmware read or software-buffer admission occurred.
    /// </summary>
    Accepted,

    /// <summary>
    ///  The backend refused to deliver the key.
    /// </summary>
    Rejected,

    /// <summary>
    ///  The key was delivered but its disposition cannot be verified.
    /// </summary>
    Unconfirmed
}
