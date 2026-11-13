// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu.M6809;

namespace Retrocore.Tests;

/// <summary>
///  Emulates the timer and exit ports used by the pinned MC6809 test programs.
/// </summary>
internal sealed class M6809TestBus : IProcessorBus
{
    private ulong _start;
    private ulong _end;
    private ulong _timerExpiration;
    private byte _interruptLines;
    private byte _scheduledInterruptLines;
    private byte _timerHigh;
    private byte _timerLow;
    private bool _timerArmed;

    /// <summary>
    ///  Gets the full 64 KiB memory image used by the test.
    /// </summary>
    internal byte[] Memory { get; } = new byte[0x10000];

    /// <summary>
    ///  Gets or sets the processor cycle counter used by the timer ports.
    /// </summary>
    internal Func<ulong>? CycleCount { get; set; }

    /// <summary>
    ///  Gets or sets the callback that updates the processor input pins.
    /// </summary>
    internal Action<M6809Signals>? SetSignals { get; set; }

    /// <summary>
    ///  Gets whether the program has written its exit port.
    /// </summary>
    internal bool Exited { get; private set; }

    /// <summary>
    ///  Gets the program's exit status.
    /// </summary>
    internal byte? ExitCode { get; private set; }

    /// <inheritdoc/>
    public byte Read(ushort address)
    {
        return address switch
        {
            0xFF00 => _interruptLines,
            0xFF01 => _scheduledInterruptLines,
            0xFF06 => (byte)((_end - _start) >> 8),
            0xFF07 => (byte)(_end - _start),
            _ => Memory[address]
        };
    }

    /// <summary>
    ///  Advances timer-controlled input pins to the specified completed processor clock count.
    /// </summary>
    /// <param name="completedCycles">The number of processor cycles completed so far.</param>
    internal void AdvanceTo(ulong completedCycles)
    {
        if (_timerArmed && completedCycles >= _timerExpiration)
        {
            _timerArmed = false;
            SetInterruptLines(_scheduledInterruptLines);
        }
    }

    /// <summary>
    ///  Clears timer, interrupt and exit state while keeping the memory array allocated.
    /// </summary>
    internal void Reset()
    {
        _start = 0;
        _end = 0;
        _timerExpiration = 0;
        _interruptLines = 0;
        _scheduledInterruptLines = 0;
        _timerHigh = 0;
        _timerLow = 0;
        _timerArmed = false;
        Exited = false;
        ExitCode = null;
    }

    /// <inheritdoc/>
    public void Write(ushort address, byte value)
    {
        switch (address)
        {
            case 0xFF00:
                SetInterruptLines(value);
                break;
            case 0xFF01:
                _scheduledInterruptLines = value;
                break;
            case 0xFF02:
                _timerHigh = value;
                break;
            case 0xFF03:
                _timerLow = value;
                _timerExpiration = CurrentCycle + (ushort)((_timerHigh << 8) | _timerLow);
                _timerArmed = true;
                AdvanceTo(CurrentCycle);
                break;
            case 0xFF04:
                _start = CurrentCycle;
                break;
            case 0xFF05:
                _end = CurrentCycle;
                break;
            case 0xFF0F:
                ExitCode = value;
                Exited = true;
                break;
            default:
                Memory[address] = value;
                break;
        }
    }

    private ulong CurrentCycle =>
        CycleCount?.Invoke() ?? throw new InvalidOperationException("Cycle counter is not connected.");

    private void SetInterruptLines(byte lines)
    {
        _interruptLines = lines;
        M6809Signals signals = M6809Signals.None;
        if ((lines & 0x01) != 0)
        {
            signals |= M6809Signals.InterruptRequest;
        }

        if ((lines & 0x02) != 0)
        {
            signals |= M6809Signals.FastInterruptRequest;
        }

        if ((lines & 0x04) != 0)
        {
            signals |= M6809Signals.NonMaskableInterrupt;
        }

        (SetSignals ?? throw new InvalidOperationException("Processor signal pins are not connected."))(signals);
    }
}
