// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu.M6809;
using Retrocore.Cpu.Z80;
using Retrocore.Machines;

namespace Retrocore.Tests;

/// <summary>
///  Steps a core or machine one cycle and returns its bus activity, for tests that check each cycle.
/// </summary>
internal static class ProcessorCycleExtensions
{
    /// <summary>
    ///  Steps the 6502 one cycle and returns its bus activity.
    /// </summary>
    /// <typeparam name="TBus">The processor's bus.</typeparam>
    /// <param name="cpu">The processor.</param>
    /// <returns>The cycle's bus activity.</returns>
    internal static ProcessorCycle NextCycle<TBus>(this Processor<TBus> cpu) where TBus : IProcessorBus
    {
        cpu.StepCycle();
        return cpu.LastCycle;
    }

    /// <summary>
    ///  Steps the Z80 one T-state and returns its bus activity.
    /// </summary>
    /// <typeparam name="TBus">The processor's bus.</typeparam>
    /// <param name="cpu">The processor.</param>
    /// <returns>The T-state's bus activity.</returns>
    internal static ProcessorCycle NextCycle<TBus>(this Z80Processor<TBus> cpu) where TBus : IProcessorBus, IIoBus
    {
        cpu.StepCycle();
        return cpu.LastCycle;
    }

    /// <summary>
    ///  Steps the MC6809 one clock and returns its bus activity.
    /// </summary>
    /// <typeparam name="TBus">The processor's bus.</typeparam>
    /// <param name="cpu">The processor.</param>
    /// <returns>The cycle's bus activity.</returns>
    internal static ProcessorCycle NextCycle<TBus>(this M6809Processor<TBus> cpu) where TBus : IProcessorBus
    {
        cpu.StepCycle();
        return cpu.LastCycle;
    }

    /// <summary>
    ///  Steps the machine one CPU cycle and returns the CPU's bus activity.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <returns>The cycle's bus activity.</returns>
    internal static ProcessorCycle NextCycle(this IMachine machine)
    {
        machine.StepCycle();
        return machine.LastCycle;
    }
}
