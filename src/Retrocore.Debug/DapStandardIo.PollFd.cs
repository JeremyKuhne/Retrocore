// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Runtime.InteropServices;

namespace Retrocore.Debug;

internal static partial class DapStandardIo
{
    /// <summary>
    ///  A POSIX <c>pollfd</c>.
    /// </summary>
    [StructLayout(LayoutKind.Sequential)]
    private struct PollFd
    {
        /// <summary>
        ///  The input file descriptor.
        /// </summary>
        internal int Fd;

        /// <summary>
        ///  The requested events.
        /// </summary>
        internal short Events;

        /// <summary>
        ///  The events found by <c>poll</c>.
        /// </summary>
        internal short ReturnedEvents;
    }
}
