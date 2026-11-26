// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  The values of a routine's registers and flags at one instruction, and what is on its stacks.
/// </summary>
internal sealed class AnalysisRoutineState
{
    /// <summary>
    ///  The slots: registers by bit, then flags from 32.
    /// </summary>
    internal const int SlotCount = 40;

    /// <summary>
    ///  Gets each slot's value: its origin, its own index for its entry value and below zero for changed, and its
    ///  constant where it is known.
    /// </summary>
    internal AnalysisValue[] Slots { get; private init; } = new AnalysisValue[SlotCount];

    /// <summary>
    ///  Gets what each stack holds, by its pointer register's bit.
    /// </summary>
    internal Dictionary<int, List<AnalysisRoutineFrame>> Stacks { get; private init; } = [];

    /// <summary>
    ///  Gets the values registers were stored to at fixed addresses, by address, so a load from one gets the value
    ///  back.
    /// </summary>
    internal Dictionary<int, AnalysisValue> Memory { get; private init; } = [];

    /// <summary>
    ///  Gets or sets whether a stack pointer changed other than by a push or pull, so the stack is not known.
    /// </summary>
    internal bool StackLost { get; set; }

    /// <summary>
    ///  Copies the state.
    /// </summary>
    /// <returns>The copy.</returns>
    internal AnalysisRoutineState Copy()
    {
        AnalysisRoutineState copy = new()
        {
            Slots = (AnalysisValue[])Slots.Clone(),
            StackLost = StackLost,
            Memory = [with(Memory)]
        };

        foreach ((int stack, List<AnalysisRoutineFrame> frames) in Stacks)
        {
            copy.Stacks[stack] = [.. frames];
        }

        return copy;
    }

    /// <summary>
    ///  Gets whether another state holds the same values.
    /// </summary>
    /// <param name="other">The other state.</param>
    /// <returns>Whether they are the same.</returns>
    internal bool SameAs(AnalysisRoutineState other)
    {
        if (StackLost != other.StackLost || !Slots.AsSpan().SequenceEqual(other.Slots) || Memory.Count != other.Memory.Count)
        {
            return false;
        }

        // Memory counts as much as registers: a join that changes only what a fixed address holds must be followed.
        foreach ((int address, AnalysisValue value) in Memory)
        {
            if (!other.Memory.TryGetValue(address, out AnalysisValue theirs) || theirs != value) { return false; }
        }

        foreach ((int stack, List<AnalysisRoutineFrame> frames) in Stacks)
        {
            List<AnalysisRoutineFrame> theirs = other.Stacks.TryGetValue(stack, out List<AnalysisRoutineFrame>? found) ? found : [];
            if (frames.Count != theirs.Count) { return false; }
            for (int index = 0; index < frames.Count; index++)
            {
                AnalysisRoutineFrame a = frames[index];
                AnalysisRoutineFrame b = theirs[index];
                if (a.Bytes != b.Bytes || a.Units.Count != b.Units.Count) { return false; }
                for (int unit = 0; unit < a.Units.Count; unit++)
                {
                    if (!a.Units[unit].Values.AsSpan().SequenceEqual(b.Units[unit].Values))
                    {
                        return false;
                    }
                }
            }
        }

        foreach ((int stack, List<AnalysisRoutineFrame> frames) in other.Stacks)
        {
            if (frames.Count != 0 && !Stacks.ContainsKey(stack)) { return false; }
        }

        return true;
    }
}
