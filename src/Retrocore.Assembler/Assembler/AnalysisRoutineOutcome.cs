// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  How an instruction's pushes and pulls left a path through a routine.
/// </summary>
internal enum AnalysisRoutineOutcome
{
    /// <summary>
    ///  The path goes on to the next instruction.
    /// </summary>
    Next,

    /// <summary>
    ///  A pull loaded PC from the return address: the routine returned.
    /// </summary>
    Returned,

    /// <summary>
    ///  The routine returned with data it pushed still on the stack.
    /// </summary>
    ReturnedThroughData,

    /// <summary>
    ///  A pull took bytes the caller pushed, as its return address.
    /// </summary>
    PulledReturnAddress,

    /// <summary>
    ///  The stack pointer changed other than by a push or pull.
    /// </summary>
    Lost,

    /// <summary>
    ///  It wrote into the stack with nothing pushed, so into its return address or its caller's data.
    /// </summary>
    WroteStack,

    /// <summary>
    ///  It pulled other bytes than its last push saved.
    /// </summary>
    PulledOtherBytes
}
