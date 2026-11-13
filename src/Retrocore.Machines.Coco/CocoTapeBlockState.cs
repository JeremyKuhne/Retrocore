// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Coco;

/// <summary>
///  Where recording is in Color BASIC's tape block format: a <c>$55</c> leader, the <c>$3C</c> sync byte, the block
///  type, the length, the data, a checksum and a <c>$55</c> trailer. Following it keeps recorded bytes aligned
///  across the partial cycles BASIC writes between blocks, as a real CoCo resynchronizes on each leader.
/// </summary>
internal enum CocoTapeBlockState : byte
{
    /// <summary>
    ///  Between blocks: sliding bit by bit until eight bits read <c>$55</c>.
    /// </summary>
    Seeking,

    /// <summary>
    ///  In the <c>$55</c> leader, until the <c>$3C</c> sync byte.
    /// </summary>
    Leader,

    /// <summary>
    ///  Expecting the block type: 0 a file header, 1 data, <c>$FF</c> the end of the file.
    /// </summary>
    Type,

    /// <summary>
    ///  Expecting the data length, 0-255.
    /// </summary>
    Length,

    /// <summary>
    ///  In the data.
    /// </summary>
    Data,

    /// <summary>
    ///  Expecting the checksum.
    /// </summary>
    Checksum,

    /// <summary>
    ///  Expecting the <c>$55</c> trailer.
    /// </summary>
    Trailer
}
