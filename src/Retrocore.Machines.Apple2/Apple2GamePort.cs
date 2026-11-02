// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;

namespace Retrocore.Machines.Apple2;

/// <summary>
///  The game port's analog side and a controller's buttons: four paddle timers, started together by any access
///  to $C070-$C07F and read in bit 7 of $C064-$C067, and push buttons that join the keyboard's Open and Closed
///  Apple keys at $C061-$C063.
/// </summary>
/// <remarks>
///  <para>
///   Each paddle is a 558 timer whose output stays high for a time set by the paddle's resistance. The Monitor's
///   PREAD counts in a loop of 11 cycles until the output falls, so a paddle reads as the number of loops it
///   stays high, 0 to 255. A paddle with nothing connected never times out within PREAD's count and reads 255.
///  </para>
/// </remarks>
public sealed class Apple2GamePort
{
    /// <summary>
    ///  The cycles PREAD's loop takes for each count.
    /// </summary>
    public const int CyclesPerCount = 11;

    // PREAD's first read of the timer comes 13 cycles after the trigger, so a timer that runs for 11 cycles a
    // count plus 8 reads as its value: still high at the value's last read, low at the next.
    private const int TriggerToFirstRead = 8;

    private readonly byte[] _paddles = [255, 255, 255, 255];
    private readonly bool[] _buttons = new bool[3];
    private ulong? _triggered;

    /// <summary>
    ///  Gets a paddle's position.
    /// </summary>
    /// <param name="paddle">0 to 3.</param>
    /// <returns>What PREAD reads for it, 0 to 255.</returns>
    public byte Paddle(int paddle) => _paddles[paddle];

    /// <summary>
    ///  Sets a paddle's position, as a controller's stick moves it.
    /// </summary>
    /// <param name="paddle">0 to 3: a joystick's X is paddle 0 (or 2) and its Y paddle 1 (or 3).</param>
    /// <param name="value">What PREAD should read, 0 to 255; 255 is also what an unconnected paddle reads.</param>
    public void SetPaddle(int paddle, byte value)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(paddle);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(paddle, 3);
        _paddles[paddle] = value;
    }

    /// <summary>
    ///  Gets whether a controller holds a push button down.
    /// </summary>
    /// <param name="button">0, 1 or 2.</param>
    /// <returns>Whether it is down.</returns>
    public bool Button(int button) => _buttons[button];

    /// <summary>
    ///  Presses or releases a push button from a controller. The bus reads it together with the keyboard's Open
    ///  and Closed Apple keys, so either one holds the button down.
    /// </summary>
    /// <param name="button">0, 1 or 2.</param>
    /// <param name="pressed">Whether it is down.</param>
    public void SetButton(int button, bool pressed)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(button);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(button, 2);
        _buttons[button] = pressed;
    }

    /// <summary>
    ///  Sets the paddles and buttons from the connected controllers, in the order they connected.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The first controller is the Apple joystick: its left stick or d-pad moves paddles 0 (X) and 1 (Y), and
    ///   its South, East and West buttons (Xbox A, B and X; PlayStation Cross, Circle and Square) press buttons
    ///   0, 1 and 2. A second controller is a second joystick on paddles 2 and 3, and its South button presses
    ///   button 2, the game port's only button left. Paddles without a controller read 255, as unconnected
    ///   paddles do.
    ///  </para>
    /// </remarks>
    /// <param name="controllers">The connected controllers; more than two are ignored.</param>
    public void Apply(IReadOnlyList<ControllerState> controllers)
    {
        for (int joystick = 0; joystick < 2; joystick++)
        {
            if (joystick < controllers.Count)
            {
                ControllerState controller = controllers[joystick];
                _paddles[joystick * 2] = Axis(controller.LeftX, controller.Buttons, ControllerButtons.Left, ControllerButtons.Right);
                _paddles[joystick * 2 + 1] = Axis(controller.LeftY, controller.Buttons, ControllerButtons.Up, ControllerButtons.Down);
            }
            else
            {
                _paddles[joystick * 2] = 255;
                _paddles[joystick * 2 + 1] = 255;
            }
        }

        ControllerButtons first = controllers.Count > 0 ? controllers[0].Buttons : ControllerButtons.None;
        ControllerButtons second = controllers.Count > 1 ? controllers[1].Buttons : ControllerButtons.None;
        _buttons[0] = first.HasFlag(ControllerButtons.South);
        _buttons[1] = first.HasFlag(ControllerButtons.East);
        _buttons[2] = first.HasFlag(ControllerButtons.West) || second.HasFlag(ControllerButtons.South);
    }

    // A stick's position as a paddle, 0 at the left or top to 255 at the right or bottom; the d-pad pushes it
    // all the way.
    private static byte Axis(short stick, ControllerButtons buttons, ControllerButtons low, ControllerButtons high)
    {
        if (buttons.HasFlag(low) && !buttons.HasFlag(high)) { return 0; }
        if (buttons.HasFlag(high) && !buttons.HasFlag(low)) { return 255; }
        return (byte)((stick + 32768) >> 8);
    }

    /// <summary>
    ///  Disconnects the controllers: the paddles read 255 and the buttons are up.
    /// </summary>
    public void Release()
    {
        _paddles.AsSpan().Fill(255);
        _buttons.AsSpan().Clear();
    }

    /// <summary>
    ///  Starts the four timers, as any access to $C070-$C07F does.
    /// </summary>
    /// <param name="cycle">The machine's cycle count at the access.</param>
    internal void Trigger(ulong cycle) => _triggered = cycle;

    /// <summary>
    ///  Gets whether a paddle's timer is still running, which reads as bit 7 of $C064-$C067.
    /// </summary>
    /// <param name="paddle">0 to 3.</param>
    /// <param name="cycle">The machine's cycle count at the read.</param>
    /// <returns>Whether the timer's output is high.</returns>
    internal bool Timing(int paddle, ulong cycle) =>
        _triggered is { } start && cycle - start < (ulong)(_paddles[paddle] * CyclesPerCount + TriggerToFirstRead);
}
