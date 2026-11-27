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
    ///  It wrote into the stack, where it may have changed its return address, its caller's data or its own.
    /// </summary>
    WroteStack,

    /// <summary>
    ///  It pulled other bytes than its last push saved.
    /// </summary>
    PulledOtherBytes,

    /// <summary>
    ///  It set the program counter other than by a return, as the 6809's <c>TFR X,PC</c> and <c>PULU PC</c>.
    /// </summary>
    Jumped
}
