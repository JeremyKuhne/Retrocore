// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  A verified blocking input path and the evidence it can provide for one key in flight.
/// </summary>
/// <param name="Profile">The verified firmware operation.</param>
/// <param name="Backend">The device or logical buffer receiving the input.</param>
/// <param name="Send">Delivers a key and reports the evidence immediately available.</param>
/// <param name="Observe">Checks further receipt evidence at instruction boundaries, when needed.</param>
internal sealed record GuestInputPath(
    string Profile,
    string Backend,
    Func<int, InputReceipt> Send,
    Func<int, InputReceipt>? Observe = null);
