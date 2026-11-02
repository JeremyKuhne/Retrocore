// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80;

public sealed partial class Trs80DiskController
{
    /// <summary>
    ///  What a running command is doing.
    /// </summary>
    private enum Phase : byte
    {
        /// <summary>
        ///  No command is running.
        /// </summary>
        Idle,

        /// <summary>
        ///  A Type I command steps the head.
        /// </summary>
        Stepping,

        /// <summary>
        ///  A Type I command with verify checks the track's ID fields after the head settles.
        /// </summary>
        Verifying,

        /// <summary>
        ///  A Type II or III command waits for its head-load delay.
        /// </summary>
        Delaying,

        /// <summary>
        ///  A read, write or read address waits for an ID field to pass the head.
        /// </summary>
        Searching,

        /// <summary>
        ///  Bytes pass from the disk to the data register.
        /// </summary>
        Reading,

        /// <summary>
        ///  Bytes pass from the data register to the disk.
        /// </summary>
        Writing,

        /// <summary>
        ///  Read track or write track waits for the index hole.
        /// </summary>
        AwaitingIndex,

        /// <summary>
        ///  Write track takes bytes until the next index hole.
        /// </summary>
        WritingTrack
    }
}
