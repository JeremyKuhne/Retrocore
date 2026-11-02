// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple2;

/// <summary>
///  Slot-four Mockingboard with two 6522 VIAs and two AY-3-8910 PSGs.
/// </summary>
/// <remarks>
///  The caller routes C400-C4FF using the address's low byte and calls Tick once per CPU cycle.
///  Bit 7 selects the right VIA (C480); bits 4-6 are not decoded. VIA PA carries AY data;
///  PB2 is active-low RESET, PB1 BDIR and PB0 BC1. Controls 4, 7, 6 and 5 respectively
///  mean inactive, address latch, register write and register read.
///  Digital bus levels settle on each access; writes/latches act on entry to their control
///  state, not repeatedly on CPU ticks. PSGs clock at the CPU rate. Left PSG channels mix
///  to the left output, right PSG channels to the right output.
/// </remarks>
public sealed class Mockingboard
{
    private readonly Via6522 _leftVia = new();
    private readonly Via6522 _rightVia = new();
    private readonly Ay38910 _leftAy = new();
    private readonly Ay38910 _rightAy = new();
    private int _leftControl = -1;
    private int _rightControl = -1;

    /// <summary>
    ///  Creates a reset card.
    /// </summary>
    public Mockingboard() => Reset();

    /// <summary>
    ///  Gets the logical OR of both enabled VIA interrupt levels.
    /// </summary>
    public bool InterruptRequested => _leftVia.InterruptRequested || _rightVia.InterruptRequested;

    /// <summary>
    ///  Gets the current normalized left PSG output.
    /// </summary>
    public float Left => _leftAy.Output;

    /// <summary>
    ///  Gets the current normalized right PSG output.
    /// </summary>
    public float Right => _rightAy.Output;

    /// <summary>
    ///  Reads the addressed VIA and acknowledges its register-access side effects.
    /// </summary>
    /// <param name="offset">The low byte of the slot-four address.</param>
    /// <returns>The selected VIA register data.</returns>
    public byte Read(byte offset)
    {
        bool right = (offset & 128) != 0;
        Synchronize(right);
        return (right ? _rightVia : _leftVia).Read(offset);
    }

    /// <summary>
    ///  Reads the addressed VIA without changing any card state.
    /// </summary>
    /// <param name="offset">The low byte of the slot-four address.</param>
    /// <returns>The selected VIA register data.</returns>
    public byte Peek(byte offset) => ((offset & 128) != 0 ? _rightVia : _leftVia).Peek(offset);

    /// <summary>
    ///  Writes the addressed VIA and settles the connected AY bus.
    /// </summary>
    /// <param name="offset">The low byte of the slot-four address.</param>
    /// <param name="value">The register data.</param>
    public void Write(byte offset, byte value)
    {
        bool right = (offset & 128) != 0;
        (right ? _rightVia : _leftVia).Write(offset, value);
        Synchronize(right);
    }

    /// <summary>
    ///  Advances both VIAs and PSGs by one CPU clock. Reset-held PSGs do not advance.
    /// </summary>
    public void Tick()
    {
        // The AY control lines are port B's low bits, which only a VIA write or reset changes, and Read,
        // Write and Reset synchronize the AYs then; the VIA's timer drives only PB7.
        _leftVia.Tick();
        _rightVia.Tick();
        if ((_leftControl & 4) != 0)
        {
            _leftAy.Tick();
        }

        if ((_rightControl & 4) != 0)
        {
            _rightAy.Tick();
        }
    }

    /// <summary>
    ///  Clears all VIA and PSG state and restores pulled-up, unconnected input pins.
    /// </summary>
    public void Reset()
    {
        _leftVia.PortAInput = _leftVia.PortBInput = 255;
        _rightVia.PortAInput = _rightVia.PortBInput = 255;
        _leftVia.Reset();
        _rightVia.Reset();
        _leftAy.Reset();
        _rightAy.Reset();
        _leftControl = _rightControl = -1;
        Synchronize(right: false);
        Synchronize(right: true);
    }

    private void Synchronize(bool right)
    {
        Via6522 via = right ? _rightVia : _leftVia;
        Ay38910 ay = right ? _rightAy : _leftAy;
        int control = via.PortB & 7;
        int previous = right ? _rightControl : _leftControl;
        if (right)
        {
            _rightControl = control;
        }
        else
        {
            _leftControl = control;
        }

        if ((control & 4) == 0)
        {
            if ((previous & 4) != 0)
            {
                ay.Reset();
            }
        }
        else if (control != previous)
        {
            if (control == 7)
            {
                ay.LatchAddress(via.PortA);
            }
            else if (control == 6)
            {
                ay.Write(via.PortA);
            }
        }

        via.PortAInput = control == 5 ? ay.Read() : (byte)255;
    }
}
