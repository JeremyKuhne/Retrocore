// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Devices;

/// <summary>
///  A tape drive's transport.
/// </summary>
/// <param name="Motor">Whether the machine has the motor running.</param>
/// <param name="Mode">Whether the tape plays or records.</param>
/// <param name="Position">The bytes played or recorded so far.</param>
/// <param name="Length">The tape's bytes: its length when playing, what is recorded when recording.</param>
public readonly record struct TapeTransport(bool Motor, TapeMode Mode, long Position, long Length);
